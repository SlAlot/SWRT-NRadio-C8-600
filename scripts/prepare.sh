#!/usr/bin/env bash
set -euo pipefail

project=$(cd "$(dirname "$0")/.." && pwd)
tree=$(realpath "${1:?Usage: prepare.sh IMMORTALWRT_TREE}")
lock="$project/sources.lock.json"
cd "$tree"
test "$(git rev-parse HEAD)" = "$(jq -er .immortalwrt.commit "$lock")"
bash "$project/scripts/test-leds.sh"
kernel=$(jq -er .immortalwrt.kernel "$lock")
series=${kernel%.*}
grep -Fx "KERNEL_PATCHVER:=$series" target/linux/mediatek/Makefile
grep -Fx "LINUX_VERSION-$series = .${kernel##*.}" "target/linux/generic/kernel-$series"

cp feeds.conf.default feeds.conf
jq -r '.feeds | to_entries[] | "src-git \(.key) https://github.com/\(.value[0]).git^\(.value[1])"' "$lock" >> feeds.conf

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p package/swrt
while IFS=$'\t' read -r name repository revision subdir; do
    mkdir "$work/$name"
    curl -fSL --retry 4 "https://codeload.github.com/$repository/tar.gz/$revision" -o "$work/$name.tar.gz"
    tar -xzf "$work/$name.tar.gz" -C "$work/$name" --strip-components=1
    mkdir -p "package/swrt/$name"
    cp -a "$work/$name/$subdir/." "package/swrt/$name/"
    test -f "package/swrt/$name/Makefile"
done < <(jq -r '.packages | to_entries[] | [.key, .value[]] | @tsv' "$lock")

download_locked() {
    local name=$1 output=$2
    curl -fSL --retry 4 "$(jq -er --arg key "$name" '.[$key].url' "$lock")" -o "$output"
    printf '%s  %s\n' "$(jq -er --arg key "$name" '.[$key].sha256' "$lock")" "$output" | sha256sum -c -
}

# Reuse the matching Filogic host tools on the Linux x86-64 runner.
if [[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] && download_locked llvm-bpf "$work/llvm.tar.zst"; then
    mkdir "$work/llvm"
    tar -xf "$work/llvm.tar.zst" -C "$work/llvm"
    if "$work/llvm/llvm-bpf/bin/clang" --version; then
        cp -a "$work/llvm/." .
    fi
fi

cp -a "$project/package/wlmb-server" package/swrt/
cp -a "$project/package/luci-app-swrt-advanced" package/swrt/
panel=package/swrt/wlmb-server/payload
mkdir -p "$panel"
download_locked wlmb-server "$work/wlmb.ipk"
tar -xOf "$work/wlmb.ipk" data.tar.gz | tar -xzf - -C "$panel"
test -x "$panel/usr/sbin/wlmb-server"
test -f "$panel/usr/share/wlmb-server/LICENSE"
readelf -h "$panel/usr/sbin/wlmb-server" | grep -F AArch64

download_locked mihomo "$work/mihomo.gz"
core=package/swrt/openclash/root/etc/openclash/core/clash_meta
mkdir -p "$(dirname "$core")"
gzip -dc "$work/mihomo.gz" > "$core"
chmod 755 "$core"
readelf -h "$core" | grep -F AArch64
sed -i '/^PKG_NAME:=luci-app-openclash$/a PKG_BUILD_DEPENDS:=luci-base/host' package/swrt/openclash/Makefile
openclash_init=package/swrt/openclash/root/etc/init.d/openclash
test "$(grep -c 'add rule inet fw4 openclash_mangle_output skgid' "$openclash_init")" = 2
# MWAN3 sets all bits of mmx_mask on its probe sockets. Keep probes on their bound device.
sed -i "/add rule inet fw4 openclash_mangle_output skgid/a\\            nft 'add rule inet fw4 openclash_mangle_output meta mark & 0x3f0000 == 0x3f0000 counter return'" "$openclash_init"

./scripts/feeds update -a
mwan3=feeds/packages/net/mwan3/files/lib/mwan3/mwan3.sh
test "$(grep -c 'mwan3_push_update -N mwan3_hook$' "$mwan3")" = 1
# Preserve OpenClash's exact transparent-proxy mark through the MWAN3 chains.
if ! grep -Fq 'mwan3_push_update -A mwan3_hook -m mark --mark 0x162 -j RETURN' "$mwan3"; then
    sed -i '/mwan3_push_update -N mwan3_hook$/a\			mwan3_push_update -A mwan3_hook -m mark --mark 0x162 -j RETURN' "$mwan3"
fi
./scripts/feeds update -i packages
for feed in packages luci routing telephony video; do
    ./scripts/feeds install -a -p "$feed"
done
# Only the pinned SWRT package contains our Mihomo core and proxy-mark rules.
rm -f package/feeds/luci/luci-app-openclash
./scripts/feeds install -p qmodem luci-app-qmodem-next
./scripts/feeds install -p istore luci-app-store
python3 "$project/scripts/apply-board.py" "$tree"
git -C feeds/qmodem diff --exit-code
git -C feeds/qmodem apply "$project/patches/qmodem/001-usb-qmi-data-format.patch"
bash "$project/scripts/test-uplink.sh"

cp "$project/config/c8-600.seed" .config
mkdir -p swrt-metadata
make defconfig 2>&1 | tee swrt-metadata/defconfig.log
cp .config swrt-metadata/config.resolved
cp tmp/.config-package.in swrt-metadata/packages.kconfig
cp tmp/.packageinfo swrt-metadata/packages.metadata
if grep -Eq 'recursive dependency detected|(^|:)error:' swrt-metadata/defconfig.log; then
    exit 1
fi
./scripts/diffconfig.sh > swrt-metadata/config.diff
./scripts/feeds list -s > swrt-metadata/feeds.resolved
printf '%s\n' "$kernel" > swrt-metadata/kernel.version
cp "$lock" swrt-metadata/
python3 "$project/scripts/check-build.py" "$tree"
