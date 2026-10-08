<#
  Creates the splash shortcut.
    -LinkName  file name of the shortcut (without .lnk)
    -Desktop   also copy it to the real Desktop folder
  Also resolves Claude's AppUserModelID into config.json and extracts Claude's icon into claude.ico.
  Note: the shortcut is written through IShellLink (Unicode). WScript.Shell cannot handle non-ANSI paths.
#>
param(
  [string]$LinkName = 'Claude (splash)',
  [switch]$Desktop
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

Add-Type -ErrorAction SilentlyContinue @'
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Text;

[ComImport, Guid("00021401-0000-0000-C000-000000000046")]
class CShellLink { }

[ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("000214F9-0000-0000-C000-000000000046")]
interface IShellLinkW {
  void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder f, int cch, IntPtr pfd, int flags);
  void GetIDList(out IntPtr ppidl);
  void SetIDList(IntPtr pidl);
  void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder s, int cch);
  void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string s);
  void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder s, int cch);
  void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string s);
  void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder s, int cch);
  void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string s);
  void GetHotkey(out short w);
  void SetHotkey(short w);
  void GetShowCmd(out int i);
  void SetShowCmd(int i);
  void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder s, int cch, out int idx);
  void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string s, int idx);
  void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string s, int reserved);
  void Resolve(IntPtr hwnd, int flags);
  void SetPath([MarshalAs(UnmanagedType.LPWStr)] string s);
}

public static class LinkMaker {
  public static void Create(string lnk, string target, string args, string workDir, string icon, string desc, int showCmd) {
    IShellLinkW l = (IShellLinkW)new CShellLink();
    l.SetPath(target);
    l.SetArguments(args);
    l.SetWorkingDirectory(workDir);
    l.SetDescription(desc);
    l.SetShowCmd(showCmd);
    if (!string.IsNullOrEmpty(icon)) l.SetIconLocation(icon, 0);
    ((IPersistFile)l).Save(lnk, true);
  }
}
'@

# AppUserModelID of the installed Claude app
$aumid = $null
try { $aumid = (Get-StartApps | Where-Object { $_.Name -eq 'Claude' } | Select-Object -First 1).AppID } catch {}
if (-not $aumid) { $aumid = 'Claude_pzs8sxrjxfjjc!Claude' }
(@{ aumid = $aumid } | ConvertTo-Json) | Set-Content -LiteralPath (Join-Path $here 'config.json') -Encoding ASCII
Write-Output "aumid = $aumid"

# icon (copied out of the app so it keeps working after Claude updates change the install path)
$icoPath = Join-Path $here 'claude.ico'
try {
  $exe = (Get-Process -Name claude -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '*WindowsApps*Claude_*' } | Select-Object -First 1).Path
  if (-not $exe) { $exe = (Get-ChildItem 'C:\Program Files\WindowsApps' -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue | Select-Object -First 1 | ForEach-Object { Join-Path $_.FullName 'app\Claude.exe' }) }
  Add-Type -AssemblyName System.Drawing
  $ic = [System.Drawing.Icon]::ExtractAssociatedIcon($exe)
  $fs = [System.IO.File]::Create($icoPath); $ic.Save($fs); $fs.Close()
  Write-Output "icon  = $icoPath (from $exe)"
} catch { Write-Output "icon extraction failed: $_" }

function New-Link([string]$dir) {
  $lnk = Join-Path $dir ($LinkName + '.lnk')
  # conhost --headless runs PowerShell without ever creating a console window (-WindowStyle Hidden still flashes one)
  $ps = Join-Path $env:SystemRoot 'System32\conhost.exe'
  $arg = '--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $here 'launch.ps1') + '"'
  $ico = ''; if (Test-Path -LiteralPath $icoPath) { $ico = $icoPath }
  [LinkMaker]::Create($lnk, $ps, $arg, $here, $ico, 'Claude with startup animation', 7)
  Write-Output "shortcut = $lnk"
}
New-Link (Split-Path -Parent $here)                       # D:\...\splash\
if ($Desktop) { New-Link ([Environment]::GetFolderPath('Desktop')) }
