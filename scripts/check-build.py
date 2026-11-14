#!/usr/bin/env python3
import argparse
import json
import re
import shutil
import subprocess
import tarfile
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROFILE = "nradio_wt9106"
BOARD = "nradio,wt9106"
RELEASE = "SWRT-C8-600-1.2.5"
OFFLINE_KMODS = {"kmod-fs-ext4", "kmod-usb-storage", "kmod-usb-storage-uas"}
LOCAL_FEEDS = {"istore", "qmodem", "video"}
MAX_IMAGE_BYTES = 100 * 1024 * 1024
BOOT_PARAMETERS = {
    "root=/dev/fit0", "rootwait", "usbcore.autosuspend=-1",
    "usbcore.old_scheme_first=Y", "pcie_aspm=off",
}


def run(*args):
    return subprocess.check_output([str(arg) for arg in args], text=True).strip()


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def check_config(tree):
    seed = (ROOT / "config/c8-600.seed").read_text().splitlines()
    resolved = set((tree / ".config").read_text().splitlines())
    required = [line for line in seed if line.startswith("CONFIG_")]
    required += [f"# CONFIG_FEED_{name} is not set" for name in sorted(LOCAL_FEEDS)]
    missing = [line for line in required if line not in resolved]
    require(not missing, "Kconfig dropped required settings:\n" + "\n".join(missing))
    require("CONFIG_USE_APK=y" in resolved, "The firmware must use APK")
    package_deps = (tree / "tmp/.packagedeps").read_text().splitlines()
    openclash = [line for line in package_deps
                 if line.startswith("package-$(CONFIG_PACKAGE_luci-app-openclash)")]
    require(openclash == ["package-$(CONFIG_PACKAGE_luci-app-openclash) += swrt/openclash"],
            "Only the pinned SWRT OpenClash package may be built")
    if (tree / "llvm-bpf/.llvm-version").is_file():
        require("CONFIG_USE_LLVM_PREBUILT=y" in resolved and "CONFIG_USE_LLVM_BUILD=y" not in resolved,
                "The build did not select the pinned prebuilt LLVM-BPF toolchain")
    require("# CONFIG_RUBY_ENABLE_YJIT is not set" in resolved,
            "Ruby YJIT must be disabled to avoid the Rust/LLVM host build")
    unwanted = {
        "dnsmasq", "opkg", "iptables-zz-legacy", "ip6tables-zz-legacy",
        "qmi_wwan_q", "qmi_wwan_f", "qmi_wwan_s", "luci-app-qmodem-mwan",
        "qmodem-uplink-manager", "quectel-cm", "quectel-CM-5G",
    }
    present = sorted(name for name in unwanted if f"CONFIG_PACKAGE_{name}=y" in resolved)
    require(not present, f"Conflicting packages: {', '.join(present)}")


def one(directory, pattern):
    items = list(directory.glob(pattern))
    require(len(items) == 1, f"Expected one {pattern} under {directory}; found {items}")
    return items[0]


def fit_blob(fit, image, external):
    node = f"/images/{image}"
    if not external:
        return bytes.fromhex(" ".join(
            item.zfill(2) for item in run("fdtget", "-t", "bx", fit, node, "data").split()
        ))
    position = int(run("fdtget", "-tx", fit, node, "data-position"), 16)
    size = int(run("fdtget", "-tx", fit, node, "data-size"), 16)
    require(0 < size < 1024 * 1024 and position + size <= fit.stat().st_size,
            f"{fit.name}: invalid DT data range")
    with fit.open("rb") as stream:
        stream.seek(position)
        return stream.read(size)


