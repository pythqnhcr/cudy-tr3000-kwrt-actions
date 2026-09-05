#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RELEASE="24.10"
TARGET="mediatek/filogic"
PROFILE="cudy_tr3000-v1"
BASE_URL="https://mirrors.tuna.tsinghua.edu.cn/openwrt/releases/${RELEASE}/targets/${TARGET}/"
PACKAGE_LIST="${SCRIPT_DIR}/pkglist-20260905.txt"

# 直接指定 Image Builder 文件名（官方 24.10 版本通用）
IB_FILE="openwrt-imagebuilder-24.10-mediatek-filogic.Linux-x86_64.tar.xz"

echo "Downloading Image Builder from ${BASE_URL}${IB_FILE}"
curl -fL -O "${BASE_URL}${IB_FILE}"

tar -xJf "${IB_FILE}"

cd openwrt-imagebuilder-*

if [ -f "${PACKAGE_LIST}" ]; then
  PACKAGES="$(awk '{print $1}' "${PACKAGE_LIST}" | tr '\n' ' ')"
else
  PACKAGES=""
fi

make image \
  PROFILE="${PROFILE}" \
  PACKAGES="${PACKAGES}"

echo "Done. Images are in bin/targets/${TARGET}/"
