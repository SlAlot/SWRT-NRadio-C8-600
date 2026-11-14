#!/usr/bin/env bash
set -eu

project=$(cd "$(dirname "$0")/.." && pwd)
app="$project/package/luci-app-swrt-advanced/root"
backend="$app/usr/libexec/swrt-upgrade"
sh -n "$backend"
sh -n "$app/usr/libexec/rpcd/luci.swrt_advanced"

scratch=$(mktemp -d)
trap 'rm -f -- "$scratch"/*.json "$scratch"/*.pem "$scratch/rom/etc/swrt-release" "$scratch/proc/mounts" "$scratch/proc/mtd" "$scratch/tmp/sysinfo/board_name" "$scratch/tmp/swrt-upgrade/"*; rmdir "$scratch/tmp/swrt-upgrade" "$scratch/tmp/sysinfo" "$scratch/tmp" "$scratch/rom/etc" "$scratch/rom" "$scratch/proc" "$scratch"' EXIT
export SWRT_UPGRADE_ROOT="$scratch"
mkdir -p "$scratch/rom/etc" "$scratch/proc" "$scratch/tmp/sysinfo"
printf 'nradio,wt9106\n' > "$scratch/tmp/sysinfo/board_name"
printf 'fit0 /rom squashfs ro 0 0\n' > "$scratch/proc/mounts"
printf 'mtd4: 07280000 00020000 "ubi"\n' > "$scratch/proc/mtd"
cp "$project/files/etc/swrt-release" "$scratch/rom/etc/"

version=$(sed -n "s/^SWRT_RELEASE='SWRT-C8-600-\([^']*\)'$/\1/p" "$project/files/etc/swrt-release")
bash "$backend" status | jq -e --arg version "$version" '.eligible and .current == $version' >/dev/null
printf 'mtd4: 00f20000 00010000 "ubi"\n' > "$scratch/proc/mtd"
bash "$backend" status | jq -e '.eligible == false' >/dev/null

source <(sed '/^case "\$MODE" in$/,$d' "$backend")
test "$REPO" = SlAlot/SWRT-NRadio-C8-600
current_tag="SWRT-C8-600-$version"
name="immortalwrt-swrt-c8-600-$version-mediatek-filogic-nradio_wt9106-squashfs-sysupgrade.itb"
base="https://github.com/$REPO/releases/download/$current_tag"
jq -n --arg tag "$current_tag" --arg name "$name" --arg base "$base" '
    {draft:false,prerelease:false,tag_name:$tag,assets:[$name,"ota.json","ota.json.sig"] |
        map({name:.,browser_download_url:($base+"/"+.),size:45,id:42})}' > "$scratch/api.json"
select_release "$scratch/api.json" "$scratch/selected.json"
jq -e --arg name "$name" --arg version "$version" '.version == $version and .name == $name' "$scratch/selected.json" >/dev/null
cp "$scratch/selected.json" "$RELEASE"
CURRENT=1.1.2
newer 1.1.10
if newer 1.1.1; then exit 1; fi
if newer 1.1.2; then exit 1; fi
CURRENT=1.1.10
newer 1.2.0
CURRENT=1.2.0
if newer 1.1.10; then exit 1; fi
newer 1.2.1
CURRENT=1.2.1
if newer 1.2.1; then exit 1; fi
for filter in '.draft=true' '.prerelease=true' '.assets[0].name="recovery.itb"' \
              'del(.assets[2])' '.assets[1].browser_download_url="https://other.example/ota.json"'; do
    jq "$filter" "$scratch/api.json" > "$scratch/invalid.json"
    if select_release "$scratch/invalid.json" "$scratch/selected.json"; then
        echo "Unexpected OTA release accepted: $filter" >&2
        exit 1
    fi
done

PUBKEY="$scratch/test-public.pem"
openssl genpkey -algorithm ED25519 -out "$scratch/test-private.pem"
openssl pkey -in "$scratch/test-private.pem" -pubout -out "$PUBKEY"
checksum=$(printf 'a%.0s' {1..64})
jq --arg board "$DEVICE" --arg layout "$LAYOUT" --arg repo "$REPO" --arg sha "$checksum" '
    {repository:$repo,board:$board,layout:$layout,version,name,size,sha256:$sha}' "$RELEASE" > "$DIR/ota.json"
openssl pkeyutl -sign -rawin -inkey "$scratch/test-private.pem" -in "$DIR/ota.json" -out "$DIR/ota.json.sig"
[ "$(manifest_digest)" = "$checksum" ]
printf '\n' >> "$DIR/ota.json"
if manifest_digest; then echo 'Tampered OTA metadata passed signature verification' >&2; exit 1; fi
echo 'OTA board, release selection, and signature regressions passed'