def check_fit(fit, external):
    require(0 < fit.stat().st_size <= MAX_IMAGE_BYTES, f"Invalid image size: {fit}")
    require(run("fdtget", "-ts", fit, "/configurations", "default") == "config-1",
            f"{fit.name}: unexpected default FIT configuration")
    overlay = run("fdtget", "-ts", fit, "/configurations/mt7981-nradio-wt9106", "fdt")
    require(overlay == "fdt-mt7981-nradio-wt9106", f"{fit.name}: FIP overlay is missing")
    base = run("fdtget", "-ts", fit, "/configurations/config-1", "fdt")
    images = run("fdtget", "-l", fit, "/images").splitlines()
    kernel = run("fdtget", "-ts", fit, "/configurations/config-1", "kernel")
    load = run("fdtget", "-tx", fit, f"/images/{kernel}", "load")
    require(load == "44000000", f"{fit.name}: incorrect kernel load address")
    with tempfile.TemporaryDirectory() as tmp:
        directory = Path(tmp)
        dtb, dtbo, merged = (directory / name for name in ("base.dtb", "board.dtbo", "merged.dtb"))
        dtb.write_bytes(fit_blob(fit, base, external))
        dtbo.write_bytes(fit_blob(fit, overlay, external))
        run("fdtoverlay", "-i", dtb, "-o", merged, dtbo)
        for tree in (dtb, merged):
            arguments = run("fdtget", "-ts", tree, "/chosen", "bootargs-override").split()
            require(BOOT_PARAMETERS.issubset(arguments), f"{fit.name}: missing early boot parameters")
            memory = run("fdtget", "-tx", tree, "/memory@40000000", "reg")
            require(memory == "0 40000000 0 20000000", f"{fit.name}: expected 512 MiB in the DTS")
            require(run("fdtget", "-ts", tree, "/soc/usb@11200000", "status") == "okay",
                    f"{fit.name}: xHCI is disabled")
            require(run("fdtget", "-ts", tree, "/soc/usb-phy@11e10000/usb-phy@700",
                        "nvmem-cell-names") == "intr rx_imp tx_imp",
                    f"{fit.name}: USB3 PHY trim is missing")
            ports = "/soc/ethernet@15100000/mdio-bus/switch@1f/ports"
            for port, label in enumerate(("lan1", "lan2", "lan3", "wan", "cpe")):
                require(run("fdtget", "-ts", tree, f"{ports}/port@{port}", "label") == label,
                        f"{fit.name}: port {port} must be {label}")
            require(run("fdtget", "-ts", tree, f"{ports}/port@4", "status") == "okay",
                    f"{fit.name}: modem Ethernet port is disabled")
            led_root = "/gpio-leds"
            require(run("fdtget", "-ts", tree, led_root, "compatible") == "gpio-leds",
                    f"{fit.name}: front-panel LEDs must be GPIO LEDs")
            for pin, (name, function) in enumerate((
                ("status", "status"), ("cellular-5g", "indicator"),
                ("cellular-4g", "indicator"), ("wifi", "wlan"),
            ), start=10):
                node = f"{led_root}/led-{name}"
                gpios = run("fdtget", "-tx", tree, node, "gpios").split()
                require(len(gpios) == 3 and gpios[1:] == [f"{pin:x}", "1"],
                        f"{fit.name}: {node} must use active-low GPIO{pin}")
                require(run("fdtget", "-ts", tree, node, "function") == function
                        and run("fdtget", "-tu", tree, node, "color") == "3",
                        f"{fit.name}: unexpected LED class name for {node}")
                if function == "indicator":
                    require(run("fdtget", "-tu", tree, node, "function-enumerator") == str(pin - 11),
                            f"{fit.name}: cellular LED class names are swapped")
                require("linux,default-trigger" not in run("fdtget", "-p", tree, node).splitlines(),
                        f"{fit.name}: unexpected kernel LED trigger on {node}")
            for state in ("boot", "failsafe", "running", "upgrade"):
                require(run("fdtget", "-ts", tree, "/aliases", f"led-{state}") == f"{led_root}/led-status",
                        f"{fit.name}: power LED missing from {state} state")
    return images


