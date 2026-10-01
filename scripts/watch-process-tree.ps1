<#
.SYNOPSIS
  监控某个进程在启动/运行期间拉起了哪些子进程（排查"读不到信息""调不起组件"类故障）。

.DESCRIPTION
  用 WMI 的 Win32_Process 轮询，记录出现过的 新进程。
  输出只有时间、PID、父 PID、进程名 —— 不含命令行、路径等可能含隐私的内容。

.EXAMPLE
  .\watch-process-tree.ps1 -ProcessName notepad -Seconds 60
#>
param(
  [Parameter(Mandatory=$true)][string]$ProcessName,
  [int]$Seconds = 60,
  [int]$IntervalMs = 400,
  [string]$OutFile = ""
)

$ErrorActionPreference = "Stop"

$target = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $target) {
  Write-Host "[!] 进程 $ProcessName 当前未运行。"
  Write-Host '    如果你想连“启动过程”一起观察，请先运行本脚本，再手动启动目标程序。'
  Write-Host '    注意：本脚本按进程名过滤，会记录所有新出现的进程；' -NoNewline
  Write-Host '如果要精确到目标程序的子进程，可以在输出里按 PPID 回溯。'
} else {
  Write-Host "[*] 已找到 $ProcessName，PID = $($target.Id)"
}

$seen = New-Object 'System.Collections.Generic.HashSet[int]'
Get-CimInstance Win32_Process | ForEach-Object { [void]$seen.Add([int]$_.ProcessId) }

$lines = New-Object 'System.Collections.Generic.List[string]'
$deadline = (Get-Date).AddSeconds($Seconds)
Write-Host "[*] 开始观察 $Seconds 秒（每 $IntervalMs ms 采样一次）..."

while ((Get-Date) -lt $deadline) {
  foreach ($p in (Get-CimInstance Win32_Process)) {
    $pidv = [int]$p.ProcessId
    if (-not $seen.Contains($pidv)) {
      [void]$seen.Add($pidv)
      $line = "{0} | PID={1} | PPID={2} | {3}" -f (Get-Date -Format "HH:mm:ss.fff"), $pidv, $p.ParentProcessId, $p.Name
      $lines.Add($line)
      Write-Host $line
    }
  }
  Start-Sleep -Milliseconds $IntervalMs
}

if ($OutFile) {
  [System.IO.File]::WriteAllLines($OutFile, $lines, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host "[*] 已写入 $OutFile（共 $($lines.Count) 行）"
} else {
  Write-Host "[*] 观察结束，共捕获 $($lines.Count) 个新进程。"
}