#!/usr/bin/env bash
set -euo pipefail

project=$(cd "$(dirname "$0")/.." && pwd)
tree=$(realpath "${1:?Usage: collect-artifacts.sh IMMORTALWRT_TREE OUTPUT_DIR}")
output=$(realpath -m "${2:?Usage: collect-artifacts.sh IMMORTALWRT_TREE OUTPUT_DIR}")
release=$(sed -n "s/^SWRT_RELEASE='\([^']*\)'$/\1/p" "$project/files/etc/swrt-release")
test -n "$release"
python3 "$project/scripts/check-build.py" "$tree" --images "$output"
cp "$project/"{README.md,CHANGELOG.md,sources.lock.json} "$output/"
cp -a "$project/docs" "$output/"
git -C "$project" rev-parse HEAD > "$output/project.commit"
cd "$output"
tar -czf "$release-docs.tar.gz" README.md CHANGELOG.md docs/ sources.lock.json project.commit config.diff sysupgrade.metadata.json
sha256sum ./*.itb ./*.manifest ./*.tar.gz > SHA256SUMS
sha256sum -c SHA256SUMS
