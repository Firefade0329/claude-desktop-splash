<#
  Claude splash launcher.

  Plays ..\splash.html in a borderless window that exactly covers (and follows) the Claude desktop window,
  starts Claude in parallel, then fades the splash out to reveal Claude.

  How the window is made borderless: Edge is started in --app mode (a normal resizable window, not fullscreen),
  which draws its own title bar inside the window. The window is made taller by the title-bar height and then
  clipped with SetWindowRgn so that only the part exactly over Claude's window stays visible.

  Where does the splash go?
    1. Claude window already visible  -> its exact frame, and it follows if you move/resize it
    2. otherwise (cold start)         -> the last remembered Claude window rectangle (last_rect.json)
    3. otherwise                      -> the whole primary screen

  Switches (for testing):
    -NoClaude         only play the splash, do not start Claude
    -NoSplash         only start Claude
    -Fullscreen       ignore Claude's window and cover the whole primary screen
    -ClaudeDelayMs N  start Claude N ms after the splash window appears (default 800)
    -FadeMs N         fade-out duration (default 800)
    -FadeInMs N       fade-in duration when the splash appears (default 250)
    -ReadyTimeoutSec N  give up on the splash if the page is not ready after N s (default 8); Claude is still started
    -MaxSplashSec N   the splash window stays at most N s (default 22), then it is ended
  Skip while playing: Esc / Space / Enter / click.  Log: launcher.log (next to this file).
  Test hooks (leave unset in normal use): env SPLASH_TRACK_PROC=<process name> / SPLASH_TRACK_TITLE=<text> follow that window
  instead of Claude, SPLASH_DEBUG=1 makes the page report frame stalls.
#>
param(
  [switch]$NoClaude,
  [switch]$NoSplash,
  [switch]$Fullscreen,
  [int]$ClaudeDelayMs = 800,
  [int]$FadeMs = 800,
  [int]$FadeInMs = 250,
  [int]$ReadyTimeoutSec = 8,
  [int]$MaxSplashSec = 22
)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$logFile = Join-Path $here 'launcher.log'
$rectFile = Join-Path $here 'last_rect.json'
if ((Test-Path -LiteralPath $logFile) -and ((Get-Item -LiteralPath $logFile).Length -gt 100KB)) { Remove-Item -LiteralPath $logFile -ErrorAction SilentlyContinue }
function Log([string]$m) { try { Add-Content -LiteralPath $logFile -Value ('{0:HH:mm:ss.fff} {1}' -f (Get-Date), $m) -Encoding UTF8 } catch {} }
Log '--- launcher start'

Add-Type -ErrorAction SilentlyContinue -ReferencedAssemblies System.Windows.Forms @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class SplashWin {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int i, int v);
  [DllImport("user32.dll")] public static extern bool SetLayeredWindowAttributes(IntPtr h, uint key, byte alpha, uint flags);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
  [DllImport("user32.dll")] public static extern int SetWindowRgn(IntPtr h, IntPtr rgn, bool redraw);
  [DllImport("user32.dll")] public static extern int GetWindowRgnBox(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("gdi32.dll")] public static extern IntPtr CreateRoundRectRgn(int l, int t, int r, int b, int w, int h);
  [DllImport("gdi32.dll")] public static extern IntPtr CreateRectRgn(int l, int t, int r, int b);
  [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int attr, out RECT r, int cb);
  [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int v, int cb);
  // Turn off everything DWM draws around a window (Mica backdrop, rounded corners, non-client rendering, border).
  // Without this the window region only clips Chromium's own content and a light frame stays visible.
  public static void StripDwmFrame(IntPtr h) {
    int v;
    v = 1; DwmSetWindowAttribute(h, 38, ref v, 4);   // DWMWA_SYSTEMBACKDROP_TYPE = none
    v = 1; DwmSetWindowAttribute(h, 33, ref v, 4);   // DWMWA_WINDOW_CORNER_PREFERENCE = do not round
    v = 1; DwmSetWindowAttribute(h, 2, ref v, 4);    // DWMWA_NCRENDERING_POLICY = disabled
    v = -2; DwmSetWindowAttribute(h, 34, ref v, 4);  // DWMWA_BORDER_COLOR = none
  }

  public static string Title(IntPtr h) { var sb = new StringBuilder(512); GetWindowText(h, sb, 512); return sb.ToString(); }
  // The visible frame of a window (without the invisible resize borders)
  public static bool FrameRect(IntPtr h, out RECT r) { return DwmGetWindowAttribute(h, 9, out r, Marshal.SizeOf(typeof(RECT))) == 0; }
  // First visible top-level Chromium window of a process
  public static IntPtr FindChromiumWindow(uint pid) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((h, l) => {
      uint p; GetWindowThreadProcessId(h, out p);
      if (p == pid && IsWindowVisible(h)) {
        var sb = new StringBuilder(64); GetClassName(h, sb, 64);
        if (sb.ToString() == "Chrome_WidgetWin_1") { found = h; return false; }
      }
      return true;
    }, IntPtr.Zero);
    return found;
  }
}
'@
[SplashWin]::SetProcessDPIAware() | Out-Null

