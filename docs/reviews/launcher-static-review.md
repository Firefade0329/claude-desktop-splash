# 启动器静态审查：`launcher/launch.ps1` 与 `launcher/make_shortcut.ps1`

> **所有结论都是「未运行验证」。** 这个项目只支持 Windows，云端是 Linux，没有 PowerShell，也没有 Edge 和 Claude 桌面应用。我只做了静态阅读：逐行读两个脚本（`launch.ps1` 361 行、`make_shortcut.ps1` 88 行），并读了 `splash.html` 里和启动器通信的部分（窗口标题协议）。**没有修改任何脚本。**
> 判断依据是 Windows PowerShell 5.1 的语法和行为。
> 每条另外标了「把握」：**高** = 来自 PowerShell / Win32 文档里明确写着的行为；**中** = 依赖我对 Edge / Windows 实际行为的了解，可能有出入；**低** = 推测。把握不等于验证过。
> 严重程度：**高** = 正常使用就可能让 Claude 打不开或功能整体失效；**中** = 有条件触发的明显问题；**低** = 轻微、罕见或只影响体验。

## 结论（先看这个）

- **2 个高、4 个中、10 个低。**
- **最重要的一条（H-1）：在好几种出错情况下，启动器根本不会启动 Claude。** 快捷方式替代了用户平时打开 Claude 的入口，所以一旦这些情况发生，用户双击后什么都不会发生（而且因为用了 `conhost --headless`，连报错窗口都没有）。README 和 CLAUDE.md 里写的"动画出问题就放弃动画、只启动 Claude"这条兜底，只在"Edge 窗口已经出现"之后才生效。
- **H-2：仓库路径里有空格，Edge 的启动参数会被拆开。** 这是 PowerShell 5.1 `Start-Process -ArgumentList <数组>` 不给元素加引号造成的，叠加 H-1，路径带空格的用户很可能打不开 Claude。
- 中文路径我没发现问题（两个脚本都是纯 ASCII，文件里没有中文；路径都走 Unicode 接口）。
- 5.1 语法：没有发现 `&&`、`||`、`??`、`?.`、三元运算符（我 grep 过）。
- 没装 Edge：有兜底（`:211`，改用 Chrome，都没有就只启动 Claude），逻辑正确。没装 Claude：**没有任何检测和提示**（H-10）。

## 发现的问题

### 高

#### H-1　多种情况下 Claude 不会被启动（高）　【未运行验证；把握：高（这是读代码得出的控制流结论）】

- 位置：`launcher/launch.ps1:230-261`、`:316-319`、`:321`、`:344-361`。
- 启动 Claude 的地方只有三处：①窗口出现后过 `-ClaudeDelayMs`（`:318`，条件里要求 `$appearAt`，即 Edge 窗口已经被找到）；②页面超过 `-ReadyTimeoutSec` 没准备好（`:316`，在 `if ($h -ne [IntPtr]::Zero)` 里面）；③播放结束后的保险（`:326`，要求 `$done -and $shown`）。下面这些情况**三处都走不到**：
  1. **Edge 进程一启动就退出**（`:259` 直接 `break`）。典型场景：上一次启动被强行终止，残留了使用同一个配置目录的 Edge（见 H-3）；新启动的 `msedge.exe` 会把请求转交给那个实例然后自己立刻退出。
  2. **Edge 窗口一直没出现**（被策略拦截、卡在对话框、GPU 挂起、H-2 的参数错乱）。窗口没出现时 `$appearAt` 为空，`-ReadyTimeoutSec` 和 `-ClaudeDelayMs` 的计时都不会开始。只有 `:319` 的"硬超时"（`MaxSplashSec + 12` = 34 秒）会 `break`，但 `break` 之后的代码不会启动 Claude。同时 `:320` 的 3 毫秒空转循环会在这 34 秒里一直 `EnumWindows`，CPU 占用不低。
  3. **`Start-Process` 本身失败**（`:230`）。`$ErrorActionPreference = 'Continue'` 下脚本会继续，`$p` 为 `$null`；`$null.HasExited` 在 5.1 里返回 `$null`（不报错），`[uint32]$p.Id` 变成 0，结果和第 2 种一样空转 34 秒。
  4. **循环里抛出终止错误**（`try`/`finally` 没有 `catch`，`:257-354`）。`finally` 执行完以后错误继续向外传播，脚本直接结束，`:357-361` 不会执行。
  5. **`Add-Type` 编译 C# 失败**（`:46`，`-ErrorAction SilentlyContinue` 把失败吞掉了）。比如受限语言模式（Constrained Language Mode）、AppLocker / 杀毒软件策略。之后 `[SplashWin]::…` 都会抛"找不到类型"，落入第 4 种情况。（`-NoSplash` 走 `:133` 的早退路径，不受影响。）
