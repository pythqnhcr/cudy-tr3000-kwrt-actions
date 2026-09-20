#!/bin/sh
#===========================================================
#  网络一键登录 v8  (自动重登 + 状态灯)
#
#  相对 v7 修复:
#   0) 登录成功后先等待外网真正放行, 不再 3 秒内误判断线
#   1) 被顶号/旧 IP 会话失效时, 首次完整重登失败即续租 WAN
#   2) ifupdate 不再重复拉起多次登录, 避免门户“已经在线”风暴
#
#  相对 v6 修掉的三个坑:
#   1) v6 检测失败满 3 次就 ifdown/ifup WAN, 等于自己把网掐断
#      -> v7 正常路径绝不重启 WAN
#   2) v6 只要 HTTP 返回非空就当"在线", 门户劫持页是 200/302
#      -> v7 只认探针地址返回 204, 200/302 一律判定为被劫持
#   3) v6 把 LED 节点写死成 white:status / red:power
#      -> v7 启动时自动扫描 /sys/class/leds 找可用节点
#===========================================================

#---------------- 账号 (改这里) ----------------
USER_ACCOUNT="@@USER_ACCOUNT@@"
USER_PASSWORD="@@USER_PASSWORD@@"
ACCOUNT_PREFIX=",0,"
ACCOUNT_ID=""

#---------------- 门户 ----------------
PORTAL_URL="http://10.8.0.3/a79.htm"
LOGIN_URL="http://10.8.0.3:801/eportal/portal/login"
PORTAL_HOST="10.8.0.3"

#---------------- 探针 ----------------
# 手机系统用来判断"是否被门户劫持"的地址: 联网正常返回 204。
# 2026-09-16 在这台 TR3000 上实测: vivo/华为/小米/微软可用,
# Cloudflare 会返回空响应, 放到最后仅作补充。
PROBE_URLS_DEFAULT="http://wifi.vivo.com.cn/generate_204 http://connectivitycheck.platform.hicloud.com/generate_204 http://connect.rom.miui.com/generate_204 http://edge.microsoft.com/captiveportal/generate_204 http://www.gstatic.com/generate_204 http://cp.cloudflare.com/generate_204"
PROBE_URLS_LEGACY="http://wifi.vivo.com.cn/generate_204 http://connectivitycheck.platform.hicloud.com/generate_204 http://www.gstatic.com/generate_204 http://cp.cloudflare.com/generate_204"
PROBE_URLS="$PROBE_URLS_DEFAULT"
PROBE_NEED=2

#---------------- 调优参数 ----------------
CHECK_INTERVAL=5
FAIL_THRESHOLD=2
LOGIN_COOLDOWN=10
POST_LOGIN_WAIT=20
POST_LOGIN_POLL=2
WAN_NOIP_RECOVER=60
WAN_RENEW_AFTER=1
WAN_RENEW_COOLDOWN=120
HTTP_TIMEOUT=5
WAN_LOGICAL="wan"

PID_FILE="/var/run/campus-login.pid"
LOG_FILE="/var/log/campus-login.log"
LOG_TAG="campus-login"

CURL="curl"
[ -x /usr/bin/curl ] && CURL="/usr/bin/curl"

#---------------- UCI 配置 (LuCI 管理页可修改) ----------------
load_uci_config() {
    [ -f /etc/config/campus_login ] || return 0
    [ -f /lib/functions.sh ] || return 0
    . /lib/functions.sh
    config_load campus_login
    config_get USER_ACCOUNT     main account        "$USER_ACCOUNT"
    config_get USER_PASSWORD    main password       "$USER_PASSWORD"
    config_get ACCOUNT_PREFIX   main account_prefix "$ACCOUNT_PREFIX"
    config_get ACCOUNT_ID       main account_id     "$ACCOUNT_ID"
    [ -n "$ACCOUNT_ID" ] && USER_ACCOUNT="${ACCOUNT_PREFIX}${ACCOUNT_ID}"
    config_get PORTAL_URL       main portal_url     "$PORTAL_URL"
    config_get LOGIN_URL        main login_url      "$LOGIN_URL"
    config_get PORTAL_HOST      main portal_host    "$PORTAL_HOST"
    config_get PROBE_URLS       main probe_urls     "$PROBE_URLS"
    config_get CHECK_INTERVAL   main check_interval "$CHECK_INTERVAL"
    config_get FAIL_THRESHOLD   main fail_threshold "$FAIL_THRESHOLD"
    config_get LOGIN_COOLDOWN   main login_cooldown "$LOGIN_COOLDOWN"
    config_get POST_LOGIN_WAIT  main post_login_wait "$POST_LOGIN_WAIT"
    config_get WAN_NOIP_RECOVER main wan_noip_recover "$WAN_NOIP_RECOVER"
    config_get HTTP_TIMEOUT     main http_timeout   "$HTTP_TIMEOUT"
    config_get WAN_LOGICAL      main wan_logical    "$WAN_LOGICAL"
    config_get WAN_RENEW_AFTER  main wan_renew_after "$WAN_RENEW_AFTER"
    config_get WAN_RENEW_COOLDOWN main wan_renew_cooldown "$WAN_RENEW_COOLDOWN"

    # 老版本安装包里的探针列表会覆盖新默认值, 这里自动迁移。
    [ "$PROBE_URLS" = "$PROBE_URLS_LEGACY" ] && PROBE_URLS="$PROBE_URLS_DEFAULT"
}