def check_images(tree, output):
    directory = tree / "bin/targets/mediatek/filogic"
    upgrade = one(directory, f"*{PROFILE}*sysupgrade.itb")
    recovery = one(directory, f"*{PROFILE}*recovery.itb")
    manifest = one(directory, "*.manifest")
    images = check_fit(upgrade, external=True)
    require(any(image.startswith("rootfs") for image in images), "Sysupgrade FIT lacks rootfs")
    check_fit(recovery, external=False)
    fwtool = tree / "staging_dir/host/bin/fwtool"
    output.mkdir(parents=True, exist_ok=True)
    metadata_file = output / "sysupgrade.metadata.json"
    run(fwtool, "-i", metadata_file, upgrade)
    metadata = json.loads(metadata_file.read_text())
    require(metadata["supported_devices"] == [BOARD], "Incorrect sysupgrade device allowlist")

    expected = {
        "luci-app-qmodem-next", "qmodem", "luci-app-wlmbstart", "wlmb-server",
        "luci-app-openclash", "luci-theme-apollo", "luci-app-store", "luci-app-ttyd",
        "mwan3", "luci-app-mwan3", "iptables-nft", "fitblk", "dnsmasq-full", "ip-full", "busybox",
        "kmod-usb3", "kmod-usb-net-qmi-wwan", "kmod-mt7981-firmware",
        "ruby", "ruby-yaml", "tom_modem", "quectel-CM-5G-M",
        "iw", "jq", "coreutils-timeout", "ubus-at-daemon", "bridger",
        "kmod-nft-offload", "kmod-mt7915e", "mt7981-wo-firmware",
        "luci-app-swrt-advanced", "openssl-util", "ca-bundle", "curl", "fwtool",
    }
    versions = manifest.read_text().splitlines()
    for name in sorted(expected):
        require(any(re.match(rf"^{re.escape(name)}(?:\s|-[0-9])", line) for line in versions),
                f"Missing from image manifest: {name}")
    kernel = json.loads((ROOT / "sources.lock.json").read_text())["immortalwrt"]["kernel"]
    match = next((re.fullmatch(r"kernel - (\S+)", line) for line in versions
                  if line.startswith("kernel - ")), None)
    require(match and match[1].startswith(f"{kernel}~"), f"Expected Linux {kernel} in the manifest")
    rootfs = one(tree, "build_dir/target-*/root-mediatek")
    lan_defaults = (rootfs / "etc/board.d/99-lan-ip").read_text()
    require('json_add_string ipaddr "192.168.17.1"' in lan_defaults
            and 'json_add_string netmask "255.255.255.0"' in lan_defaults,
            "The default LAN must generate 192.168.17.1/24")
    board_defaults = (rootfs / "etc/uci-defaults/99-swrt-c8600").read_text()
    require((rootfs / "etc/uci-defaults/96-swrt-lan-subnet").stat().st_mode & 0o111
            and "network.lan.ipaddr" not in board_defaults,
            "Preserve the generated LAN prefix and migrate the legacy bare address")
    openclash_defaults = (rootfs / "etc/config/openclash").read_text()
    require(re.search(r"^\s*option enable '0'$", openclash_defaults, re.M)
            and "openclash.config.enable" not in board_defaults,
            "OpenClash must default to disabled and preserve the user's setting on upgrade")
    core = Path("etc/openclash/core/clash_meta")
    installed_core = rootfs / core
    require(installed_core.is_file() and installed_core.stat().st_mode & 0o111,
            "OpenClash must contain an executable Mihomo core")
    with tempfile.TemporaryDirectory() as work:
        expected_core = Path(work) / "clash_meta"
        shutil.copyfile(tree / "package/swrt/openclash/root" / core, expected_core)
        # The package build strips padding and metadata from the locked binary.
        run(tree / "staging_dir/host/bin/sstrip", "-z", expected_core)
        require(installed_core.read_bytes() == expected_core.read_bytes(),
                "OpenClash must contain the pinned Mihomo core")
    require((rootfs / "usr/bin/quectel-CM-M").is_file() and (rootfs / "usr/bin/tom_modem").is_file(),
            "TOM dialing core or AT utility is missing from the root filesystem")
    require((rootfs / "etc/swrt-release").read_text().strip() == f"SWRT_RELEASE='{RELEASE}'",
            "Missing SWRT release identifier")
    repos = (rootfs / "etc/apk/repositories.d/distfeeds.list").read_text().splitlines()
    require(all(repo.split("/")[-2] not in LOCAL_FEEDS for repo in repos if repo.strip()),
            "An unavailable feed is still in the firmware APK configuration")
    ttyd = (rootfs / "etc/init.d/ttyd").read_text()
    require('[ -n "$interface" ] || return 1' in ttyd and "procd_add_reload_interface_trigger" in ttyd,
            "ttyd must wait for its configured network interface")
    require((rootfs / "etc/rc.d/S78swrt-uplink").is_symlink(),
            "Fourth port and modem uplink service is not enabled")
    require((rootfs / "usr/sbin/swrt-uplink").stat().st_mode & 0o111,
            "Fourth port and modem uplink program must be executable")
    require((rootfs / "etc/rc.d/S97swrt-leds").is_symlink(),
            "Front-panel LED service is not enabled")
    require((rootfs / "usr/sbin/swrt-leds").stat().st_mode & 0o111,
            "Front-panel LED program must be executable")
    qmodem = tree / "feeds/qmodem/application/qmodem/files/etc/init.d/qmodem_network"
    require((rootfs / "etc/init.d/qmodem_network").read_bytes() == qmodem.read_bytes(),
            "QModem dialing must use the unmodified feed script")
    scanner = (rootfs / "usr/bin/modem_scand").read_bytes()
    require(b"/usr/sbin/swrt-uplink\0" not in scanner,
            "QModem scanning must use the unmodified feed")
    require("wed_enable=Y" in (rootfs / "etc/modules.d/mt7915e").read_text(),
            "mt7915e must load with WED enabled")
    fw4_code = (rootfs / "usr/share/ucode/fw4.uc").read_text()
    fw4_rules = (rootfs / "usr/share/firewall4/templates/ruleset.uc").read_text()
    require("nft_try_hw_offload" in fw4_code and "flow offload @ft" in fw4_rules
            and "swrt-ppe" not in fw4_code and "swrt_egress" not in fw4_rules
            and not (rootfs / "usr/sbin/swrt-ppe").exists()
            and not (rootfs / "etc/hotplug.d/iface/12-swrt-ppe").exists(),
            "Firmware must use native Firewall4 flow offload without the SWRT policy")
    wifi = (rootfs / "etc/board.d/04_defaults").read_text()
    for expected in ('ucidef_set_country "CN"', '"2g" "SWRT-660" "none"',
                     '"5g" "SWRT-660-5G" "none"', 'channel "1"', 'channel "149"'):
        require(expected in wifi, f"Missing wireless default: {expected}")
    require("defaults?.channel || channel" in (rootfs / "lib/wifi/mac80211.uc").read_text(),
            "Wireless generator must consume the board default channels")
    require("option port_mode 'wan'" in (rootfs / "etc/config/swrt_uplink").read_text(),
            "Fourth port must default to WAN")
    for name in ("usr/libexec/swrt-upgrade", "usr/libexec/rpcd/luci.swrt_advanced",
                 "usr/libexec/qmodem-host-ipv4-owner", "usr/sbin/swrt-qmi-format",
                 "etc/hotplug.d/net/10-swrt-qmi-format"):
        require((rootfs / name).stat().st_mode & 0o111, f"Missing executable: {name}")
    for name in ("usr/share/swrt/ota-public.pem",
                 "www/luci-static/resources/view/system/swrt-advanced.js",
                 "www/luci-static/resources/view/system/swrt-ota.js"):
        require((rootfs / name).is_file(), f"Missing SWRT Advanced Settings asset: {name}")
    source = ROOT / "package/luci-app-swrt-advanced/root"
    for name in ("usr/libexec/swrt-upgrade", "usr/share/swrt/ota-public.pem"):
        require((rootfs / name).read_bytes() == (source / name).read_bytes(),
                f"Installed OTA component does not match the release source: {name}")
    menu = json.loads((rootfs / "usr/share/luci/menu.d/luci-app-swrt-advanced.json").read_text())
    require(menu["admin/system/swrt-uplink"]["action"] == {"type": "view", "path": "system/swrt-advanced"}
            and menu["admin/system/swrt-upgrade"]["action"] == {"type": "view", "path": "system/swrt-ota"}
            and "admin/network/swrt-uplink" not in menu,
            "SWRT pages must be under System")
    upgrade_view = rootfs / "www/luci-static/resources/view/system/swrt-ota.js"
    require("L.url('admin', 'system', 'swrt-uplink')" in upgrade_view.read_text()
            and not upgrade_view.with_name("swrt-upgrade.js").exists(),
            "The OTA page must load its new script and link to Advanced Settings under System")
    luci_proto = rootfs / "www/luci-static/resources/protocol/qmodem_runtime.js"
    netifd_proto = rootfs / "lib/netifd/proto/qmodem_runtime.sh"
    require(luci_proto.is_file() and "registerProtocol('qmodem_runtime'" in luci_proto.read_text()
            and netifd_proto.is_file() and netifd_proto.stat().st_mode & 0o111,
            "QModem runtime protocol must be available to netifd and LuCI")
    archive_apk_repository(tree, directory / "packages", rootfs, output, match[1])
    for file in (upgrade, recovery, manifest, tree / "swrt-metadata/config.diff"):
        shutil.copy2(file, output / file.name)


def archive_apk_repository(tree, repository, rootfs, output, kernel):
    index = json.loads((repository / "index.json").read_text())["packages"]
    require(index.get("kernel") == kernel, "Offline APK repository has the wrong kernel ABI")
    require(OFFLINE_KMODS.issubset(index), "Offline APK repository is missing optional modules")
    key = tree / "public-key.pem"
    require(key.read_bytes() == (rootfs / "etc/apk/keys/public-key.pem").read_bytes(),
            "The image is missing the offline APK repository verification key")
    with tarfile.open(output / f"{RELEASE}-apk.tar.gz", "w:gz") as archive:
        for file in sorted(repository.glob("*.apk")) + [repository / "packages.adb", key]:
            archive.add(file, arcname=f"{RELEASE}-apk/{file.name}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("tree", type=Path)
    parser.add_argument("--images", type=Path)
    args = parser.parse_args()
    check_config(args.tree)
    if args.images:
        check_images(args.tree, args.images)
