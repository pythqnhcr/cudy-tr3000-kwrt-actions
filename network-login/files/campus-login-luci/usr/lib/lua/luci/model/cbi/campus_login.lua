m = Map("campus_login", translate("网络自动登录"))
m.description = translate("管理网络自动登录脚本的账号、密码、检测参数和运行状态。")

m:section(SimpleSection).template = "campus_login/status"

s = m:section(TypedSection, "login", translate("账号设置"))
s.anonymous = true
s.addremove = false

o = s:option(Flag, "enabled", translate("启用/开机自启"))
o.rmempty = false

o = s:option(Value, "account_id", translate("账号"))
o.description = translate("直接填写账号，例如 202500000000。")
o.rmempty = true

o = s:option(Value, "account_prefix", translate("账号前缀"))
o.default = ",0,"
o.description = translate("一般保持 ,0, 不变。")

o = s:option(Value, "account", translate("完整账号(高级)"))
o.description = translate("如果填写账号，此项可不填。也可直接填写门户抓包得到的完整账号。")
o.rmempty = true

o = s:option(Value, "password", translate("密码"))
o.password = true
o.rmempty = false

a = m:section(TypedSection, "login", translate("检测与重连"))
a.anonymous = true
a.addremove = false

o = a:option(Value, "check_interval", translate("检测间隔(秒)"))
o.default = "5"

o = a:option(Value, "fail_threshold", translate("失败次数阈值"))
o.default = "2"

o = a:option(Value, "login_cooldown", translate("登录冷却(秒)"))
o.default = "10"

o = a:option(Value, "post_login_wait", translate("登录后等待外网生效(秒)"))
o.default = "20"
o.description = translate("门户返回认证成功后，网络可能还要几秒到二十秒才真正放行；超时前不会再次注销或续租。")

o = a:option(Value, "wan_noip_recover", translate("WAN 无 IP 后续租(秒)"))
o.default = "60"
o.description = translate("WAN 连续多久没有 IP 后执行一次 DHCP 恢复。")

o = a:option(Value, "wan_renew_after", translate("连续重登失败后续租 WAN"))
o.default = "1"
o.description = translate("检测不到网络且连续重登失败达到此次数后，自动向 WAN 续租 DHCP，不重启整机。")

o = a:option(Value, "wan_renew_cooldown", translate("WAN 续租冷却(秒)"))
o.default = "120"

o = a:option(Value, "http_timeout", translate("HTTP 超时(秒)"))
o.default = "5"

o = a:option(Value, "probe_urls", translate("连通性探针 URL"))
o.description = translate("多个地址用空格分隔，必须以 generate_204 或等价地址为准。")

o = a:option(Value, "portal_url", translate("门户地址"))
o = a:option(Value, "login_url", translate("登录接口地址"))
o = a:option(Value, "portal_host", translate("门户主机"))
o = a:option(Value, "wan_logical", translate("WAN 逻辑接口"))
o.default = "wan"

function m.on_commit(map)
    luci.sys.call("/etc/init.d/campus-login restart >/dev/null 2>&1")
end

return m
