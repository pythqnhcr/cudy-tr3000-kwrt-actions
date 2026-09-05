#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# OpenGirl / Kwrt 24.10-SNAPSHOT 固件构建脚本
# 适配 Cudy TR3000 v1 (mediatek/filogic)
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RELEASE="24.10-SNAPSHOT"
TARGET="mediatek/filogic"
PROFILE="cudy_tr3000-v1"
BASE_URL="https://downloads.openwrt.org/releases/${RELEASE}/targets/${TARGET}/"
PACKAGE_LIST="${SCRIPT_DIR}/pkglist-20260905.txt"
BUILD_LOG="${SCRIPT_DIR}/build.log"

echo "============================================"
echo "  OpenWrt Image Builder 下载"
echo "============================================"
echo ">> 版本: ${RELEASE}"
echo ">> 设备: ${PROFILE}"
echo ">> 源地址: ${BASE_URL}"

# ============================================================
# 1. 解析并下载 Image Builder
# ============================================================
echo ">> 解析 Image Builder 文件名..."
# 关键修复：扩展名从 .tar.xz 改为 .tar.zst
IB_FILE=$(curl -fsSL "${BASE_URL}" | grep -o 'openwrt-imagebuilder-[^"<>]*\.tar\.zst' | head -n1)

if [ -z "${IB_FILE}" ]; then
    echo "ERROR: 未找到 Image Builder 文件"
    echo ">> 尝试备用解析方式..."
    IB_FILE=$(curl -fsSL "${BASE_URL}sha256sums" 2>/dev/null | grep "imagebuilder.*\.tar\.zst" | awk '{print $2}' | head -n1)
    if [ -z "${IB_FILE}" ]; then
        echo "ERROR: 无法获取 Image Builder 文件名"
        exit 1
    fi
fi

echo ">> 找到文件: ${IB_FILE}"
echo ">> 下载中..."
curl -fL --retry 3 --retry-delay 5 -O "${BASE_URL}${IB_FILE}" || {
    echo "ERROR: 下载失败"
    exit 1
}

# 关键修复：使用 --zstd 解压
echo ">> 解压 Image Builder..."
tar --zstd -xf "${IB_FILE}" || {
    echo "ERROR: 解压失败，请确认系统已安装 zstd"
    echo ">> 安装命令: sudo apt-get install zstd"
    exit 1
}

IB_DIR="$(find . -maxdepth 1 -type d -name 'openwrt-imagebuilder-*' | head -n1)"
if [ -z "${IB_DIR}" ]; then
    echo "ERROR: 未找到 Image Builder 目录"
    exit 1
fi
cd "${IB_DIR}"
echo ">> 进入目录: $(pwd)"

# ============================================================
# 2. 添加 OpenGirl / openwrt.ai 的 feeds（关键步骤）
# ============================================================
echo "============================================"
echo "  添加第三方 feeds"
echo "============================================"

cp repositories.conf repositories.conf.bak

# 追加 openwrt.ai 的 feeds（OpenGirl/Kwrt 的包源）
# 注意：架构是 aarch64_cortex-a53（mediatek/filogic 的 MT7981/MT7986 芯片）
cat >> repositories.conf << 'EOF'

# OpenGirl / Kwrt / openwrt.ai feeds
src/gz openwrt_ai_base https://dl.openwrt.ai/releases/24.10/packages/aarch64_cortex-a53/base
src/gz openwrt_ai_packages https://dl.openwrt.ai/releases/24.10/packages/aarch64_cortex-a53/packages
src/gz openwrt_ai_luci https://dl.openwrt.ai/releases/24.10/packages/aarch64_cortex-a53/luci
src/gz openwrt_ai_routing https://dl.openwrt.ai/releases/24.10/packages/aarch64_cortex-a53/routing
src/gz openwrt_ai_kiddin9 https://dl.openwrt.ai/releases/24.10/packages/aarch64_cortex-a53/kiddin9
EOF

echo ">> Feeds 已更新"

# ============================================================
# 3. 构建固件
# ============================================================
echo "============================================"
echo "  开始构建固件"
echo "============================================"

# 读取包列表
if [ -f "${PACKAGE_LIST}" ]; then
    PACKAGES=$(awk '{print $1}' "${PACKAGE_LIST}" | tr '\n' ' ')
    echo ">> 包列表: ${PACKAGE_LIST}"
    echo ">> 包数量: $(echo ${PACKAGES} | wc -w)"
else
    echo ">> 未找到包列表，使用默认包"
    PACKAGES=""
fi

echo ">> 开始构建（日志: ${BUILD_LOG}）..."
set +e
make image \
    PROFILE="${PROFILE}" \
    PACKAGES="${PACKAGES}" \
    V=s 2>&1 | tee "${BUILD_LOG}"
BUILD_EXIT=$?
set -e

if [ ${BUILD_EXIT} -ne 0 ]; then
    echo ""
    echo "============================================"
    echo "  构建失败"
    echo "============================================"
    echo ">> 错误摘要:"
    grep -E "(ERROR|Error|failed|Cannot satisfy|not found)" "${BUILD_LOG}" | tail -20 || tail -n 30 "${BUILD_LOG}"
    
    echo ""
    echo ">> 常见解决方法:"
    echo "   1. 某些 kmod-* 内核模块与 Image Builder 内核版本不匹配，建议从包列表中移除所有 kmod-* 包"
    echo "   2. 检查 openwrt.ai feeds 是否可访问: curl -I https://dl.openwrt.ai/releases/24.10/packages/aarch64_cortex-a53/base/Packages.gz"
    echo "   3. 尝试最小包列表先验证: make image PROFILE='${PROFILE}' PACKAGES='luci-base'"
    exit 1
fi

# ============================================================
# 4. 输出结果
# ============================================================
echo "============================================"
echo "  构建成功！"
echo "============================================"

OUTPUT_DIR="bin/targets/${TARGET}/"
if [ -d "${OUTPUT_DIR}" ]; then
    echo ">> 产物目录: ${OUTPUT_DIR}"
    ls -lh "${OUTPUT_DIR}"*.bin 2>/dev/null || echo "   未找到 .bin 文件"
    ls -lh "${OUTPUT_DIR}"*.itb 2>/dev/null || true
else
    echo ">> 警告: 未找到输出目录"
fi

echo ">> 完成时间: $(date)"
