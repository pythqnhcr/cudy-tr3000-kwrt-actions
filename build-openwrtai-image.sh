#!/usr/bin/env bash
set -euo pipefail

# Run this on a Linux x86_64 machine with internet access.
# It downloads the matching openwrt.ai Image Builder and tries to build a
# sysupgrade image for the Cudy TR3000 v1.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RELEASE="24.10"
KERNEL="6.6.118"
TARGET="mediatek/filogic"
PROFILE="cudy_tr3000-v1"
BASE_URL="https://dl.openwrt.ai/releases/${RELEASE}/targets/${TARGET}/${KERNEL}"
PACKAGE_LIST="${SCRIPT_DIR}/pkglist-20260905.txt"

echo "Downloading Image Builder index: ${BASE_URL}/"
IB_FILE="$(
  curl -fsSL "${BASE_URL}/" \
  | grep -o 'openwrt-imagebuilder-[^"<>]*\.tar\.xz' \
  | head -n 1
)"

if [ -z "${IB_FILE}" ]; then
  echo "Could not find an Image Builder archive in ${BASE_URL}/"
  exit 1
fi

echo "Downloading ${IB_FILE}"
curl -fL -O "${BASE_URL}/${IB_FILE}"
tar -xJf "${IB_FILE}"

cd openwrt-imagebuilder-*

if [ -f "${PACKAGE_LIST}" ]; then
  PACKAGES="$(awk '{print $1}' "${PACKAGE_LIST}" | tr '\n' ' ')"
else
  PACKAGES=""
fi

# If a package name is unavailable in this Image Builder feed, remove it from
# pkglist-20260905.txt or add the matching feed, then rerun.
make image \
  PROFILE="${PROFILE}" \
  PACKAGES="${PACKAGES}"

echo "Done. Images are in bin/targets/${TARGET}/"
