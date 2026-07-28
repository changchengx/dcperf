#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright(c) 2026 Liu, Changcheng <changcheng.liu@aliyun.com>

set -Eeuo pipefail

usage() {
    cat <<EOF
Usage:
  ${0##*/} BDF TIMEOUT_CODE
  ${0##*/} -d|--disable BDF
  ${0##*/} -h|--help

Set and enable the Completion Timeout used by a PCIe function for
non-posted requests that it originates.

The selected PCIe function must be a Root Port of a PCI Express Root
Complex.

Use --disable to disable the Completion Timeout without changing its
configured timeout value.

This does not control how long the selected function has to respond to
requests received from another PCIe function.

Arguments:
  BDF             PCI device address in [DOMAIN:]BUS:DEVICE.FUNCTION form.
  TIMEOUT_CODE    Hexadecimal PCIe Completion Timeout Value.

Options:
  -d, --disable   Disable the Completion Timeout.
  -h, --help      Show this help text.

Timeout codes:
  0  50 us to 50 ms (default range)
  1  50 us to 100 us
  2  1 ms to 10 ms
  5  16 ms to 55 ms
  6  65 ms to 210 ms
  9  260 ms to 900 ms
  a  1 s to 3.5 s
  d  4 s to 13 s
  e  17 s to 64 s

Codes other than 0 require the function to advertise support for the
corresponding timeout range. Hardware selects the actual timeout within
the indicated range.

The setting may be restored by a reboot, device reset, suspend/resume,
or driver recovery.

Examples:
  ${0##*/} 0000:3a:00.0 e
  ${0##*/} 3a:00.0 0x6
  ${0##*/} --disable 3a:00.0
EOF
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

usage_error() {
    printf 'error: %s\n\n' "$*" >&2
    usage >&2
    exit 2
}

DISABLE=0

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    -d|--disable)
        [[ $# -eq 2 ]] || usage_error "--disable requires BDF"
        DISABLE=1
        BDF="$2"
        ;;
    -*)
        usage_error "unknown option: $1"
        ;;
    *)
        [[ $# -eq 2 ]] || usage_error "BDF and TIMEOUT_CODE are required"
        if [[ $2 == -* ]]; then
            usage_error "unknown option: $2"
        fi
        BDF="$1"
        RAW_CODE="$2"
        ;;
esac

# Permit 3a:00.0 as shorthand for domain 0000.
if [[ $BDF =~ ^[[:xdigit:]]{2}:[01][[:xdigit:]]\.[0-7]$ ]]; then
    BDF="0000:$BDF"
fi

BDF="${BDF,,}"
[[ $BDF =~ ^[[:xdigit:]]{4}:[[:xdigit:]]{2}:[01][[:xdigit:]]\.[0-7]$ ]] ||
    usage_error "invalid PCI address: $BDF"

if (( ! DISABLE )); then
    RAW_CODE="${RAW_CODE#0x}"
    RAW_CODE="${RAW_CODE#0X}"
    [[ $RAW_CODE =~ ^[[:xdigit:]]{1,4}$ ]] ||
        usage_error "invalid timeout code: $RAW_CODE"

    CODE_VALUE=$((16#$RAW_CODE))

    case "$CODE_VALUE" in
        0)  DESCRIPTION="50 us to 50 ms";   REQUIRED_RANGE=0; RANGE_NAME="default" ;;
        1)  DESCRIPTION="50 us to 100 us";  REQUIRED_RANGE=1; RANGE_NAME="A" ;;
        2)  DESCRIPTION="1 ms to 10 ms";     REQUIRED_RANGE=1; RANGE_NAME="A" ;;
        5)  DESCRIPTION="16 ms to 55 ms";    REQUIRED_RANGE=2; RANGE_NAME="B" ;;
        6)  DESCRIPTION="65 ms to 210 ms";   REQUIRED_RANGE=2; RANGE_NAME="B" ;;
        9)  DESCRIPTION="260 ms to 900 ms";  REQUIRED_RANGE=4; RANGE_NAME="C" ;;
        10) DESCRIPTION="1 s to 3.5 s";       REQUIRED_RANGE=4; RANGE_NAME="C" ;;
        13) DESCRIPTION="4 s to 13 s";        REQUIRED_RANGE=8; RANGE_NAME="D" ;;
        14) DESCRIPTION="17 s to 64 s";       REQUIRED_RANGE=8; RANGE_NAME="D" ;;
        *)  usage_error \
                "reserved Completion Timeout code: $(printf '0x%x' "$CODE_VALUE")" ;;
    esac
fi

command -v setpci >/dev/null ||
    die "'setpci' is required; install pciutils"

if (( EUID == 0 )); then
    SUDO=()
else
    command -v sudo >/dev/null || die "run as root or install sudo"
    SUDO=(sudo)
    "${SUDO[@]}" -v || die "could not acquire root privileges"
fi

read_config() {
    "${SUDO[@]}" setpci -r -s "$BDF" "$1"
}

check_pcie_root_port() {
    local pcie_cap=$1
    local device_port_type=$(((pcie_cap >> 4) & 0x0f))

    (( device_port_type == 0x4 )) ||
        die "$BDF is not a Root Port of a PCI Express Root Complex"
}

