#!/usr/bin/env bash
set -euo pipefail

PACKAGE_NAME="linuwu_sense"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

detect_version() {
    if [[ $# -gt 0 && -n "$1" ]]; then
        printf '%s\n' "$1"
        return
    fi

    if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git -C "$REPO_ROOT" describe --tags --always --dirty 2>/dev/null
        return
    fi

    date -u +%Y%m%d%H%M%S
}

sanitize_version() {
    local version="$1"

    version="${version// /_}"
    version="${version//\//-}"
    printf '%s\n' "${version//[^A-Za-z0-9._+-]/_}"
}

run_root() {
    if [[ ${EUID} -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

build_source_tree() {
    local stage_dir="$1"
    local version="$2"

    mkdir -p "$stage_dir"

    tar \
        --exclude=.git \
        --exclude=.zed \
        --exclude=.tmp_versions \
        --exclude='*.o' \
        --exclude='*.ko' \
        --exclude='*.mod' \
        --exclude='*.mod.c' \
        --exclude='*.mod.o' \
        --exclude='*.cmd' \
        --exclude='Module.symvers' \
        --exclude='modules.order' \
        -C "$REPO_ROOT" -cf - . | tar -C "$stage_dir" -xf -

    sed "s/@PACKAGE_VERSION@/${version}/g" \
        "$REPO_ROOT/dkms.conf.in" > "${stage_dir}/dkms.conf"
}

VERSION="$(sanitize_version "$(detect_version "${1:-}")")"
SOURCE_DIR="/usr/src/${PACKAGE_NAME}-${VERSION}"
TMP_DIR="$(mktemp -d)"
STAGE_DIR="${TMP_DIR}/source"

trap 'rm -rf "$TMP_DIR"' EXIT

build_source_tree "$STAGE_DIR" "$VERSION"

if run_root dkms status -m "$PACKAGE_NAME" -v "$VERSION" 2>/dev/null | grep -q "$PACKAGE_NAME"; then
    run_root dkms remove -m "$PACKAGE_NAME" -v "$VERSION" --all || true
fi

run_root rm -rf "$SOURCE_DIR"
run_root install -d "$SOURCE_DIR"
run_root cp -a "${STAGE_DIR}/." "$SOURCE_DIR/"

run_root dkms add -m "$PACKAGE_NAME" -v "$VERSION"
run_root dkms build -m "$PACKAGE_NAME" -v "$VERSION"
run_root dkms install -m "$PACKAGE_NAME" -v "$VERSION"

printf 'Installed DKMS module %s/%s\n' "$PACKAGE_NAME" "$VERSION"
