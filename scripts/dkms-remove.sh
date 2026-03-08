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

    printf 'Provide the DKMS version to remove.\n' >&2
    exit 1
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

VERSION="$(sanitize_version "$(detect_version "${1:-}")")"
SOURCE_DIR="/usr/src/${PACKAGE_NAME}-${VERSION}"

if run_root dkms status -m "$PACKAGE_NAME" -v "$VERSION" >/dev/null 2>&1; then
    run_root dkms remove -m "$PACKAGE_NAME" -v "$VERSION" --all
else
    printf 'DKMS module %s/%s is not registered.\n' "$PACKAGE_NAME" "$VERSION"
fi

run_root rm -rf "$SOURCE_DIR"

printf 'Removed DKMS module %s/%s\n' "$PACKAGE_NAME" "$VERSION"
