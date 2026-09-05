#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RELEASE="24.10"
TARGET="mediatek/filogic"
PROFILE="cudy_tr3000-v1"
# 正确路径：去掉重复的 ${RELEASE}/targets/${TARGET}
BASE_URL="https://mirrors.tuna.tsinghua.edu.cn/openwrt/releases/${RELEASE}/targets/${TARGET}/"
PACKAGE_LIST="${SCRIPT_DIR}/pkglist-20260905.txt"

echo "Downloading Image Builder index from ${BASE_URL}"

# 尝试从目录列表解析文件名
IB_FILE="$(
  curl -fsSL "${BASE_URL}" \
  | grep -o 'openwrt-imagebuilder-[^"<>"]*\.tar\.xz' \
  | head -n 1
)"

if [ -z "${IB_FILE}" ]; then
  echo "Could not find via grep, using fallback filename."
  # 常见的两个候选（根据官方源命名）
  # 候选1：带 Linux-x86_64
  IB_FILE="openwrt-imagebuilder-24.10-mediatek-filogic.Linux-x86_64.tar.xz"
  # 如果候选1失败，可以尝试候选2（不带架构后缀）
  # IB_FILE="openwrt-imagebuilder-24.10-mediatek-filogic.tar.xz"
fi

echo "Downloading ${IB_FILE}"
curl -fL -O "${BASE_URL}${IB_FILE}" || {
  echo "Download failed! Please manually verify the filename at ${BASE_URL}"
  echo "You can list available files with: curl -fsSL ${BASE_URL} | grep -o 'openwrt-imagebuilder[^\"]*\.tar\.xz'"
  exit 1
}

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
