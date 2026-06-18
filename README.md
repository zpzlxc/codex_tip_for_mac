# Codex 额度菜单栏

macOS 原生菜单栏应用，直接展示 **ChatGPT 订阅额度**（5 小时 / 周窗口）。

![Codex Helper 截图](./image.png)

## 功能

- **额度监控** — 菜单栏直接展示 5 小时与周剩余百分比
- **刷新时间** — 点击菜单栏额度后展示两个窗口的重置时间
- **菜单栏常驻** — 无 Dock 图标、无悬浮窗
- **官方本地协议** — 通过 Codex app-server 读取账号与额度，无需接触 Token
- **低频网络请求** — 额度默认 10 分钟刷新一次，降低频繁请求风险

## 环境要求

| 项目 | 要求 |
|------|------|
| 系统 | macOS 13 (Ventura) 或更高 |
| 工具链 | Xcode Command Line Tools / Swift 5.9+ |
| Codex | 已在 Codex Desktop 或 CLI 完成登录 |

登录状态由本机 Codex app-server 管理。应用不会直接读取、刷新或写入 OAuth Token。

可通过环境变量 `CODEX_HOME` 指定 Codex 数据目录，通过
`CODEX_EXECUTABLE` 指定 Codex 可执行文件。

## 快速开始

### 1. 克隆仓库

```bash
git clone https://github.com/zpzlxc/codex_tip_for_mac.git
cd codex_tip_for_mac
```

### 2. 打包为 .app

```bash
chmod +x build.sh
./build.sh
open dist/CodexHelper.app
```

构建产物位于 `dist/CodexHelper.app`。如需安装到应用程序文件夹：

```bash
cp -R dist/CodexHelper.app /Applications/
```

### 3. 开发调试（不打包）

```bash
swift run -c release
```

## 构建说明

`build.sh` 会依次执行：

1. `swift build -c release` — 编译 Release 二进制到 `.build/release/CodexHelper`
2. 组装 `dist/CodexHelper.app` 目录结构（`Contents/MacOS`、`Contents/Info.plist`）
3. 复制可执行文件与 `Resources/Info.plist`

手动构建等价命令：

```bash
swift build -c release
mkdir -p dist/CodexHelper.app/Contents/MacOS
cp .build/release/CodexHelper dist/CodexHelper.app/Contents/MacOS/
cp Resources/Info.plist dist/CodexHelper.app/Contents/
chmod +x dist/CodexHelper.app/Contents/MacOS/CodexHelper
open dist/CodexHelper.app
```

> **说明：** `dist/` 为本地构建输出，建议不要提交到 Git。克隆后自行执行 `./build.sh` 生成。

## 使用方式

启动后：

1. 菜单栏直接显示 `5小时 xx% · 周 xx%`（无 Dock 图标，属正常行为）
2. 点击额度可查看 5 小时与周额度的刷新时间

| 菜单项 | 快捷键 | 说明 |
|--------|--------|------|
| 刷新额度 | ⌘R | 手动刷新额度 |
| 设置… | ⌘, | 调整轮询间隔 |
| 退出 | ⌘Q | 退出应用 |

### 设置项

- **额度刷新间隔** — 5～60 分钟，默认 10 分钟，可按 1 分钟调整

## 工作原理

| 数据 | 来源 | 频率 |
|------|------|------|
| 5 小时 / 周额度 | Codex app-server `account/rateLimits/read` | 默认 10 分钟 |

## 项目结构

```
codex_tip_for_mac/
├── Sources/CodexHelper/       # Swift 源码
│   ├── Services/              # 额度读取与设置存储
│   ├── Views/                 # 设置窗口
│   └── Models/                # 数据模型
├── Resources/Info.plist       # App Bundle 配置
├── build.sh                   # 打包脚本
├── Package.swift              # Swift Package 定义
└── image.png                  # 应用截图
```

## 隐私与安全

- 本应用不读取、保存、刷新或上传 OAuth Token
- 登录态及 Token 生命周期完全由 Codex app-server 管理
- 仓库中不含任何个人 Token 或 API Key

## 免责声明

本项目为**非官方**第三方工具，与 OpenAI 无关。账号及额度读取使用 OpenAI
公开记录的 Codex app-server 协议。

## License

MIT（如需更换许可证，请自行添加 `LICENSE` 文件。）