# ---- Claude (Microsoft Store app) ----
$aumid = 'Claude_pzs8sxrjxfjjc!Claude'
$cfgFile = Join-Path $here 'config.json'
if (Test-Path -LiteralPath $cfgFile) { try { $cfg = Get-Content -LiteralPath $cfgFile -Raw | ConvertFrom-Json; if ($cfg.aumid) { $aumid = $cfg.aumid } } catch {} }      # (config.json is written by make_shortcut.ps1; without it the default id below is used)
function Start-ClaudeApp { Log "starting Claude ($aumid)"; try { Start-Process -FilePath 'explorer.exe' -ArgumentList ('shell:AppsFolder\' + $aumid) } catch { Log ('start Claude failed: ' + $_) } }
function Find-ClaudeProcess {
  $trackTitle = $env:SPLASH_TRACK_TITLE
  if ($trackTitle) { return (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like "*$trackTitle*" } | Select-Object -First 1) }
  $track = $env:SPLASH_TRACK_PROC
  if ($track) { return (Get-Process -Name $track -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1) }
  Get-Process -Name claude -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 -and $_.Path -like '*WindowsApps*Claude_*' } | Select-Object -First 1
}
# The handle is cached: walking all Claude processes on every 30 ms tick made the splash lag behind a moving window.
# Only when the cached window is gone/hidden is the process list searched again (at most every 400 ms).
$script:cHwnd = [IntPtr]::Zero
$script:cLook = [DateTime]::MinValue
function Get-ClaudeWindow {
  if ($script:cHwnd -ne [IntPtr]::Zero -and [SplashWin]::IsWindow($script:cHwnd) -and [SplashWin]::IsWindowVisible($script:cHwnd)) { return [pscustomobject]@{ MainWindowHandle = $script:cHwnd } }
  $script:cHwnd = [IntPtr]::Zero
  if (((Get-Date) - $script:cLook).TotalMilliseconds -lt 400) { return $null }
  $script:cLook = Get-Date
  $c = Find-ClaudeProcess
  if ($c) { $script:cHwnd = $c.MainWindowHandle; return [pscustomobject]@{ MainWindowHandle = $script:cHwnd } }
  return $null
}

function Stop-ProcessesUsing([string]$needle) {
  try {
    Get-CimInstance Win32_Process -Filter "Name='msedge.exe' OR Name='chrome.exe'" |
      Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($needle, [StringComparison]::OrdinalIgnoreCase) -ge 0 } |
      ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  } catch {}
}

if ($NoSplash) { Start-ClaudeApp; return }

# Only one launcher at a time: a second double-click would otherwise kill the first one's browser and delete its profile.
$script:mutex = New-Object System.Threading.Mutex($false, 'Local\ClaudeDesktopSplashLauncher')
$hasMutex = $false
try { $hasMutex = $script:mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $hasMutex = $true }      # a killed earlier run: we own it now
if (-not $hasMutex) { Log 'another splash launcher is already running: starting Claude only'; if (-not $NoClaude) { Start-ClaudeApp }; return }

