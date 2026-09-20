module("luci.controller.campus_login", package.seeall)

function index()
    entry({"admin", "services", "campus_login"}, cbi("campus_login"), _("网络自动登录"), 93)
    entry({"admin", "services", "campus_login", "status"}, call("act_status")).leaf = true
end

function act_status()
    local running = luci.sys.call("pgrep -f '[c]ampus-login.sh --daemon' >/dev/null") == 0
    local status = luci.sys.exec("/root/campus-login.sh --status 2>/dev/null")
    local online = luci.sys.exec("/root/campus-login.sh --probe 2>/dev/null")
    local logs = luci.sys.exec("logread -e campus-login 2>/dev/null | tail -20")

    luci.http.prepare_content("application/json")
    luci.http.write_json({
        running = running,
        status = status,
        online = online,
        logs = logs
    })
end
