#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
MODE="${1:-all}"
case "$MODE" in rootless|roothide|all) ;; *) echo 'Usage: scripts/build.sh [rootless|roothide|all]' >&2; exit 2;; esac
MAKE_BIN="${MAKE_BIN:-make}"
command -v "$MAKE_BIN" >/dev/null
command -v dpkg-deb >/dev/null
command -v python3 >/dev/null
command -v xcrun >/dev/null

build_one() (
    set -euo pipefail
    local scheme="$1" archs theos output packages
    output="$ROOT/dist/$scheme"
    packages="$ROOT/.build-packages/$scheme"
    if [[ "$scheme" == rootless ]]; then
        archs='arm64 arm64e'
        theos="${THEOS_ROOTLESS:-${THEOS:-$HOME/theos}}"
    else
        archs='arm64e'
        theos="${THEOS_ROOTHIDE:-${THEOS:-$HOME/theos-roothide}}"
    fi
    [[ -f "$theos/makefiles/common.mk" ]] || { echo "Missing $scheme Theos: $theos" >&2; exit 1; }
    mkdir -p "$output" "$packages"
    # Remove only this script's previous products, never unrelated package directories.
    rm -f "$output/"*.deb "$output/SHA256SUMS" "$output/build.log" "$output/verification.txt" "$packages/"*.deb
    export THEOS="$theos" THEOS_PACKAGE_SCHEME="$scheme" ARCHS="$archs"
    export DEBUG=0 FINALPACKAGE=1
    {
        echo "scheme=$scheme architectures=$archs target=${TARGET:-iphone:clang:16.5:15.0}"
        "$MAKE_BIN" clean THEOS_PACKAGE_DIR="$packages"
        # Keep collecting independent compiler diagnostics; make still fails
        # if any object/link/package target fails, before package verification.
        "$MAKE_BIN" -k package THEOS_PACKAGE_DIR="$packages" DEBUG=0 FINALPACKAGE=1
        shopt -s nullglob
        debs=("$packages/"*.deb)
        [[ ${#debs[@]} -eq 1 ]] || { echo "Expected one fresh deb, found ${#debs[@]}" >&2; exit 1; }
        python3 scripts/verify-package.py "${debs[0]}" "$scheme" | tee "$output/verification.txt"
        cp "${debs[0]}" "$output/"
        (cd "$output"; shasum -a 256 ./*.deb > SHA256SUMS)
    } 2>&1 | tee "$output/build.log"
)

status=0
if [[ "$MODE" == all ]]; then
    for scheme in rootless roothide; do
        if bash "$ROOT/scripts/build.sh" "$scheme"; then
            echo "$scheme: PASS"
        else
            echo "$scheme: FAIL (see dist/$scheme/build.log)" >&2
            status=1
        fi
    done
else
    build_one "$MODE"
fi
exit "$status"
