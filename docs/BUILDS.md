# Prebuilt packages

Every `v*` tag starts four jobs; each one attaches its packages to the matching
release.

| Platform | Runner | Architecture | Files |
| --- | --- | --- | --- |
| Linux | `ubuntu-22.04` | x86_64 | `.deb`, `.pkg.tar.zst`, `.tar.gz`, `.AppImage` |
| Linux | `ubuntu-24.04-arm` | aarch64 | `.deb`, `.pkg.tar.zst`, `.tar.gz` |
| macOS | `macos-15` | Apple Silicon | `quiet-md-<ver>-macos-arm64-unsigned.zip` |
| macOS | `macos-15` | Intel (cross) | `quiet-md-<ver>-macos-x86_64-unsigned.zip` |
| Windows | `windows-2022` | x64 | `quiet-md-<ver>-windows-x64-setup.exe` |
| Windows | `windows-2022` | arm64 (experimental, non-blocking) | `quiet-md-<ver>-windows-arm64-setup.exe` |

## Which package for which distribution

| Distribution | Package | Install |
| --- | --- | --- |
| Debian / Ubuntu / Mint / Pop!_OS | `quiet-md_<ver>_<arch>.deb` | `sudo apt install ./quiet-md_*.deb` |
| Arch / Manjaro / EndeavourOS / CachyOS | `quiet-md-<ver>-1-<arch>.pkg.tar.zst` | `sudo pacman -U ./quiet-md-*.pkg.tar.zst` |
| Any Linux, no install | `quiet-md-<ver>-x86_64.AppImage` | `chmod +x` then run |
| Any Linux, portable tree | `quiet-md-<ver>-linux-<arch>.tar.gz` | unpack and run `bin/quiet_md` |
| macOS | `quiet-md-<ver>-macos-<arch>-unsigned.zip` | right-click → Open on first launch |
| Windows | `quiet-md-<ver>-windows-<arch>-setup.exe` | run the installer |

The Arch package is assembled by `scripts/package-arch.sh` on the Ubuntu runner:
a `.pkg.tar.zst` is just a zstd-compressed tar with a `.PKGINFO` at its root, so
`pacman -U` accepts it even though it was not built on Arch. Its dependency
names are Arch's (`fontconfig`, `freetype2`, `libxkbcommon`, `libxcb`,
`wayland`, `vulkan-icd-loader`, `openssl`, …).

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

## Automatic upstream sync

`sync-upstream.yml` runs on a GitHub-hosted schedule (every six hours) and on
demand. It merges `s1dashu/quiet-md` `main` into this repository, pushes, and
then dispatches the three build workflows explicitly — a push made with
`GITHUB_TOKEN` does not start other workflows, so the dispatch is required.
When the merged `Cargo.toml` carries a version that has no tag yet, the matching
`v<version>` tag is created so the builds attach to a release.

This fork only *adds* files (workflows, packaging scripts, docs) and never edits
upstream sources, so the merge is conflict-free by construction. Patch-replay
forks (MindustryX and similar) need `patches/*.patch` because they modify
upstream code; here a merge is both simpler and safer — if a future change does
touch upstream code, git reports the conflict instead of silently dropping a
patch.

To sync by hand:

```sh
gh workflow run sync-upstream.yml --repo mlfc666/quiet-md-builds
# or force a rebuild without new upstream commits
gh workflow run sync-upstream.yml --repo mlfc666/quiet-md-builds -f force=true
```