- 场景：用户双击"Claude 开屏启动"，上面任何一种情况发生，Claude 不会打开，也没有任何提示。
- 建议：
  - 在 `finally` 之后（或 `finally` 里）加一个总兜底：`if (-not $NoClaude -and -not $claudeStarted) { Start-ClaudeApp }`；并给整个主循环加 `catch { Log ... }`，让错误被记录而不是终止脚本。
  - 给"窗口出现"单独计时：从 `$t0` 起超过 `-ReadyTimeoutSec` 仍没有 `$appearAt`，就放弃动画并启动 Claude。
  - 给 `Start-Process` 包 `try/catch`，失败时直接 `Start-ClaudeApp`。
  - 这些都是"补强兜底"，不删除现有逻辑，和 CLAUDE.md 里"兜底逻辑不要删"的要求不冲突。

#### H-2　路径带空格时，`--user-data-dir` 被拆成两个参数（高）　【未运行验证；把握：高（`Start-Process` 数组参数不加引号）/ 中（Edge 拿到被拆开的参数后的具体表现）】

- 位置：`launch.ps1:216-230`（`$prof`、`$args`、`Start-Process -ArgumentList $args`）。
- 原因：Windows PowerShell 5.1 的 `Start-Process -ArgumentList` 收到数组时，只是用空格把元素连起来，**不会给含空格的元素加引号**。`--user-data-dir=$prof` 里 `$prof` 是 `<脚本目录>\edge-profile`，只要脚本目录里有空格（用户名带空格、或文件夹叫 `My Projects` 这类，都很常见），命令行就变成：
  `msedge.exe --app=… --user-data-dir=<含空格的目录>\launcher\edge-profile …`
  Edge 会在第一个空格处把它截断，只拿到空格之前的那一段当作配置目录，空格之后的部分成了一个游离参数。
- 场景：Edge 要么在一个没有写权限的目录里建配置目录（可能弹"无法读写数据目录"的对话框，窗口类不是 `Chrome_WidgetWin_1`，启动器找不到），要么直接退出——两者都落入 H-1，Claude 不会启动；游离参数还可能被 Edge 当成地址打开。
- README 只说"放在一个固定的位置"，没有提空格。
- `--app=$url` 不受影响：`[System.Uri].AbsoluteUri` 会把空格和中文都做百分号编码。
- 建议：给带路径的参数手动加引号，例如 `"--user-data-dir=`"$prof`""`；或者把整个参数列表拼成一个字符串再传。同时在 `make_shortcut.ps1` 里提示"路径含空格时需要……"（修好以后就不用提示了）。

### 中

#### H-3　启动器被强行终止后，Edge 窗口残留，下一次启动还会失败一次（中）　【未运行验证；把握：中】

- 位置：`launch.ps1:345-354`（`finally`）、`:259`、`:216`（固定的配置目录）。
- 场景：`finally` 只在脚本正常结束或抛错时运行。启动器进程被强行结束（任务管理器、关掉 conhost、注销、断电）就不会运行，留下：
  1. **一个残留的 Edge 窗口**：窗口已被设为置顶（`HWND_TOPMOST`）、工具窗口（不在任务栏、Alt-Tab 里也没有）、透明度 0 或 255；页面在 `DONE` 之后不会自己关闭（`splash.html` 只改窗口标题），用户只能去任务管理器找 `msedge.exe`。如果残留时透明度是 255，它会盖在屏幕上挡住 Claude。
  2. **残留的配置目录**（约 100 MB，见 H-5）。
  3. **下一次启动会失败一次**：新的 `msedge.exe` 用同一个 `--user-data-dir`，会把请求转交给残留的实例并立刻退出，`$p.HasExited` 为真，走 H-1 第 1 种情况，Claude 不启动。`finally` 里的 `Stop-Splash` 会杀掉残留实例并清理，所以**再双击一次就恢复正常**。