load_uci_config

LED_OK=""
LED_BAD=""

log() {
    ts=$(date '+%m-%d %H:%M:%S')
    logger -t "$LOG_TAG" "$1" 2>/dev/null
    echo "[$ts] $1" >> "$LOG_FILE" 2>/dev/null
    [ -t 1 ] && echo "[$ts] $1"
}

#===========================================================
# 状态灯
#===========================================================
led_pick() {
    for n in $1; do
        p="/sys/class/leds/$n/brightness"
        if [ -w "$p" ]; then
            echo "$p"
            return 0
        fi
    done
    return 1
}

led_setup() {
    LED_OK=$(led_pick "white:status blue:status green:status green:wan blue:wan white:wan")
    LED_BAD=$(led_pick "red:power red:status orange:power red:wan orange:wan")

    for p in "$LED_OK" "$LED_BAD"; do
        [ -n "$p" ] || continue
        d=$(dirname "$p")
        # 关掉 OpenWrt 自带 trigger, 否则它会覆盖我们写的亮度
        [ -w "$d/trigger" ] && echo none > "$d/trigger" 2>/dev/null
    done

    log "LED ok=${LED_OK:-未找到} bad=${LED_BAD:-未找到}"
}

led_online() {
    [ -n "$LED_BAD" ] && echo 0 > "$LED_BAD" 2>/dev/null
    [ -n "$LED_OK" ]  && echo 1 > "$LED_OK"  2>/dev/null
    return 0
}

led_offline() {
    [ -n "$LED_OK" ]  && echo 0 > "$LED_OK"  2>/dev/null
    [ -n "$LED_BAD" ] && echo 1 > "$LED_BAD" 2>/dev/null
    return 0
}

#===========================================================
# WAN 信息
#===========================================================
wan_iface() {
    ip route show default 2>/dev/null | awk '{print $5; exit}'
}

wan_ip() {
    [ -n "$1" ] || return 0
    ip -4 addr show dev "$1" 2>/dev/null | awk '/inet /{print $2; exit}' | cut -d/ -f1
}

wan_mac() {
    [ -n "$1" ] || return 0
    tr -d ':' < "/sys/class/net/$1/address" 2>/dev/null
}

wan_gw() {
    ip route show default 2>/dev/null | awk '{print $3; exit}'
}

#===========================================================
# 连通性检测
#===========================================================
probe_one() {
    code=$("$CURL" -s -o /dev/null -w '%{http_code}' \
        --connect-timeout 3 --max-time "$HTTP_TIMEOUT" \
        --noproxy '*' "$1" 2>/dev/null)
    [ "$code" = "204" ]
}

