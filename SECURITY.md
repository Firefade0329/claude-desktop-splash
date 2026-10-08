# 安全政策 / Security Policy

*English summary: please report security problems privately through GitHub's "Report a vulnerability" (Security tab), not in a public issue. Below is what the scripts read, write and run, and whether they use the network, taken from the code. None of it was run for this document (it is Windows-only).*

## 支持的版本

只维护最新发布的版本（见 `CHANGELOG.md`）。请先确认问题在最新版里仍然存在。

## 怎么私下报告安全问题

请**不要**在公开的 Issue 里写漏洞细节。

1. 在本仓库页面打开 **Security** 标签页，点 **Report a vulnerability**（GitHub 的私下漏洞报告功能），按提示填写。
2. 如果你没有看到这个入口（说明维护者还没有启用它），请新建一个 Issue，标题写"想私下报告一个安全问题"，**正文不要写任何细节**，维护者看到后会给出私下联系的办法。

请在报告里写明：影响了什么、怎么复现、Windows 版本和这个项目的版本。**不要**在报告里放个人信息、令牌或日志里的私人内容。

这是个人项目，没有固定的响应时间，但会尽力处理。Claude 桌面应用、Microsoft Edge 或 Windows 本身的安全问题，请通过各自厂商的官方渠道报告。

## 这个项目读写什么、运行什么（以代码为准）

下面的内容来自我对 `launcher/launch.ps1`、`launcher/make_shortcut.ps1` 和 `splash.html` 的逐行阅读。**这个项目只能在 Windows 上运行，我没有实际运行过它，所以以下都是读代码得出的结论，"实际行为"未验证。**

### 联网

- **脚本和页面本身不联网**：两个 PowerShell 脚本里没有任何下载或网络请求的命令；`splash.html` 只加载仓库里的两个本地数据文件（`assets/*.js`），页面里没有网络请求，数据文件里也没有 `http(s)` 地址。
- **Edge 自己可能联网（未验证）**：动画用 Edge（或 Chrome）的应用窗口播放。启动参数里有 `--disable-background-networking`、`--disable-sync`，并且使用独立的临时配置目录；但我没法确认 Edge 在这种模式下是否完全不发起任何网络请求。

### 读取的数据

- **进程和窗口**：用 `Get-Process` 找名为 `claude` 的进程（并要求安装路径符合 Microsoft Store 版的位置）及其主窗口，用 Windows 接口读它的窗口位置和大小。
- **Claude 自己保存的窗口位置**：读取 `%LOCALAPPDATA%\Packages\<Claude 的包名>\LocalCache\Roaming\Claude\window-state.json`，只取位置、大小、最大化状态和显示器范围。
- **开始菜单应用列表**：`make_shortcut.ps1` 用 `Get-StartApps` 查名为 "Claude" 的应用 ID。
- **Claude 的图标**：`make_shortcut.ps1` 从你已安装的 Claude 里提取图标，存到本机的 `launcher\claude.ico`。
- **进程命令行**：用 WMI（`Win32_Process`）读 Edge / Chrome 进程的命令行，只为了找到自己启动的那批、并在结束时清理。
- **仓库里的文件**：`splash.html`、`assets/*.js`、`launcher\config.json`、`launcher\last_rect.json`。

### 写入的数据（都在你本机）

- 仓库的 `launcher\` 文件夹里：`launcher.log`（运行日志，超过 100 KB 会被清空）、`last_rect.json`（上次记住的窗口位置）、`config.json`（Claude 的应用 ID）、`claude.ico`（图标）、`edge-profile\`（动画用的一次性 Edge 配置目录，每次运行结束时删除）。
- 快捷方式：仓库根目录里一个 `.lnk`；用 `-Desktop` 时桌面上再放一个。
- **不写注册表、不创建启动项或计划任务**（脚本里没有这类操作）。
- 日志里会有 Edge 的安装路径、Claude 的应用 ID、窗口坐标，出错时还有错误信息，不含对话内容；你分享日志之前请自己检查有没有不想公开的信息。

### 会运行的东西（使用前请知晓）

- **快捷方式用 `-ExecutionPolicy Bypass` 运行脚本**：这会绕过 PowerShell 的执行策略。请只从可信的来源获取本仓库，并在运行前读一遍 `launcher\*.ps1`。
- **启动 Claude**：通过 `explorer.exe shell:AppsFolder\<应用 ID>` 启动，应用 ID 来自 `launcher\config.json`（由 `make_shortcut.ps1` 写入）。如果有人能改写这个文件，就能让它启动另一个已安装的应用；但能改写你本机文件的人本来就有更大的权限。
- **结束进程**：动画结束时，用 `Stop-Process -Force` 结束命令行里包含本仓库 `launcher\edge-profile` 路径的 Edge / Chrome 进程；不会按进程名结束你其它的浏览器窗口（这是读代码得出的结论，未验证）。
- **每次运行现场编译一小段 C#**（`Add-Type`），用来调用 Windows 的窗口接口（设置窗口位置、透明度、区域等）。
- **Edge 启动参数**：没有使用 `--no-sandbox`，没有放宽本地文件的访问。

### 其它

- `assets/claude-closed.js`、`assets/eyes-frames.js` 是生成的 base64 图片数据，不适合逐行审阅，请不要手改。
- `claude.ico` 是 Claude 的官方图标，只在你自己的电脑上生成，不包含在仓库里。