list_supported_timeout_codes() {
    local supported_ranges=$1
    local allowed_values="0x0"

    (( supported_ranges & 0x1 )) && allowed_values+=", 0x1, 0x2"
    (( supported_ranges & 0x2 )) && allowed_values+=", 0x5, 0x6"
    (( supported_ranges & 0x4 )) && allowed_values+=", 0x9, 0xa"
    (( supported_ranges & 0x8 )) && allowed_values+=", 0xd, 0xe"

    printf '%s\n' "$allowed_values"
}

# Confirm the PCI Express capability exists and is version 2 or newer.
if ! PCIE_CAP_HEX=$(read_config CAP_EXP+02.w); then
    die "$BDF is absent or has no PCI Express capability"
fi

[[ $PCIE_CAP_HEX =~ ^[[:xdigit:]]{4}$ ]] ||
    die "unexpected PCIe capability value: $PCIE_CAP_HEX"

PCIE_CAP=$((16#$PCIE_CAP_HEX))
PCIE_VERSION=$((PCIE_CAP & 0x0f))

check_pcie_root_port "$PCIE_CAP"

(( PCIE_VERSION >= 2 )) ||
    die "$BDF has PCIe capability version $PCIE_VERSION; DevCtl2 is unavailable"

# DevCap2 is at PCIe capability offset 0x24.
if ! DEVCAP2_HEX=$(read_config CAP_EXP+24.l); then
    die "failed to read DevCap2 from $BDF"
fi

[[ $DEVCAP2_HEX =~ ^[[:xdigit:]]{8}$ ]] ||
    die "unexpected DevCap2 value from $BDF: $DEVCAP2_HEX"

DEVCAP2=$((16#$DEVCAP2_HEX))
SUPPORTED_RANGES=$((DEVCAP2 & 0x0f))
DISABLE_SUPPORTED=$((DEVCAP2 & 0x10))

case "$SUPPORTED_RANGES" in
    0|1|2|3|6|7|14|15)
        ;;
    *)
        die "DevCap2 contains reserved Completion Timeout range encoding: \
$(printf '0x%x' "$SUPPORTED_RANGES")"
        ;;
esac

if (( DISABLE && ! DISABLE_SUPPORTED )); then
    die "$BDF does not support disabling the Completion Timeout"
fi

if (( ! DISABLE && REQUIRED_RANGE != 0 &&
      (SUPPORTED_RANGES & REQUIRED_RANGE) == 0 )); then
    die "code $(printf '0x%x' "$CODE_VALUE") requires Range $RANGE_NAME; \
DevCap2 range mask is $(printf '0x%x' "$SUPPORTED_RANGES"); allowed values: \
$(list_supported_timeout_codes "$SUPPORTED_RANGES")"
fi

# DevCtl2 is at PCIe capability offset 0x28.
if ! BEFORE_HEX=$(read_config CAP_EXP+28.w); then
    die "failed to read DevCtl2 from $BDF"
fi

[[ $BEFORE_HEX =~ ^[[:xdigit:]]{4}$ ]] ||
    die "unexpected DevCtl2 value from $BDF: $BEFORE_HEX"

BEFORE=$((16#$BEFORE_HEX))

# Disable mode updates only bit 4, preserving the configured timeout value.
# Enable mode updates bits 3:0 and clears bit 4. All other DevCtl2 bits remain
# unchanged.
if (( DISABLE )); then
    WRITE_VALUE=0x0010
    WRITE_MASK=0x0010
else
    WRITE_VALUE=$CODE_VALUE
    WRITE_MASK=0x001f
fi
WRITE_OPERATION=$(printf 'CAP_EXP+28.w=%04x:%04x' \
    "$WRITE_VALUE" "$WRITE_MASK")

if (( (BEFORE & WRITE_MASK) != WRITE_VALUE )); then
    if ! "${SUDO[@]}" setpci -r -s "$BDF" "$WRITE_OPERATION"; then
        die "failed to write DevCtl2 for $BDF"
    fi
fi

if ! AFTER_HEX=$(read_config CAP_EXP+28.w); then
    die "failed to read back DevCtl2 from $BDF"
fi

[[ $AFTER_HEX =~ ^[[:xdigit:]]{4}$ ]] ||
    die "unexpected DevCtl2 readback from $BDF: $AFTER_HEX"

AFTER=$((16#$AFTER_HEX))

if (( (AFTER & WRITE_MASK) != WRITE_VALUE )); then
    die "verification failed: DevCtl2 read back as 0x$AFTER_HEX"
fi

printf '%s DevCtl2: 0x%s -> 0x%s\n' "$BDF" "$BEFORE_HEX" "$AFTER_HEX"
if (( DISABLE )); then
    printf 'Completion Timeout: disabled\n'
else
    printf 'Completion Timeout: %s, enabled\n' "$DESCRIPTION"
fi

if command -v lspci >/dev/null; then
    if ! "${SUDO[@]}" lspci -D -s "$BDF" -vv |
         grep -E 'DevCap2:|DevCtl2:'; then
        printf 'warning: lspci summary is unavailable for %s\n' "$BDF" >&2
    fi
fi
