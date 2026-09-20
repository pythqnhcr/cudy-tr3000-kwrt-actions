#!/bin/sh

# Example first-boot script for ImmortalWrt 25.12.2.
# Replace every CHANGE_ME value before use.

wlan_name="CHANGE_ME"
wlan_password="CHANGE_ME"
root_password="CHANGE_ME"
lan_ip_address="192.168.1.1/24"

exec >/tmp/setup.log 2>&1

[ -n "$root_password" ] && {
    (echo "$root_password"; sleep 1; echo "$root_password") | passwd >/dev/null
}

[ -n "$lan_ip_address" ] && {
    uci set network.lan.ipaddr="$lan_ip_address"
    uci commit network
}

if [ -n "$wlan_name" ] && [ -n "$wlan_password" ] && [ ${#wlan_password} -ge 8 ]; then
    i=0
    while uci -q get "wireless.@wifi-device[$i]" >/dev/null; do
        uci set "wireless.@wifi-device[$i].disabled=0"
        i=$((i + 1))
    done

    i=0
    while uci -q get "wireless.@wifi-iface[$i]" >/dev/null; do
        uci set "wireless.@wifi-iface[$i].disabled=0"
        uci set "wireless.@wifi-iface[$i].encryption=psk2"
        uci set "wireless.@wifi-iface[$i].ssid=$wlan_name"
        uci set "wireless.@wifi-iface[$i].key=$wlan_password"
        i=$((i + 1))
    done
    uci commit wireless
fi

exit 0