- 建议：
  - 启动 Edge 之前先调用一次 `Stop-Splash` 并清理旧的配置目录（自愈）。
  - 配置目录改成每次运行唯一的名字（带 PID 或 GUID），放在 `$env:TEMP` 下，不放在仓库目录里（也顺带解决 H-5、H-7）。
  - 页面在 `DONE` 后或一段时间没有启动器响应时自己 `window.close()`，让残留窗口自我了结（`splash.html` 里要加，需要在 Windows 上验证 `--app` 窗口能否被脚本关闭）。

#### H-4　播放结束后用 `SW_RESTORE` 置前 Claude，会把最大化的窗口还原（中）　【未运行验证；把握：中高（`ShowWindow` 文档）】

- 位置：`launch.ps1:359`，`[SplashWin]::ShowWindow($c.MainWindowHandle, 9)`。
- 原因：`9` 是 `SW_RESTORE`。文档写明：窗口处于最小化、**最大化**或排列状态时，系统会把它恢复到原来的大小和位置。
- 场景：Claude 窗口是最大化的（代码里 `Zoomed` 就是在处理这种情况，说明作者知道它很常见）。动画结束、淡出完成后，最后一步会把它从最大化还原成普通窗口，用户看到窗口突然缩小。
- 建议：只在 `IsIconic`（最小化）时才用 `SW_RESTORE`；否则只调 `SetForegroundWindow`。
- 附带：`SetForegroundWindow` 在后台进程里常被系统限制，只会让任务栏图标闪烁（低把握，未验证）。

#### H-5　`launcher/edge-profile/` 不在 `.gitignore` 里（中）　【未运行验证（我没法让它产生残留）；这条是读文件得出的，把握：高】

- 位置：`launch.ps1:216`（`$prof = Join-Path $here 'edge-profile'`，即仓库里的 `launcher/edge-profile/`）；`.gitignore` 只列了 `launcher.log`、`last_rect.json`、`config.json`、`claude.ico`、`*.lnk`；CLAUDE.md 的"不要提交的文件"清单里也没有它。
- 场景：正常情况下它在每次运行结束时被删除（`:350-353`，最多重试 8 次、共约 4 秒）。但清理失败（日志里会有 `profile cleanup incomplete`）或启动器被强杀（H-3）后，约 100 MB 的 Edge 配置会留在仓库目录里。之后维护者在本机 `git add -A`，就会把整个 Edge 配置目录提交进公开仓库。
- 建议：`.gitignore` 加一行 `launcher/edge-profile/`；CLAUDE.md 的清单里补上；或者按 H-3 把它挪到 `$env:TEMP`。

#### H-6　混合缩放的多显示器下，位置和大小可能算错（中）　【未运行验证；把握：中】

- 位置：`launch.ps1:105`（`SetProcessDPIAware()`）、`:184-188`（读取 Claude 窗口矩形）、`:252-254`（放置）、`:150-175`（把 Claude 保存的 DIP 坐标换算成物理像素）。
- 原因：`SetProcessDPIAware()` 只是"系统 DPI 感知"，不是"每显示器感知"。Chromium（Edge）和 Electron（Claude）都是每显示器感知的。当 Claude 所在的显示器和主显示器缩放比例不同（例如笔记本 150% + 外接屏 100%），系统会对启动器看到的坐标做虚拟化，`GetWindowRect` / `DwmGetWindowAttribute` / `SetWindowPos` 的数值和实际像素之间有换算差，窗口可能偏位或大小不对。`:161-172` 里用 `$k = 屏幕宽 / DIP 宽` 推算缩放并要求"同一块屏"的判定，在虚拟化后的坐标下也可能失败而改走保存的矩形（这条路径本身是安全的）。
- README 已经写了"没有测试过多显示器和不同缩放比例的所有组合"。
- 建议：改用每显示器 v2 感知：`SetProcessDpiAwarenessContext(-4)`（Windows 10 1703 以上），失败再退回 `SetProcessDpiAwareness(2)`。需要在多屏混合缩放的机器上实测。

