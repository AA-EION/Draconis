#!/usr/bin/env bash
# Builds the Linux release and packages it as tar.gz, deb, rpm, AppImage and
# (with --flatpak) a Flatpak bundle, into build/linux/dist.
#   Scripts/package-linux.sh <version> [--flatpak]
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?version, e.g. 0.13.0}"
FLATPAK="${2:-}"
ID=io.github.aa_eion.Draconis
ARCH=x86_64
OUT=build/linux
PAYLOAD=$OUT/payload
DIST=$OUT/dist
rm -rf "$OUT"; mkdir -p "$PAYLOAD" "$DIST"

sed -i "s/static let version = \"[^\"]*\"/static let version = \"$VERSION\"/" CrossPlatform/Sources/DraconisCross/Settings.swift
swift build -c release --package-path CrossPlatform --product Draconis
BIN=$(swift build -c release --package-path CrossPlatform --show-bin-path)

# Payload shared by every format: binary next to its resource bundle and the
# Swift runtime it links (found through rpath $ORIGIN). GTK and libcurl come
# from the system.
cp "$BIN/Draconis" "$PAYLOAD/draconis"
strip "$PAYLOAD/draconis" || true
cp -r "$BIN/DraconisCross_Draconis.bundle" "$PAYLOAD/"
SWIFT_LIB=$(dirname "$(dirname "$(command -v swift)")")/lib/swift/linux
ldd "$PAYLOAD/draconis" | awk '{print $3}' | grep "^$SWIFT_LIB\|swift" | sort -u | while read -r lib; do
  [ -f "$lib" ] && cp -L "$lib" "$PAYLOAD/"
