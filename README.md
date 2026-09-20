# Cudy TR3000 Network Auto Login and Firmware Build

Sanitized tooling for Cudy TR3000 256MB v1:

- OpenWrt/ImmortalWrt package lists for reference.
- A generic network auto-login service with WAN recovery and LED status.
- A LuCI management page.
- Linux ImageBuilder and GitHub Actions build helpers.
- A first-boot `uci-defaults` example with placeholders only.
- An optional UA2F installation guide: [docs/ua2f.md](docs/ua2f.md).

No account, password, Wi-Fi key, SSH key, VPN profile, router backup, or other
personal credential is included.

## Repository Layout

```text
.github/workflows/       GitHub Actions build workflow
network-login/           Generic auto-login source and installer
firmware-build/          ImageBuilder files and package lists
examples/                Sanitized first-boot examples
```

## ImmortalWrt 25.12.2

1. Open the ImmortalWrt Firmware Selector.
2. Select `Cudy TR3000 256MB v1`.
3. Select a 25.12.2 image.
4. Paste the package names from
   `firmware-build/immortalwrt-25.12.2/packages-per-line.txt`.
5. Use `examples/immortalwrt-25.12.2-uci-defaults.sh` as the first-boot
   script, replacing every `CHANGE_ME` value.
6. Run the local installer after boot and enter the account interactively.

## GitHub Actions

The workflow in `.github/workflows/build-tr3000.yml` can be started manually
from the Actions tab. Build artifacts are uploaded from the ImageBuilder output
directory.

## Security

Generated files such as `/etc/config/campus_login`, router overlay backups,
and `sysupgrade` archives normally contain credentials. They are intentionally
ignored by `.gitignore` and must not be pushed to a public repository.

## License

MIT. Third-party packages and firmware remain under their respective licenses.
