# Patch Merge Analysis

[简体中文](merge-analysis.md) | English

This document records the per-patch handling of both upstream patchsets, along with the conflicts and code-level trade-offs encountered during the merge.

## Base differences

| Project | Base used for its patches | Characteristics |
|---------|---------------------------|-----------------|
| jdkeke142/glfw-wayland-minecraft | LWJGL-CI/glfw (3.5.1 header; includes `pointer_warp_v1`, fractional scaling, toplevel icon) | Patch numbers are generated against the newer base and depend on `wp_pointer_warp_v1` |
| AUR glfw-wayland-minecraft-cursorfix | upstream GLFW 3.4 tarball | No `pointer_warp_v1`; cursor positioning uses `zwp_locked_pointer_v1` |

Applying the AUR series directly to the LWJGL-CI base fails on the `wl_platform.h` hunk in `0003-Implement-glfwSetCursorPosWayland.patch`. The AUR series inserts `pointerAxisTime` first, while the newer base has already reworked pointer event handling and the window state layout. That conflict also shows that the two projects evolved the same code in different directions.

## Per-source-patch handling

### GitHub project

| Source patch | Content | Handling | Reason |
|--------------|---------|----------|--------|
| 0001 | Do not emit text input while Ctrl/Alt is held | Merged into 0001 | Logically equivalent to AUR 0001 |
| 0002 | `pointer_warp_v1` plus locked-pointer fallback | Merged into 0003 | Absorbs AUR 0003's deferred request and adds GitHub 0007's environment switch |
| 0003 | Fire window size callback when exiting fullscreen | Merged into 0004 | Equivalent to AUR 0004 |
| 0004 | Round framebuffer size for fractional scaling | **Not applied** | The pinned base already contains the `+ 60` round-half-up implementation |
| 0005 | `cursor-shape-v1` standard cursors | Merged into 0005 | Keeps the required tablet protocol symbol, but does not bind the tablet manager |
| 0006 | `GLFW_FORCE_WAYLAND` | Merged into 0006 | No conflict |
| 0007 | `GLFW_USE_LEGACY_CURSOR_WARP` | Folded into 0003 | It modifies the same function as the cursor-position work, so a separate patch would duplicate changes |

### AUR project

| Source patch | Content | Handling | Reason |
|--------------|---------|----------|--------|
| 0001 | Key modifiers fix | Merged into 0001 | Equivalent to GitHub 0001; duplicate removed |
| 0002 | Deduplicate GNOME pointer scroll events | Merged into 0002 (rewritten) | Timestamp-only deduplication would drop one axis of two-axis scrolling |
| 0003 | `glfwSetCursorPosWayland` via locked pointer | Removed | Superseded by GitHub 0002's complete implementation |
| 0004 | Window size after leaving fullscreen | Merged into 0004 | Equivalent to GitHub 0003; duplicate removed |
| 0005 | Unofficial-build startup notice | Merged into 0009 | Text updated to point at the merged sources |
| 0006 | Downgrade window icon error | Merged into 0007 | The base implements `glfwSetWindowIcon`, but still errors when `xdg_toplevel_icon_manager_v1` is unavailable |
| 0007 | Omit output when entering fullscreen | Merged into 0008 | No conflict; behavior fix retained |
| 0008 | Forge window-position crash | Merged into 0007 | Combined with 0006 into one error-downgrade patch |

## Conflict details

### Window state in `wl_platform.h`

AUR 0002 and 0003 both append fields to `_GLFWwindowWayland`:

```c
uint32_t pointerAxisTime;
double askedCursorPosX, askedCursorPosY;
GLFWbool didAskForSetCursorPos;
```

The newer base splits pointer state into `cursorPosX/Y`, `pointer`, `lockedPointer`, and other fields, and routes scroll events through `_glfw.wl.pending` before processing them in `wl_pointer.frame`. The AUR 0003 hunk no longer matches the surrounding structure.

The merged fields are placed where they belong semantically:

```c
struct {
    GLFWbool valid;
    uint32_t time;
    wl_fixed_t value;
} pointerAxis[2];

double askedCursorPosX, askedCursorPosY;
GLFWbool didAskForSetCursorPos;
```

### Three cursor-position paths

The merged `_glfwSetCursorPosWayland` uses this priority:

1. If `GLFW_USE_LEGACY_CURSOR_WARP=1` is not set and `pointer_warp_v1` is available, warp directly.
2. Otherwise, if the pointer is locked, call `zwp_locked_pointer_v1_set_cursor_position_hint`.
3. Otherwise, store the request and replay it from `lockedPointerHandleLocked`.

This is more complete than either upstream version: GitHub 0002 has no environment switch, and AUR 0003 has no `pointer_warp_v1` path.

