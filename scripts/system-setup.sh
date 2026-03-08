#!/usr/bin/env bash
set -euo pipefail

MODNAME="linuwu_sense"
GROUP_NAME="${MODNAME}"
SERVICE_NAME="${MODNAME}.service"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

BLACKLIST_FILE="/etc/modprobe.d/blacklist-acer_wmi.conf"
MODULES_LOAD_FILE="/etc/modules-load.d/${MODNAME}.conf"
SYSTEMD_SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"
TMPFILES_FILE="/etc/tmpfiles.d/${MODNAME}.conf"
SYSFS_BASE="/sys/module/${MODNAME}/drivers/platform:acer-wmi/acer-wmi"

run_root() {
    if [[ ${EUID} -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

real_user() {
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
        printf '%s\n' "$SUDO_USER"
    else
        id -un
    fi
}

install_generated_file() {
    local path="$1"
    local mode="$2"
    local content="$3"
    local tmp_file

    tmp_file="$(mktemp)"
    chmod 600 "$tmp_file"
    printf '%s' "$content" > "$tmp_file"
    run_root install -Dm"$mode" "$tmp_file" "$path"
    rm -f "$tmp_file"
}

write_tmpfiles_config() {
    local tmp_file
    local model_path=""
    local supported_fields=(
        backlight_timeout
        battery_calibration
        battery_limiter
        boot_animation_sound
        fan_speed
        lcd_override
        usb_charging
    )
    local kb_fields=(
        four_zone_mode
        per_zone_mode
    )

    tmp_file="$(mktemp)"

    if [[ -d "${SYSFS_BASE}/predator_sense" ]]; then
        model_path="predator_sense"
    elif [[ -d "${SYSFS_BASE}/nitro_sense" ]]; then
        model_path="nitro_sense"
    fi

    if [[ -n "$model_path" ]]; then
        for field in "${supported_fields[@]}"; do
            if [[ -e "${SYSFS_BASE}/${model_path}/${field}" ]]; then
                printf 'f %s/%s/%s 0660 root %s\n' \
                    "$SYSFS_BASE" "$model_path" "$field" "$GROUP_NAME" >> "$tmp_file"
            fi
        done
    else
        printf 'Warning: Could not detect predator_sense or nitro_sense in sysfs.\n' >&2
    fi

    if [[ -d "${SYSFS_BASE}/four_zoned_kb" ]]; then
        for field in "${kb_fields[@]}"; do
            if [[ -e "${SYSFS_BASE}/four_zoned_kb/${field}" ]]; then
                printf 'f %s/four_zoned_kb/%s 0660 root %s\n' \
                    "$SYSFS_BASE" "$field" "$GROUP_NAME" >> "$tmp_file"
            fi
        done
    fi

    run_root install -Dm644 "$tmp_file" "$TMPFILES_FILE"
    rm -f "$tmp_file"

    run_root systemd-tmpfiles --create "$TMPFILES_FILE"
}

install_setup() {
    local user_name

    user_name="$(real_user)"
    if [[ "$user_name" == "root" ]]; then
        printf 'Warning: running as root, no user added to %s group\n' "$GROUP_NAME" >&2
    fi

    install_generated_file "$BLACKLIST_FILE" 644 $'blacklist acer_wmi\n'
    install_generated_file "$MODULES_LOAD_FILE" 644 "${MODNAME}"$'\n'
    run_root install -Dm644 "${REPO_ROOT}/${SERVICE_NAME}" "$SYSTEMD_SERVICE_FILE"

    if ! getent group "$GROUP_NAME" >/dev/null; then
        run_root groupadd "$GROUP_NAME"
    fi

    if [[ "$user_name" != "root" ]]; then
        run_root usermod -aG "$GROUP_NAME" "$user_name"
    fi

    run_root modprobe -r acer_wmi || true
    run_root modprobe "$MODNAME"
    write_tmpfiles_config

    run_root systemctl daemon-reload
    run_root systemctl enable "$SERVICE_NAME"
    run_root systemctl start "$SERVICE_NAME"

    printf 'Configured system integration for %s\n' "$MODNAME"
}

uninstall_setup() {
    local user_name

    user_name="$(real_user)"
    if [[ "$user_name" == "root" ]]; then
        printf 'Warning: running as root, no user added to %s group\n' "$GROUP_NAME" >&2
    fi

    run_root systemctl stop "$SERVICE_NAME" || true
    run_root systemctl disable "$SERVICE_NAME" || true
    run_root rm -f "$SYSTEMD_SERVICE_FILE"
    run_root systemctl daemon-reload

    run_root rm -f "$BLACKLIST_FILE" "$MODULES_LOAD_FILE" "$TMPFILES_FILE"

    run_root modprobe -r "$MODNAME" || true
    run_root modprobe acer_wmi || true

    if getent group "$GROUP_NAME" >/dev/null; then
        if [[ "$user_name" != "root" ]]; then
            run_root gpasswd -d "$user_name" "$GROUP_NAME" || true
        fi
        run_root groupdel "$GROUP_NAME" || true
    fi

    printf 'Removed system integration for %s\n' "$MODNAME"
}

case "${1:-}" in
    install)
        install_setup
        ;;
    uninstall)
        uninstall_setup
        ;;
    *)
        printf 'Usage: %s install|uninstall\n' "$0" >&2
        exit 1
        ;;
esac
