#!/usr/bin/env bash
# Build a Debian package from the binary produced by `cargo build --profile dist`.
#
#   scripts/package-deb.sh                     # target/dist -> dist/linux/*.deb
#   CARGO_TARGET_DIR=/tmp/t scripts/package-deb.sh
#
# The architecture comes from dpkg-architecture, so building inside an arm64
# root (a Debian/Ubuntu arm64 machine or an arm64 container) produces an arm64
# package. Runtime dependencies are read back from the binary with ldd and
# mapped onto the Debian package that ships each soname, so the list always
# matches what was actually linked instead of what the build machine happened
# to have installed.
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")/.."

[[ $(uname -s) == Linux ]] || { echo 'Build this package on Linux.' >&2; exit 1; }
command -v dpkg-deb >/dev/null || { echo 'Install dpkg-dev.' >&2; exit 1; }

if command -v magick >/dev/null 2>&1; then resize=magick
elif command -v convert >/dev/null 2>&1; then resize=convert
else echo 'Install ImageMagick to generate the icon.' >&2; exit 1
fi

version=$(sed -n 's/^version = "\([^"]*\)"/\1/p' Cargo.toml | head -1)
arch=$(dpkg --print-architecture)
target_dir=${CARGO_TARGET_DIR:-target}
if [[ -n ${BIN:-} ]]; then
  binary=$BIN
elif [[ -x $target_dir/dist/quiet_md ]]; then
  binary=$target_dir/dist/quiet_md
else
  binary=$target_dir/release/quiet_md
fi
[[ -x "$binary" ]] || { echo "Missing $binary; run: cargo build --release or --profile dist" >&2; exit 1; }

pkg=quiet-md
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
chmod 755 "$stage"
outdir=dist/linux
mkdir -p "$outdir"

# Layout: a plain FHS tree, no /opt and no bundled libraries. The graphics
# driver, fonts and desktop portal stay system-provided, as on every other
# distribution package.
install -d "$stage/DEBIAN" \
          "$stage/usr/bin" \
          "$stage/usr/share/applications" \
          "$stage/usr/share/icons/hicolor/512x512/apps" \
          "$stage/usr/share/doc/$pkg"
install -m755 "$binary" "$stage/usr/bin/quiet_md"
command -v strip >/dev/null && strip --strip-unneeded "$stage/usr/bin/quiet_md" 2>/dev/null || true
ln -s quiet_md "$stage/usr/bin/quiet-md"
install -m644 packaging/linux/com.s1dashu.quietmd.desktop "$stage/usr/share/applications/"
"$resize" assets/branding/app-icon.png -resize 512x512 "$stage/usr/share/icons/hicolor/512x512/apps/com.s1dashu.quietmd.png"
install -m644 LICENSE "$stage/usr/share/doc/$pkg/copyright"

# soname -> Debian package. Anything unmapped is reported and skipped; the
# package then needs that dependency added by hand.
declare -A map=(
  [libc.so.6]='libc6 (>= 2.35)'
  [libm.so.6]='libc6 (>= 2.35)'
  [libdl.so.2]='libc6 (>= 2.35)'
  [librt.so.1]='libc6 (>= 2.35)'
  [libpthread.so.0]='libc6 (>= 2.35)'
  [ld-linux-aarch64.so.1]='libc6 (>= 2.35)'
  [ld-linux-x86-64.so.2]='libc6 (>= 2.35)'
  [libgcc_s.so.1]='libgcc-s1'
  [libstdc++.so.6]='libstdc++6'
  [libfontconfig.so.1]='libfontconfig1'
  [libfreetype.so.6]='libfreetype6'
  [libexpat.so.1]='libexpat1'
  [libz.so.1]='zlib1g'
  [libbz2.so.1.0]='libbz2-1.0'
  [libpng16.so.16]='libpng16-16'
  [libbrotlidec.so.1]='libbrotli1'
  [libxkbcommon.so.0]='libxkbcommon0'
  [libxkbcommon-x11.so.0]='libxkbcommon-x11-0'
  [libxcb.so.1]='libxcb1'
  [libX11.so.6]='libx11-6'
  [libX11-xcb.so.1]='libx11-xcb1'
  [libxcb-*.so.*]='libxcb1'
  [libwayland-client.so.0]='libwayland-client0'
  [libwayland-cursor.so.0]='libwayland-cursor0'
  [libwayland-egl.so.1]='libwayland-egl1'
  [libvulkan.so.1]='libvulkan1'
  [libssl.so.3]='libssl3t64 | libssl3'
  [libcrypto.so.3]='libssl3t64 | libssl3'
  [libdbus-1.so.3]='libdbus-1-3'
  [libudev.so.1]='libudev1'
  [libdrm.so.2]='libdrm2'
  [libgbm.so.1]='libgbm1'
  [libEGL.so.1]='libegl1'
  [libGL.so.1]='libgl1'
)

declare -A deps=()
unknown=()
while read -r soname _; do
  [[ -n ${soname:-} ]] || continue
  hit=${map[$soname]:-}
  if [[ -z $hit ]]; then
    for pattern in "${!map[@]}"; do
      [[ $pattern == *'*'* && $soname == $pattern ]] && { hit=${map[$pattern]}; break; }
    done
  fi
  if [[ -n $hit ]]; then deps[$hit]=1; else unknown+=("$soname"); fi
done < <(ldd "$binary" | awk '$2 == "=>" && $3 ~ /^\// {print $1; next} $2 ~ /^\// {print $1}')

if ((${#unknown[@]})); then
  printf 'warning: no Debian package known for: %s\n' "${unknown[*]}" >&2
fi

# Libraries addressed with dlopen never show up in ldd but are still required:
# fontconfig for font discovery, the Vulkan loader for blade, the Wayland client
# protocols for the native window path when no X server is around.
for extra in libfontconfig1 libvulkan1 libwayland-client0 libwayland-cursor0 libwayland-egl1; do
  deps[$extra]=1
done

depends=$(printf '%s\n' "${!deps[@]}" | sort | paste -sd, - | sed 's/,/, /g')

installed_size=$(du -sk "$stage" | cut -f1)

cat > "$stage/DEBIAN/control" <<EOF
Package: $pkg
Version: $version
Section: editors
Priority: optional
Architecture: $arch
Maintainer: s1dashu <s1dashu@users.noreply.github.com>
Installed-Size: $installed_size
Depends: $depends
Recommends: fonts-noto-core, fonts-noto-cjk, mesa-vulkan-drivers, xdg-desktop-portal, xdg-utils
Homepage: https://quiet.md
Description: fast, local-first rich-text notes app
 Quiet.md is a note-taking app and rich-text editor drawn with GPUI. Notes are
 stored as files under ~/Documents/Quiet.md, Markdown files can be edited in
 place, and export covers DocxXML-compatible formats.
EOF

(cd "$stage" && find . -path ./DEBIAN -prune -o -type f -print0 | sort -z | xargs -0 md5sum > DEBIAN/md5sums)
chmod 644 "$stage/DEBIAN/md5sums" "$stage/DEBIAN/control"

deb="$outdir/${pkg}_${version}_${arch}.deb"
dpkg-deb --root-owner-group -Zxz --build "$stage" "$deb" >/dev/null
(cd "$outdir" && sha256sum "$(basename "$deb")" > "$(basename "$deb").sha256")
dpkg-deb --info "$deb"
printf '%s\n' "$deb"
