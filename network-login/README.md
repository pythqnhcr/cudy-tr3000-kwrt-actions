# Generic Network Auto Login

This directory contains a sanitized OpenWrt auto-login service:

- Periodic connectivity checks.
- WAN reauthentication and DHCP recovery.
- White/red LED status.
- Optional LuCI configuration pages.

## Files

```text
files/campus-login.sh                 main service
files/campus-login.init               init.d service
files/99-campus-login.hotplug         WAN hotplug helper
files/campus_login.config             UCI template
files/campus-login-luci/              LuCI files
files/install.sh                      router installer
```

The scripts contain `@@USER_ACCOUNT@@` and `@@USER_PASSWORD@@` placeholders.
Never commit a generated script that contains real credentials.

Third-party binaries are intentionally not bundled.