# ---- where should the splash go? ----
Add-Type -AssemblyName System.Windows.Forms
$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$script:lastSaved = [DateTime]::MinValue
$script:lastRgnLog = [DateTime]::MinValue
function Save-Rect($r, [bool]$zoomed) {
  if ($env:SPLASH_TRACK_TITLE -or $env:SPLASH_TRACK_PROC) { return }     # test hooks: never overwrite the real remembered rectangle
  if (((Get-Date) - $script:lastSaved).TotalSeconds -lt 1) { return }
  $script:lastSaved = Get-Date
  try { (@{ l = $r.L; t = $r.T; r = $r.R; b = $r.B; zoomed = $zoomed } | ConvertTo-Json) | Set-Content -LiteralPath $rectFile -Encoding ASCII } catch {}
}
# Claude (Electron) saves its own window position in window-state.json whenever the window is moved/resized, in
# device-independent pixels of the display it is on. That file is the best guess for where the window will appear.
$script:stateAt = [DateTime]::MinValue
$script:stateRect = $null
function Get-ClaudeStateRect {
  if (((Get-Date) - $script:stateAt).TotalMilliseconds -lt 1000) { return $script:stateRect }
  $script:stateAt = Get-Date
  $script:stateRect = $null
  try {
    $pkg = $aumid.Split('!')[0]
    $f = Join-Path $env:LOCALAPPDATA "Packages\$pkg\LocalCache\Roaming\Claude\window-state.json"
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    $s = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
    $dw = [double]$s.displayBounds.width; $dh = [double]$s.displayBounds.height
    if ($dw -lt 100 -or $dh -lt 100) { return $null }
    foreach ($scr in [System.Windows.Forms.Screen]::AllScreens) {
      $k = $scr.Bounds.Width / $dw
      # same display: same scale in both directions and the same origin
      if ([Math]::Abs($k * $dh - $scr.Bounds.Height) -gt 3 -or [Math]::Abs($k * [double]$s.displayBounds.x - $scr.Bounds.X) -gt 3 -or [Math]::Abs($k * [double]$s.displayBounds.y - $scr.Bounds.Y) -gt 3) { continue }
      if ($s.isMaximized -or $s.isFullScreen) {
        $wa = $scr.WorkingArea
        $script:stateRect = @{ L = $wa.Left; T = $wa.Top; R = $wa.Right; B = $wa.Bottom; Zoomed = $true; Source = 'claude-state' }
      } else {
        $script:stateRect = @{ L = [int][Math]::Round($k * $s.x); T = [int][Math]::Round($k * $s.y); R = [int][Math]::Round($k * ($s.x + $s.width)); B = [int][Math]::Round($k * ($s.y + $s.height)); Zoomed = $false; Source = 'claude-state' }
      }
      break
    }
  } catch {}
  return $script:stateRect
}
function Get-TargetRect {
  # returns @{ L; T; R; B; Zoomed; Source }
  if (-not $Fullscreen) {
    $c = Get-ClaudeWindow
    if ($c) {
      $ch = $c.MainWindowHandle
      if (-not [SplashWin]::IsIconic($ch)) {
        $r = New-Object SplashWin+RECT
        if ([SplashWin]::FrameRect($ch, [ref]$r) -and (($r.R - $r.L) -ge 300) -and (($r.B - $r.T) -ge 200)) {
          $z = [SplashWin]::IsZoomed($ch)
          Save-Rect $r $z
          return @{ L = $r.L; T = $r.T; R = $r.R; B = $r.B; Zoomed = $z; Source = 'claude' }
        }
      }
    }
    if (-not $env:SPLASH_TRACK_TITLE -and -not $env:SPLASH_TRACK_PROC) { $st = Get-ClaudeStateRect; if ($st) { return $st } }
    try {
      $s = Get-Content -LiteralPath $rectFile -Raw | ConvertFrom-Json
      $vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
      $w = $s.r - $s.l; $h = $s.b - $s.t
      if ($w -ge 300 -and $h -ge 200 -and $s.r -gt $vs.Left + 50 -and $s.l -lt $vs.Right - 50 -and $s.b -gt $vs.Top + 50 -and $s.t -lt $vs.Bottom - 50) {
        return @{ L = [int]$s.l; T = [int]$s.t; R = [int]$s.r; B = [int]$s.b; Zoomed = [bool]$s.zoomed; Source = 'saved' }
      }
    } catch {}
  }
  return @{ L = $screen.Left; T = $screen.Top; R = $screen.Right; B = $screen.Bottom; Zoomed = $true; Source = 'screen' }
}