probe_fallback() {
    # 探针地址被网络封掉时的备用判断:
    # 必须完成经过证书校验的 HTTPS 请求, 且响应内容确实是目标站点。
    # 只看 HTTP 200 会把门户劫持页误判成"已经联网"。
    nslookup www.baidu.com >/dev/null 2>&1 || return 1
    body=$("$CURL" -fsSL --compressed \
        --connect-timeout 3 --max-time "$HTTP_TIMEOUT" \
        --noproxy '*' https://www.baidu.com/ 2>/dev/null) || return 1
    echo "$body" | grep -Eiq 'baidu|百度|全球领先的中文搜索引擎'
}

is_online() {
    ok=0
    for u in $PROBE_URLS; do
        probe_one "$u" && ok=$((ok + 1))
        [ "$ok" -ge "$PROBE_NEED" ] && return 0
    done
    probe_fallback && return 0
    return 1
}

# 门户返回“认证成功”后, 网络通常还要几秒到二十秒才会真正放行外网。
# 这段时间持续轮询, 避免刚登录成功就被误判为离线, 再次注销/续租。
wait_for_online() {
    wait_secs=${1:-$POST_LOGIN_WAIT}
    waited=0
    while [ "$waited" -lt "$wait_secs" ]; do
        is_online && return 0
        sleep "$POST_LOGIN_POLL"
        waited=$((waited + POST_LOGIN_POLL))
    done
    return 1
}

#===========================================================
# 登录
#===========================================================
last_login_ts=0
LOGIN_WAS_ALREADY=0
LOGIN_LAST_STATUS="none"
LOGOUT_LAST_STATUS="none"
last_wan_renew_ts=0

do_login() {
    iface=$(wan_iface)
    ip=$(wan_ip "$iface")
    mac=$(wan_mac "$iface")
    gw=$(wan_gw)

    if [ -z "$ip" ]; then
        log "跳过登录: $iface 没有 IP"
        return 1
    fi

    log "登录中: iface=$iface ip=$ip mac=$mac gw=$gw"

    resp=$("$CURL" -s --connect-timeout 5 --max-time 12 --insecure \
        "${LOGIN_URL}?callback=dr1007&login_method=1&user_account=${USER_ACCOUNT}&user_password=${USER_PASSWORD}&wlan_user_ip=${ip}&wlan_user_ipv6=&wlan_user_mac=${mac}&wlan_ac_ip=${gw}&wlan_ac_name=&jsVersion=4.2.1&terminal_type=1&lang=zh-cn" \
        -H "Accept: */*" \
        -H "Referer: ${PORTAL_URL}" \
        -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" 2>/dev/null)

    log "门户响应: $(echo "$resp" | head -c 200)"

    LOGIN_WAS_ALREADY=0
    LOGIN_LAST_STATUS="failed"
    case "$resp" in
        *already*|*'"ret_code":2'*|*已经在线*)
            LOGIN_WAS_ALREADY=1
            LOGIN_LAST_STATUS="already"
            log "门户认为已在线(不一定真通)"
            return 2
            ;;
        *success*|*SUCCESS*|*login_ok*|*'"result":1'*|*认证成功*)
            LOGIN_LAST_STATUS="success"
            log "登录成功"
            return 0
            ;;
        *)
            log "登录失败"
            return 1
            ;;
    esac
}

do_login_throttled() {
    now=$(date +%s)
    if [ $((now - last_login_ts)) -lt "$LOGIN_COOLDOWN" ]; then
        LOGIN_LAST_STATUS="cooldown"
        log "登录冷却中, 本次跳过"
        return 3
    fi
    last_login_ts=$now
    do_login
}

# 一次完整的重登流程:
#   首次登录 -> 等外网真正放行 -> 失败则注销 -> 再登录 -> 再等待。
# 登录接口返回成功后立刻判离线会把“认证生效中”误当成失败, 这里专门修掉。
try_login_recover() {
    do_login_throttled
    login_rc=$?
    [ "$login_rc" -eq 3 ] && return 3

    if [ "$login_rc" -eq 0 ] || [ "$login_rc" -eq 2 ]; then
        if wait_for_online "$POST_LOGIN_WAIT"; then
            log "登录后外网已恢复"
            return 0
        fi
        log "登录成功但外网未就绪, 准备注销旧会话后重登"
    else
        log "首次登录未成功, 准备注销旧会话后重登"
    fi

    do_logout
    do_login
    login_rc=$?
    if [ "$login_rc" -eq 0 ] || [ "$login_rc" -eq 2 ]; then
        if wait_for_online "$POST_LOGIN_WAIT"; then
            log "注销重登后外网已恢复"
            return 0
        fi
    fi
    return 1
}