### 低

#### H-7　固定的配置目录名，两个实例同时启动会互相干扰（低）　【未运行验证；把握：中】

- 位置：`launch.ps1:216`、`:243`（`Stop-Splash` 按命令行包含 `$prof` 来杀进程）。
- 场景：快速双击两次快捷方式（或同时有两个快捷方式）。第二个实例的 Edge 把请求转交给第一个并退出；第二个启动器的 `finally` 里 `Stop-Splash` 会杀掉第一个实例正在播放的 Edge，并删掉它正在用的配置目录。结果是第一个动画被中途打断，第二个启动器因 H-1 不启动 Claude（第一个启动器通常已经启动了 Claude，因此用户最终会看到一个被打断的动画和一个 Claude）。
- 建议：按 H-3 使用唯一的配置目录名；或者用命名互斥量（Mutex）保证同一时间只有一个启动器。

#### H-8　`Stop-Splash` 用 `-like` 匹配路径，路径里有 `[` 或 `]` 时失效（低）　【未运行验证；把握：高（`-like` 通配符语法）】

- 位置：`launch.ps1:243`，`$_.CommandLine -like "*$prof*"`。
- 原因：`-like` 里 `[abc]` 是字符类。目录名含 `[backup]` 这类方括号时匹配不上，既杀不掉 Edge，配置目录也因被占用而删不掉（`:352` 会反复重试后放弃）。
- 建议：改成 `$_.CommandLine.IndexOf($prof, [StringComparison]::OrdinalIgnoreCase) -ge 0`（并先判断 `CommandLine` 不为 `$null`）。

#### H-9　README 承诺"Esc / 空格 / 回车跳过"，但窗口从不获得键盘焦点（低）　【未运行验证；把握：中】

- 位置：`launch.ps1:252`、`:310`（`SetWindowPos` 带 `NOACTIVATE`）、全文只有 `:359` 一处调用 `SetForegroundWindow`（对象是 Claude，不是动画窗口）。
- 场景：动画窗口始终以"不激活"方式放置，800 毫秒后 Claude 又被启动并通常抢到前台，于是键盘事件送给了 Claude，页面收不到 Esc / 空格 / 回车；鼠标点击不依赖激活，所以点击跳过应该可用。是否真的这样要在 Windows 上实测（Edge 窗口刚创建时可能自带一次激活）。
- 建议：实测后，要么在显示窗口时对它调用一次 `SetForegroundWindow`，要么在 README 里把"点击"作为主要的跳过方式。

#### H-10　没装 Claude 时没有任何检测和提示（低）　【未运行验证；把握：中】

- 位置：`launch.ps1:108-111`、`:201`（回退到整个主屏）、`:324-333`；`make_shortcut.ps1:60-63`、`:76`。
- 场景：`Get-StartApps` 找不到 Claude 时，`make_shortcut.ps1` 静默使用默认 AUMID（`Claude_pzs8sxrjxfjjc!Claude`），图标提取失败也只是输出一行 `icon extraction failed`，快捷方式照样生成。运行时，找不到 Claude 窗口、没有保存的矩形，回退链走到最后一级"整个主屏"，动画盖满屏幕播完，再空等 8 秒找 Claude 窗口，最后只在日志里写 `Claude window not found at the end`。`explorer.exe shell:AppsFolder\<无效 id>` 的行为我没验证过，可能弹出资源管理器窗口或错误框，留下一个窗口。
- 建议：`make_shortcut.ps1` 找不到 Claude 时明确报错并退出（或至少用醒目的警告）；`launch.ps1` 开头检查 Claude 是否存在，不存在就不播动画，并给出提示。

#### H-11　只认 Microsoft Store 版 Claude 的窗口（低）　【未运行验证；把握：中】

