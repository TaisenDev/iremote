#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${THEOS:?Set THEOS to your Theos installation}"
work="$(mktemp -d -t iremote.XXXXXXXX)"
trap 'rm -rf -- "$work"' EXIT
cp -r "$root"/{Makefile,control,Resources,Sources} "$work/"
make -C "$work" package FINALPACKAGE=1
mkdir -p "$root/../dist/ios"
cp "$work"/packages/*.deb "$root/../dist/ios/"