# 门户有时会认为"你的 IP 还在线", 可实际流量已经被掐。
# 这种情况光登录没用, 得先注销掉旧会话再重新认证。
do_logout() {
    iface=$(wan_iface)
    ip=$(wan_ip "$iface")
    [ -n "$ip" ] || return 1
    log "先注销旧会话 ..."
    LOGOUT_LAST_STATUS="failed"
    resp=$("$CURL" -s --connect-timeout 5 --max-time 10 \
        "http://${PORTAL_HOST}:801/eportal/portal/logout?callback=dr1003&login_method=1&user_account=${USER_ACCOUNT}&user_password=&wlan_user_ip=${ip}&wlan_user_ipv6=&wlan_user_mac=$(wan_mac "$iface")&wlan_ac_ip=$(wan_gw)&wlan_ac_name=&jsVersion=4.2.1&lang=zh" 2>/dev/null)
    log "注销响应: $(echo "$resp" | head -c 160)"
    sleep 2
    case "$resp" in
        *success*|*SUCCESS*|*logout_ok*|*'"result":1'*|*注销成功*)
            LOGOUT_LAST_STATUS="success"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# 只有 WAN 长时间真的没有 IP 才动接口, 正常用网时绝不碰它
recover_wan() {
    log "WAN 已连续无 IP ${WAN_NOIP_RECOVER}s, 尝试恢复 $WAN_LOGICAL ..."
    if command -v ubus >/dev/null 2>&1; then
        ubus call network.interface."$WAN_LOGICAL" down 2>/dev/null
        sleep 2
        ubus call network.interface."$WAN_LOGICAL" up 2>/dev/null
    else
        ifup "$WAN_LOGICAL" 2>/dev/null
    fi
    sleep 5
    log "恢复后 IP: $(wan_ip "$(wan_iface)")"
}

gateway_resolved() {
    gw=$(wan_gw)
    [ -n "$gw" ] || return 1
    ip neigh show "$gw" 2>/dev/null | grep -q 'lladdr '
}

# 被顶号后有时 DHCP/网关邻居状态会卡死: WAN 还有旧 IP, 但网关 ARP 为 INCOMPLETE,
# 门户 10.8.0.3 完全不可达, 登录请求只能返回空。连续重登失败后自动续租一次。
recover_wan_session() {
    now=$(date +%s)
    if [ $((now - last_wan_renew_ts)) -lt "$WAN_RENEW_COOLDOWN" ]; then
        log "WAN 续租冷却中, 暂不重复操作"
        return 1
    fi
    last_wan_renew_ts=$now

    old_iface=$(wan_iface)
    old_ip=$(wan_ip "$old_iface")
    log "连续重登失败, 自动续租 WAN (old_iface=${old_iface:-none} old_ip=${old_ip:-none})"

    if command -v ubus >/dev/null 2>&1; then
        ubus call network.interface."$WAN_LOGICAL" renew >/tmp/campus-wan-renew.log 2>&1 || true
    else
        ifup "$WAN_LOGICAL" 2>/dev/null || true
    fi

    i=0
    new_iface="$old_iface"
    new_ip="$old_ip"
    while [ "$i" -lt 10 ]; do
        sleep 2
        new_iface=$(wan_iface)
        new_ip=$(wan_ip "$new_iface")
        if [ -n "$new_ip" ] && [ "$new_ip" != "$old_ip" ]; then
            break
        fi
        gateway_resolved && break
        i=$((i + 1))
    done

    # renew 无效时做一次短促的 WAN down/up, 不重启整机。
    if [ -z "$new_ip" ] || { [ "$new_ip" = "$old_ip" ] && ! gateway_resolved; }; then
        log "DHCP renew 未生效, 执行一次 WAN 重拨"
        if command -v ubus >/dev/null 2>&1; then
            ubus call network.interface."$WAN_LOGICAL" down >/dev/null 2>&1 || true
            sleep 2
            ubus call network.interface."$WAN_LOGICAL" up >/dev/null 2>&1 || true
        else
            ifdown "$WAN_LOGICAL" 2>/dev/null || true
            sleep 2
            ifup "$WAN_LOGICAL" 2>/dev/null || true
        fi

        i=0
        while [ "$i" -lt 15 ]; do
            sleep 2
            new_iface=$(wan_iface)
            new_ip=$(wan_ip "$new_iface")
            [ -n "$new_ip" ] && break
            i=$((i + 1))
        done
    fi

    log "WAN 续租完成: iface=${new_iface:-none} ip=${new_ip:-none}"
    return 0
}

