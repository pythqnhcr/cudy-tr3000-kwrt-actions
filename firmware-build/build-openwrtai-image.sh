#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# OpenGirl / Kwrt 24.10-SNAPSHOT 固件构建脚本
# 适配: Cudy TR3000 v1 (mediatek/filogic, aarch64_cortex-a53)
# 内核: 6.6.118
# 作者: FirmwareSister (OpenGirl)
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RELEASE="24.10-SNAPSHOT"
TARGET="mediatek/filogic"
PROFILE="cudy_tr3000-v1"
BASE_URL="https://downloads.openwrt.org/releases/${RELEASE}/targets/${TARGET}/"
PACKAGE_LIST="${SCRIPT_DIR}/pkglist-20260905.txt"
BUILD_LOG="${SCRIPT_DIR}/build.log"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "============================================"
echo "  OpenWrt Image Builder 下载与构建"
echo "============================================"
echo ">> 版本: ${RELEASE}"
echo ">> 设备: ${PROFILE}"
echo ">> 目标: ${TARGET}"
echo ">> 源地址: ${BASE_URL}"
echo ""

# ============================================================
# 0. 环境检查
# ============================================================
echo ">> 检查依赖..."
for cmd in curl tar zstd awk grep sed; do
    if ! command -v "$cmd" &> /dev/null; then
        echo -e "${RED}ERROR: 未找到命令: $cmd${NC}"
        if [ "$cmd" = "zstd" ]; then
            echo ">> 安装命令: sudo apt-get update && sudo apt-get install -y zstd"
        fi
        exit 1
    fi
done
echo -e "${GREEN}>> 环境检查通过${NC}"

# ============================================================
# 1. 解析并下载 Image Builder
# ============================================================
echo ""
echo "============================================"
echo "  步骤 1: 下载 Image Builder"
echo "============================================"

echo ">> 解析 Image Builder 文件名..."
IB_FILE=$(curl -fsSL "${BASE_URL}" | grep -o 'openwrt-imagebuilder-[^"<>]*\.tar\.zst' | head -n1)

if [ -z "${IB_FILE}" ]; then
    echo ">> 主页面解析失败，尝试从 sha256sums 获取..."
    IB_FILE=$(curl -fsSL "${BASE_URL}sha256sums" 2>/dev/null | grep "imagebuilder.*\.tar\.zst" | awk '{print $2}' | head -n1)
fi

if [ -z "${IB_FILE}" ]; then
    echo -e "${RED}ERROR: 无法获取 Image Builder 文件名${NC}"
    exit 1
fi

echo -e "${GREEN}>> 找到文件: ${IB_FILE}${NC}"

if [ -s "${IB_FILE}" ]; then
    echo ">> 文件已存在，跳过下载"
else
    echo ">> 下载中..."
    curl -fL --progress-bar --retry 3 --retry-delay 5 -O "${BASE_URL}${IB_FILE}" || {
        echo -e "${RED}ERROR: 下载失败${NC}"
        exit 1
    }
fi

echo ">> 解压 Image Builder..."
tar --zstd -xf "${IB_FILE}" || {
    echo -e "${RED}ERROR: 解压失败${NC}"
    exit 1
}

IB_DIR="$(find . -maxdepth 1 -type d -name 'openwrt-imagebuilder-*' | head -n1)"
if [ -z "${IB_DIR}" ]; then
    echo -e "${RED}ERROR: 未找到 Image Builder 目录${NC}"
    exit 1
fi

cd "${IB_DIR}"
echo -e "${GREEN}>> 进入目录: $(pwd)${NC}"

# ============================================================
# 2. 添加 OpenGirl / openwrt.ai 的 feeds
# ============================================================
echo ""
echo "============================================"
echo "  步骤 2: 配置 Feeds"
echo "============================================"

cp repositories.conf repositories.conf.bak

echo ">> 添加 openwrt.ai feeds..."

cat >> repositories.conf << 'EOF'

# OpenGirl / Kwrt / openwrt.ai feeds (aarch64_cortex-a53)
src/gz openwrt_ai_base https://dl.openwrt.ai/releases/24.10/packages/aarch64_cortex-a53/base
src/gz openwrt_ai_packages https://dl.openwrt.ai/releases/24.10/packages/aarch64_cortex-a53/packages
src/gz openwrt_ai_luci https://dl.openwrt.ai/releases/24.10/packages/aarch64_cortex-a53/luci
src/gz openwrt_ai_routing https://dl.openwrt.ai/releases/24.10/packages/aarch64_cortex-a53/routing
src/gz openwrt_ai_kiddin9 https://dl.openwrt.ai/releases/24.10/packages/aarch64_cortex-a53/kiddin9
EOF

# ============================================================
# 关键修复：三重防护彻底禁用签名检查
# ============================================================
echo ">> 禁用签名检查..."

