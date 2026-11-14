#!/usr/bin/env python3
import argparse
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BOARD = "nradio,wt9106"


def replace_once(path, old, new):
    text = path.read_text(encoding="utf-8")
    if new in text:
        return
    if text.count(old) != 1:
        raise SystemExit(f"{path}: expected one occurrence of {old!r}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8", newline="\n")


def apply_board(tree):
    target = tree / "target/linux/mediatek"
    base = target / "filogic/base-files"
    for name in ("mt7981b-nradio-wt9106.dts", "mt7981-nradio-wt9106.dtso", "wt9106-bootargs.h"):
        shutil.copyfile(ROOT / "board" / name, target / "dts" / name)
    image = target / "image/filogic.mk"
    marker = "define Device/nradio_c8-668gl\n"
    profile = (ROOT / "board/nradio-wt9106.mk").read_text(encoding="utf-8")
    replace_once(image, marker, profile + "\n" + marker)

    case = '\tcase $board in\n'
    first_board = '\tabt,asr3000|\\\n'
    entry = (
        f"\t{BOARD})\n"
        '\t\tucidef_set_interfaces_lan_wan "lan1 lan2 lan3" "wan"\n'
        "\t\t;;\n"
    )
    replace_once(base / "etc/board.d/02_network", case + first_board, case + entry + first_board)

    gpio_case = 'case "$board" in\n'
    gpio_entry = (
        f"{BOARD})\n"
        '\tucidef_add_gpio_switch "cpe_power" "Cellular modem power" "cpe-pwr" "1"\n'
        '\tucidef_add_gpio_switch "cpe_sim" "External SIM" "cpe-sel0" "1"\n'
        "\t;;\n"
    )
    replace_once(base / "etc/board.d/03_gpio_switches", gpio_case, gpio_case + gpio_entry)

    wifi = base / "etc/board.d/04_defaults"
    wifi_entry = (
        f"{BOARD})\n"
        '\tucidef_set_country "CN"\n'
        '\tucidef_set_wireless "2g" "SWRT-600" "none"\n'
        '\tucidef_set_wireless "5g" "SWRT-600-5G" "none"\n'
        '\tjson_select wlan\n'
        '\tjson_select defaults\n'
        '\tjson_select ssids\n'
        '\tjson_select "2g"\n'
        '\tjson_add_string channel "1"\n'
        '\tjson_select ..\n'
        '\tjson_select "5g"\n'
        '\tjson_add_string channel "149"\n'
        '\tjson_select ..\n'
        '\tjson_select ..\n'
        '\tjson_select ..\n'
        '\tjson_select ..\n'
        "\t;;\n"
    )
    replace_once(wifi, "case $board in\n", "case $board in\n" + wifi_entry)
    wifi_generator = tree / "package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
    replace_once(wifi_generator, "set ${s}.channel='${channel}'",
                 "set ${s}.channel='${defaults?.channel || channel}'")

    platform = base / "lib/upgrade/platform.sh"
    text = platform.read_text(encoding="utf-8")
    anchor = "\tnokia,ea0326gmp|\\\n"
    entry = f"\t{BOARD}|\\\n"
    if text.count(entry) == 0:
        if text.count(anchor) != 2:
            raise SystemExit(f"{platform}: expected the FIT check and upgrade cases")
        platform.write_text(text.replace(anchor, entry + anchor), encoding="utf-8", newline="\n")
    elif text.count(entry) != 2:
        raise SystemExit(f"{platform}: incomplete FIT upgrade cases")

    usb_modules = tree / "package/kernel/linux/modules/usb.mk"
    autoload = "  AUTOLOAD:=$(call AutoLoad,20,usbcore,1)\n"
    params = "  MODPARAMS.usbcore:=autosuspend=-1 old_scheme_first=Y\n"
    replace_once(usb_modules, autoload, autoload + params)

    ttyd = tree / "feeds/packages/utils/ttyd/files/ttyd.init"
    interface_lookup = '\t\t\techo -n "$device"\n\t\t)\n'
    replace_once(ttyd, interface_lookup, interface_lookup + '\t\t[ -n "$interface" ] || return 1\n')
    replace_once(ttyd, 'service_triggers() {\n\tprocd_add_reload_trigger "$NAME"\n}', '''\
ttyd_interface_trigger() {
	local interface
	config_get interface "$1" interface
	case "$interface" in
		@?*) procd_add_reload_interface_trigger "${interface#@}" ;;
	esac
}

service_triggers() {
	procd_add_reload_trigger "$NAME"
	config_load "$NAME"
	config_foreach ttyd_interface_trigger ttyd
}''')

    shutil.copytree(ROOT / "files", tree / "files", dirs_exist_ok=True)
    for name in ("etc/init.d", "etc/uci-defaults", "etc/hotplug.d/iface", "etc/hotplug.d/net", "usr/sbin", "usr/libexec"):
        for script in (tree / "files" / name).iterdir():
            if script.is_file():
                script.chmod(0o755)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("tree", type=Path)
    apply_board(parser.parse_args().tree.resolve())