# ---- browser ----
$browser = @(
  "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
  "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
  "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $browser) { Log 'no Edge/Chrome found, starting Claude only'; if (-not $NoClaude) { Start-ClaudeApp }; return }

$splashHtml = (Resolve-Path -LiteralPath (Join-Path $here '..\splash.html')).Path
$url = ([System.Uri]$splashHtml).AbsoluteUri + '?launcher'
if ($env:SPLASH_DEBUG) { $url += '&dbg' }                  # test hook: the page reports frame stalls through the window title
$prof = Join-Path $here ('edge-profile-' + [guid]::NewGuid().ToString('N').Substring(0, 8))      # a new folder every run
# Whatever an earlier run left behind (it was killed before it could clean up): its browser window, then its profile folder.
# We hold the mutex, so no other launcher is running, and nothing of ours is alive.
Stop-ProcessesUsing (Join-Path $here 'edge-profile')
Start-Sleep -Milliseconds 300
Get-ChildItem -LiteralPath $here -Directory -Filter 'edge-profile*' -ErrorAction SilentlyContinue | ForEach-Object { try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop; Log ('removed a leftover profile folder: ' + $_.Name) } catch { Log ('could not remove a leftover profile folder: ' + $_.Name) } }
$edgeArgs = @(
  "--app=$url",
  '--window-position=-32000,-32000', '--window-size=800,600',      # born off-screen so it never flashes at a default position
  ('--user-data-dir="' + $prof + '"'),      # quoted: the path may contain spaces (5.1 does not quote array items itself)
  '--no-first-run', '--no-default-browser-check', '--disable-sync', '--disable-infobars', '--lang=zh-CN', '--disable-translate',
  '--disable-session-crashed-bubble', '--hide-crash-restore-bubble',
  # An off-screen / invisible window counts as "occluded" to Chromium, which then stops requestAnimationFrame and resize events
  # (that was the white screen + skipped animation): keep rendering no matter what.
  '--disable-features=Translate,msEdgeSignIn,EdgeFirstRunExperience,msEdgeShopping,CalculateNativeWinOcclusion',
  '--disable-backgrounding-occluded-windows', '--disable-renderer-backgrounding', '--disable-background-timer-throttling',
  '--disable-background-networking'
)
Log "browser: $browser"
try { $p = Start-Process -FilePath $browser -ArgumentList $edgeArgs -PassThru -ErrorAction Stop }
catch { Log ('could not start the splash window: ' + $_); if (-not $NoClaude) { Start-ClaudeApp }; return }
$h = [IntPtr]::Zero
$claudeStarted = $false
$t0 = Get-Date
$appearAt = $null
$setup = $false          # window restyled (borderless, hidden)
$placed = $false         # page reported READY/PLAYING and the (invisible) window has been moved over the target
$shown = $false          # page reported PLAYING: window made visible
$nc = 0                  # height of the browser's own title bar in physical pixels
$curRect = $null
$done = $false

function Stop-Splash { Stop-ProcessesUsing $prof }
# put the splash window over the target rectangle (extra height = title bar, which is clipped away with a window region)
$bx = 0; $bb = 0        # invisible frame Chromium keeps left/right ($bx each) and at the bottom ($bb); measured after the first placement
function Place-Splash($hwnd, $tr) {
  $w = $tr.R - $tr.L; $hgt = $tr.B - $tr.T
  # window = target rect, grown by the title bar on top and by the invisible frame on the other sides;
  # the window region keeps only the part that is exactly over the target rect.
  # 0x0010 NOACTIVATE | 0x0020 FRAMECHANGED | 0x0040 SHOWWINDOW ; HWND_TOPMOST = -1
  [SplashWin]::SetWindowPos($hwnd, [IntPtr](-1), ($tr.L - $bx), ($tr.T - $nc), ($w + 2 * $bx), ($hgt + $nc + $bb), 0x0070) | Out-Null
  if ($tr.Zoomed) { $rgn = [SplashWin]::CreateRectRgn($bx, $nc, ($bx + $w), ($nc + $hgt)) } else { $rgn = [SplashWin]::CreateRoundRectRgn($bx, $nc, ($bx + $w + 1), ($nc + $hgt + 1), 16, 16) }
  [SplashWin]::SetWindowRgn($hwnd, $rgn, $true) | Out-Null
}

