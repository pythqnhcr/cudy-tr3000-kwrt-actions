#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# 脚本：为 Cudy TR3000 v1 构建 OpenWrt 固件（官方源）
# 说明：由于 dl.openwrt.ai 不可用，改用官方源，动态解析 Image Builder 文件名
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RELEASE="24.10"
TARGET="mediatek/filogic"
PROFILE="cudy_tr3000-v1"
BASE_URL="https://downloads.openwrt.org/releases/${RELEASE}/targets/${TARGET}/"
PACKAGE_LIST="${SCRIPT_DIR}/pkglist-20260905.txt"
BUILD_LOG="${SCRIPT_DIR}/build.log"

# ============================================================
# 1. 下载 Image Builder（动态解析文件名）
# ============================================================
echo "============================================"
echo "  OpenWrt Image Builder 下载"
echo "============================================"

echo ">> 尝试从 ${BASE_URL} 解析 Image Builder 文件名..."
# 获取目录列表，匹配 imagebuilder 的 tar.xz 文件
IB_FILE=$(curl -fsSL "${BASE_URL}" | grep -o 'openwrt-imagebuilder-[^"]*\.tar\.xz' | head -n1)

if [ -z "${IB_FILE}" ]; then
    echo ">> 未找到任何 Image Builder 文件，请检查源目录。"
    exit 1
fi

echo ">> 找到文件: ${IB_FILE}"
echo ">> 下载中..."
curl -fL --retry 3 --retry-delay 5 -O "${BASE_URL}${IB_FILE}" || {
    echo "ERROR: 下载失败！"
    exit 1
}

echo ">> 解压 Image Builder..."
tar -xJf "${IB_FILE}" || {
    echo "ERROR: 解压失败，文件可能损坏。"
    exit 1
}

# 进入目录
IB_DIR="$(find . -maxdepth 1 -type d -name 'openwrt-imagebuilder-*' | head -n1)"
if [ -z "${IB_DIR}" ]; then
    echo "ERROR: 未找到 Image Builder 目录"
    exit 1
fi
cd "${IB_DIR}"
echo ">> 进入目录: $(pwd)"

# ============================================================
# 2. 智能包过滤（只保留可用包）
# ============================================================
echo "============================================"
echo "  包列表过滤"
echo "============================================"

echo ">> 生成可用包列表..."
make package_index 2>/dev/null || true

# 收集所有可用包名
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
echo ""

echo ">> 开始构建（日志保存至 ${BUILD_LOG}）..."
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