- 位置：`launch.ps1:117`（`$_.Path -like '*WindowsApps*Claude_*'`）；`:156`（`Packages\$pkg\LocalCache\...`）。
- 场景：非商店安装（安装路径不含 `WindowsApps`）时永远找不到 Claude 窗口：跟随功能失效，最后置前不执行，播完固定多等 8 秒。（`Start-ClaudeApp` 用的 AUMID 来自 `Get-StartApps`，非商店安装也可能能启动。）README 的要求写的是"Claude 桌面应用（Windows 版）"，没说明只支持商店版。
- 建议：README 的"要求"里写明"Microsoft Store 版"；或者放宽路径判断（按进程名 + 窗口类，或排除 CLI 的路径）。

#### H-12　等待和性能的几个小问题（低）　【未运行验证；把握：中】

- `launch.ps1:320`：窗口出现之前每 3 毫秒调一次 `EnumWindows`，空转占用 CPU，窗口一直不出现时最长持续 34 秒（H-1 第 2 种）。建议改成 10–20 毫秒。
- `:350-353`：清理配置目录的循环**先睡 500 毫秒再尝试**，所以淡出结束后至少多等 0.5 秒（Edge 子进程没退干净时更久，最长约 4 秒），而"置前 Claude"（`:357-360`）在这之后才执行。可以把置前放到 `finally` 之前，或把清理放到后台。
- `:46-104`：每次启动都用 `Add-Type` 现场编译 C#（调用编译器、在 `%TEMP%` 写临时文件），启动延迟大约几百毫秒到 1 秒，杀毒软件有时也会拦。可以改成预编译的 DLL 或只在第一次编译（需要权衡维护成本）。

#### H-13　`make_shortcut.ps1` 用名字取第一个 "Claude"，可能取错（低）　【未运行验证；把握：中】

- 位置：`make_shortcut.ps1:62`，`Get-StartApps | Where-Object { $_.Name -eq 'Claude' } | Select-Object -First 1`。
- 场景：开始菜单里有多个叫 "Claude" 的条目（例如把 claude.ai 安装成 Edge / Chrome 的网页应用，也会叫这个名字）。取到哪个取决于枚举顺序，AUMID 写错后，快捷方式启动的是另一个东西，或者什么都不启动。脚本会打印 `aumid = …`，但不会提示有多个匹配。
- 建议：优先匹配 AppID 以 `Claude_` 开头且含 `!` 的条目；匹配到多个时全部列出，让用户确认。

#### H-14　图标提取：路径假设和清晰度（低）　【未运行验证；把握：中】

- 位置：`make_shortcut.ps1:70-76`。
- ① 进程没在运行时，回退用 `Get-ChildItem 'C:\Program Files\WindowsApps'` 找安装目录；普通用户通常没有权限列出这个目录，`-ErrorAction SilentlyContinue` 把失败吞掉，`$exe` 为空，`ExtractAssociatedIcon($null)` 抛错，落入 `catch` 只输出一行 "icon extraction failed"（快捷方式生成成功但没有图标）。更稳的做法是 `Get-AppxPackage -Name 'Claude*'` 的 `InstallLocation`。② 路径写死了 `C:`（系统盘不是 C 时失败）。③ `ExtractAssociatedIcon` 只返回一个 32×32 的图标，保存成 .ico 后在高分屏上会发糊。

#### H-15　可维护性小问题（低）　【未运行验证；把握：高】

- `launch.ps1:217`：`$args = @(...)` 给自动变量 `$args` 赋值。5.1 里不会报错、能正常工作，但容易被后来的人改坏（比如挪到函数里就不是同一个 `$args` 了）。建议改名为 `$edgeArgs`。
- `param` 里的 `-MaxSplashSec`（默认 22）没有出现在头部注释和 README 的参数表里。
- 测试用的环境变量钩子（`SPLASH_TRACK_PROC`、`SPLASH_TRACK_TITLE`、`SPLASH_DEBUG`）在正式脚本里一直生效；如果用户的环境里恰好有同名变量，行为会很奇怪。风险很小，在注释里提一句即可。

#### H-16　`make_shortcut.ps1:87` 的注释里有带盘符的路径（低）　【已确认（文字存在）】

