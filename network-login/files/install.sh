#!/bin/sh
#===========================================================
#  网络登录 v8 一键安装
#
#  用法:
#    1) 把整个 v7 文件夹传到路由器, 例如 /tmp/v7/
#    2) ssh 进路由器, 执行:
#         cd /tmp/v7 && sh install.sh
#
#  装完会自动开机自启。
#===========================================================

SRC=$(cd "$(dirname "$0")" && pwd)
TS=$(date +%Y%m%d-%H%M%S)

echo "============================================"
echo "  安装网络登录 v8"
echo "  来源目录: $SRC"
echo "============================================"

# ---- 1. 备份旧文件 ----
if [ -f /root/campus-login.sh ]; then
    cp /root/campus-login.sh "/root/campus-login.sh.bak-$TS"
    echo "[备份] /root/campus-login.sh -> /root/campus-login.sh.bak-$TS"
fi
if [ -f /etc/init.d/campus-login ]; then
    cp /etc/init.d/campus-login "/etc/init.d/campus-login.bak-$TS"
    echo "[备份] /etc/init.d/campus-login -> /etc/init.d/campus-login.bak-$TS"
fi
if [ -f /etc/hotplug.d/iface/99-campus-login ]; then
    cp /etc/hotplug.d/iface/99-campus-login "/etc/hotplug.d/iface/99-campus-login.bak-$TS"
    echo "[备份] /etc/hotplug.d/iface/99-campus-login -> ...bak-$TS"
fi
if [ -f /etc/config/campus_login ]; then
    cp /etc/config/campus_login "/etc/config/campus_login.bak-$TS"
    echo "[备份] /etc/config/campus_login -> ...bak-$TS"
fi

# ---- 2. 停掉旧守护进程 ----
if [ -f /root/campus-login.sh ]; then
    /root/campus-login.sh --stop 2>/dev/null
fi
rm -f /var/run/campus-login.pid /var/run/campus-login.lock

# ---- 3. 放文件 ----
mkdir -p /etc/hotplug.d/iface

cp "$SRC/campus-login.sh"         /root/campus-login.sh
cp "$SRC/99-campus-login.hotplug" /etc/hotplug.d/iface/99-campus-login
cp "$SRC/campus-login.init"       /etc/init.d/campus-login

chmod 755 /root/campus-login.sh
chmod 755 /etc/hotplug.d/iface/99-campus-login
chmod 755 /etc/init.d/campus-login

# ---- 3.1 LuCI 管理页 ----
LUCI_SRC="$SRC/campus-login-luci"
if [ -d "$LUCI_SRC" ]; then
    mkdir -p /usr/lib/lua/luci/controller
    mkdir -p /usr/lib/lua/luci/model/cbi
    mkdir -p /usr/lib/lua/luci/view/campus_login
    cp "$LUCI_SRC/usr/lib/lua/luci/controller/campus_login.lua" /usr/lib/lua/luci/controller/
    cp "$LUCI_SRC/usr/lib/lua/luci/model/cbi/campus_login.lua" /usr/lib/lua/luci/model/cbi/
    cp "$LUCI_SRC/usr/lib/lua/luci/view/campus_login/status.htm" /usr/lib/lua/luci/view/campus_login/
    echo "[安装] LuCI 网络自动登录管理页"
fi

# ---- 3.2 UCI 配置 ----
mkdir -p /etc/config
cp "$SRC/campus_login" /etc/config/campus_login
chmod 600 /etc/config/campus_login
echo "[安装] /etc/config/campus_login"

rm -f /tmp/luci-indexcache 2>/dev/null || true
rm -rf /tmp/luci-modulecache/* 2>/dev/null || true

echo "[安装] /root/campus-login.sh"
echo "[安装] /etc/hotplug.d/iface/99-campus-login"
echo "[安装] /etc/init.d/campus-login"

# ---- 4. 开机自启 + 启动 ----
/etc/init.d/campus-login enable
/etc/init.d/campus-login start

sleep 3

echo ""
echo "============================================"
echo "  安装完成"
echo "============================================"
/root/campus-login.sh --status
/root/campus-login.sh --diag
echo ""
echo "  改账号:  vi /root/campus-login.sh    (第 15/16 行)"
echo "  改完重启: /etc/init.d/campus-login restart"
echo "  看日志:   logread -e campus-login"
echo "  LuCI:     服务 -> 网络自动登录 / 破解网络"
