# 更新日志 / Changelog

## 1.0.2 — 2026-10-08

只有文档，没有改动脚本和动画。

### 文档
- README 对照代码做了一轮核对：说明只支持 Microsoft Store 版 Claude；Windows 10 未验证；找不到 Edge 时会尝试 Chrome；“8 秒放弃”从窗口出现后开始计时、窗口一直不出现要等约 34 秒；补上 `-MaxSplashSec` 选项；快捷方式生成在仓库文件夹里、加 `-Desktop` 才复制到桌面；欢迎语是固定文字、可在 `splash.html` 里修改；整段动画实测约 13 秒。
- 新增“故障排查”（日志对照、定位问题的顺序、没装 Edge、杀毒软件或权限拦截、多显示器、窗口不消失）和“卸载”两节；其中没在 Windows 上实际验证的内容都已标明“未验证”。
- 新增 `CONTRIBUTING.md`、`SECURITY.md` 和 issue 模板（反馈 bug 时请附 Claude 桌面应用版本、Windows 版本和 `launcher.log` 片段）。安全问题请用 GitHub 的 “Report a vulnerability” 私下报告。

## 1.0.1 — 2026-10-08

### 修复
- **仓库路径里带空格时动画几乎不播就结束。** 原因是传给 Edge 的配置目录参数没有加引号，在 Windows PowerShell 5.1 下被空格截断。已加引号，实测在带空格的路径下能完整播放。
- **某些出错情况下 Claude 可能根本不启动。** 比如 Edge 窗口启动失败、立刻退出，或窗口一直不出现。现在增加了两层兜底：窗口启动失败时直接启动 Claude；循环结束时如果 Claude 还没被启动，会补启动一次。（这两处兜底我没有在真实的“启动 Claude”流程里验证，只检查了语法并验证了正常播放路径没有受影响。）
- 清理了 `make_shortcut.ps1` 里一处带盘符的示意性注释。

### 其他
- `.gitignore` 增加 `launcher/edge-profile/`（Edge 的临时配置目录，约 100 MB，不应提交）。
- 这些问题由一次对启动脚本的独立静态审查发现，随后逐条核对。

## 1.0.0 — 2026-10-07

首个公开版本：Claude 桌面应用（Windows）的开屏动画，Edge 应用窗口覆盖播放，同时启动 Claude，播完淡出；Esc / 空格 / 回车 / 点击可跳过。