try {
  while (-not $done) {
    if ($p.HasExited) { Log 'splash process exited'; break }
    if ($h -eq [IntPtr]::Zero) { $h = [SplashWin]::FindChromiumWindow([uint32]$p.Id) }

    if ($h -ne [IntPtr]::Zero) {
      if (-not $setup) {
        # make it invisible (layered, alpha 0), borderless, hidden from the taskbar, until the page is ready
        $ex = [SplashWin]::GetWindowLong($h, -20)
        $ex = ($ex -bor 0x80000 -bor 0x80) -band (-bnot 0x40000)
        [SplashWin]::SetWindowLong($h, -20, $ex) | Out-Null
        [SplashWin]::SetLayeredWindowAttributes($h, 0, 0, 2) | Out-Null
        $st = [SplashWin]::GetWindowLong($h, -16)
        $st = $st -band (-bnot (0x00C00000 -bor 0x00040000 -bor 0x00080000 -bor 0x00020000 -bor 0x00010000))
        [SplashWin]::SetWindowLong($h, -16, $st) | Out-Null
        [SplashWin]::StripDwmFrame($h)
        $appearAt = Get-Date; $setup = $true; Log 'splash window created (hidden until ready)'
      }
      $title = [SplashWin]::Title($h)
      # Phase 1 (page says READY): move the still invisible window over the target and let the page paint there.
      # Phase 2 (page says PLAYING, i.e. it already has a frame at the final size): only now make the window visible.
      if (-not $placed -and $title -match 'CLAUDE_SPLASH_(READY|PLAYING)') {
        if ($title -match 'nc=(\d+)') { $nc = [int]$Matches[1] }
        $curRect = Get-TargetRect
        Place-Splash $h $curRect
        $placed = $true
        Log ("splash placed at {0},{1} {2}x{3} nc={4} source={5} (still invisible)" -f $curRect.L, $curRect.T, ($curRect.R - $curRect.L), ($curRect.B - $curRect.T), $nc, $curRect.Source)
        # Chromium keeps a resize frame even without WS_THICKFRAME: the client area is smaller than the window.
        # Measure it and grow the window by that much so the visible area ends up exactly on the target rectangle.
        Start-Sleep -Milliseconds 250
        $wr = New-Object SplashWin+RECT; $cr = New-Object SplashWin+RECT
        [SplashWin]::GetWindowRect($h, [ref]$wr) | Out-Null; [SplashWin]::GetClientRect($h, [ref]$cr) | Out-Null
        $bx = [Math]::Max(0, [int](((($wr.R - $wr.L) - ($cr.R - $cr.L)) / 2)))
        $bb = [Math]::Max(0, [int]((($wr.B - $wr.T) - ($cr.B - $cr.T))))
        Log ("frame measured: window {0}x{1}, client {2}x{3} -> side border {4}, bottom border {5}" -f ($wr.R-$wr.L), ($wr.B-$wr.T), ($cr.R-$cr.L), ($cr.B-$cr.T), $bx, $bb)
        Place-Splash $h $curRect
        $title = [SplashWin]::Title($h)
      }
      if ($placed -and -not $shown -and $title -like '*CLAUDE_SPLASH_PLAYING*') {
        # fade the window in (the page holds its first frame for 0.15 s, so nothing is missed)
        $fi = [System.Diagnostics.Stopwatch]::StartNew()
        while ($fi.ElapsedMilliseconds -lt $FadeInMs) {
          [SplashWin]::SetLayeredWindowAttributes($h, 0, [byte][Math]::Min(255, 255 * $fi.ElapsedMilliseconds / $FadeInMs), 2) | Out-Null
          Start-Sleep -Milliseconds 10
        }
        [SplashWin]::SetLayeredWindowAttributes($h, 0, 255, 2) | Out-Null
        $shown = $true
        Log ("splash shown (page ready after {0:N1} s)" -f ((Get-Date) - $appearAt).TotalSeconds)
      }
      if ($placed) {
        # follow the Claude window; keep on top
        $tr = Get-TargetRect
        if ($tr.L -ne $curRect.L -or $tr.T -ne $curRect.T -or $tr.R -ne $curRect.R -or $tr.B -ne $curRect.B -or $tr.Zoomed -ne $curRect.Zoomed) { Place-Splash $h $tr; $curRect = $tr }
        else { [SplashWin]::SetWindowPos($h, [IntPtr](-1), 0, 0, 0, 0, 0x0013) | Out-Null }       # NOMOVE|NOSIZE|NOACTIVATE
        if ($shown -and $title -like '*CLAUDE_SPLASH_DONE*') { Log 'splash reported DONE'; $done = $true }
        if ($env:SPLASH_DEBUG -and $title -match 'gaps=(.*)$' -and $Matches[1] -ne $script:lastGaps) { $script:lastGaps = $Matches[1]; Log ('page frame gaps (t:ms) ' + $Matches[1]) }
      }
      if ($appearAt -and (((Get-Date) - $appearAt).TotalSeconds -gt $MaxSplashSec)) { Log 'splash max time reached'; $done = $true }
      # the page never became ready (broken page / blocked browser): give up quietly, Claude is started anyway
      if ($appearAt -and -not $shown -and (((Get-Date) - $appearAt).TotalSeconds -gt $ReadyTimeoutSec)) { Log ("page not ready after {0} s, giving up on the splash" -f $ReadyTimeoutSec); if (-not $claudeStarted -and -not $NoClaude) { $claudeStarted = $true; Start-ClaudeApp }; break }
    }
    if (-not $claudeStarted -and -not $NoClaude -and $appearAt -and (((Get-Date) - $appearAt).TotalMilliseconds -ge $ClaudeDelayMs)) { $claudeStarted = $true; Start-ClaudeApp }
    if (((Get-Date) - $t0).TotalSeconds -gt ($MaxSplashSec + 12)) { Log 'hard timeout'; break }
    if ($setup) { Start-Sleep -Milliseconds 30 } else { Start-Sleep -Milliseconds 3 }     # catch the new window as early as possible
  }

  if ($done -and $shown -and -not $p.HasExited) {
    # hold the last frame until the Claude window exists (up to 8 s), so the fade reveals Claude and not the desktop
    if (-not $NoClaude) {
      if (-not $claudeStarted) { $claudeStarted = $true; Start-ClaudeApp }
      $w = Get-Date
      while (((Get-Date) - $w).TotalSeconds -lt 8) {
        if (Get-ClaudeWindow) { Log 'Claude window found'; break }
        $tr = Get-TargetRect; if ($tr.L -ne $curRect.L -or $tr.T -ne $curRect.T -or $tr.R -ne $curRect.R -or $tr.B -ne $curRect.B) { Place-Splash $h $tr; $curRect = $tr }
        Start-Sleep -Milliseconds 100
      }
    }
    # fade the whole window out (layered window alpha 255 -> 0), still following the Claude window
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $FadeMs) {
      $a = [int][Math]::Max(0, 255 * (1 - ($sw.ElapsedMilliseconds / $FadeMs)))
      [SplashWin]::SetLayeredWindowAttributes($h, 0, [byte]$a, 2) | Out-Null
      $tr = Get-TargetRect; if ($tr.L -ne $curRect.L -or $tr.T -ne $curRect.T -or $tr.R -ne $curRect.R -or $tr.B -ne $curRect.B) { Place-Splash $h $tr; $curRect = $tr }
      Start-Sleep -Milliseconds 16
    }
    Log 'fade finished'
  }
}
finally {
  if (-not $claudeStarted -and -not $NoClaude) { $claudeStarted = $true; Log 'safety net: starting Claude after the splash ended without starting it'; Start-ClaudeApp }
  Stop-Splash
  Log 'splash closed'
  # bring Claude to the front once the splash is gone (before the slow clean-up below). SW_RESTORE only for a minimised
  # window: on a maximised one it would shrink the window back to its normal size.
  if (-not $NoClaude) {
    $c = Get-ClaudeWindow
    if ($c) {
      if ([SplashWin]::IsIconic($c.MainWindowHandle)) { [SplashWin]::ShowWindow($c.MainWindowHandle, 9) | Out-Null }
      [SplashWin]::SetForegroundWindow($c.MainWindowHandle) | Out-Null
      Log 'Claude brought to front'
    } else { Log 'Claude window not found at the end' }
  }
  # the browser profile is throw-away (Edge fills it with ~100 MB of metrics/models): delete it after every run, it is re-created on the next start
  # (Edge's helper processes can take a moment to let go of their files, especially when the machine is busy: retry)
  for ($try = 0; $try -lt 8 -and (Test-Path -LiteralPath $prof); $try++) {
    Start-Sleep -Milliseconds 500
    try { Remove-Item -LiteralPath $prof -Recurse -Force -ErrorAction Stop } catch { if ($try -eq 7) { Log ('profile cleanup incomplete: ' + $_.Exception.Message) } else { Stop-Splash } }
  }
  try { $script:mutex.ReleaseMutex() } catch {}
}

Log '--- launcher end'