#===========================================================
# 主循环
#===========================================================
run_daemon() {
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
        log "已有实例在跑 (pid=$(cat "$PID_FILE")), 退出"
        exit 1
    fi
    echo $$ > "$PID_FILE"

    trap 'rm -f "$PID_FILE"' EXIT
    trap 'led_offline; log "守护进程停止"; exit 0' INT TERM

    led_setup
    log "守护进程启动 pid=$$ interval=${CHECK_INTERVAL}s"

    fails=0
    noip_secs=0
    recovery_fails=0
    last_wan_ip=""
    # 启动时先保持红灯, 第一次探针成功后再切白灯, 避免“白一下又红”的误导。
    led_offline

    while :; do
        iface=$(wan_iface)
        ip=$(wan_ip "$iface")
        if [ -n "$last_wan_ip" ] && [ -n "$ip" ] && [ "$ip" != "$last_wan_ip" ]; then
            log "WAN IP 已变化: $last_wan_ip -> $ip, 立即允许重新登录"
            last_login_ts=0
            recovery_fails=0
        fi
        [ -n "$ip" ] && last_wan_ip=$ip

        if is_online; then
            [ "$fails" -gt 0 ] && log "网络已恢复 (失败 $fails 次)"
            fails=0
            noip_secs=0
            recovery_fails=0
            led_online
        else
            fails=$((fails + 1))
            led_offline
            log "离线判定 #$fails"

            if [ -z "$iface" ] || [ -z "$ip" ]; then
                noip_secs=$((noip_secs + CHECK_INTERVAL))
                log "WAN $iface 无 IP, 已持续 ${noip_secs}s"
                if [ "$noip_secs" -ge "$WAN_NOIP_RECOVER" ]; then
                    recover_wan
                    noip_secs=0
                fi
            else
                if [ "$fails" -ge "$FAIL_THRESHOLD" ]; then
                    try_login_recover
                    login_rc=$?
                    if [ "$login_rc" -ne 3 ]; then
                        if [ "$login_rc" -eq 0 ]; then
                            log "重连成功"
                            recovery_fails=0
                        else
                            log "本次重登流程仍不通 (status=$LOGIN_LAST_STATUS rc=$login_rc)"
                            recovery_fails=$((recovery_fails + 1))
                            if [ "$recovery_fails" -ge "$WAN_RENEW_AFTER" ]; then
                                log "连续 $recovery_fails 次重登失败, 触发 WAN 续租兜底"
                                recover_wan_session
                                recovery_fails=0
                                last_login_ts=0
                            fi
                        fi
                    fi
                    fails=0
                fi
            fi
        fi
        sleep "$CHECK_INTERVAL"
    done
}

stop_daemon() {
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE")
        kill "$pid" 2>/dev/null
        sleep 1
        kill -9 "$pid" 2>/dev/null
        log "已停止 pid=$pid"
        rm -f "$PID_FILE"
    else
        log "没有在跑"
    fi
}

#===========================================================
# 自检: 打印 LED / WAN / 探针结果, 用来排错
#===========================================================
diagnose() {
    led_setup
    echo "---- LED 节点 ----"
    ls -1 /sys/class/leds/ 2>/dev/null
    echo "---- WAN ----"
    echo "iface: $(wan_iface)"
    echo "ip   : $(wan_ip "$(wan_iface)")"
    echo "gw   : $(wan_gw)"
    echo "mac  : $(wan_mac "$(wan_iface)")"
    echo "---- 探针 ----"
    for u in $PROBE_URLS; do
        code=$("$CURL" -s -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time "$HTTP_TIMEOUT" --noproxy '*' "$u" 2>/dev/null)
        echo "$code  $u"
    done
    is_online && echo "结论: 在线" || echo "结论: 离线"
}

case "${1:---daemon}" in
    --daemon|-d) run_daemon ;;
    --stop|-s)   stop_daemon ;;
    --status)
        if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
            echo "运行中 pid=$(cat "$PID_FILE")"
        else
            echo "未运行"
        fi
        ;;
    --force|-f)
        led_setup
        if is_online; then
            led_online
            log "当前已在线, 跳过重复强制登录"
        else
            do_login
        fi
        ;;
    --logout)    led_setup; do_logout ;;
    --test|-t)   led_setup; is_online && echo "在线" || echo "离线" ;;
    --probe|-p)  is_online && echo "在线" || echo "离线" ;;
    --renew-wan) last_wan_renew_ts=0; recover_wan_session ;;
    --diag)      diagnose ;;
    --led-on)    led_setup; led_online ;;
    --led-off)   led_setup; led_offline ;;
    *)
        echo "用法: $0 [--daemon|--stop|--status|--force|--logout|--test|--probe|--renew-wan|--diag|--led-on|--led-off]"
        ;;
esac
