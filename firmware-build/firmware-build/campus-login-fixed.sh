#!/bin/sh
#===========================================
# Campus Net Auto-Login v6 + LED Control
# white:status = online | red:power = offline
# online check = at least 2 external HTTPS sites reachable
#===========================================

USER_ACCOUNT=",0,202546010247"
USER_PASSWORD="t20060406"
PORTAL_URL="http://10.8.0.3/a79.htm"
LOGIN_URL="http://10.8.0.3:801/eportal/portal/login"
SCHOOL_URL="https://www.cqepc.edu.cn/"
ONLINE_URLS="https://www.baidu.com/ https://www.taobao.com/ https://www.qq.com/"
ONLINE_MIN_OK=2
HTTP_TIMEOUT=4
CHECK_INTERVAL=10
MAX_FAIL_COUNT=2
MAX_LOGIN_FAILS=3
LOCK_FILE="/var/run/campus-login.lock"
PID_FILE="/var/run/campus-login.pid"
LOG_TAG="campus-login"
LED_WHITE="/sys/class/leds/white:status/brightness"
LED_RED="/sys/class/leds/red:power/brightness"

log() {
    msg="[$(date '+%m-%d %H:%M:%S')] $1"
    logger -t "$LOG_TAG" "$1"
    echo "$msg"
}

led_online() {
    echo 0 > "$LED_RED" 2>/dev/null
    echo 1 > "$LED_WHITE" 2>/dev/null
}

led_offline() {
    echo 1 > "$LED_RED" 2>/dev/null
    echo 0 > "$LED_WHITE" 2>/dev/null
}

get_wan_iface() {
    iface=$(ip route show default 2>/dev/null | awk '{print $5; exit}')
    [ -z "$iface" ] && iface="eth0"
    echo "$iface"
}

get_local_ip() {
    _iface="$1"
    ip=$(ip -4 addr show "$_iface" 2>/dev/null | awk '/inet /{print $2; exit}' | cut -d/ -f1)
    echo "$ip"
}

get_local_mac() {
    _iface="$1"
    mac=""
    [ -f "/sys/class/net/${_iface}/address" ] && mac=$(tr -d ':' < "/sys/class/net/${_iface}/address")
    [ -z "$mac" ] && mac=$(ip link show "$_iface" 2>/dev/null | awk '/link\/ether/{print $2; exit}' | tr -d ':')
    echo "$mac"
}

get_gateway() {
    gw=$(ip route show default 2>/dev/null | awk '{print $3; exit}')
    [ -z "$gw" ] && gw="10.1.0.33"
    echo "$gw"
}

http_code() {
    curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time "$HTTP_TIMEOUT" "$1" 2>/dev/null
}

check_online() {
    ok=0
    for url in $ONLINE_URLS; do
        code=$(http_code "$url")
        case "$code" in
            ""|000) ;;
            *) ok=$((ok + 1)) ;;
        esac
    done
    [ "$ok" -ge "$ONLINE_MIN_OK" ]
}

check_portal() {
    code=$(http_code "$PORTAL_URL")
    case "$code" in
        2*|3*) return 0 ;;
        *) return 1 ;;
    esac
}

check_network() {
    check_online && return 0
    check_portal && return 1
    return 1
}

do_login() {
    iface=$(get_wan_iface)
    ip=$(get_local_ip "$iface")
    mac=$(get_local_mac "$iface")
    gw=$(get_gateway)

    [ -z "$ip" ] && { log "ERROR: no IP on $iface"; return 1; }
    [ -z "$mac" ] && { log "ERROR: no MAC on $iface"; return 1; }

    log "Login: $iface ip=$ip mac=$mac gw=$gw"

    resp=$(curl -s --connect-timeout 5 --max-time 10 --insecure \
        "${LOGIN_URL}?callback=dr1007&login_method=1&user_account=${USER_ACCOUNT}&user_password=${USER_PASSWORD}&wlan_user_ip=${ip}&wlan_user_ipv6=&wlan_user_mac=${mac}&wlan_ac_ip=${gw}&wlan_ac_name=&jsVersion=4.2.1&terminal_type=1&lang=zh-cn&v=7006&lang=zh" \
        -H "Accept: */*" \
        -H "Accept-Language: zh-CN,zh;q=0.9,en;q=0.8" \
        -H "Referer: ${PORTAL_URL}" \
        -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36 Edg/149.0.0.0")

    resp_short=$(echo "$resp" | head -c 200)
    log "Resp: $resp_short"

    case "$resp" in
        *success*|*SUCCESS*|*login_ok*|*result*0*|*result?1*) log "=== LOGIN SUCCESS ==="; return 0 ;;
        *already*|*ret_code*2*) log "Already online."; return 0 ;;
        *) log "Login failed."; return 1 ;;
    esac
}

