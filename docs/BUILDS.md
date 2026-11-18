# Prebuilt packages

Every `v*` tag starts four jobs; each one attaches its packages to the matching
release.

| Platform | Runner | Architecture | Files |
| --- | --- | --- | --- |
| Linux | `ubuntu-22.04` | x86_64 | `quiet-md_<ver>_amd64.deb`, `quiet-md-<ver>-linux-x86_64.tar.gz`, `quiet-md-x86_64.AppImage` |
| Linux | `ubuntu-24.04-arm` | aarch64 | `quiet-md_<ver>_arm64.deb`, `quiet-md-<ver>-linux-aarch64.tar.gz` |
| macOS | `macos-15` | Apple Silicon | `quiet-md-<ver>-macos-arm64-unsigned.zip` |
| macOS | `macos-15` | Intel (cross) | `quiet-md-<ver>-macos-x86_64-unsigned.zip` |
| Windows | `windows-2022` | x64 | `quiet-md-<ver>-windows-x64-setup.exe` |
| Windows | `windows-2022` | arm64 (experimental, non-blocking) | `quiet-md-<ver>-windows-arm64-setup.exe` |

## What the packages are

* **Linux `.deb`** — `scripts/package-deb.sh` reads the binary's `NEEDED`
  entries and maps them onto packages with `dpkg -S`, so the control file names
  what was actually linked instead of a guessed table. Runtime dependencies are
  fontconfig, freetype, xkbcommon(+x11), xcb, Wayland client, Vulkan loader and
  OpenSSL; the GPU driver and fonts stay system-provided.
* **Linux tarball** — `scripts/package-linux.sh`, an FHS tree plus a desktop
  entry and a 512×512 icon.
* **AppImage** — `scripts/package-appimage.sh`, only on x86_64: the pinned
  `linuxdeploy` tooling has no reliable arm64 story.
* **macOS ZIPs** — `scripts/release.sh` with `SIGNING_IDENTITY=-`, i.e. ad-hoc
  signed. They run locally after a right-click → Open; they are not notarized
  and `publish-downloads.sh` refuses them on purpose.
* **Windows installer** — `scripts/package-windows.ps1` with Inno Setup 6 from
  the `windows-2022` image; unsigned, so SmartScreen asks once.

## Requirements on the target machine

Linux builds are made on Ubuntu 22.04, so the floor is glibc 2.35 with the
packages listed above. The binary is dynamically linked by design; run
`ldd quiet_md` to see exactly what a given package needs. A Vulkan-capable
driver is required at runtime (Mesa on ARM devices works).

## Building locally

```sh
cargo build --release --locked          # macOS / Windows / Linux
scripts/package-deb.sh                  # Linux .deb
scripts/package-linux.sh                # Linux tarball
scripts/package-appimage.sh             # Linux AppImage (x86_64)
scripts/release.sh                      # macOS ZIP (needs a Developer ID for a real release)
scripts/package-windows.ps1             # Windows installer (needs Inno Setup 6)
```
