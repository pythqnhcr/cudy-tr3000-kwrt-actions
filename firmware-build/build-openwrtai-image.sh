#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# 脚本：为 Cudy TR3000 v1 构建 OpenGirl (Kwrt) 固件
# 功能：自动下载 Image Builder，过滤无效包，构建固件
# 作者：自动化构建脚本
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RELEASE="24.10"
TARGET="mediatek/filogic"
PROFILE="cudy_tr3000-v1"
KERNEL="6.6.118"

# 源配置（按优先级）
SOURCES=(
    "https://dl.openwrt.ai/releases/${RELEASE}/targets/${TARGET}/"
    "https://downloads.openwrt.org/releases/${RELEASE}/targets/${TARGET}/"
)

PACKAGE_LIST="${SCRIPT_DIR}/pkglist-20260905.txt"
BUILD_LOG="${SCRIPT_DIR}/build.log"

# ============================================================
# 1. 下载 Image Builder（带自动源切换）
# ============================================================
echo "============================================"
echo "  OpenWrt Image Builder 下载"
echo "============================================"

IB_FILE=""
SELECTED_SOURCE=""

for SOURCE in "${SOURCES[@]}"; do
    echo ">> 尝试源: ${SOURCE}"
    # 尝试解析文件名
    IB_FILE="$(curl -fsSL --connect-timeout 10 "${SOURCE}" 2>/dev/null | grep -oE 'openwrt-imagebuilder-[^"<>]+\.tar\.xz' | head -n1 || true)"
    
    if [ -n "${IB_FILE}" ]; then
        SELECTED_SOURCE="${SOURCE}"
        echo ">> 找到文件: ${IB_FILE}"
        break
    else
        echo ">> 此源未找到 Image Builder，尝试下一个..."
    fi
done

# 如果所有源都失败，使用硬编码文件名（官方最常见）
if [ -z "${IB_FILE}" ]; then
    echo ">> 所有源解析失败，使用硬编码文件名..."
    IB_FILE="openwrt-imagebuilder-${RELEASE}-${TARGET/\//-}.Linux-x86_64.tar.xz"
    SELECTED_SOURCE="${SOURCES[1]}"  # 使用官方源
    echo ">> 尝试: ${IB_FILE}"
fi

# 下载
echo ">> 从 ${SELECTED_SOURCE} 下载 ${IB_FILE}"
curl -fL --retry 3 --retry-delay 5 -O "${SELECTED_SOURCE}${IB_FILE}" || {
    echo "ERROR: 下载失败！请检查网络或手动下载。"
    echo "手动下载命令: wget ${SELECTED_SOURCE}${IB_FILE}"
    exit 1
}

echo ">> 解压 Image Builder..."
tar -xJf "${IB_FILE}" || {
    echo "ERROR: 解压失败，文件可能损坏。"
    exit 1
}

# 进入目录（支持带后缀的目录名）
IB_DIR="$(find . -maxdepth 1 -type d -name 'openwrt-imagebuilder-*' | head -n1)"
if [ -z "${IB_DIR}" ]; then
    echo "ERROR: 未找到 Image Builder 目录"
    exit 1
fi
cd "${IB_DIR}"
echo ">> 进入目录: $(pwd)"

# ============================================================
# 2. 智能包过滤（自动跳过不存在的包）
# ============================================================
echo "============================================"
echo "  包列表过滤"
echo "============================================"

# 生成可用包索引
echo ">> 生成可用包列表..."
make package_index 2>/dev/null || true

# 收集所有可用包名（兼容多种目录结构）
AVAILABLE_PKGS_FILE="/tmp/available_pkgs.txt"
find ./packages -name "Packages" -exec grep -h "^Package:" {} \; 2>/dev/null | awk '{print $2}' | sort -u > "${AVAILABLE_PKGS_FILE}"

PKG_COUNT=$(wc -l < "${AVAILABLE_PKGS_FILE}")
echo ">> 可用包总数: ${PKG_COUNT}"

# 读取包列表并过滤
if [ -f "${PACKAGE_LIST}" ]; then
    echo ">> 读取包列表: ${PACKAGE_LIST}"
    ALL_PKGS=($(awk '{print $1}' "${PACKAGE_LIST}" | tr '\n' ' '))
    
    FILTERED_PKGS=()
    MISSING_PKGS=()
    
    for pkg in "${ALL_PKGS[@]}"; do
        if grep -qx "${pkg}" "${AVAILABLE_PKGS_FILE}" 2>/dev/null; then
            FILTERED_PKGS+=("${pkg}")
        else
            MISSING_PKGS+=("${pkg}")
        fi
    done
    
    # 输出统计信息
    echo ">> 总包数: ${#ALL_PKGS[@]}"
    echo ">> 有效包: ${#FILTERED_PKGS[@]}"
    echo ">> 跳过包: ${#MISSING_PKGS[@]}"
    
    if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
        echo ">> 跳过的包列表（前20个）:"
        printf '  %s\n' "${MISSING_PKGS[@]}" | head -20
        if [ ${#MISSING_PKGS[@]} -gt 20 ]; then
            echo "  ... 还有 $((${#MISSING_PKGS[@]} - 20)) 个"
        fi
    fi
    
    PACKAGES="${FILTERED_PKGS[@]}"
else
    echo ">> 未找到包列表，将使用默认包"
    PACKAGES=""
fi

# ============================================================
# 3. 构建固件
# ============================================================
echo "============================================"
echo "  开始构建固件"
echo "============================================"
echo ">> Profile: ${PROFILE}"
echo ">> 包含包数: $(echo ${PACKAGES} | wc -w)"
echo ">> 完整包列表（前10个）:"
echo ${PACKAGES} | tr ' ' '\n' | head -10
echo ""

# 构建（捕获详细日志）
echo ">> 开始构建（日志保存至 ${BUILD_LOG}）..."
set +e  # 暂时允许错误捕获

make image \
    PROFILE="${PROFILE}" \
    PACKAGES="${PACKAGES}" \
    V=s 2>&1 | tee "${BUILD_LOG}"

BUILD_EXIT=$?
set -e

# 检查结果
if [ ${BUILD_EXIT} -ne 0 ]; then
    echo ""
    echo "============================================"
    echo "  构建失败！"
    echo "============================================"
    echo ">> 错误摘要（最后30行日志）:"
    tail -n 30 "${BUILD_LOG}" | grep -E "(ERROR|Error|failed|not found)" || tail -n 30 "${BUILD_LOG}"
    echo ""
    echo ">> 完整日志: ${BUILD_LOG}"
    echo ">> 常见解决方法:"
    echo "   1. 检查包列表中是否有不兼容的第三方包"
    echo "   2. 在 pkglist-20260905.txt 中注释掉 kmod-* 内核模块"
    echo "   3. 尝试只保留基础包: luci-base firewall4 dropbear"
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
    echo ">> 文件列表:"
    ls -lh "${OUTPUT_DIR}"*.bin 2>/dev/null || echo "   未找到 .bin 文件"
else
    echo ">> 警告: 未找到输出目录"
fi

echo ""
echo ">> 构建完成时间: $(date)"
echo "============================================"