reset_wan() {
    iface=$(get_wan_iface)
    log "Resetting WAN $iface ..."
    ifdown "$iface" 2>/dev/null
    sleep 3
    ifup "$iface" 2>/dev/null
    sleep 5
    log "WAN reset done, IP: $(get_local_ip "$iface")"
}

run_daemon() {
    [ -f "$LOCK_FILE" ] && { log "Already running."; exit 1; }
    echo $$ > "$PID_FILE"
    touch "$LOCK_FILE"
    log "Daemon PID=$$, interval=${CHECK_INTERVAL}s"

    fail_count=0
    login_fails=0
    heartbeat=0
    led_online

    trap 'led_offline; log "Daemon stopped."; rm -f "$LOCK_FILE" "$PID_FILE"; exit 0' INT TERM

    while true; do
        if check_network; then
            led_online
            [ "$fail_count" -gt 0 ] && log "Network RECOVERED ($fail_count failures)"
            fail_count=0
            login_fails=0
        else
            led_offline
            fail_count=$((fail_count + 1))
            log "Check FAIL #$fail_count"
            [ "$fail_count" -ge "$MAX_FAIL_COUNT" ] && {
                iface=$(get_wan_iface)
                if [ -z "$(get_local_ip "$iface")" ]; then
                    log "No IP on $iface, waiting for WAN/DHCP"
                    login_fails=$((login_fails + 1))
                    fail_count=$((MAX_FAIL_COUNT - 1))
                    [ "$login_fails" -ge "$MAX_LOGIN_FAILS" ] && {
                        log "=== No IP for $login_fails checks, resetting WAN ==="
                        reset_wan
                        login_fails=0; fail_count=0
                    }
                else
                    log "Network DOWN, login..."
                    if do_login; then
                        sleep 3
                        if check_network; then
                            led_online
                            log "Login OK!"
                            fail_count=0; login_fails=0
                        else
                            log "Login sent, still offline"
                            fail_count=$((MAX_FAIL_COUNT - 1))
                        fi
                    else
                        login_fails=$((login_fails + 1))
                        log "Login fail #$login_fails"
                        fail_count=$((MAX_FAIL_COUNT - 1))
                        [ "$login_fails" -ge "$MAX_LOGIN_FAILS" ] && {
                            log "=== $login_fails fails, resetting WAN ==="
                            reset_wan
                            login_fails=0; fail_count=0
                        }
                    fi
                fi
            }
        fi
        heartbeat=$((heartbeat + 1))
        [ "$heartbeat" -ge 30 ] && { heartbeat=0; log "Heartbeat: fail=$fail_count login_fails=$login_fails"; }
        sleep "$CHECK_INTERVAL"
    done
}

stop_daemon() {
    [ -f "$PID_FILE" ] && {
        pid=$(cat "$PID_FILE")
        kill "$pid" 2>/dev/null; sleep 1
        kill -9 "$pid" 2>/dev/null
        log "Daemon PID=$pid stopped."
        rm -f "$PID_FILE" "$LOCK_FILE"
    } || log "No PID file."
}

case "${1:-}" in
    --daemon|-d)   run_daemon ;;
    --stop|-s)     stop_daemon ;;
    --status)      [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null && log "Running PID=$(cat $PID_FILE)" || log "NOT running" ;;
    --force|-f)    log "Force login..."; do_login ;;
    --test)        check_network && log "ONLINE" || log "OFFLINE" ;;
    *)             check_network && log "Network OK." || { log "DOWN, login..."; do_login; } ;;
esac
