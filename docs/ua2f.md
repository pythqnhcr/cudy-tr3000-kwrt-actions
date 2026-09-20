# UA2F Optional Guide

UA2F is an optional third-party package. This repository does not bundle its
binary or configuration files.

## Before Installing

- Confirm the target device architecture.
- Use the package feed matching the firmware release.
- Install UA2F only where local policy permits HTTP header rewriting.

## Install

OpenWrt 24.10 and earlier:

```sh
opkg update
opkg install ua2f
```

OpenWrt/ImmortalWrt versions using APK:

```sh
apk update
apk add ua2f
```

## Enable

```sh
uci set ua2f.enabled.enabled=1
uci set ua2f.firewall.handle_fw=1
uci commit ua2f
/etc/init.d/ua2f enable
/etc/init.d/ua2f restart
```

## Verify

```sh
/etc/init.d/ua2f status
ps w | grep '[u]a2f'
```

If the package provides a LuCI page, it normally appears under `Services`.

## Disable or Remove

```sh
/etc/init.d/ua2f stop
/etc/init.d/ua2f disable
uci set ua2f.enabled.enabled=0
uci commit ua2f
```

Remove the package with `opkg remove ua2f` or `apk del ua2f` only when it is no
longer needed.

## Upstream

See the upstream project documentation for supported releases and licenses:

<https://github.com/Zxilly/UA2F>
