# GLFW Wayland Minecraft Merged Patchset

[简体中文](README.md) | English

**!Important Disclaimer!: This project was generated entirely using DeepSeek Harness (dsh) and has only been tested on my own machine.**

This repository merges two Minecraft-oriented GLFW Wayland patch projects into one directly applicable series:

- [jdkeke142/glfw-wayland-minecraft](https://github.com/jdkeke142/glfw-wayland-minecraft) (7 patches)
- [glfw-wayland-minecraft-cursorfix](https://aur.archlinux.org/packages/glfw-wayland-minecraft-cursorfix) (AUR, 8 patches)

The merge removes duplicate patches, overlapping hunks, duplicate implementations, and fixes already present in the newer base. The result is **9 patches**.

## Target base

The patches are generated and verified against [LWJGL-CI/glfw](https://github.com/LWJGL-CI/glfw) at:

```text
03f63972b7238a179123f4cb3fa2c2539d5a6dea
tag: LWJGL-3.4.3
```

That commit reports version 3.5.1 in `include/GLFW/glfw3.h`. The GitHub project targets the LWJGL-CI fork, while the AUR project targets upstream GLFW 3.4. Unifying on the LWJGL-CI base is necessary; applying the AUR series directly conflicts in `wl_platform.h` and other places.

## Patch series

| # | Patch | Source | Notes |
|---|-------|--------|-------|
| 0001 | `Wayland: Ignore text input for shortcut combinations` | GitHub 0001 + AUR 0001 | Equivalent patches; one copy kept |
| 0002 | `Wayland: Filter duplicate pointer scroll events` | AUR 0002 | Rewritten to drop only identical repeats on the same axis |
| 0003 | `Wayland: Add cursor position fallback` | GitHub 0002 + 0007 + AUR 0003 | Locked-pointer fallback plus `GLFW_USE_LEGACY_CURSOR_WARP` |
| 0004 | `Wayland: Notify window size when leaving fullscreen` | GitHub 0003 + AUR 0004 | Equivalent patches; one copy kept |
| 0005 | `Wayland: Use cursor-shape-v1 for standard cursors` | GitHub 0005 | Keeps the tablet protocol symbol dependency, but does not bind the tablet manager |
| 0006 | `Add GLFW_FORCE_WAYLAND opt-in override` | GitHub 0006 | Merged unchanged |
| 0007 | `Wayland: Downgrade unsupported window errors` | AUR 0008 + 0006 | Downgrades window position errors and the missing-toplevel-icon error |
| 0008 | `Wayland: Let compositor choose fullscreen output` | AUR 0007 | Merged unchanged |
| 0009 | `Warn when the patched GLFW is initialized` | AUR 0005 | Message rewritten for the merged sources |

See [docs/merge-analysis.en.md](docs/merge-analysis.en.md) for per-patch conflict, duplicate, and design analysis.

## Applying

### Automatic

```bash
./scripts/apply.sh /tmp/glfw-wayland-merged
```

The script clones LWJGL-CI/glfw, checks out the pinned base commit, creates a `glfw-wayland-merged` branch, and applies every patch in `patches/` with `git am`. The destination must not already exist, so an existing worktree is never overwritten.

### Manual

```bash
git clone https://github.com/LWJGL-CI/glfw.git
cd glfw
git switch --create glfw-wayland-merged 03f63972b7238a179123f4cb3fa2c2539d5a6dea
git -c user.name='Patch Merge' \
    -c user.email='patch-merge@example.invalid' \
    am /path/to/patches/*.patch
```

Patches must be applied in filename order.

## Building

Wayland development dependencies (Arch Linux):

```bash
sudo pacman -S --needed base-devel cmake wayland wayland-protocols \
    libxkbcommon mesa libxi libxrandr libxcursor libxinerama
```

Build:

```bash
cmake -S glfw -B glfw/build \
    -DGLFW_BUILD_WAYLAND=ON \
    -DGLFW_BUILD_X11=ON \
    -DBUILD_SHARED_LIBS=ON \
    -DGLFW_BUILD_EXAMPLES=OFF \
    -DGLFW_BUILD_TESTS=OFF \
    -DGLFW_BUILD_DOCS=OFF
cmake --build glfw/build -j"$(nproc)"
```

The output is `glfw/build/src/libglfw.so`.

## Using with Minecraft

Add this to the launcher JVM arguments:

```text
-Dorg.lwjgl.glfw.libname=/absolute/path/to/libglfw.so
```

`-Dorg.lwjgl.librarypath` does not work for LWJGL: LWJGL extracts its bundled `libglfw.so` from the jar first. Use `org.lwjgl.glfw.libname` to force a specific file.

### Environment variables

| Variable | Effect |
|----------|--------|
| `GLFW_FORCE_WAYLAND=1` | If an application explicitly requests X11 (for example Minecraft 26.1+) and `WAYLAND_DISPLAY` is set, switch to Wayland |
| `GLFW_USE_LEGACY_CURSOR_WARP=1` | Skip `pointer_warp_v1` and use the `zwp_locked_pointer_v1` locked-pointer fallback. Useful on Hyprland and similar compositors where pointer warps stop working after repeated lock/unlock cycles |

Both variables must be explicitly set to the string `1`; unset or any other value leaves behavior unchanged.

## Key merge decisions

### Already in the new base, dropped

GitHub 0004's fractional-scale rounding fix is already present in the LWJGL-CI base:

```c
window->wl.fbWidth = (window->wl.width * window->wl.scalingNumerator + 60) / 120;
```

Reapplying it only causes context conflicts, so it is omitted.

### Duplicates and overlaps, merged

- GitHub 0001 and AUR 0001 are the same Ctrl/Alt text-input fix.
- GitHub 0003 and AUR 0004 are the same fullscreen-exit size-callback fix.
- GitHub 0002 already includes AUR 0003's locked-pointer fallback and additionally supports `pointer_warp_v1`. GitHub 0002 is the base implementation, and GitHub 0007's environment switch is folded into the same patch.
- AUR 0006 downgrades the "window icon is not supported" error to a warning. The current base implements `glfwSetWindowIcon`, but still raises that error when `xdg_toplevel_icon_manager_v1` is unavailable, so the still-relevant part is merged into 0007.

### Rewrite of AUR 0002

The original patch compares only timestamps:

```c
if (window->wl.pointerAxisTime == time)
    return;
```

That also discards the second axis of a two-axis event, such as a touchpad producing horizontal and vertical scroll with the same timestamp. The merged version tracks `(time, value)` per axis and drops only exact repeats on the same axis, preserving two-axis and normal high-resolution scrolling.

### cursor-shape-v1 tablet protocol dependency

`cursor-shape-v1.xml` has a `wp_cursor_shape_manager_v1.get_tablet_tool_v2` request that references `zwp_tablet_tool_v2_interface`. The interface table generated by wayland-scanner refers to that symbol. Building only the cursor-shape protocol produces this link failure for executables using `libglfw.so`:

```text
undefined reference to `zwp_tablet_tool_v2_interface'
```

The patchset therefore keeps `tablet-unstable-v2.xml` and its generated interface code solely to provide the symbol. GLFW does not bind the tablet manager and does not create tablet objects. This is recorded in the commit message for patch 0005.

## Verification

- `git am` of all 9 patches on the pinned base: all succeed, no fuzz, no conflicts.
- CMake build with both Wayland and X11, shared library: successful.
- Minimal runtime test in a KDE Wayland session: `glfwInit` selects Wayland, a standard cursor is created and destroyed, and `glfwTerminate` exits cleanly.
- `wayland-info` reports `wp_cursor_shape_manager_v1` v2 in that session; the patchset binds v1, which is protocol-compatible.
- **In-game verification**: Minecraft 1.21.1 + NeoForge and Minecraft 1.20.1 + Forge both pass, with the functionality covered by these patches working normally.
- **Test environment**: Mesa 26.2.5, KWin 6.8.1, 1.75x fractional scaling.

NVIDIA proprietary drivers and multi-monitor setups were not available for testing and still need validation on such systems.

## Known issues

- **Input methods do not work**: Fcitx 5 input methods do not work correctly, and the IMBlocker Mod does not work either. The same issue is reproducible on upstream GLFW; it was not introduced by this merge, and this patchset does not fix it.

## Known trade-offs

- **Fullscreen output hint**: Patch 0008 stops passing `wl_output` to `xdg_toplevel_set_fullscreen` and lets the compositor choose the output. This fixes some cases where fullscreen landed on the wrong monitor, but GLFW's monitor argument is no longer forwarded as an output hint. Multi-monitor setups can use [WayFix](https://github.com/jdkeke142/WayFix/tree/wayland-fixes) alongside this patchset.
- **Window error downgrade**: Patch 0007 changes `glfwGetWindowPos` / `glfwSetWindowPos` and the missing-toplevel-icon `glfwSetWindowIcon` error into stderr warnings, preventing Forge's error callback from aborting startup. Applications that rely on those error codes will no longer receive them.
- **Startup notice**: Patch 0009 prints a notice to stderr whenever `glfwInit` succeeds, so users can first reproduce issues with stock GLFW.

## Repository layout

```text
.
├── README.md
├── README.en.md
├── docs/
│   ├── merge-analysis.md
│   └── merge-analysis.en.md
├── patches/
│   ├── 0001-...patch
│   └── ... 0009-...patch
└── scripts/
    └── apply.sh
```

## License

Patched GLFW code remains under GLFW's zlib/libpng license. `deps/wayland/cursor-shape-v1.xml` and `deps/wayland/tablet-unstable-v2.xml` come from wayland-protocols; their copyright and license notices are retained in the files.
