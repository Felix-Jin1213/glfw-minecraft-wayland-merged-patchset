# 补丁合并分析

[English](merge-analysis.en.md) | 简体中文

本文记录两个上游补丁集的逐项处理，以及合并时实际遇到的冲突和代码级取舍。

## 基线差异

| 项目 | 写作基线 | 特征 |
|------|----------|------|
| jdkeke142/glfw-wayland-minecraft | LWJGL-CI/glfw（3.5.1 头文件，含 `pointer_warp_v1`、分数缩放、toplevel icon） | 补丁序号按新基线生成，依赖 `wp_pointer_warp_v1` |
| AUR glfw-wayland-minecraft-cursorfix | upstream GLFW 3.4 tarball | 没有 `pointer_warp_v1`；用 `zwp_locked_pointer_v1` 实现光标位置 |

把 AUR 序列直接套到 LWJGL-CI 基线时，`0003-Implement-glfwSetCursorPosWayland.patch` 对 `wl_platform.h` 的 hunk 会失败，原因是 AUR 0002 先插入了 `pointerAxisTime`，而新基线已经改写了指针事件处理和结构体布局。这个冲突本身也说明两个项目对同一块代码有不同的演进方向。

## 源补丁逐项处理

### GitHub 项目

| 源补丁 | 内容 | 处理 | 原因 |
|--------|------|------|------|
| 0001 | Ctrl/Alt 按下时不发送文本输入 | 合并为 0001 | 与 AUR 0001 逻辑等价 |
| 0002 | `pointer_warp_v1` + 锁定指针回退 | 合并为 0003 | 吸收 AUR 0003 的延迟应用逻辑，并加入 GitHub 0007 的环境变量 |
| 0003 | 退出全屏时触发窗口尺寸回调 | 合并为 0004 | 与 AUR 0004 等价 |
| 0004 | 分数缩放 framebuffer 取整 | **不应用** | 固定基线已经包含 `+ 60` 的 round-half-up 实现 |
| 0005 | `cursor-shape-v1` 标准光标 | 合并为 0005 | 保留所需的 tablet 协议符号，但不绑定 tablet manager |
| 0006 | `GLFW_FORCE_WAYLAND` | 合并为 0006 | 无冲突 |
| 0007 | `GLFW_USE_LEGACY_CURSOR_WARP` | 折入 0003 | 与光标位置实现是同一函数，拆开会重复修改 |

### AUR 项目

| 源补丁 | 内容 | 处理 | 原因 |
|--------|------|------|------|
| 0001 | Key Modifiers Fix | 合并为 0001 | 与 GitHub 0001 等价，删除 |
| 0002 | 去重 GNOME 重复滚轮事件 | 合并为 0002（改写） | 原实现按时间戳去重会误伤二维滚动 |
| 0003 | `glfwSetCursorPosWayland` 锁定指针实现 | 删除 | 已被 GitHub 0002 的完整实现取代 |
| 0004 | 退出全屏窗口尺寸 | 合并为 0004 | 与 GitHub 0003 等价，删除 |
| 0005 | 非官方补丁启动提示 | 合并为 0009 | 更新提示文字，指向合并来源 |
| 0006 | 窗口图标错误降级 | 并入 0007 | 当前基线已实现 `glfwSetWindowIcon`，但缺少 `xdg_toplevel_icon_manager_v1` 时仍会报错 |
| 0007 | 全屏时不指定输出 | 合并为 0008 | 无冲突，保留行为修复 |
| 0008 | Forge 窗口位置崩溃 | 合并为 0007 | 与 0006 一起统一降级为警告 |

## 冲突细节

### `wl_platform.h` 的窗口状态结构

AUR 0002 和 0003 都向 `_GLFWwindowWayland` 尾部插入字段：

```c
uint32_t pointerAxisTime;
double askedCursorPosX, askedCursorPosY;
GLFWbool didAskForSetCursorPos;
```

新基线把指针状态拆成 `cursorPosX/Y`、`pointer`、`lockedPointer` 等多组字段，并把滚动事件改为先进入 `_glfw.wl.pending`、在 `wl_pointer.frame` 中统一处理。直接应用 AUR 0003 时，结构体上下文已经对不上。

合并后的字段放在对应语义位置：

```c
struct {
    GLFWbool valid;
    uint32_t time;
    wl_fixed_t value;
} pointerAxis[2];

double askedCursorPosX, askedCursorPosY;
GLFWbool didAskForSetCursorPos;
```

### 光标位置的三种路径

合并后的 `_glfwSetCursorPosWayland` 按优先级处理：

1. 未设置 `GLFW_USE_LEGACY_CURSOR_WARP=1` 且存在 `pointer_warp_v1`：直接 warp。
2. 否则如果指针已锁定：调用 `zwp_locked_pointer_v1_set_cursor_position_hint`。
3. 否则：记录请求，在 `lockedPointerHandleLocked` 中补发。

这比两个上游版本都完整：GitHub 0002 没有环境变量开关，AUR 0003 没有 `pointer_warp_v1` 路径。