- 内容：`New-Link (Split-Path -Parent $here)` 这一行末尾的注释，是一个以盘符开头、中间用省略号的示意路径（形如 `X:\...\splash\`）。
- CLAUDE.md 的"公开仓库的底线"写明不要出现盘符、本机路径。这里只是个省略写法的示意，不是真实路径，泄露风险极小，但按字面规则应该去掉盘符。
- 建议：把注释改成 `# the repository folder`，需要维护者在本机改。（我没有改脚本。）
- 我同时在两个仓库里 grep 了盘符 / 用户目录 / 邮箱 / 令牌的样式，只有这一处（另有桌宠仓库 `README.md` 里一个通用的示例路径，以及本脚本 `:71` 的系统目录 `WindowsApps`，二者都不是个人信息）。

## 检查过、没有发现问题的地方（静态阅读）

- **编码**：两个脚本都是纯 ASCII（我数过：0 个非 ASCII 字符），没有 BOM 问题；文件里不含中文，所以中文系统（GBK 代码页）下不会乱码。
- **中文路径**：日志写 UTF-8；JSON 只含 ASCII，用 `-Encoding ASCII` 没问题；命令行走 Unicode；URL 经 `AbsoluteUri` 百分号编码；快捷方式用 `IShellLinkW`（Unicode）。没发现中文路径会出错的地方。
- **5.1 语法**：没有 `&&`、`||`、`??`、三元运算符；C# 部分没有用到 C# 6 以上的特性（PowerShell 5.1 的 `Add-Type` 用的是 C# 5 编译器）；`IShellLinkW` 的方法顺序与系统定义一致。
- **没装 Edge / Chrome**：`:205-211` 找不到浏览器时记录日志、启动 Claude 后返回，逻辑正确。
- **Claude 窗口读不到的回退链**：Claude 窗口 → Claude 自己保存的 `window-state.json` → 上次记住的矩形（并校验仍在可见屏幕范围内，`:196`）→ 整个主屏。读文件的地方都有 `try/catch`；`Save-Rect` 只保存非最小化、尺寸合理的矩形（`:182-185`）。
- **轮询开销**：找 Claude 窗口的句柄做了缓存，且未找到时 400 毫秒才重新枚举一次（`:123-131`）；读 `window-state.json` 每秒最多一次（`:151`）。
- **窗口区域（Window Region）**：`SetWindowRgn` 成功后区域归系统所有，不需要释放，代码没有 GDI 泄漏。
- **`finally` 清理**：脚本正常结束、抛错、Ctrl+C 时，都会杀掉命令行包含配置目录的 Edge / Chrome 进程（不会碰用户自己的浏览器），并重试删除配置目录。
- **浏览器参数**：没有 `--no-sandbox`，没有放开 `file://` 之间的访问；配置目录是隔离的。遮挡相关开关（`CalculateNativeWinOcclusion` 等）我没有建议改动，按 CLAUDE.md 保留。
- **日志**：超过 100 KB 会清空（`:42`）；日志、矩形、`config.json`、`claude.ico`、`*.lnk` 都在 `.gitignore` 里。
- **`docs/` 截图**：我检查了两张 JPEG 的段结构，没有 EXIF（APP1）段，只有 JFIF。两个仓库的提交作者都是 `Firefade0329` 加 noreply 邮箱。

## 未验证清单（需要 Windows 才能确认）

1. H-1 里每一种"Claude 不启动"的情况；尤其是 Edge 启动即退出、窗口不出现时 34 秒空转的实际表现。
2. H-2：带空格的路径下 Edge 实际收到什么参数、弹什么窗口。
3. H-3：被强杀后的残留窗口是否可见、能否被页面 `window.close()` 关掉、"转交后立刻退出"是否真的发生。
4. H-4：最大化的 Claude 在 `SW_RESTORE` 后是否真的被还原。
5. H-6：混合缩放多屏下的偏差有多大。
6. H-9：键盘跳过是否真的无效。
7. `conhost.exe --headless` 在 Windows 10 上是否可用（README 只说在 Windows 11 上测试过）。
8. `explorer.exe shell:AppsFolder\<无效 id>` 的行为。
9. 动画本身的画面、时长、淡入淡出效果（我没看，也无法看）。
