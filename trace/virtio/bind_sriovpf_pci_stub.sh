#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -Eeuo pipefail

TARGET_DRIVER="pci-pf-stub"
PCI_BUS_PATH="/sys/bus/pci"

usage() {
    cat <<EOF
Usage:
  ${0##*/} BDF SRIOV_VFS
  ${0##*/} -h|--help

Bind an SR-IOV Physical Function to pci-pf-stub and configure its
number of Virtual Functions.

Arguments:
  BDF          PCI address in [DOMAIN:]BUS:DEVICE.FUNCTION form.
  SRIOV_VFS    Number of VFs to enable; use 0 to disable all VFs.

Examples:
  sudo ${0##*/} 0000:3d:00.0 64
  sudo ${0##*/} 3d:00.0 16
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

case "${1:-}" in
    -h|--help)
        [[ $# -eq 1 ]] || usage_error "--help does not accept arguments"
        usage
        exit 0
        ;;
esac

[[ $# -eq 2 ]] || usage_error "BDF and SRIOV_VFS are required"

BDF="$1"
VF_COUNT_RAW="$2"

# Permit 3d:00.0 as shorthand for domain 0000.
if [[ $BDF =~ ^[[:xdigit:]]{2}:[01][[:xdigit:]]\.[0-7]$ ]]; then
    BDF="0000:$BDF"
fi

BDF="${BDF,,}"
[[ $BDF =~ ^[[:xdigit:]]{4}:[[:xdigit:]]{2}:[01][[:xdigit:]]\.[0-7]$ ]] ||
    usage_error "invalid PCI address: $BDF"

[[ $VF_COUNT_RAW =~ ^[0-9]+$ ]] ||
    usage_error "SRIOV_VFS must be a non-negative integer: $VF_COUNT_RAW"
VF_COUNT=$((10#$VF_COUNT_RAW))

(( EUID == 0 )) || die "this script must be run as root"

PCI_DEVICE="$PCI_BUS_PATH/devices/$BDF"
[[ -d $PCI_DEVICE ]] || die "PCI device $BDF does not exist"

TOTAL_VFS_PATH="$PCI_DEVICE/sriov_totalvfs"
NUM_VFS_PATH="$PCI_DEVICE/sriov_numvfs"
AUTOPROBE_PATH="$PCI_DEVICE/sriov_drivers_autoprobe"
DRIVER_OVERRIDE_PATH="$PCI_DEVICE/driver_override"

[[ -r $TOTAL_VFS_PATH && -w $NUM_VFS_PATH ]] ||
    die "$BDF is not an SR-IOV Physical Function"
[[ -w $AUTOPROBE_PATH ]] ||
    die "$BDF does not provide writable sriov_drivers_autoprobe"
[[ -w $DRIVER_OVERRIDE_PATH ]] ||
    die "$BDF does not provide writable driver_override"

TOTAL_VFS_RAW=$(<"$TOTAL_VFS_PATH")
[[ $TOTAL_VFS_RAW =~ ^[0-9]+$ ]] ||
    die "unexpected sriov_totalvfs value for $BDF: $TOTAL_VFS_RAW"
TOTAL_VFS=$((10#$TOTAL_VFS_RAW))

(( TOTAL_VFS > 0 )) || die "$BDF does not support any VFs"
(( VF_COUNT <= TOTAL_VFS )) ||
    die "requested $VF_COUNT VFs, but $BDF supports 0 through $TOTAL_VFS"

command -v modprobe >/dev/null || die "'modprobe' is required"
modprobe "$TARGET_DRIVER" || die "failed to load $TARGET_DRIVER"

TARGET_DRIVER_PATH="$PCI_BUS_PATH/drivers/$TARGET_DRIVER"
[[ -d $TARGET_DRIVER_PATH ]] ||
    die "$TARGET_DRIVER is unavailable after loading the driver"
[[ -w $TARGET_DRIVER_PATH/bind ]] ||
    die "$TARGET_DRIVER_PATH/bind is not writable"

write_sysfs() {
    local value=$1
    local path=$2

    printf '%s\n' "$value" >"$path" ||
        die "failed to write '$value' to $path"
}

get_current_driver() {
    local driver_path

    if [[ ! -L $PCI_DEVICE/driver ]]; then
        return
    fi

    driver_path=$(readlink -f "$PCI_DEVICE/driver") ||
        die "failed to resolve the current driver for $BDF"
    printf '%s\n' "${driver_path##*/}"
}

CURRENT_DRIVER=$(get_current_driver)
CURRENT_VFS_RAW=$(<"$NUM_VFS_PATH")
[[ $CURRENT_VFS_RAW =~ ^[0-9]+$ ]] ||
    die "unexpected sriov_numvfs value for $BDF: $CURRENT_VFS_RAW"
CURRENT_VFS=$((10#$CURRENT_VFS_RAW))

if [[ $CURRENT_DRIVER != "$TARGET_DRIVER" ]]; then
    # VFs must be disabled before changing the PF driver.
    if (( CURRENT_VFS != 0 )); then
        write_sysfs 0 "$NUM_VFS_PATH"
        CURRENT_VFS=0
    fi

    write_sysfs "$TARGET_DRIVER" "$DRIVER_OVERRIDE_PATH"

    if [[ -n $CURRENT_DRIVER ]]; then
        [[ -w $PCI_DEVICE/driver/unbind ]] ||
            die "the unbind file for driver $CURRENT_DRIVER is not writable"
        write_sysfs "$BDF" "$PCI_DEVICE/driver/unbind"
    fi

    write_sysfs "$BDF" "$TARGET_DRIVER_PATH/bind"

    CURRENT_DRIVER=$(get_current_driver)
    [[ $CURRENT_DRIVER == "$TARGET_DRIVER" ]] ||
        die "failed to bind $BDF to $TARGET_DRIVER"

    # The override was needed only for this bind operation.
    write_sysfs "" "$DRIVER_OVERRIDE_PATH"
fi

# Prevent the enabled VFs from being automatically attached to host drivers.
write_sysfs 0 "$AUTOPROBE_PATH"

if (( CURRENT_VFS != VF_COUNT )); then
    if (( CURRENT_VFS != 0 )); then
        write_sysfs 0 "$NUM_VFS_PATH"
    fi
    if (( VF_COUNT != 0 )); then
        write_sysfs "$VF_COUNT" "$NUM_VFS_PATH"
    fi
fi

ACTUAL_VFS_RAW=$(<"$NUM_VFS_PATH")
[[ $ACTUAL_VFS_RAW =~ ^[0-9]+$ ]] ||
    die "unexpected sriov_numvfs readback for $BDF: $ACTUAL_VFS_RAW"
ACTUAL_VFS=$((10#$ACTUAL_VFS_RAW))
(( ACTUAL_VFS == VF_COUNT )) ||
    die "requested $VF_COUNT VFs, but sriov_numvfs read back as $ACTUAL_VFS"

AUTOPROBE_RAW=$(<"$AUTOPROBE_PATH")
[[ $AUTOPROBE_RAW == 0 ]] ||
    die "sriov_drivers_autoprobe read back as '$AUTOPROBE_RAW' instead of 0"

VF_LINKS=()
for VF_LINK in "$PCI_DEVICE"/virtfn*; do
    [[ -L $VF_LINK ]] || continue
    VF_LINKS+=("$VF_LINK")
done

(( ${#VF_LINKS[@]} == VF_COUNT )) ||
    die "requested $VF_COUNT VFs, but found ${#VF_LINKS[@]} virtfn links"

for VF_LINK in "${VF_LINKS[@]}"; do
    VF_DEVICE=$(readlink -f "$VF_LINK") ||
        die "failed to resolve VF link $VF_LINK"
    VF_BDF=${VF_DEVICE##*/}

    if [[ -L $VF_DEVICE/driver ]]; then
        VF_DRIVER_PATH=$(readlink -f "$VF_DEVICE/driver") ||
            die "failed to resolve the driver for VF $VF_BDF"
        die "VF $VF_BDF is bound to driver ${VF_DRIVER_PATH##*/}"
    fi
done

printf 'PCI device: %s\n' "$BDF"
printf 'PF driver:  %s\n' "$TARGET_DRIVER"
printf 'SR-IOV VFs: %d of %d\n' "$ACTUAL_VFS" "$TOTAL_VFS"
printf 'VF drivers: unbound\n'
