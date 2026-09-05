#!/usr/bin/env bash
set -euo pipefail

# 说明：为 Cudy TR3000 v1 构建 OpenGirl（Kwrt）固件
# 使用 dl.openwrt.ai 官方源，若源不可用则回退到官方 OpenWrt

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RELEASE="24.10"
TARGET="mediatek/filogic"
PROFILE="cudy_tr3000-v1"
KERNEL="6.6.118"   # 仅用于日志，不参与 URL

# 主源：OpenGirl（Kwrt）专用
BASE_URL="https://dl.openwrt.ai/releases/${RELEASE}/targets/${TARGET}/"
# 备用源：官方 OpenWrt（当主源失效时）
FALLBACK_URL="https://downloads.openwrt.org/releases/${RELEASE}/targets/${TARGET}/"

PACKAGE_LIST="${SCRIPT_DIR}/pkglist-20260905.txt"

# 1. 尝试从主源解析 Image Builder 文件名
echo ">> Trying OpenGirl source: ${BASE_URL}"
IB_FILE="$(curl -fsSL "${BASE_URL}" | grep -o 'openwrt-imagebuilder-[^"<>]*\.tar\.xz' | head -n1)"

if [ -z "${IB_FILE}" ]; then
    echo ">> No Image Builder found at ${BASE_URL}, trying fallback source..."
    BASE_URL="${FALLBACK_URL}"
    IB_FILE="$(curl -fsSL "${BASE_URL}" | grep -o 'openwrt-imagebuilder-[^"<>]*\.tar\.xz' | head -n1)"
fi

# 如果仍然没有，使用硬编码已知文件名（常见于官方24.10）
if [ -z "${IB_FILE}" ]; then
    echo ">> Could not parse filename, using hardcoded fallback."
    IB_FILE="openwrt-imagebuilder-${RELEASE}-mediatek-filogic.Linux-x86_64.tar.xz"
fi

echo ">> Downloading ${IB_FILE} from ${BASE_URL}"
curl -fL -O "${BASE_URL}${IB_FILE}" || {
    echo "ERROR: Failed to download ${IB_FILE}. Please check the URL manually."
    exit 1
}

tar -xJf "${IB_FILE}"
cd openwrt-imagebuilder-*

# 2. 生成可用的包列表（过滤掉 Image Builder 中不存在的包）
if [ -f "${PACKAGE_LIST}" ]; then
    echo ">> Generating package list from ${PACKAGE_LIST}"
    # 提取所有包名（第一列）
    ALL_PKGS="$(awk '{print $1}' "${PACKAGE_LIST}" | tr '\n' ' ')"
    
    # 生成 Image Builder 内部可用的包索引（只执行一次，快速）
    make package_index 2>/dev/null || true
    AVAILABLE_PKGS="$(find ./packages -name "Packages" -exec grep -h "^Package:" {} \; | awk '{print $2}' | sort -u)"

    # 过滤：只保留在可用列表中的包
    FILTERED_PKGS=""
    for pkg in ${ALL_PKGS}; do
        if echo "${AVAILABLE_PKGS}" | grep -qx "${pkg}"; then
            FILTERED_PKGS="${FILTERED_PKGS} ${pkg}"
        else
            echo ">> WARNING: Package '${pkg}' not found, skipping."
        fi
    done
    PACKAGES="${FILTERED_PKGS}"
else
    echo ">> No package list found, building with default packages."
    PACKAGES=""
fi

echo ">> Final packages: ${PACKAGES}"

# 3. 开始构建
echo ">> Building image for ${PROFILE} ..."
make image \
    PROFILE="${PROFILE}" \
    PACKAGES="${PACKAGES}" \
    FILES="${SCRIPT_DIR}/files" 2>/dev/null || {
        echo "ERROR: Build failed. Check logs above for missing dependencies."
        exit 1
    }

echo ">> Build succeeded! Images are in bin/targets/${TARGET}/"
ls -lh "bin/targets/${TARGET}/"*.bin 2>/dev/null || echo "No .bin files found."
