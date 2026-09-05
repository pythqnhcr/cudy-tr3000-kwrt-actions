本目录用途：在 Linux 编译机上构建 Cudy TR3000 v1 固件。

重要说明
1. 当前这台 Windows 机器没有 Linux/OpenWrt 工具链，也无法访问外网源码，
   所以这里不产出可刷机 .bin，产出的是可直接交给编译机使用的定制包。
2. 固件原始版本来自 openwrt.ai 的 Kwrt/OpenGirl 24.10-SNAPSHOT。
   精确复刻需要 openwrt.ai 的同一套源码/Image Builder 和其自带的 feeds；
   build-openwrtai-image.sh 会优先下载与路由器 opkg 地址一致的
   mediatek/filogic + 6.6.118 Image Builder。
3. pkglist-20260905.txt 是 2026-09-05 路由器上 opkg 实际安装清单。
   packages-only.txt 是去掉版本号的包名清单。
4. tr3000-overlay-20260905.tar.gz 是路由器 /overlay/upper 全量增量备份，
   用于刷机后恢复当前配置/脚本/软件状态；其中包含账号密码等敏感信息，
   请勿外传。Image Builder 构建时不要直接整包注入该 overlay，
   建议刷机后用 sysupgrade/LuCI 恢复，或只挑 etc/config、root 等配置注入。
5. 本目录里的 campus-login-fixed.sh 为修复后的校园网登录 + LED 脚本。

编译步骤（在 Linux 编译机执行）
1. 上传本目录到 Linux，例如 /home/you/tr3000-build
2. chmod +x build-openwrtai-image.sh && ./build-openwrtai-image.sh
3. 若提示某个包不存在：把该包名从 pkglist-20260905.txt 删掉后重跑，
   或把 openwrt.ai 对应 feed 加入 Image Builder 配置。
4. 产物在 bin/targets/mediatek/filogic/ 下，选择含 sysupgrade 的 .bin
   （Cudy TR3000 使用哪类镜像以 bootloader 实际要求为准，先不要刷机，
   确认好命名和校验值再刷）。

需要保留当前路由配置：
刷机完成重启后，通过 LuCI “备份/恢复”上传
sysupgrade 配置备份，或手工把 overlay 中的 etc/config 覆盖回去。
