#!/usr/bin/env bash
set -euo pipefail

sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends build-essential clang flex bison gawk gcc-multilib g++-multilib \
    gettext git libncurses-dev libssl-dev python3 python3-setuptools python3-pyelftools \
    rsync swig unzip zlib1g-dev file wget curl ccache cmake ninja-build \
    libelf-dev libfuse-dev libglib2.0-dev libgmp3-dev libmpc-dev libmpfr-dev \
    libreadline-dev libtool autoconf automake autopoint pkgconf subversion \
    device-tree-compiler xsltproc libxml-parser-perl patch tar xz-utils zstd jq ca-certificates nodejs
