# Firmware Build Files

## OpenWrt.ai / Kwrt 24.10

- `build-openwrtai-image.sh` downloads the matching ImageBuilder and runs a
  custom package build.
- `pkglist-20260905.txt` is a reference list copied from one router.
- `packages-only.txt` is the versionless package list.

## ImmortalWrt 25.12.2

`immortalwrt-25.12.2/` contains a filtered list derived from the original
snapshot. Packages unavailable in the 25.12.2 feed have been removed.

Use `packages-per-line.txt` for the Firmware Selector package field and
`packages-one-line.txt` for the ImageBuilder `PACKAGES=` argument.

Package availability changes over time. If a feed no longer contains a listed
package, remove it and retry.
