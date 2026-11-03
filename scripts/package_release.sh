#!/usr/bin/env bash
# Builds the release packages into dist/ (no game files in them):
#   dist/Amped2-Recomp-<version>-<disc>-linux-x86_64.tar.gz   built in an Ubuntu 24.04 container -> glibc 2.39+
#   dist/Amped2-Recomp-<version>-<disc>-windows-x86_64.zip    MinGW cross build (scripts/build_win.sh), or on
#                                                              Windows (Git Bash) the native build in build-win/
# <disc> is the disc version the generated code belongs to (pal or ntsc-u): a package runs only with that disc.
#   scripts/package_release.sh v0.1.0
# Needs: docker (or podman) for the Linux build, mingw-w64-gcc and zip on the host for the Windows build, and the
# generated code (scripts/run_pipeline.sh).
#   SKIP_LINUX=1 / SKIP_WINDOWS=1   build only one of them
source "$(dirname "$0")/_common.sh"
VERSION="${1:?Usage: scripts/package_release.sh <version, e.g. v0.1.0>}"
[ -f "$GEN_DIR/recomp_funcs.h" ] || { echo "No generated code. First run: scripts/run_pipeline.sh" >&2; exit 1; }
DISC="$(tr _ - < "$GEN_DIR/xbe_version.txt")"   # pal / ntsc-u
DIST="$ROOT/dist"
JOBS="${JOBS:-8}"
mkdir -p "$DIST"
apply_runtime_patches

# Files every package gets: the player README, licenses, game_files/ with a note
common_files() {  # common_files <package dir>
  local pkg="$1"
  mkdir -p "$pkg/game_files"
  sed "s/@VERSION@/$VERSION/" "$ROOT/scripts/release/README.txt" > "$pkg/README.txt"
  cp "$ROOT/scripts/release/game_files_README.txt" "$pkg/game_files/README.txt"
  cp "$ROOT/LICENSE" "$pkg/LICENSE.txt"
  mkdir -p "$pkg/licenses"
  cp "$TOOLKIT/LICENSE" "$pkg/licenses/xboxrecomp-MIT.txt"
  cp "$TOOLKIT/NOTICE" "$pkg/licenses/xboxrecomp-NOTICE.txt"
  cp "$TOOLKIT/LICENSES/LGPL-2.1.txt" "$pkg/licenses/LGPL-2.1.txt"
  cp "$ROOT/third_party/volk/LICENSE.md" "$pkg/licenses/volk-MIT.txt"
  cp "$ROOT/third_party/SDL/LICENSE.txt" "$pkg/licenses/SDL2-zlib.txt"
}

if [ "${SKIP_LINUX:-0}" != 1 ]; then
  # Ubuntu 24.04 container (docker/Dockerfile) -> glibc 2.39, runs on older distros and SteamOS too
  BUILD_DIR="$ROOT/build-release-linux" JOBS="$JOBS" "$ROOT/scripts/docker.sh" scripts/build.sh
  PKG="$DIST/Amped2-Recomp-$VERSION-$DISC-linux-x86_64"
  rm -rf "$PKG"; mkdir -p "$PKG"
  cp "$ROOT/build-release-linux/amped2_recomp" "$ROOT/scripts/run.sh" "$PKG/"
  common_files "$PKG"
  tar -C "$DIST" -czf "$PKG.tar.gz" "$(basename "$PKG")"
  echo "Linux package: $PKG.tar.gz"
fi

if [ "${SKIP_WINDOWS:-0}" != 1 ]; then
  if command -v x86_64-w64-mingw32-gcc >/dev/null; then
    JOBS="$JOBS" "$ROOT/scripts/build_win.sh"
  elif [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* ]] && [ -f "$ROOT/build-win/CMakeCache.txt" ]; then
    # Native Windows (Git Bash): the configured build-win/ (llvm-mingw / MinGW toolchain on PATH)
    cmake --build "$ROOT/build-win" -j "$JOBS"
  else
    echo "No Windows toolchain: x86_64-w64-mingw32-gcc, or on Windows a configured build-win/" >&2; exit 1
  fi
  PKG="$DIST/Amped2-Recomp-$VERSION-$DISC-windows-x86_64"
  rm -rf "$PKG"; mkdir -p "$PKG"
  cp "$ROOT/build-win/amped2_recomp.exe" "$ROOT/scripts/release/run.bat" "$ROOT/scripts/release/run.ps1" "$PKG/"
  common_files "$PKG"
  # Windows line endings for the text files people open in Notepad
  for f in "$PKG"/*.txt "$PKG"/licenses/*.txt "$PKG"/game_files/*.txt "$PKG"/run.bat "$PKG"/run.ps1; do sed -i 's/\r*$/\r/' "$f"; done
  if command -v zip >/dev/null; then
    (cd "$DIST" && rm -f "$(basename "$PKG").zip" && zip -qr "$(basename "$PKG").zip" "$(basename "$PKG")")
  else                                              # Git Bash has no zip
    (cd "$DIST" && rm -f "$(basename "$PKG").zip" &&
     python -I -c 'import shutil, sys; shutil.make_archive(sys.argv[1], "zip", ".", sys.argv[1])' "$(basename "$PKG")")
  fi
  echo "Windows package: $PKG.zip"
fi

(cd "$DIST" && rm -f "SHA256SUMS-$VERSION.txt" &&
 sha256sum $(ls Amped2-Recomp-"$VERSION"-*.tar.gz Amped2-Recomp-"$VERSION"-*.zip 2>/dev/null) > "SHA256SUMS-$VERSION.txt")
cat "$DIST/SHA256SUMS-$VERSION.txt"
