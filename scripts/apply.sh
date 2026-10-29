#!/usr/bin/env bash
#
# Clone the pinned LWJGL-CI/glfw base and apply the merged patch series.
#
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BASE_COMMIT=03f63972b7238a179123f4cb3fa2c2539d5a6dea
DEST=${1:-"$ROOT/glfw-wayland-merged"}

if [ -e "$DEST" ]; then
    printf 'error: destination already exists: %s\n' "$DEST" >&2
    printf 'choose another path or remove it first\n' >&2
    exit 1
fi

printf 'cloning LWJGL-CI/glfw into %s\n' "$DEST"
git clone https://github.com/LWJGL-CI/glfw.git "$DEST"

printf 'checking out base commit %s\n' "$BASE_COMMIT"
git -C "$DEST" switch --create glfw-wayland-merged "$BASE_COMMIT"

printf 'applying %s patches\n' "$(find "$ROOT/patches" -maxdepth 1 -name '*.patch' | wc -l)"
git -C "$DEST" \
    -c user.name='Patch Merge' \
    -c user.email='patch-merge@example.invalid' \
    am "$ROOT"/patches/*.patch

cat <<EOF

Applied patch series:
$(git -C "$DEST" log --oneline --decorate "$BASE_COMMIT"..HEAD)

Build with:
  cmake -S "$DEST" -B "$DEST/build" \\
      -DGLFW_BUILD_WAYLAND=ON -DGLFW_BUILD_X11=ON \\
      -DBUILD_SHARED_LIBS=ON -DGLFW_BUILD_EXAMPLES=OFF \\
      -DGLFW_BUILD_TESTS=OFF -DGLFW_BUILD_DOCS=OFF
  cmake --build "$DEST/build" -j"\$(nproc)"
EOF
