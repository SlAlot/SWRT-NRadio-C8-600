#!/usr/bin/env python3
import argparse
import hashlib
import json
import re
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PUBLIC_KEY = ROOT / "package/luci-app-swrt-advanced/root/usr/share/swrt/ota-public.pem"
REPOSITORY = "SlAlot/SWRT-NRadio-C8-600"
IMAGE = re.compile(
    r"immortalwrt-swrt-c8-600-((?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*))"
    r"-mediatek-filogic-nradio_wt9106-squashfs-sysupgrade\.itb"
)


def sign(image, key, openssl):
    match = IMAGE.fullmatch(image.name)
    if not match or not 0 < image.stat().st_size <= 100 * 1024**2:
        raise SystemExit("Expected a WT9106 SquashFS sysupgrade FIT of at most 100 MiB")
    with image.open("rb") as stream:
        checksum = hashlib.file_digest(stream, "sha256").hexdigest()
    sums = (image.parent / "SHA256SUMS").read_text().splitlines()
    if sums.count(f"{checksum}  ./{image.name}") != 1:
        raise SystemExit("Firmware does not match the build's SHA256SUMS")

    release = {
        "repository": REPOSITORY,
        "board": "nradio,wt9106",
        "layout": "spi-nand-128m-fit",
        "version": match[1],
        "name": image.name,
        "size": image.stat().st_size,
        "sha256": checksum,
    }
    with tempfile.TemporaryDirectory(dir=image.parent) as temporary:
        manifest = Path(temporary) / "ota.json"
        signature = manifest.with_suffix(".json.sig")
        manifest.write_bytes((json.dumps(release, indent=2) + "\n").encode("ascii"))
        subprocess.run([openssl, "pkeyutl", "-sign", "-rawin", "-inkey", key,
                        "-in", manifest, "-out", signature], check=True)
        subprocess.run([openssl, "pkeyutl", "-verify", "-rawin", "-pubin", "-inkey", PUBLIC_KEY,
                        "-in", manifest, "-sigfile", signature], check=True)
        manifest.replace(image.parent / manifest.name)
        signature.replace(image.parent / signature.name)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Sign a verified SWRT sysupgrade release")
    parser.add_argument("image", type=Path)
    parser.add_argument("--key", required=True, type=Path)
    parser.add_argument("--openssl", default="openssl")
    args = parser.parse_args()
    sign(args.image, args.key, args.openssl)
