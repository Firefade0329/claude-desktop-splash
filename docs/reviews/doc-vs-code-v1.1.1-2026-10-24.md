# 文档与代码核对（开屏动画 v1.1.1）

- 日期：2026-10-24　版本：v1.1.1（main 已合并进 `claude/review-reports`）
- 范围：`README.md`、`CHANGELOG.md`（1.0.2–1.1.1）、`SECURITY.md`、`CONTRIBUTING.md`、`CLAUDE.md`，对照 `launcher/launch.ps1`、`launcher/make_shortcut.ps1`、`.gitignore`
- 方法标注：**读代码** = 只读源码与文档，没有运行（云端是 Linux，跑不了）。本篇所有结论都是“读代码”，没有“实际运行”。
- 配套报告：`launcher-review-v1.1.1-2026-10-24.md`（代码层面的发现 R-1…R-10）

## 结论

文档整体和代码一致，上一轮指出的大部分差异已修好。这一轮新发现 **5 处不一致（均为低）**，其中 2 处和 v1.1.1 的新日志 / 新路径有关；没有发现文档把“未验证”的事写成“已验证”的情况。

| 编号 | 位置 | 差异 | 严重程度 | 标注 |
|---|---|---|---|---|
| DC-1 | `README.md:102`、`CHANGELOG.md:9` vs `launch.ps1:362` | 文档说 `found` 记录的是“Claude 窗口刚出现时”；代码里 `found` 是在**动画播完、进入“等 Claude 窗口”循环之后**才记的，冷启动时并不是窗口刚出现的瞬间 | 低（会误导排查“窗口变大”） | 读代码 |
| DC-2 | `launch.ps1:11-14` | 文件头注释写的目标位置只有三级（真实窗口 → `last_rect.json` → 全屏），漏了 `window-state.json` 这一级（实际顺序见 `Get-TargetRect`，`:205-231`） | 低 | 读代码 |
| DC-3 | `SECURITY.md:32` | “读取的数据”只列了旧位置 `Packages\<包名>\LocalCache\Roaming\Claude\window-state.json`，没有 v1.1.1 新增读取的 `%LOCALAPPDATA%\Claude-Data\<包名>\window-state.json` | 低（隐私披露不完整，读取范围变宽了） | 读代码 |
| DC-4 | `SECURITY.md:49` | 写“动画结束时”结束进程；代码在**启动时**也会结束命令行含 `edge-profile` 的 Edge/Chrome 进程（`launch.ps1:248`，清理上次残留）。另外目录写成 `edge-profile`，实际是 `edge-profile-<8位>`；`SECURITY.md:40`、`CONTRIBUTING.md:49`、`README.md:168` 同样写成了不带后缀的 `edge-profile\` | 低 | 读代码 |
| DC-5 | `README.md:25` | “实测约 13 秒”：我无法核实，也看不出和代码里的 `MaxSplashSec`（22 秒）的关系；这是维护者的实测值，标为“无法核实” | 信息 | 无法核实 |

### DC-1 详情

- `launch.ps1:356-366`：`Get-ClaudeWindow` 找到窗口时才 `Log-ClaudeRect 'found'`，而这个循环只在 `$done -and $shown` 之后执行（动画已播完）。
- 所以日志里的 `found` 的含义是“动画播完后，第一次在循环里看到 Claude 窗口时的位置”。如果 Claude 在动画中途就已经出现，`found` 和 `end` 之间只隔几十毫秒，两行必然一致，**证明不了**“Claude 窗口出现时是什么大小”。
- 这恰好是 CHANGELOG 1.1.1“说明”里想拿来区分“Claude 自己开成那个大小 / 启动器动了它”的证据，所以不准确的描述会影响判断。
- 建议：文档改成“动画播完、启动器第一次看到 Claude 窗口时”；或者代码里在 `Get-TargetRect` 第一次拿到真实窗口时就记一行（需要维护者在 Windows 上测）。
- 与 R-1 是同一件事的文档侧。

### DC-3 / DC-4 建议

- `SECURITY.md:32` 补一个路径：`%LOCALAPPDATA%\Claude-Data\<包名>\window-state.json`，并说明“两处取最近写过的那个”。
- `SECURITY.md:49` 改成“启动时（清理上次残留）和动画结束时”；目录统一写 `edge-profile-<8位十六进制>`（或 `edge-profile*`，和 `.gitignore` 一致）。
- `CONTRIBUTING.md:49` 的 `launcher/edge-profile/` 改成 `launcher/edge-profile*/`。
- 这些都是 SECURITY / CONTRIBUTING 文档，按仓库规则可直接改；本轮按你的要求只出报告，没有改。

## 已核对一致的条目

| 文档说法 | 位置 | 代码依据 | 结果 |
|---|---|---|---|
| 页面 8 秒没准备好就放弃动画、只启动 Claude | README:24 | `launch.ps1:36`（默认 8）、`:349` | 一致 |
| 动画窗口一直不出现，约 34 秒硬超时 | README:24、:104、:136 | `launch.ps1:352`（`MaxSplashSec + 12` = 34） | 一致 |
| `-MaxSplashSec` 默认 22 秒 | README:62 | `launch.ps1:37` | 一致 |
| 每次运行新配置目录 `edge-profile-xxxxxxxx` | README:76、CHANGELOG:20 | `launch.ps1:245`（`NewGuid` 前 8 位） | 一致 |
| 启动时清掉上次残留的窗口和目录 | README:76、:109-110 | `launch.ps1:248-250`，日志串 `removed a leftover profile folder` / `could not remove ...` 与 README 一致 | 一致 |
| 同一时间一个启动器，第二个只启动 Claude | CHANGELOG 1.1.0 | 互斥体 `launch.ps1:146-149` | 一致（读代码；`AbandonedMutexException` 的处理见 launcher-review） |
| 只在最小化时还原 Claude，不缩小最大化窗口 | CHANGELOG 1.1.0 | `launch.ps1:387`（`IsIconic` → `ShowWindow(…, 9)`） | 一致 |
| `Stop-ProcessesUsing` 用子串匹配 | CHANGELOG 1.1.0 | `launch.ps1:135-141`（`IndexOf(…, OrdinalIgnoreCase)`） | 一致 |
| `window-state.json` 两处都找，取最近写过的 | README:154、CHANGELOG 1.1.1 | `launch.ps1:173-175` | 一致 |
| 日志来源 `claude-state` | README:154 | `Get-TargetRect` 的来源标签 | 一致（读代码） |
| `.gitignore` 用 `edge-profile*` | CHANGELOG:28、CLAUDE.md:22 | `.gitignore:6` | 一致 |
| `make_shortcut.ps1` 多个 “Claude” 条目时优先 Store 版并列出候选；找不到给警告；图标用包信息兜底 | CHANGELOG 1.1.0 | `make_shortcut.ps1:62-73`、`:80-83` | 一致（读代码）；R-7 指出“有 Claude 条目但都不是 Store 版”时没有警告 |
| 脚本头部补了 `-MaxSplashSec`、测试环境变量说明 | CHANGELOG:27 | `launch.ps1:20-37` | 一致；但见 DC-2 |

## 文档里自带的“没验证”声明

这些文档已经如实写了“未验证”，核对时没有发现反例，也无法由我验证（需要 Windows 实测）：

- CHANGELOG 1.1.1：“窗口比上次大”那次的原因没查清。
- CHANGELOG 1.1.0：最大化的 Claude 只读代码得出，没有实测。
- README:129：Chrome 下的实际表现没验证。
- README:168：键盘按键“某些情况下收不到”没验证（与 H-9 相关，见 launcher-review）。
- SECURITY.md:27、:49：Edge 自己是否联网、进程不会误杀都是读代码结论。

## 需要维护者回答的问题

1. DC-1：`found` 日志是否有意放在“等 Claude 窗口”循环里？如果希望它代表“窗口刚出现”，需要在更早的位置记一次——这属于脚本改动，我不改，请你在 Windows 上测过再合。
2. DC-5：“约 13 秒”是几次实测的平均？是否包含 Claude 自己启动的时间？（文档里没说，读者可能误会。）
3. DC-3：新增读取 `Claude-Data` 目录，是否希望在 SECURITY.md 里专门说明它是 Claude 自己的内部文件、仓库只读不写？
