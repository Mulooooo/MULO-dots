#!/usr/bin/env bash

set -euo pipefail

RULE_FILE=/etc/udev/rules.d/61-hybrid-gpu-aliases.rules
INTEL_ALIAS=/dev/dri/intel-card
NVIDIA_ALIAS=/dev/dri/nvidia-card

if [[ ${EUID} -ne 0 ]]; then
    printf 'Run this script as root: sudo %s\n' "$0" >&2
    exit 1
fi

command -v udevadm >/dev/null || {
    printf 'udevadm is required.\n' >&2
    exit 1
}

tmp_rule=$(mktemp)
trap 'rm -f "$tmp_rule"' EXIT

printf '%s\n' \
    '# Stable DRM aliases for clement-m16-r2 hybrid graphics.' \
    '# PCI 00:02.0 = Intel Arc integrated GPU.' \
    '# PCI 01:00.0 = NVIDIA GeForce RTX 4070.' \
    '# Keep these aliases free of colons: AQ_DRM_DEVICES uses colon separators.' \
    'SUBSYSTEM=="drm", KERNEL=="card[0-9]", KERNELS=="0000:00:02.0", SYMLINK+="dri/intel-card"' \
    'SUBSYSTEM=="drm", KERNEL=="card[0-9]", KERNELS=="0000:01:00.0", SYMLINK+="dri/nvidia-card"' \
    >"$tmp_rule"

install -D -m 0644 "$tmp_rule" "$RULE_FILE"
udevadm control --reload-rules
udevadm trigger --subsystem-match=drm
udevadm settle

printf 'Installed %s\n' "$RULE_FILE"
for alias in "$INTEL_ALIAS" "$NVIDIA_ALIAS"; do
    if [[ -e "$alias" ]]; then
        printf '%s -> %s\n' "$alias" "$(readlink -f "$alias")"
    else
        printf 'Missing %s; reboot once for udev to recreate DRM devices.\n' "$alias" >&2
        exit 1
    fi
done