done
# The resolver may only see libs through the build tree's rpath; copy any the
# binary needs from the toolchain by name.
for name in $(readelf -d "$PAYLOAD/draconis" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p'); do
  [ -f "$SWIFT_LIB/$name" ] && cp -L "$SWIFT_LIB/$name" "$PAYLOAD/"
done
# Runtime libs pull in more runtime libs.
for _ in 1 2 3; do
  for so in "$PAYLOAD"/*.so; do
    for name in $(readelf -d "$so" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p'); do
      [ -f "$SWIFT_LIB/$name" ] && [ ! -f "$PAYLOAD/$name" ] && cp -L "$SWIFT_LIB/$name" "$PAYLOAD/"
    done
  done
done
strip --strip-unneeded "$PAYLOAD"/*.so || true
# Only ever look next to ourselves, never in the build machine's toolchain.
patchelf --set-rpath '$ORIGIN' "$PAYLOAD/draconis"
for so in "$PAYLOAD"/*.so; do patchelf --set-rpath '$ORIGIN' "$so"; done
cp packaging/linux/$ID.desktop "$PAYLOAD/"
sed -e "s/@VERSION@/$VERSION/" -e "s/@DATE@/$(date -u +%Y-%m-%d)/" packaging/linux/$ID.metainfo.xml > "$PAYLOAD/$ID.metainfo.xml"
cp CrossPlatform/Sources/DraconisCross/Resources/icon.png "$PAYLOAD/icon.png"
cp LICENSE THIRD-PARTY-NOTICES.md "$PAYLOAD/"

# tar.gz: run ./draconis from the extracted folder.
TARDIR="draconis-$VERSION-linux-$ARCH"
mkdir -p "$OUT/tar/$TARDIR"
cp -r "$PAYLOAD"/. "$OUT/tar/$TARDIR/"
tar -C "$OUT/tar" -czf "$DIST/$TARDIR.tar.gz" "$TARDIR"

# Filesystem tree for deb and rpm.
ROOT=$OUT/root
install -d "$ROOT/opt/draconis" "$ROOT/usr/bin"
cp "$PAYLOAD/draconis" "$PAYLOAD"/*.so "$ROOT/opt/draconis/"
cp -r "$PAYLOAD/DraconisCross_Draconis.bundle" "$ROOT/opt/draconis/"
ln -s ../../opt/draconis/draconis "$ROOT/usr/bin/draconis"
install -Dm644 "$PAYLOAD/$ID.desktop" "$ROOT/usr/share/applications/$ID.desktop"
install -Dm644 "$PAYLOAD/$ID.metainfo.xml" "$ROOT/usr/share/metainfo/$ID.metainfo.xml"
install -Dm644 "$PAYLOAD/icon.png" "$ROOT/usr/share/icons/hicolor/512x512/apps/$ID.png"
install -Dm644 -t "$ROOT/usr/share/doc/draconis" LICENSE THIRD-PARTY-NOTICES.md

# deb
DEB=$OUT/deb
cp -a "$ROOT" "$DEB"
install -d "$DEB/DEBIAN"
cat > "$DEB/DEBIAN/control" <<CONTROL
Package: draconis
Version: $VERSION
Architecture: amd64
Maintainer: AA-EION <noreply@github.com>
Depends: libgtk-4-1 (>= 4.6), libcurl4t64 | libcurl4
Recommends: steam | umu-launcher
Section: games
Priority: optional
Homepage: https://github.com/AA-EION/Draconis
Description: Titanfall 2 and Northstar launcher
 Installs and updates Northstar, manages Thunderstore mods, browses servers and
 launches Titanfall 2 through Steam, Proton (umu-launcher) or Wine.
CONTROL
dpkg-deb --root-owner-group --build "$DEB" "$DIST/draconis_${VERSION}_amd64.deb"

# rpm (from the same tree)
RPMTOP=$PWD/$OUT/rpm
mkdir -p "$RPMTOP"/{SPECS,BUILD,RPMS,SOURCES,SRPMS}
cat > "$RPMTOP/SPECS/draconis.spec" <<SPEC
Name: draconis
Version: ${VERSION//-/_}
Release: 1
Summary: Titanfall 2 and Northstar launcher
License: GPL-3.0-or-later
URL: https://github.com/AA-EION/Draconis
Requires: gtk4 >= 4.6, libcurl
AutoReqProv: no
%description
Installs and updates Northstar, manages Thunderstore mods, browses servers and
launches Titanfall 2 through Steam, Proton (umu-launcher) or Wine.
%install
cp -a $PWD/$ROOT/. %{buildroot}/
%files
/opt/draconis
/usr/bin/draconis
/usr/share/applications/$ID.desktop
/usr/share/metainfo/$ID.metainfo.xml
/usr/share/icons/hicolor/512x512/apps/$ID.png
/usr/share/doc/draconis
SPEC
rpmbuild --define "_topdir $RPMTOP" --define "_build_id_links none" -bb "$RPMTOP/SPECS/draconis.spec"
cp "$RPMTOP"/RPMS/*/draconis-*.rpm "$DIST/"

# AppImage (uses the system's GTK 4)
APPDIR=$OUT/AppDir
install -d "$APPDIR/usr/bin"
cp "$PAYLOAD/draconis" "$PAYLOAD"/*.so "$APPDIR/usr/bin/"
cp -r "$PAYLOAD/DraconisCross_Draconis.bundle" "$APPDIR/usr/bin/"
cp "$PAYLOAD/$ID.desktop" "$APPDIR/"
cp "$PAYLOAD/icon.png" "$APPDIR/$ID.png"
install -Dm644 "$PAYLOAD/$ID.metainfo.xml" "$APPDIR/usr/share/metainfo/$ID.appdata.xml"
cat > "$APPDIR/AppRun" <<'APPRUN'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/bin/draconis" "$@"
APPRUN
chmod +x "$APPDIR/AppRun"
TOOL=$OUT/appimagetool
curl -fsSL -o "$TOOL" https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage
echo "ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0  $TOOL" | sha256sum -c -
chmod +x "$TOOL"
ARCH=$ARCH "$TOOL" --appimage-extract-and-run --no-appstream "$APPDIR" "$DIST/Draconis-$VERSION-$ARCH.AppImage"

# Flatpak bundle
if [ "$FLATPAK" = "--flatpak" ]; then
  flatpak-builder --user --force-clean --repo="$OUT/flatpak-repo" "$OUT/flatpak-build" packaging/linux/$ID.yml
  flatpak build-bundle "$OUT/flatpak-repo" "$DIST/Draconis-$VERSION-$ARCH.flatpak" $ID \
    --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo
fi

(cd "$DIST" && sha256sum * > SHA256SUMS)
ls -la "$DIST"
