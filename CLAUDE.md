# claude-desktop-splash — 维护说明（给 AI 助手和协作者）

给 Claude 桌面应用（Windows）加的开屏动画：用 Edge 的应用窗口覆盖在 Claude 的窗口上播放，同时启动 Claude，播完淡出。公开仓库，MIT 协议；动画里内嵌的角色图是 AI 生成的，版权另行说明，不在 MIT 范围内。

## 先看这个：这个项目在云端环境里跑不了

- 它**只支持 Windows**，需要 Microsoft Edge 和已安装的 Claude 桌面应用，并且会生成桌面快捷方式。云端的 Linux 环境里**无法运行也无法测试**。
- 所以在云端改了脚本或网页，**没法验证效果**。回答和提交说明里要如实写“没有实际运行验证”，不要写“已测试通过”。
- 能放心做的是文档（`README.md`）和对脚本的**阅读、分析、给出建议**；改 `launcher/` 里的脚本时要特别小心，并明确标注“未运行验证”，最好交给维护者在 Windows 上测试后再合并。

## 目录

- `splash.html`：动画本体（Canvas）。运行时只依赖 `assets/` 里的数据文件。
- `assets/claude-closed.js`（闭眼底图）、`assets/eyes-frames.js`（`window.EYE_SEQ`：31 帧睁眼序列）：由维护者本机的素材生成的内嵌图片数据（base64），**不要手改，也不要重新生成**。
- `assets/classic/claude-closed.js`、`assets/classic/eyes-frames.js`：原来那套角色图（v1.1.3 及以前的，`window.EYE_CROPS` 格式，配合 `splash.html` 里的 `RIG` 曲线），`?art=classic` / `-Art classic` 时使用。同样**不要手改**。
- `assets/video/open_4k60.mp4`、`assets/video/open_1080p60.mp4`：新图的睁眼动画（Live2D，4K60 / 1080p60，无音轨，已去掉全部元数据），**不要重新编码**。视频版的线稿用底图按 `splash.html` 里的 `VIDEO_FRAMING` 放大、平移后提取（不再单独存视频第一帧：一个只装 base64 图片的 `.js` 会被 Windows Defender 的机器学习规则误报）。载入失败时页面退回到 `eyes-frames.js` 的合成序列。
- `assets/sound.js`：开屏音效（Ogg/Opus，base64），由 `tools/make_sound.py`（预设 `video`）合成；原图的在 `assets/classic/sound.js`（预设 `classic`）。`assets/icon.png`、`launcher/custom.ico`：页面图标和快捷方式图标。
- `tools/make_sound.py`：音效生成脚本（Python + numpy，输出 wav；转成 Ogg 并写进 `assets/sound.js` 需要 ffmpeg）。
- `launcher/launch.ps1`：启动器。用 Edge `--app` 模式开窗口，裁剪到刚好盖住 Claude 的窗口，并在后台启动 Claude。
- `launcher/make_shortcut.ps1`：生成快捷方式；同时写入 `config.json`（Claude 的应用 ID）和 `claude.ico`（从用户已安装的 Claude 里提取的图标）。有 `launcher/custom.ico` 时快捷方式用它做图标。
- `docs/`：README 用的截图。
- `README.md`、`LICENSE`、`.gitignore`

## 不要提交的文件（已在 .gitignore）

`launcher/launcher.log`、`launcher/last_rect.json`、`launcher/config.json`、`launcher/claude.ico`、`launcher/edge-profile*/`（Edge 的临时配置目录，每次运行一个新的，约 100 MB）、`*.lnk`。其中 `claude.ico` 是 Claude 应用的官方图标，属于商标素材，**绝对不要加入仓库**。

## 改脚本时的注意事项（PowerShell 5.1）

- 脚本在 Windows PowerShell 5.1 下运行：不支持 `&&`、`||`、三元运算符、`??`。
- 脚本文件目前没有 BOM，改动时保持编码不变，避免中文乱码。
- 启动窗口时用 `--window-position=-32000,-32000` 先放到屏幕外，避免闪一下；不要随意改启动参数和遮挡相关的开关（`--disable-features=CalculateNativeWinOcclusion` 等），它们是为了防止窗口被判定为被遮挡而暂停动画。
- 页面准备好之前窗口保持不可见，页面超过 `-ReadyTimeoutSec` 没准备好就放弃动画、只启动 Claude。这个兜底逻辑不要删。

## 公开仓库的底线

- 绝不写入真实姓名、邮箱、本机路径（如盘符、用户目录）、令牌、密码。
- 不上传任何第三方的参考图或截图；README 截图只能用本项目动画自己的画面，并且要去掉 EXIF 元数据。
- 提交作者使用 GitHub 的 noreply 邮箱，作者名为 Inanis404。
- 提交信息末尾带 `Co-Authored-By: Claude <noreply@anthropic.com>` 署名行。

## 更新记录

版本记录在 `CHANGELOG.md`（当前 1.2.0）。每次更新同时：在 CHANGELOG 里加一节，打 `vX.Y.Z` 标签，并用 `gh release create` 发布说明；这些由维护者确认后再做，云端不要自己打标签或发 Release。

## 和用户沟通

- 用中文回复。专业术语可以用英文，并在后面附上中文解释。
- 先说结论，再说细节；不确定的地方直接说“我没验证过”。
- 报告要如实：失败就贴出失败，跳过的步骤要说明跳过了。
- 对外发布内容（推送、发帖、建 Release）前先让用户确认；删除或覆盖文件前先核对目标，范围模糊时先列清单。
