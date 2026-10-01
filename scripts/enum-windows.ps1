<#
.SYNOPSIS
  枚举某个进程的所有顶层窗口（可选：连同子控件一起打印）。

.EXAMPLE
  .\enum-windows.ps1 -ProcessId 12345
  .\enum-windows.ps1 -ProcessId 12345 -DumpControls
  .\enum-windows.ps1 -ProcessName notepad
#>
param(
  [int]$ProcessId = 0,
  [string]$ProcessName = "",
  [switch]$DumpControls
)

$ErrorActionPreference = "Stop"

Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public class WinEnum {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);

  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, EnumProc cb, IntPtr p);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }

  public static string Cls(IntPtr h) { var sb = new StringBuilder(256); GetClassName(h, sb, 256); return sb.ToString(); }
  public static string Txt(IntPtr h) { var sb = new StringBuilder(512); GetWindowText(h, sb, 512); return sb.ToString(); }

  public static List<object[]> TopLevel(uint targetPid) {
    var list = new List<object[]>();
    EnumWindows((h, p) => {
      uint pid; GetWindowThreadProcessId(h, out pid);
      if (targetPid != 0 && pid != targetPid) return true;
      RECT r; GetWindowRect(h, out r);
      list.Add(new object[] { h, pid, Cls(h), Txt(h),
        string.Format("{0},{1},{2},{3}", r.Left, r.Top, r.Right, r.Bottom), IsWindowVisible(h) });
      return true;
    }, IntPtr.Zero);
    return list;
  }

  public static List<object[]> Children(IntPtr root) {
    var list = new List<object[]>();
    EnumChildWindows(root, (h, p) => {
      RECT r; GetWindowRect(h, out r);
      list.Add(new object[] { h, GetDlgCtrlID(h), Cls(h), Txt(h),
        string.Format("{0},{1},{2},{3}", r.Left, r.Top, r.Right, r.Bottom), IsWindowEnabled(h) });
      return true;
    }, IntPtr.Zero);
    return list;
  }

  [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr h);
}
"@

if ($ProcessId -eq 0 -and $ProcessName) {
  $p = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $p) { throw "找不到进程：$ProcessName" }
  $ProcessId = $p.Id
}
if ($ProcessId -eq 0) { throw "必须提供 -ProcessId 或 -ProcessName" }

Write-Host "== 进程 $ProcessId 的顶层窗口 =="
$tops = [WinEnum]::TopLevel([uint32]$ProcessId)
if ($tops.Count -eq 0) { Write-Host "  (没有找到窗口，进程可能已退出)" }

foreach ($t in $tops) {
  $h = [IntPtr]$t[0]
  Write-Host ("  hwnd=0x{0:X}  pid={1}  vis={2}  cls={3}  rect={4}  title={5}" -f `
    [int64]$h, $t[1], $t[5], $t[2], $t[4], "`"$($t[3])`"")
  if ($DumpControls) {
    $kids = [WinEnum]::Children($h)
    Write-Host ("    子控件 {0} 个：" -f $kids.Count)
    foreach ($k in ($kids | Sort-Object { [int]$_[1] })) {
      Write-Host ("      id={0,-6} cls={1,-22} enabled={2} rect={3} text=[{4}]" -f `
        $k[1], $k[2], $k[5], $k[4], $k[3])
    }
  }
}