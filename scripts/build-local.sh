#!/usr/bin/env bash
set -euo pipefail

project=$(cd "$(dirname "$0")/.." && pwd)
cd "$project"
if [[ $(uname -s) != Linux || $EUID == 0 || $project == /mnt/[a-z]/* || $project == *[[:space:]]* ]]; then
    echo 'Run as a normal Linux user from a Linux filesystem path without spaces.' >&2
    exit 1
fi
if [[ -n $(git status --porcelain --untracked-files=no) ]]; then
    echo 'Commit tracked source changes before building a release.' >&2
    exit 1
fi

revision=$(git rev-parse HEAD)
pin=$(jq -er .immortalwrt.commit sources.lock.json)
tree="$project/openwrt/$revision"
out="$project/artifacts/$revision"
jobs=${SWRT_BUILD_JOBS:-$(nproc)}
mkdir -p "$tree" "$out"
exec 9>"$tree/.swrt-build.lock"
flock -n 9

if [[ ! -d "$tree/.git" ]]; then
    git -C "$tree" init
fi
if ! git -C "$tree" cat-file -e "$pin^{commit}" 2>/dev/null; then
    git -C "$tree" fetch --depth=1 https://github.com/immortalwrt/immortalwrt.git "$pin"
fi
if [[ ! -f "$tree/.swrt-prepared" ]]; then
    git -C "$tree" checkout --force --detach "$pin"
    bash scripts/test-ota.sh
    for script in package/luci-app-swrt-advanced/root/www/luci-static/resources/{view/*,protocol}/*.js; do
        node --check "$script"
    done
    bash scripts/prepare.sh "$tree" 2>&1 | tee "$tree/prepare.log"
    touch "$tree/.swrt-prepared"
fi

make -C "$tree" download -j8 V=s 2>&1 | tee "$tree/download.log"
if ! make -C "$tree" -j"$jobs" V=s 2>&1 | tee "$tree/build.log"; then
    make -C "$tree" -j1 V=s 2>&1 | tee "$tree/build-retry.log"
fi
bash scripts/collect-artifacts.sh "$tree" "$out"
printf 'Verified release assets: %s\n' "$out"