### 滚轮事件去重

AUR 原逻辑：

```c
if (window->wl.pointerAxisTime == time)
    return;
window->wl.pointerAxisTime = time;
```

问题：横向和纵向滚动可以共享同一个 `time`，这样第二条轴会被吞掉。合并版改成：

```c
if (window->wl.pointerAxis[i].valid &&
    window->wl.pointerAxis[i].time == time &&
    window->wl.pointerAxis[i].value == value)
    return;
```

只丢弃同轴、同时间、同值的重复事件。对于新基线中带 `wl_pointer.frame` 的路径，frame 内本来就会合并滚动值；这个检查主要覆盖跨 frame 的重复事件，以及旧版 compositor 路径。

### cursor-shape 协议链接失败

只保留 `cursor-shape-v1.xml` 时，CMake 构建 `libglfw.so` 可以通过，但链接一个使用 GLFW 的可执行文件会失败：

```text
/usr/bin/ld: libglfw.so: undefined reference to `zwp_tablet_tool_v2_interface'
```

原因是 wayland-scanner 生成的 `wp_cursor_shape_manager_v1_interface` 的方法表里包含：

```c
{ "get_tablet_tool_v2", "no", cursor_shape_v1_types + 4 },
```

而 `cursor_shape_v1_types` 的第 6 项是 `&zwp_tablet_tool_v2_interface`。这个符号必须存在。

处理方式：

- 保留 `deps/wayland/tablet-unstable-v2.xml`；
- 在 `src/CMakeLists.txt` 中同时生成 tablet 协议；
- 在 `src/wl_init.c` 中编译 tablet 的 private-code，提供 `zwp_tablet_tool_v2_interface`；
- 不绑定 `zwp_tablet_manager_v2`，不创建 tablet 对象；
- 用注释说明这是链接依赖，不是功能依赖。

这样比手工伪造一个 `wl_interface` 符号安全，也不会在协议升级时留下假接口。

### 窗口图标错误仍然存在

AUR 0006 把：

```c
_glfwInputError(GLFW_FEATURE_UNAVAILABLE,
                "Wayland: The platform does not support setting the window icon");
```

改成 `fprintf`。固定基线的 `_glfwSetWindowIconWayland` 虽然已经通过 `xdg_toplevel_icon_manager_v1` 实现图标设置，但在合成器没有该 manager 时仍会走这条错误路径。部分 Minecraft 版本启动时会无条件设置图标，Forge 的错误回调会把它当成致命错误。

因此合并版保留了这个降级，并把它和 AUR 0008 的两个窗口位置错误放进同一个补丁 0007。

### 全屏输出参数

AUR 0007 把四处：

```c
libdecor_frame_set_fullscreen(frame, window->monitor->wl.output);
xdg_toplevel_set_fullscreen(toplevel, window->monitor->wl.output);
```

改成传 `NULL`。合并版保留这个改动，原因是：

- 部分合成器会用传入的 `wl_output` 强制把全屏窗口放到旧显示器；
- 传 `NULL` 时合成器按窗口当前所在输出处理，和用户看到的窗口位置一致；
- 代价是 GLFW 的 `monitor` 参数不再作为输出提示传递，多显示器精确目标需要额外处理。

这是行为取舍，不是纯粹的代码去重。

## 没有合并的代码

| 代码 | 原因 |
|------|------|
| GitHub 0004 的 `+ 60` 取整 | 基线已有完全相同实现 |
| AUR 0006 的独立补丁 | 有效改动已并入 0007，不再单独成补丁 |
| AUR 0001 / 0003 / 0004 | 分别被 GitHub 0001 / 0002 / 0003 覆盖 |
| GitHub 0005 中的 tablet manager 绑定/使用 | 原补丁也没有真正使用 tablet，只保留协议符号 |
| AUR 0002 的时间戳单值判断 | 会误伤二维滚动，改为按轴精确去重 |

## 验证记录

```text
基线: 03f63972b7238a179123f4cb3fa2c2539d5a6dea
应用: git am patches/*.patch
结果: 9/9 成功，无冲突

构建:
cmake -DGLFW_BUILD_WAYLAND=ON -DGLFW_BUILD_X11=ON -DBUILD_SHARED_LIBS=ON ...
cmake --build ...
结果: libglfw.so 构建成功

运行:
KDE Wayland 会话下 glfwInit -> glfwCreateStandardCursor -> glfwDestroyCursor -> glfwTerminate
结果: 正常退出，平台为 Wayland

游戏内:
Minecraft 1.21.1 + NeoForge
Minecraft 1.20.1 + Forge
结果: 补丁覆盖的功能正常

环境:
Mesa 26.2.5
KWin 6.8.1
1.75x 分数缩放
结果: 通过
```

未覆盖：NVIDIA 专有驱动、多显示器全屏切换。

## 已知问题

在 Fcitx 5 下输入法无法正常工作，IMBlocker Mod 也不能正常工作。该问题在上游 GLFW 上同样存在，不是本次合并引入的，当前补丁集没有修复它。
