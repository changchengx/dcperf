#!/bin/bash

set -euo pipefail

DEV_NAME="${1:-vda}"
ITERATIONS="${2:-16}"

if [[ ${EUID} -ne 0 ]]; then
  echo "ERROR: this script must be run as root because it writes to /sys." >&2
  exit 1
fi

if [[ ! "${ITERATIONS}" =~ ^[0-9]+$ ]] || [[ "${ITERATIONS}" -lt 1 ]]; then
  echo "ERROR: iterations must be a positive integer." >&2
  exit 1
fi

validate_block_device() {
  local dev_name="$1"
  local block_dev="/sys/block/${dev_name}"

  if [[ ! -e "${block_dev}" ]]; then
    echo "ERROR: block device ${dev_name} was not found at ${block_dev}." >&2
    exit 1
  fi

  local root_dev
  root_dev="$(findmnt -no SOURCE / || true)"
  if [[ "${root_dev}" == *"${dev_name}"* ]]; then
    echo "ERROR: ${dev_name} appears to back the root filesystem (${root_dev}); refusing to unbind it." >&2
    exit 1
  fi

  local mount_src
  while read -r mount_src _; do
    if [[ "${mount_src}" == "/dev/${dev_name}"* ]]; then
      echo "ERROR: ${mount_src} is mounted; refusing to unbind ${dev_name}." >&2
      exit 1
    fi
  done < /proc/mounts
}

validate_block_device "${DEV_NAME}"
BLOCK_DEV="/sys/block/${DEV_NAME}"

PCI_ADDR=""
# Sets the global PCI_ADDR to the parent PCI address of the given device path.
resolve_pci_addr() {
  local device_path="$1"
  local path base

  path="${device_path}"
  while [[ "${path}" != "/" ]]; do
    base="$(basename "${path}")"
    if [[ "${base}" =~ ^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]$ ]]; then
      PCI_ADDR="${base}"
      break
    fi
    path="$(dirname "${path}")"
  done

  if [[ -z "${PCI_ADDR}" ]]; then
    echo "ERROR: could not find a parent PCI address for ${device_path}." >&2
    exit 1
  fi
}

DEVICE_PATH="$(readlink -f "${BLOCK_DEV}/device")"
resolve_pci_addr "${DEVICE_PATH}"

PCI_DEV="/sys/bus/pci/devices/${PCI_ADDR}"
if [[ ! -e "${PCI_DEV}" ]]; then
  echo "ERROR: PCI device ${PCI_ADDR} was not found at ${PCI_DEV}." >&2
  exit 1
fi

if [[ ! -L "${PCI_DEV}/driver" ]]; then
  echo "ERROR: PCI device ${PCI_ADDR} is not currently bound to a driver." >&2
  exit 1
fi

DRIVER_PATH="$(readlink -f "${PCI_DEV}/driver")"
DRIVER_NAME="$(basename "${DRIVER_PATH}")"
UNBIND="${DRIVER_PATH}/unbind"
BIND="${DRIVER_PATH}/bind"

if [[ ! -w "${UNBIND}" || ! -w "${BIND}" ]]; then
  echo "ERROR: bind/unbind files are not writable for driver ${DRIVER_NAME}." >&2
  exit 1
fi

echo "block device : ${DEV_NAME}"
echo "device path  : ${DEVICE_PATH}"
echo "pci address  : ${PCI_ADDR}"
echo "pci driver   : ${DRIVER_NAME}"
echo "bind path    : ${BIND}"
echo "unbind path  : ${UNBIND}"
echo "iterations   : ${ITERATIONS}"

for ((i = 1; i <= ITERATIONS; i++)); do
  echo "${PCI_ADDR}" > "${UNBIND}"

  # Wait until the PCI device is detached from the driver before binding again.
  for _ in {1..50}; do
    [[ ! -L "${PCI_DEV}/driver" ]] && break
    sleep 0.1
  done

  echo "${PCI_ADDR}" > "${BIND}"

  # Wait until the block device has reappeared before the next cycle.
  for _ in {1..100}; do
    [[ -e "${BLOCK_DEV}" ]] && break
    sleep 0.1
  done

  if [[ ! -e "${BLOCK_DEV}" ]]; then
    echo "ERROR: ${DEV_NAME} did not reappear after bind at iteration ${i}." >&2
    exit 1
  fi

  printf 'completed %d/%d\n' "${i}" "${ITERATIONS}"
done

echo "done"