# 防护1: 删除 repositories.conf 中的签名检查选项
sed -i '/option check_signature/d' repositories.conf

# 防护2: 清理 keys 目录中的官方公钥
if [ -d "keys" ]; then
    rm -f keys/*.gpg keys/*.asc 2>/dev/null || true
    echo ">> 已清理 keys 目录"
fi

# 防护3: 设置环境变量
export IGNORE_SIGNATURES=1

echo -e "${GREEN}>> Feeds 配置完成（签名检查已禁用）${NC}"

# ============================================================
# 3. 处理包列表
# ============================================================
echo ""
echo "============================================"
echo "  步骤 3: 处理包列表"
echo "============================================"

PACKAGES=""

if [ -f "${PACKAGE_LIST}" ]; then
    echo ">> 读取包列表: ${PACKAGE_LIST}"
    
    # 过滤掉 kmod-* 内核模块、空行、注释行
    FILTERED_PKGS=$(grep -v '^\s*$' "${PACKAGE_LIST}" | grep -v '^#' | grep -v '^kmod-' | tr '\n' ' ')
    
    KMOD_COUNT=$(grep -c '^kmod-' "${PACKAGE_LIST}" 2>/dev/null || echo "0")
    TOTAL_COUNT=$(grep -v '^\s*$' "${PACKAGE_LIST}" | grep -v '^#' | wc -l)
    FINAL_COUNT=$(echo "${FILTERED_PKGS}" | wc -w)
    
    echo ">> 原始包数: ${TOTAL_COUNT}"
    if [ "${KMOD_COUNT}" -gt 0 ]; then
        echo -e "${YELLOW}>> 已自动过滤 ${KMOD_COUNT} 个 kmod-* 内核模块${NC}"
    fi
    echo ">> 有效包数: ${FINAL_COUNT}"
    
    PACKAGES="${FILTERED_PKGS}"
    
    if [ -z "${PACKAGES}" ]; then
        echo -e "${YELLOW}>> 警告: 包列表为空，将使用默认包${NC}"
    fi
else
    echo -e "${YELLOW}>> 未找到包列表: ${PACKAGE_LIST}${NC}"
    echo ">> 将使用默认包构建"
fi

# ============================================================
# 4. 构建固件
# ============================================================
echo ""
echo "============================================"
echo "  步骤 4: 构建固件"
echo "============================================"
echo ">> Profile: ${PROFILE}"
echo ">> 包含包数: $(echo ${PACKAGES} | wc -w)"
echo ">> 日志文件: ${BUILD_LOG}"
echo ""

> "${BUILD_LOG}"

echo ">> 开始构建..."
set +e
make image \
    PROFILE="${PROFILE}" \
    PACKAGES="${PACKAGES}" \
    V=s 2>&1 | tee "${BUILD_LOG}"
BUILD_EXIT=${PIPESTATUS[0]}
set -e

if [ ${BUILD_EXIT} -ne 0 ]; then
    echo ""
    echo "============================================"
    echo -e "${RED}  构建失败${NC}"
    echo "============================================"
    echo ">> 错误摘要:"
    grep -E "(ERROR|Error|failed|Cannot satisfy|not found|No such package|Unknown package)" "${BUILD_LOG}" | tail -30 || tail -n 30 "${BUILD_LOG}"
    
    echo ""
    echo ">> 排查建议:"
    echo "   1. 从 pkglist-20260905.txt 中移除日志中显示不存在的包"
    echo "   2. 验证 openwrt.ai feeds 可访问性"
    echo "   3. 尝试最小构建: make image PROFILE='${PROFILE}' PACKAGES='luci-base'"
    exit 1
fi

# ============================================================
# 5. 输出结果
# ============================================================
echo ""
echo "============================================"
echo -e "${GREEN}  构建成功！${NC}"
echo "============================================"

OUTPUT_DIR="bin/targets/${TARGET}/"
if [ -d "${OUTPUT_DIR}" ]; then
    echo ">> 产物目录: ${OUTPUT_DIR}"
    echo ""
    echo ">> 生成的固件文件:"
    ls -lh "${OUTPUT_DIR}"*.bin "${OUTPUT_DIR}"*.itb 2>/dev/null || true
    
    SYSUPGRADE=$(ls "${OUTPUT_DIR}"*sysupgrade* 2>/dev/null | head -n1)
    if [ -n "${SYSUPGRADE}" ]; then
        echo ""
        echo -e "${GREEN}>> 推荐刷入文件: ${SYSUPGRADE}${NC}"
    fi
else
    echo -e "${YELLOW}>> 警告: 未找到标准输出目录${NC}"
    find . -name "*.bin" -o -name "*.itb" | head -10
fi

echo ""
echo ">> 完成时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================"
