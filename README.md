# GLFW Wayland Minecraft 合并补丁集

[English](README.en.md) | 简体中文

**! 重要声明 !：本项目完全使用 DeepSeek Harness (dsh) 生成，并且只在我自己的机器上测试过。**

把下面两个面向 Minecraft 的 GLFW Wayland 补丁项目合并成一套可直接应用的补丁：

- [jdkeke142/glfw-wayland-minecraft](https://github.com/jdkeke142/glfw-wayland-minecraft)（7 个补丁）
- [glfw-wayland-minecraft-cursorfix](https://aur.archlinux.org/packages/glfw-wayland-minecraft-cursorfix)（AUR，8 个补丁）

合并结果消除了重复补丁、互相覆盖的 hunk、重复实现，以及已经被新基线包含的修复。最终得到 **9 个补丁**。

## 目标基线

补丁针对 [LWJGL-CI/glfw](https://github.com/LWJGL-CI/glfw) 的以下提交生成并验证：

```text
03f63972b7238a179123f4cb3fa2c2539d5a6dea
tag: LWJGL-3.4.3
```

该提交的 `include/GLFW/glfw3.h` 报告版本为 3.5.1。GitHub 项目的补丁按 LWJGL-CI 分支编写；AUR 项目的补丁按 upstream GLFW 3.4 编写，因此统一到 LWJGL-CI 基线是必要的。直接使用 AUR 的补丁序列会在 `wl_platform.h` 等处发生上下文冲突。

## 补丁序列

| # | 补丁 | 来源 | 说明 |
|---|------|------|------|
| 0001 | `Wayland: Ignore text input for shortcut combinations` | GitHub 0001 + AUR 0001 | 两个补丁等价，只保留一份 |
| 0002 | `Wayland: Filter duplicate pointer scroll events` | AUR 0002 | 改写为只过滤“同轴、同时间戳、同值”的重复事件 |
| 0003 | `Wayland: Add cursor position fallback` | GitHub 0002 + 0007 + AUR 0003 | 合并指针锁定回退与 `GLFW_USE_LEGACY_CURSOR_WARP` |
| 0004 | `Wayland: Notify window size when leaving fullscreen` | GitHub 0003 + AUR 0004 | 两个补丁等价，只保留一份 |
| 0005 | `Wayland: Use cursor-shape-v1 for standard cursors` | GitHub 0005 | 保留 tablet 协议符号依赖，但不绑定 tablet manager |
| 0006 | `Add GLFW_FORCE_WAYLAND opt-in override` | GitHub 0006 | 原样合并 |
| 0007 | `Wayland: Downgrade unsupported window errors` | AUR 0008 + 0006 | 窗口位置与缺少 toplevel-icon manager 时的窗口图标错误统一降级 |
| 0008 | `Wayland: Let compositor choose fullscreen output` | AUR 0007 | 原样合并 |
| 0009 | `Warn when the patched GLFW is initialized` | AUR 0005 | 改写提示文字，指向合并后的补丁来源 |

逐补丁的冲突、重复和取舍分析见 [docs/merge-analysis.md](docs/merge-analysis.md)。

## 应用

### 自动应用

```bash
./scripts/apply.sh /tmp/glfw-wayland-merged
```

脚本会克隆 LWJGL-CI/glfw、检出固定基线提交，然后用 `git am` 应用 `patches/` 下的全部补丁。目标目录必须不存在，避免覆盖已有工作区。

### 手动应用

```bash
git clone https://github.com/LWJGL-CI/glfw.git
cd glfw
git switch --create glfw-wayland-merged 03f63972b7238a179123f4cb3fa2c2539d5a6dea
git -c user.name='Patch Merge' \
    -c user.email='patch-merge@example.invalid' \
    am /path/to/patches/*.patch
```

补丁按文件名顺序应用，顺序不能打乱。

## 构建

Wayland 开发依赖（Arch 系）：

```bash
sudo pacman -S --needed base-devel cmake wayland wayland-protocols \
    libxkbcommon mesa libxi libxrandr libxcursor libxinerama
```

构建：

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

产物为 `glfw/build/src/libglfw.so`。

## 在 Minecraft 中使用

在启动器 JVM 参数中加入：

```text
-Dorg.lwjgl.glfw.libname=/绝对路径/libglfw.so
```

`-Dorg.lwjgl.librarypath` 对 LWJGL 无效：LWJGL 会先从 jar 中解压自带的 `libglfw.so`，所以必须用 `org.lwjgl.glfw.libname` 强制指定文件。

### 环境变量

| 变量 | 作用 |
|------|------|
| `GLFW_FORCE_WAYLAND=1` | 当应用显式请求 X11（例如 Minecraft 26.1+）且存在 `WAYLAND_DISPLAY` 时，强制改用 Wayland |
| `GLFW_USE_LEGACY_CURSOR_WARP=1` | 跳过 `pointer_warp_v1`，改用 `zwp_locked_pointer_v1` 的锁定指针回退。适用于 Hyprland 等 pointer warp 在反复锁定/解锁后失效的环境 |

两个变量都必须显式设为字符串 `1`，未设置或设为其他值时行为不变。

## 合并时的主要判断

### 已在新基线中，删除

GitHub 0004 的分数缩放取整修复已经存在于 LWJGL-CI 基线：

```c
window->wl.fbWidth = (window->wl.width * window->wl.scalingNumerator + 60) / 120;
```

因此不再重复打补丁，否则会产生上下文冲突。

### 重复或互相覆盖，合并

- GitHub 0001 与 AUR 0001 是同一个 Ctrl/Alt 文本输入修复。
- GitHub 0003 与 AUR 0004 是同一个退出全屏尺寸回调修复。
- GitHub 0002 已经包含 AUR 0003 的锁定指针回退，并额外支持 `pointer_warp_v1`，所以以 GitHub 0002 为主，把 GitHub 0007 的环境变量开关折进同一补丁。
- AUR 0006 把“不支持设置窗口图标”从错误降为警告。当前基线虽然实现了 `glfwSetWindowIcon`，但在缺少 `xdg_toplevel_icon_manager_v1` 的合成器上仍会报错，所以该改动的有效部分并入 0007。

### AUR 0002 的改写

原补丁只比较时间戳：

```c
if (window->wl.pointerAxisTime == time)
    return;
```

这会误伤同一时间戳内的第二条轴事件，例如触控板一次二维滚动会同时产生横向和纵向事件。合并版按轴分别记录 `(time, value)`，只丢弃同轴、同时间戳、同值的完全重复事件，保留二维滚动和正常的高分辨率滚动。

### cursor-shape-v1 的 tablet 协议依赖

`cursor-shape-v1.xml` 的 `wp_cursor_shape_manager_v1.get_tablet_tool_v2` 请求引用了 `zwp_tablet_tool_v2_interface`。wayland-scanner 生成的接口表会引用该符号，如果只编译 cursor-shape 协议，可执行文件链接 `libglfw.so` 时会报：

```text
undefined reference to `zwp_tablet_tool_v2_interface'
```

因此补丁保留了 `tablet-unstable-v2.xml` 及其生成的接口代码，仅用于满足链接符号；GLFW 不会绑定 tablet manager，也不会创建任何 tablet 对象。这一点在补丁 0005 的提交说明中有记录。

## 验证情况

- 在固定基线上用 `git am` 应用 9 个补丁：全部成功，无 fuzz、无冲突。
- 使用 CMake 同时构建 Wayland 与 X11、共享库：构建成功。
- 在 KDE Wayland 会话中做最小运行测试：`glfwInit` 选择 Wayland 平台，创建/销毁标准光标，`glfwTerminate` 正常退出。
- `wayland-info` 显示该会话提供 `wp_cursor_shape_manager_v1` v2；补丁按 v1 绑定，协议兼容。
- **游戏内验证**：Minecraft 1.21.1 + NeoForge、Minecraft 1.20.1 + Forge 均测试通过，补丁覆盖的功能正常。
- **测试环境**：Mesa 26.2.5、KWin 6.8.1、1.75x 分数缩放。

NVIDIA 专有驱动和多显示器环境没有测试条件，仍需在对应机器上验证。

## 已知问题

- **输入法不工作**：在 Fcitx 5 下无法正常使用输入法，IMBlocker Mod 也不能正常工作。该问题在上游补丁集上同样可以复现，不是本次补丁合并引入的；当前补丁集没有修复它。

## 已知取舍

- **全屏输出提示**：补丁 0008 不再把 `wl_output` 传给 `xdg_toplevel_set_fullscreen`，由合成器选择输出。这修复了部分“全屏跑到错误显示器”的情况，但也意味着 GLFW 的 monitor 参数不再作为输出提示传给合成器。多显示器场景可配合 [WayFix](https://github.com/jdkeke142/WayFix/tree/wayland-fixes) 使用。
- **窗口相关错误降级**：补丁 0007 把 `glfwGetWindowPos` / `glfwSetWindowPos` 以及缺少 toplevel-icon manager 时的 `glfwSetWindowIcon` 错误改为 stderr 警告，避免 Forge 的错误回调直接终止启动。依赖这些错误码的应用将不再收到错误。
- **启动提示**：补丁 0009 会在每次 `glfwInit` 成功时向 stderr 打印一行提示，方便用户先对照原版 GLFW 复现问题。

## 目录结构

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

## 许可

补丁修改的 GLFW 代码沿用 GLFW 的 zlib/libpng 许可。`deps/wayland/cursor-shape-v1.xml` 和 `deps/wayland/tablet-unstable-v2.xml` 来自 wayland-protocols，版权与许可声明保留在文件内。