### Scroll event deduplication

The original AUR logic:

```c
if (window->wl.pointerAxisTime == time)
    return;
window->wl.pointerAxisTime = time;
```

The problem is that horizontal and vertical scroll can share the same `time`, so the second axis would be swallowed. The merged version uses:

```c
if (window->wl.pointerAxis[i].valid &&
    window->wl.pointerAxis[i].time == time &&
    window->wl.pointerAxis[i].value == value)
    return;
```

Only an identical repeat on the same axis at the same timestamp is dropped. On the newer base, frame-based processing already coalesces scroll values within a frame; this check mainly covers duplicates arriving in separate frames and the legacy compositor path.

### cursor-shape protocol link failure

Keeping only `cursor-shape-v1.xml` allows `libglfw.so` itself to build, but linking an executable that uses GLFW fails:

```text
/usr/bin/ld: libglfw.so: undefined reference to `zwp_tablet_tool_v2_interface'
```

The generated `wp_cursor_shape_manager_v1_interface` method table contains:

```c
{ "get_tablet_tool_v2", "no", cursor_shape_v1_types + 4 },
```

and entry 6 of `cursor_shape_v1_types` is `&zwp_tablet_tool_v2_interface`. The symbol must exist.

The solution:

- keep `deps/wayland/tablet-unstable-v2.xml`;
- generate the tablet protocol in `src/CMakeLists.txt`;
- compile the tablet private-code in `src/wl_init.c` to provide `zwp_tablet_tool_v2_interface`;
- do not bind `zwp_tablet_manager_v2` and do not create tablet objects;
- comment that this is a link dependency, not a feature dependency.

This is safer than forging a `wl_interface` symbol by hand and avoids leaving a fake interface behind when the protocol is updated.

### Window icon error still exists

AUR 0006 changes:

```c
_glfwInputError(GLFW_FEATURE_UNAVAILABLE,
                "Wayland: The platform does not support setting the window icon");
```

into an `fprintf`. The pinned base's `_glfwSetWindowIconWayland` already implements icon setting through `xdg_toplevel_icon_manager_v1`, but it still takes this error path when the compositor does not provide that manager. Some Minecraft versions set a window icon unconditionally at startup, and Forge's error callback treats it as fatal.

The merged patchset therefore keeps the downgrade and puts it together with AUR 0008's two window-position errors in patch 0007.

### Fullscreen output argument

AUR 0007 changes four call sites from:

```c
libdecor_frame_set_fullscreen(frame, window->monitor->wl.output);
xdg_toplevel_set_fullscreen(toplevel, window->monitor->wl.output);
```

to passing `NULL`. The merge keeps this change because:

- some compositors use the supplied `wl_output` to force a fullscreen window onto a stale monitor;
- with `NULL`, the compositor uses the output where the window currently is, matching what the user sees;
- the cost is that GLFW's `monitor` argument is no longer forwarded as an output hint, so precise multi-monitor targeting needs additional handling.

This is a behavioral trade-off, not pure code deduplication.

## Code not merged

| Code | Reason |
|------|--------|
| GitHub 0004's `+ 60` rounding | The base already contains exactly the same implementation |
| AUR 0006 as a separate patch | Its still-relevant changes are merged into 0007 |
| AUR 0001 / 0003 / 0004 | Covered by GitHub 0001 / 0002 / 0003 respectively |
| Tablet manager binding/use from GitHub 0005 | The original patch did not actually use tablets either; only the protocol symbol is retained |
| AUR 0002's single-timestamp check | It would drop one axis of two-axis scrolling; replaced by per-axis exact deduplication |

## Verification record

```text
Base: 03f63972b7238a179123f4cb3fa2c2539d5a6dea
Apply: git am patches/*.patch
Result: 9/9 succeed, no conflicts

Build:
cmake -DGLFW_BUILD_WAYLAND=ON -DGLFW_BUILD_X11=ON -DBUILD_SHARED_LIBS=ON ...
cmake --build ...
Result: libglfw.so builds successfully

Runtime:
KDE Wayland session, glfwInit -> glfwCreateStandardCursor -> glfwDestroyCursor -> glfwTerminate
Result: clean exit, Wayland platform selected

In-game:
Minecraft 1.21.1 + NeoForge
Minecraft 1.20.1 + Forge
Result: functionality covered by the patches works normally

Environment:
Mesa 26.2.5
KWin 6.8.1
1.75x fractional scaling
Result: pass
```

Not covered: NVIDIA proprietary drivers and multi-monitor fullscreen transitions.

## Known issue

Under Fcitx 5, input methods do not work correctly, and the IMBlocker Mod does not work either. The same issue exists on upstream patchset; it was not introduced by this merge, and this patchset does not fix it.
