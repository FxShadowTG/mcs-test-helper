param(
    [string]$MapName = "",
    [string]$ProjectType = "map",
    [string]$BoundItemId = "",
    [string]$PublishKeyword = "",
    [ValidateSet("free", "review")]
    [string]$SelfTestMode = "free",
    [string]$WorkRoot = "D:\MCStudioDownload\work",
    [string]$ProgressFile = "",
    [switch]$DryRun,
    [switch]$NoPause,
    [int]$Countdown = 3
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne "STA") {
    $argList = @(
        "-NoProfile", "-STA", "-ExecutionPolicy", "Bypass",
        "-File", $PSCommandPath
    )
    if ($MapName) { $argList += @("-MapName", $MapName) }
    if ($ProjectType) { $argList += @("-ProjectType", $ProjectType) }
    if ($BoundItemId) { $argList += @("-BoundItemId", $BoundItemId) }
    if ($PublishKeyword) { $argList += @("-PublishKeyword", $PublishKeyword) }
    if ($SelfTestMode) { $argList += @("-SelfTestMode", $SelfTestMode) }
    if ($WorkRoot) { $argList += @("-WorkRoot", $WorkRoot) }
    if ($ProgressFile) { $argList += @("-ProgressFile", $ProgressFile) }
    if ($DryRun) { $argList += "-DryRun" }
    if ($NoPause) { $argList += "-NoPause" }
    $argList += @("-Countdown", "$Countdown")
    $child = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $argList -Wait -PassThru
    exit $child.ExitCode
}

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class McWin32 {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr hWnd, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  public struct POINT { public int X; public int Y; }
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT lpwndpl);
  [DllImport("user32.dll")] public static extern bool SetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT lpwndpl);
  [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint dwFlags);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO lpmi);
  [DllImport("user32.dll")] public static extern bool ScreenToClient(IntPtr hWnd, ref POINT lpPoint);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr hWnd, EnumProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  [StructLayout(LayoutKind.Sequential)]
  public struct WINDOWPLACEMENT {
    public int length;
    public int flags;
    public int showCmd;
    public POINT ptMinPosition;
    public POINT ptMaxPosition;
    public RECT rcNormalPosition;
  }
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct MONITORINFO {
    public int cbSize;
    public RECT rcMonitor;
    public RECT rcWork;
    public uint dwFlags;
  }
}
"@
[void][McWin32]::SetProcessDPIAware()
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:LogPath = Join-Path $PSScriptRoot "last-run.log"
$script:ProgressFile = $ProgressFile
$script:StepPercent = 0
Set-Content -Path $script:LogPath -Encoding UTF8 -Value ("开始 " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))

function Write-RunProgress([int]$Percent, [string]$Message) {
    $script:StepPercent = $Percent
    if (-not $script:ProgressFile) { return }
    try {
        $safe = (($Message -replace '\|','/') -replace "`r|`n", " ")
        $text = "{0}|{1}" -f $Percent, $safe
        $utf8 = New-Object System.Text.UTF8Encoding $false
        $fs = New-Object System.IO.FileStream($script:ProgressFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
        $sw = New-Object System.IO.StreamWriter($fs, $utf8)
        $sw.Write($text)
        $sw.Dispose()
    } catch {}
}

function Log([string]$Message) {
    $line = "{0} {1}" -f (Get-Date -Format "HH:mm:ss"), $Message
    Add-Content -Path $script:LogPath -Value $line -Encoding UTF8
    Write-Host $line
}

function Set-Step([int]$Percent, [string]$Message) {
    Log $Message
    Write-RunProgress $Percent $Message
}

function Get-TopWindows {
    $names = @{}
    Get-Process | ForEach-Object { $names[[int]$_.Id] = $_.ProcessName }
    $list = New-Object System.Collections.Generic.List[object]
    $cb = [McWin32+EnumProc]{
        param($h, $l)
        if (-not [McWin32]::IsWindowVisible($h)) { return $true }
        $sb = New-Object System.Text.StringBuilder 512
        [void][McWin32]::GetWindowText($h, $sb, $sb.Capacity)
        $title = $sb.ToString()
        $procId = [uint32]0
        [void][McWin32]::GetWindowThreadProcessId($h, [ref]$procId)
        $rect = New-Object McWin32+RECT
        [void][McWin32]::GetWindowRect($h, [ref]$rect)
        $cls = New-Object System.Text.StringBuilder 256
        [void][McWin32]::GetClassName($h, $cls, $cls.Capacity)
        $w = $rect.Right - $rect.Left
        $hh = $rect.Bottom - $rect.Top
        $left = $rect.Left
        $top = $rect.Top
        if ([McWin32]::IsIconic($h)) {
            $wp = New-Object McWin32+WINDOWPLACEMENT
            $wp.length = [System.Runtime.InteropServices.Marshal]::SizeOf($wp)
            if ([McWin32]::GetWindowPlacement($h, [ref]$wp)) {
                $left = $wp.rcNormalPosition.Left
                $top = $wp.rcNormalPosition.Top
                $w = $wp.rcNormalPosition.Right - $wp.rcNormalPosition.Left
                $hh = $wp.rcNormalPosition.Bottom - $wp.rcNormalPosition.Top
            }
        }
        if ($w -lt 40 -or $hh -lt 20) { return $true }
        $list.Add([pscustomobject]@{
            Hwnd = $h
            Pid = [int]$procId
            ProcessName = [string]$names[[int]$procId]
            Title = $title
            ClassName = $cls.ToString()
            Left = $left
            Top = $top
            Width = $w
            Height = $hh
        }) | Out-Null
        return $true
    }
    $script:EnumKeepAlive = $cb
    [void][McWin32]::EnumWindows($cb, [IntPtr]::Zero)
    return $list
}

function Get-Ui([IntPtr]$Hwnd) {
    if ($Hwnd -eq [IntPtr]::Zero) { return $null }
    try {
        if (-not [McWin32]::IsWindow($Hwnd)) { return $null }
        return [System.Windows.Automation.AutomationElement]::FromHandle($Hwnd)
    } catch {
        return $null
    }
}

function Test-OnScreen($Element) {
    if (-not $Element) { return $false }
    $r = $Element.Current.BoundingRectangle
    if ([double]::IsNaN($r.Width) -or [double]::IsInfinity($r.Width)) { return $false }
    if ([double]::IsNaN($r.Height) -or [double]::IsInfinity($r.Height)) { return $false }
    if ($r.Width -le 2 -or $r.Height -le 2) { return $false }
    if ($r.X -lt -2000 -or $r.Y -lt -2000 -or $r.X -gt 12000 -or $r.Y -gt 8000) { return $false }
    return $true
}

function Find-AllExact($Root, [string]$Name, [string]$ControlType) {
    if (-not $Root -or -not $Name) { return @() }
    $nameCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty, $Name)
    if ($ControlType) {
        $ct = [System.Windows.Automation.ControlType]::$ControlType
        $typeCond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty, $ct)
        $cond = New-Object System.Windows.Automation.AndCondition($nameCond, $typeCond)
    } else {
        $cond = $nameCond
    }
    $found = $Root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($el in $found) {
        if (Test-OnScreen $el) { $list.Add($el) | Out-Null }
    }
    return $list
}

function Find-FirstExact($Root, [string]$Name, [string]$ControlType) {
    $all = @(Find-AllExact $Root $Name $ControlType)
    if ($all.Count -gt 0) { return $all[0] }
    return $null
}

function Find-AnyByName($Root, [string]$Name, [string]$ControlType) {
    if (-not $Root -or -not $Name) { return @() }
    $nameCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty, $Name)
    if ($ControlType) {
        $ct = [System.Windows.Automation.ControlType]::$ControlType
        $typeCond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty, $ct)
        $cond = New-Object System.Windows.Automation.AndCondition($nameCond, $typeCond)
    } else {
        $cond = $nameCond
    }
    $found = $Root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($el in $found) { $list.Add($el) | Out-Null }
    return $list
}

function Find-DomButton([IntPtr]$Hwnd, [string]$Label, [string]$ClassHint) {
    $root = Get-Ui $Hwnd
    if (-not $root) { return $null }
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Button)
    $buttons = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
    $fallback = $null
    foreach ($el in $buttons) {
        $name = ""
        $cls = ""
        try {
            $name = ([string]$el.Current.Name).Trim()
            $cls = [string]$el.Current.ClassName
        } catch { continue }
        if ($name -ne $Label) { continue }
        if ($cls -eq "BackForwardButton") { continue }
        if ($ClassHint -and $cls.Contains($ClassHint)) { return $el }
        if (-not $fallback) { $fallback = $el }
    }
    if ($ClassHint) { return $null }
    return $fallback
}

function Find-PageButton([IntPtr]$Hwnd, [string]$Label) {
    $root = Get-Ui $Hwnd
    if (-not $root) { return $null }
    $exact = @(Find-AnyByName $root $Label "Button")
    if ($exact.Count -gt 0) { return $exact[0] }
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Button)
    $buttons = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
    foreach ($el in $buttons) {
        $name = ""
        try { $name = ([string]$el.Current.Name).Trim() } catch { continue }
        if ($name -eq $Label) { return $el }
    }
    foreach ($el in $buttons) {
        $name = ""
        try { $name = ([string]$el.Current.Name).Trim() } catch { continue }
        if ($name -and $name.Contains($Label) -and $name.Length -le ($Label.Length + 8)) { return $el }
    }
    return $null
}

function Invoke-PageButton($Element, [string]$Label, [switch]$InvokeOnly, [switch]$KeepFocus) {
    if (-not $Element) { return $false }
    Log ("调用网页按钮 [{0}]" -f $Label)
    $done = $false
    foreach ($pattern in $Element.GetSupportedPatterns()) {
        if ($pattern.Id -eq [System.Windows.Automation.InvokePattern]::Pattern.Id) {
            $invoker = $Element.GetCurrentPattern($pattern)
            $invoker.Invoke()
            $done = $true
            break
        }
    }
    if (-not $done) {
        try {
            $legacy = $Element.GetCurrentPattern([System.Windows.Automation.LegacyIAccessiblePattern]::Pattern)
            $legacy.DoDefaultAction()
            $done = $true
        } catch {}
    }
    if ($done -and -not $KeepFocus) { Restore-BackgroundFocus }
    return $done
}

function Show-Target([IntPtr]$Hwnd) {
    if ($Hwnd -eq [IntPtr]::Zero) { return }
    [void][McWin32]::ShowWindow($Hwnd, 9)
    Set-WindowForeground $Hwnd
    Start-Sleep -Milliseconds 180
}

function Set-WindowForeground([IntPtr]$Hwnd) {
    if ($Hwnd -eq [IntPtr]::Zero) { return }
    if (-not [McWin32]::IsWindow($Hwnd)) { return }
    $current = [McWin32]::GetForegroundWindow()
    if ($current -eq $Hwnd) { return }
    $unused = [uint32]0
    $targetThread = [McWin32]::GetWindowThreadProcessId($Hwnd, [ref]$unused)
    $currentThread = [uint32]0
    if ($current -ne [IntPtr]::Zero) {
        $currentThread = [McWin32]::GetWindowThreadProcessId($current, [ref]$unused)
    }
    $thisThread = [McWin32]::GetCurrentThreadId()
    $attachedCurrent = $false
    $attachedTarget = $false
    if ($currentThread -ne 0 -and $currentThread -ne $thisThread) {
        $attachedCurrent = [McWin32]::AttachThreadInput($thisThread, $currentThread, $true)
    }
    if ($targetThread -ne 0 -and $targetThread -ne $thisThread) {
        $attachedTarget = [McWin32]::AttachThreadInput($thisThread, $targetThread, $true)
    }
    [void][McWin32]::SetForegroundWindow($Hwnd)
    if ($attachedTarget) { [void][McWin32]::AttachThreadInput($thisThread, $targetThread, $false) }
    if ($attachedCurrent) { [void][McWin32]::AttachThreadInput($thisThread, $currentThread, $false) }
}

function Push-WindowBehind([IntPtr]$Hwnd) {
    if ($Hwnd -eq [IntPtr]::Zero) { return }
    [void][McWin32]::SetWindowPos($Hwnd, [IntPtr]1, 0, 0, 0, 0, 0x0013)
}

function Ensure-LauncherBackground([IntPtr]$Hwnd) {
    if ($Hwnd -eq [IntPtr]::Zero) { return }
    if (-not [McWin32]::IsIconic($Hwnd)) { return }
    $wp = New-Object McWin32+WINDOWPLACEMENT
    $wp.length = [System.Runtime.InteropServices.Marshal]::SizeOf($wp)
    if ([McWin32]::GetWindowPlacement($Hwnd, [ref]$wp)) {
        $wp.showCmd = 4
        [void][McWin32]::SetWindowPlacement($Hwnd, [ref]$wp)
    }
    if ([McWin32]::IsIconic($Hwnd)) {
        [void][McWin32]::ShowWindow($Hwnd, 4)
    }
    Push-WindowBehind $Hwnd
    Start-Sleep -Milliseconds 250
}

function Remember-BackgroundFocus {
    $fg = [McWin32]::GetForegroundWindow()
    if ($fg -eq [IntPtr]::Zero) { return }
    $procId = [uint32]0
    [void][McWin32]::GetWindowThreadProcessId($fg, [ref]$procId)
    $name = ""
    try { $name = [string](Get-Process -Id $procId -ErrorAction Stop).ProcessName } catch {}
    if ($name -match "^(MCStudio|msedge|chrome|firefox|MC_Editor)$") {
        foreach ($w in @(Get-TopWindows)) {
            if ($w.Title -eq "一键保存发布自测") {
                $script:BackgroundReturn = $w.Hwnd
                if ($script:GuardState) { $script:GuardState.ReturnHwnd = [int64]$w.Hwnd }
                return
            }
        }
        return
    }
    $script:BackgroundReturn = $fg
    if ($script:GuardState) { $script:GuardState.ReturnHwnd = [int64]$fg }
}

function Restore-BackgroundFocus {
    $back = $script:BackgroundReturn
    if (-not $back -or $back -eq [IntPtr]::Zero) { return }
    if (-not [McWin32]::IsWindow($back)) { $script:BackgroundReturn = [IntPtr]::Zero; return }
    $now = [McWin32]::GetForegroundWindow()
    if ($now -eq $back) { return }
    $procId = [uint32]0
    [void][McWin32]::GetWindowThreadProcessId($now, [ref]$procId)
    $name = ""
    try { $name = [string](Get-Process -Id $procId -ErrorAction Stop).ProcessName } catch {}
    if ($name -notmatch "^(MCStudio|msedge|chrome|firefox)$") {
        $script:BackgroundReturn = $now
        if ($script:GuardState) { $script:GuardState.ReturnHwnd = [int64]$now }
        return
    }
    Push-WindowBehind $now
    Set-WindowForeground $back
}

function Set-FocusGuardPause([bool]$Paused) {
    if ($script:GuardState) { $script:GuardState.Pause = $Paused }
}

function Start-FocusGuard {
    if ($script:GuardPower) { return }
    if (-not $script:BackgroundReturn -or $script:BackgroundReturn -eq [IntPtr]::Zero) { Remember-BackgroundFocus }
    $hwnd = [int64]0
    if ($script:BackgroundReturn) { $hwnd = [int64]$script:BackgroundReturn }
    $script:GuardState = [hashtable]::Synchronized(@{
        Stop = $false
        Pause = $false
        ReturnHwnd = $hwnd
    })
    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
        param($state)
        while (-not $state.Stop) {
            try {
                if (-not $state.Pause) {
                    $back = [IntPtr]([int64]$state.ReturnHwnd)
                    $now = [McWin32]::GetForegroundWindow()
                    if ($now -ne [IntPtr]::Zero -and $now -ne $back) {
                        $procId = [uint32]0
                        [void][McWin32]::GetWindowThreadProcessId($now, [ref]$procId)
                        $name = ""
                        try { $name = [string](Get-Process -Id ([int]$procId) -ErrorAction Stop).ProcessName } catch {}
                        if ($name -match "^(MCStudio|msedge|chrome|firefox)$") {
                            [void][McWin32]::SetWindowPos($now, [IntPtr]1, 0, 0, 0, 0, 0x0013)
                            if ($back -eq [IntPtr]::Zero) {
                                $cursor = $now
                                for ($i = 0; $i -lt 12 -and $cursor -ne [IntPtr]::Zero; $i++) {
                                    $cursor = [McWin32]::GetWindow($cursor, 2)
                                    if ($cursor -eq [IntPtr]::Zero) { break }
                                    if (-not [McWin32]::IsWindowVisible($cursor)) { continue }
                                    $nextPid = [uint32]0
                                    [void][McWin32]::GetWindowThreadProcessId($cursor, [ref]$nextPid)
                                    $nextName = ""
                                    try { $nextName = [string](Get-Process -Id ([int]$nextPid) -ErrorAction Stop).ProcessName } catch {}
                                    if ($nextName -and $nextName -notmatch "^(MCStudio|msedge|chrome|firefox|MC_Editor)$") {
                                        $back = $cursor
                                        $state.ReturnHwnd = [int64]$cursor
                                        break
                                    }
                                }
                            }
                            if ($back -ne [IntPtr]::Zero -and [McWin32]::IsWindow($back)) {
                                $unused = [uint32]0
                                $targetThread = [McWin32]::GetWindowThreadProcessId($back, [ref]$unused)
                                $currentThread = [McWin32]::GetWindowThreadProcessId($now, [ref]$unused)
                                $thisThread = [McWin32]::GetCurrentThreadId()
                                $attachedCurrent = $false
                                $attachedTarget = $false
                                if ($currentThread -ne 0 -and $currentThread -ne $thisThread) {
                                    $attachedCurrent = [McWin32]::AttachThreadInput($thisThread, $currentThread, $true)
                                }
                                if ($targetThread -ne 0 -and $targetThread -ne $thisThread) {
                                    $attachedTarget = [McWin32]::AttachThreadInput($thisThread, $targetThread, $true)
                                }
                                [void][McWin32]::SetForegroundWindow($back)
                                if ($attachedTarget) { [void][McWin32]::AttachThreadInput($thisThread, $targetThread, $false) }
                                if ($attachedCurrent) { [void][McWin32]::AttachThreadInput($thisThread, $currentThread, $false) }
                            }
                        } elseif ($name -and $name -ne "MC_Editor") {
                            $state.ReturnHwnd = [int64]$now
                        }
                    }
                }
            } catch {}
            Start-Sleep -Milliseconds 30
        }
    }).AddArgument($script:GuardState)
    $script:GuardRunspace = $rs
    $script:GuardPower = $ps
    $script:GuardAsync = $ps.BeginInvoke()
}

function Stop-FocusGuard {
    if (-not $script:GuardPower) { return }
    $script:GuardState.Stop = $true
    try { [void]$script:GuardPower.EndInvoke($script:GuardAsync) } catch {}
    try { $script:GuardPower.Dispose() } catch {}
    try { $script:GuardRunspace.Close() } catch {}
    $script:GuardPower = $null
    $script:GuardRunspace = $null
}

function Maximize-Browser([IntPtr]$Hwnd) {
    if ($Hwnd -eq [IntPtr]::Zero) { return }
    Log "后台放大浏览器，不切换到前台"
    if ([McWin32]::IsIconic($Hwnd)) {
        $wp = New-Object McWin32+WINDOWPLACEMENT
        $wp.length = [System.Runtime.InteropServices.Marshal]::SizeOf($wp)
        if ([McWin32]::GetWindowPlacement($Hwnd, [ref]$wp)) {
            $wp.showCmd = 4
            [void][McWin32]::SetWindowPlacement($Hwnd, [ref]$wp)
        }
        Start-Sleep -Milliseconds 200
    }
    $mon = [McWin32]::MonitorFromWindow($Hwnd, 2)
    $info = New-Object McWin32+MONITORINFO
    $info.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($info)
    if ([McWin32]::GetMonitorInfo($mon, [ref]$info)) {
        $work = $info.rcWork
        $flags = 0x0010 -bor 0x0040
        [void][McWin32]::SetWindowPos($Hwnd, [IntPtr]1, $work.Left, $work.Top, ($work.Right - $work.Left), ($work.Bottom - $work.Top), $flags)
    }
    Push-WindowBehind $Hwnd
    Restore-BackgroundFocus
    Start-Sleep -Milliseconds 300
}

function Send-BackgroundHover([IntPtr]$Hwnd, $Element) {
    if ($Hwnd -eq [IntPtr]::Zero -or -not $Element) { return $false }
    $script:RenderBest = [IntPtr]::Zero
    $script:RenderArea = [int64]0
    $cb = [McWin32+EnumProc]{
        param($h, $l)
        $cls = New-Object System.Text.StringBuilder 256
        [void][McWin32]::GetClassName($h, $cls, $cls.Capacity)
        if ($cls.ToString() -eq "Chrome_RenderWidgetHostHWND") {
            $rect = New-Object McWin32+RECT
            if ([McWin32]::GetWindowRect($h, [ref]$rect)) {
                $area = [int64]($rect.Right - $rect.Left) * [int64]($rect.Bottom - $rect.Top)
                if ($area -gt $script:RenderArea) {
                    $script:RenderArea = $area
                    $script:RenderBest = $h
                }
            }
        }
        return $true
    }
    $script:EnumKeepAlive = $cb
    [void][McWin32]::EnumChildWindows($Hwnd, $cb, [IntPtr]::Zero)
    $target = $script:RenderBest
    if ($target -eq [IntPtr]::Zero) { $target = $Hwnd }
    $br = $Element.Current.BoundingRectangle
    $pt = New-Object McWin32+POINT
    $pt.X = [int]($br.X + ($br.Width / 2))
    $pt.Y = [int]($br.Y + ($br.Height / 2))
    if (-not [McWin32]::ScreenToClient($target, [ref]$pt)) { return $false }
    $packed = (($pt.Y -band 0xFFFF) * 65536) + ($pt.X -band 0xFFFF)
    $lp = New-Object System.IntPtr ([int]$packed)
    [void][McWin32]::SendMessage($target, 0x0200, [IntPtr]::Zero, $lp)
    [void][McWin32]::SendMessage($target, 0x02A1, [IntPtr]::Zero, $lp)
    return $true
}

function Scroll-BrowserToTop([IntPtr]$Hwnd) {
    if ($Hwnd -eq [IntPtr]::Zero) { return }
    Log "把网页滚到最上"
    $el = Get-Ui $Hwnd
    if ($el) {
        $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
        $stack = New-Object System.Collections.Stack
        $stack.Push($el)
        $seen = 0
        while ($stack.Count -gt 0 -and $seen -lt 1500) {
            $node = $stack.Pop()
            $seen++
            try {
                foreach ($pattern in $node.GetSupportedPatterns()) {
                    if ($pattern.Id -eq [System.Windows.Automation.ScrollPattern]::Pattern.Id) {
                        $scroll = $node.GetCurrentPattern($pattern)
                        if ($scroll.Current.VerticallyScrollable) {
                            $scroll.SetScrollPercent(-1, 0)
                        }
                    }
                }
            } catch {}
            $child = $walker.GetFirstChild($node)
            while ($child) {
                $stack.Push($child)
                $child = $walker.GetNextSibling($child)
            }
        }
    }
}

function Move-MouseSmooth([int]$X, [int]$Y, [int]$MinMs = 90) {
    $pt = New-Object McWin32+POINT
    [void][McWin32]::GetCursorPos([ref]$pt)
    $dx = $X - $pt.X
    $dy = $Y - $pt.Y
    $dist = [Math]::Sqrt(($dx * $dx) + ($dy * $dy))
    if ($dist -lt 2) {
        [void][McWin32]::SetCursorPos($X, $Y)
        return
    }
    $duration = [Math]::Min(220, [Math]::Max($MinMs, [int]($dist * 0.16)))
    $steps = [Math]::Max(8, [int]($duration / 12))
    $slice = [Math]::Max(6, [int]($duration / $steps))
    for ($i = 1; $i -le $steps; $i++) {
        $t = $i / [double]$steps
        $e = $t * $t * (3 - (2 * $t))
        $nx = [int][Math]::Round($pt.X + ($dx * $e))
        $ny = [int][Math]::Round($pt.Y + ($dy * $e))
        [void][McWin32]::SetCursorPos($nx, $ny)
        Start-Sleep -Milliseconds $slice
    }
    [void][McWin32]::SetCursorPos($X, $Y)
}

function Click-MouseAt([int]$X, [int]$Y, [int]$HoverMs = 320) {
    Move-MouseSmooth $X $Y
    Start-Sleep -Milliseconds $HoverMs
    [McWin32]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 90
    [McWin32]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 180
}

function Test-InvokeNode($Element) {
    if (-not $Element) { return $false }
    foreach ($pattern in @($Element.GetSupportedPatterns())) {
        try {
            if ($pattern.Id -eq [System.Windows.Automation.InvokePattern]::Pattern.Id) {
                $Element.GetCurrentPattern($pattern).Invoke()
                return $true
            }
            if ($pattern.Id -eq [System.Windows.Automation.TogglePattern]::Pattern.Id) {
                $toggle = $Element.GetCurrentPattern($pattern)
                if ($toggle.Current.ToggleState -ne [System.Windows.Automation.ToggleState]::On) {
                    $toggle.Toggle()
                }
                return $true
            }
            if ($pattern.Id -eq [System.Windows.Automation.SelectionItemPattern]::Pattern.Id) {
                $Element.GetCurrentPattern($pattern).Select()
                return $true
            }
            if ($pattern.Id -eq [System.Windows.Automation.ExpandCollapsePattern]::Pattern.Id) {
                $expand = $Element.GetCurrentPattern($pattern)
                if ($expand.Current.ExpandCollapseState -eq [System.Windows.Automation.ExpandCollapseState]::Collapsed) {
                    $expand.Expand()
                }
                return $true
            }
        } catch {}
    }
    return $false
}

function Invoke-LauncherElement($Element, [string]$Label, [switch]$KeepFocus) {
    if (-not $Element) { return $false }
    if ($DryRun) {
        Log ("将调用 [{0}]" -f $Label)
        return $true
    }
    $node = $Element
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $done = $false
    for ($i = 0; $i -lt 6 -and $node; $i++) {
        if (Test-InvokeNode $node) {
            Log ("调用 [{0}]" -f $Label)
            $done = $true
            break
        }
        try { $node = $walker.GetParent($node) } catch { break }
    }
    if (-not $done) {
        try {
            $legacy = $Element.GetCurrentPattern([System.Windows.Automation.LegacyIAccessiblePattern]::Pattern)
            $legacy.DoDefaultAction()
            Log ("调用 [{0}]" -f $Label)
            $done = $true
        } catch {}
    }
    if ($done -and -not $KeepFocus) { Restore-BackgroundFocus }
    return $done
}

function Click-Ui($Element, [string]$Label, [IntPtr]$Hwnd, [switch]$MouseOnly) {
    $r = $Element.Current.BoundingRectangle
    $how = "Invoke"
    if ($MouseOnly) { $how = "鼠标" }
    Log ("{0} [{1}] {2} @ {3:N0},{4:N0}  {5:N0}x{6:N0}" -f $(if ($DryRun) { "将点击" } else { "点击" }), $Label, $how, $r.X, $r.Y, $r.Width, $r.Height)
    if ($DryRun) { return }
    if ($Hwnd -ne [IntPtr]::Zero) { Show-Target $Hwnd }
    $invoked = $false
    if (-not $MouseOnly) {
        foreach ($pattern in $Element.GetSupportedPatterns()) {
            if ($pattern.Id -eq [System.Windows.Automation.InvokePattern]::Pattern.Id) {
                $pat = $Element.GetCurrentPattern($pattern)
                $pat.Invoke()
                $invoked = $true
                break
            }
        }
    }
    if (-not $invoked) {
        $fresh = $Element.Current.BoundingRectangle
        if ($fresh.Width -gt 4 -and $fresh.Height -gt 4) { $r = $fresh }
        $x = [int]($r.X + ($r.Width / 2))
        $y = [int]($r.Y + ($r.Height / 2))
        Move-MouseSmooth $x $y
        Start-Sleep -Milliseconds 180
        [void][McWin32]::SetCursorPos($x, $y)
        Start-Sleep -Milliseconds 80
        [McWin32]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 90
        [McWin32]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
    }
    Start-Sleep -Milliseconds 280
}

function Wait-Until([int]$TimeoutSec, [scriptblock]$Probe, [int]$IntervalMs = 400) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $result = & $Probe
        if ($result) { return $result }
        if ($IntervalMs -gt 0) { Start-Sleep -Milliseconds $IntervalMs }
    }
    return $null
}

function Get-LauncherMain {
    $wins = @(Get-TopWindows | Where-Object {
        $_.ProcessName -eq "MCStudio" -and $_.Width -gt 700 -and $_.Height -gt 400 -and $_.Title -ne "配置"
    })
    return $wins | Sort-Object { $_.Width * $_.Height } -Descending | Select-Object -First 1
}

function Get-ConfigElement {
    foreach ($w in @(Get-TopWindows | Where-Object { $_.ProcessName -eq "MCStudio" -and $_.Title -eq "配置" -and $_.Width -gt 200 })) {
        return @{ Element = (Get-Ui $w.Hwnd); Hwnd = $w.Hwnd }
    }
    $main = Get-LauncherMain
    if (-not $main) { return $null }
    $root = Get-Ui $main.Hwnd
    $win = Find-FirstExact $root "配置" "Window"
    if ($win -and (Test-OnScreen $win)) {
        return @{ Element = $win; Hwnd = $main.Hwnd }
    }
    return $null
}

function Get-PublishWorkWindow {
    foreach ($w in @(Get-TopWindows | Where-Object { $_.ProcessName -eq "MCStudio" -and $_.Width -gt 280 -and $_.Height -gt 280 -and $_.Title -ne "我的世界编辑器" })) {
        try {
            $el = Get-Ui $w.Hwnd
            if (-not $el) { continue }
            if ($w.Title -eq "发布作品" -or (Find-FirstExact $el "发布作品" "Text") -or (Find-FirstExact $el "请选择操作类型:" "Text")) {
                return @{ Element = $el; Hwnd = $w.Hwnd }
            }
        } catch { continue }
    }
    return $null
}

function Find-FirstContains($Root, [string]$Needle) {
    if (-not $Root -or -not $Needle) { return $null }
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $stack = New-Object System.Collections.Stack
    $stack.Push(@($Root, 0))
    $seen = 0
    $best = $null
    $bestLen = 10000
    while ($stack.Count -gt 0 -and $seen -lt 2500) {
        $pair = $stack.Pop()
        $node = $pair[0]
        $depth = [int]$pair[1]
        $seen++
        if ($depth -gt 16) { continue }
        $name = ""
        try { $name = [string]$node.Current.Name } catch { continue }
        if ($name -and $name.Contains($Needle) -and $name.Length -le 80 -and (Test-OnScreen $node) -and $name.Length -lt $bestLen) {
            $best = $node
            $bestLen = $name.Length
        }
        $child = $walker.GetFirstChild($node)
        while ($child) {
            $stack.Push(@($child, ($depth + 1)))
            $child = $walker.GetNextSibling($child)
        }
    }
    return $best
}

function Find-Edits($Root) {
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Edit)
    $found = $Root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($el in $found) {
        if (Test-OnScreen $el) { $list.Add($el) | Out-Null }
    }
    return $list
}

function Set-EditText($Element, [string]$Text) {
    foreach ($pattern in $Element.GetSupportedPatterns()) {
        if ($pattern.Id -eq [System.Windows.Automation.ValuePattern]::Pattern.Id) {
            $value = $Element.GetCurrentPattern($pattern)
            $value.SetValue($Text)
            return $true
        }
    }
    return $false
}

function Confirm-PublishWork([string]$MapTitle, [string]$MatchKeyword = "") {
    $searchTerm = $MatchKeyword.Trim()
    if (-not $searchTerm) { $searchTerm = $MapTitle }
    Log "等待发布作品窗口"
    $dlg = Wait-Until 8 { Get-PublishWorkWindow } 100
    if (-not $dlg) { return $null }
    Set-FocusGuardPause $true
    $updateBox = $null
    $ready = Wait-Until 8 {
        $dlgNow = Get-PublishWorkWindow
        if (-not $dlgNow) { return $null }
        $boxCondNow = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::CheckBox)
        $boxesNow = $dlgNow.Element.FindAll([System.Windows.Automation.TreeScope]::Descendants, $boxCondNow)
        foreach ($el in $boxesNow) {
            if (-not (Test-OnScreen $el)) { continue }
            if ($el.Current.Name -eq "新建作品") { continue }
            $script:PublishUpdateBox = $el
            return $dlgNow
        }
        $label = Find-FirstContains $dlgNow.Element "更新已有作品"
        if ($label -and (Test-OnScreen $label)) {
            $script:PublishUpdateBox = $label
            return $dlgNow
        }
        return $null
    } 80
    if (-not $ready) { throw "发布作品窗口里没有「更新已有作品」" }
    $dlg = $ready
    $updateBox = $script:PublishUpdateBox
    Start-Sleep -Milliseconds 500
    Set-Step 66 "选择更新已有作品"
    if (-not (Invoke-LauncherElement $updateBox "更新已有作品" -KeepFocus)) {
        throw "「更新已有作品」无法直接调用"
    }
    Start-Sleep -Milliseconds 400
    $dlg = Get-PublishWorkWindow
    if (-not $dlg) { throw "点了更新已有作品后，发布作品窗口关掉了" }
    $edits = @(Find-Edits $dlg.Element)
    if ($edits.Count -eq 0) { throw "发布作品窗口里没有搜索框" }
    $edit = $edits | Sort-Object { $_.Current.BoundingRectangle.Width } -Descending | Select-Object -First 1
    Set-Step 72 ("搜索已有作品：{0}" -f $searchTerm)
    if (-not $DryRun) {
        if (-not (Set-EditText $edit $searchTerm)) {
            try { $edit.SetFocus() } catch {}
            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.SendKeys]::SendWait("^a")
            Start-Sleep -Milliseconds 80
            [System.Windows.Forms.SendKeys]::SendWait($searchTerm)
        }
    }
    $editBottom = $edit.Current.BoundingRectangle.Y + $edit.Current.BoundingRectangle.Height
    $row = $null
    if (-not $DryRun) {
        Log "等待搜索结果，最多 15 秒"
        $foundRow = Wait-Until 15 {
            $dlgNow = Get-PublishWorkWindow
            if (-not $dlgNow) { return $null }
            $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
            $stack = New-Object System.Collections.Stack
            $stack.Push(@($dlgNow.Element, 0))
            $seen = 0
            $best = $null
            $bestScore = 100000
            while ($stack.Count -gt 0 -and $seen -lt 2500) {
                $pair = $stack.Pop()
                $node = $pair[0]
                $depth = [int]$pair[1]
                $seen++
                if ($depth -gt 16) { continue }
                $name = ""
                $ctype = ""
                try {
                    $name = [string]$node.Current.Name
                    $ctype = $node.Current.ControlType.ProgrammaticName
                } catch { continue }
                if ($name -eq "抱歉，无法找到匹配的结果" -or $name.Contains("无法找到匹配的结果")) { continue }
                $rr = $node.Current.BoundingRectangle
                $inList = (Test-OnScreen $node) -and $rr.Y -gt ($editBottom + 4) -and $rr.Height -ge 14 -and $rr.Height -le 80 -and $rr.Width -gt 40
                if ($inList -and $name -and $ctype -ne "ControlType.Edit" -and -not $name.StartsWith("更新已有作品") -and $name.Contains($searchTerm)) {
                    $score = $rr.Y
                    if ($name -eq $searchTerm) { $score -= 10000 }
                    if ($score -lt $bestScore) { $best = $node; $bestScore = $score }
                }
                $child = $walker.GetFirstChild($node)
                while ($child) {
                    $stack.Push(@($child, ($depth + 1)))
                    $child = $walker.GetNextSibling($child)
                }
            }
            return $best
        }
        if (-not $foundRow) {
            throw "等了 15 秒仍没有搜到「$searchTerm」。已退出，没有点确定。"
        }
        $row = $foundRow
        $dlg = Get-PublishWorkWindow
    }
    if (-not $DryRun) {
        if (-not $dlg) { throw "选择作品前，发布作品窗口关掉了" }
        Log ("调用搜索结果 [{0}]" -f $row.Current.Name)
        if (-not (Invoke-LauncherElement $row $searchTerm -KeepFocus)) {
            throw "搜索结果无法直接调用"
        }
        # UIA Invoke is synchronous; refresh the dialog immediately instead of waiting an extra 300 ms.
        $dlg = Get-PublishWorkWindow
    }
    if (-not $dlg) { throw "选择作品后，发布作品窗口关掉了" }
    $ok = Find-FirstExact $dlg.Element "确定" "Button"
    if (-not $ok) { throw "发布作品窗口里没有「确定」" }
    if (-not (Invoke-LauncherElement $ok "确定" -KeepFocus)) {
        throw "「确定」无法直接调用"
    }
    Set-FocusGuardPause $false
    if (-not $DryRun) {
        [void](Wait-Until 15 { if (Get-PublishWorkWindow) { return $null } else { return $true } })
    }
    Set-Step 76 "已确认发布作品"
    return $true
}

function Get-LatestMap {
    if ($MapName) {
        return [pscustomobject]@{ Name = $MapName; Dir = ""; Updated = "" }
    }
    if (-not (Test-Path $WorkRoot)) { throw "找不到作品目录 $WorkRoot" }
    $best = $null
    foreach ($account in @(Get-ChildItem $WorkRoot -Directory -ErrorAction SilentlyContinue)) {
        $mapRoot = Join-Path $account.FullName "Cpp\Map"
        if (-not (Test-Path $mapRoot)) { continue }
        foreach ($mapDir in @(Get-ChildItem $mapRoot -Directory -ErrorAction SilentlyContinue)) {
            $cfg = Join-Path $mapDir.FullName "work.mcscfg"
            if (-not (Test-Path $cfg)) { continue }
            try {
                $json = Get-Content -Raw -Encoding UTF8 $cfg | ConvertFrom-Json
            } catch { continue }
            if (-not $json.Name) { continue }
            $updated = [datetime]::MinValue
            if ($json.UpdateTime) {
                try { $updated = [datetime]$json.UpdateTime } catch { $updated = (Get-Item $cfg).LastWriteTime }
            } else {
                $updated = (Get-Item $cfg).LastWriteTime
            }
            if (-not $best -or $updated -gt $best.Updated) {
                $best = [pscustomobject]@{ Name = [string]$json.Name; Dir = $mapDir.FullName; Updated = $updated }
            }
        }
    }
    if (-not $best) { throw "作品目录里没有基岩版地图" }
    return $best
}

function Find-TextContains($Root, [string]$Needle) {
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $hits = New-Object System.Collections.Generic.List[object]
    $stack = New-Object System.Collections.Stack
    $stack.Push(@($Root, 0))
    $seen = 0
    while ($stack.Count -gt 0 -and $seen -lt 6000) {
        $pair = $stack.Pop()
        $node = $pair[0]
        $depth = [int]$pair[1]
        $seen++
        if ($depth -gt 24) { continue }
        $name = ""
        try { $name = [string]$node.Current.Name } catch { continue }
        if ($name -and $name.Contains($Needle) -and $name.Length -le ($Needle.Length + 24) -and (Test-OnScreen $node)) {
            $hits.Add($node) | Out-Null
        }
        $child = $walker.GetFirstChild($node)
        while ($child) {
            $stack.Push(@($child, $depth + 1))
            $child = $walker.GetNextSibling($child)
        }
    }
    return $hits
}

function Find-MapCard($Root, [string]$Name) {
    $texts = @(Find-TextContains $Root $Name)
    if ($texts.Count -eq 0) { return $null }
    $texts = $texts | Sort-Object { $_.Current.Name.Length }
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $candidates = New-Object System.Collections.Generic.List[object]
    foreach ($text in $texts) {
        $textRect = $text.Current.BoundingRectangle
        $node = $text
        for ($i = 0; $i -lt 12 -and $node; $i++) {
            if ($node.Current.ControlType.ProgrammaticName -eq "ControlType.Window") { break }
            $rowRect = $node.Current.BoundingRectangle
            if ($rowRect.Width -ge 160 -and $rowRect.Width -le 1800 -and $rowRect.Height -ge 50 -and $rowRect.Height -le 700) {
                $more = Find-MoreButton $node
                if ($more) {
                    $moreRect = $more.Current.BoundingRectangle
                    $textInside = ($textRect.X -ge ($rowRect.X - 8) -and $textRect.Right -le ($rowRect.Right + 8) -and $textRect.Y -ge ($rowRect.Y - 8) -and $textRect.Bottom -le ($rowRect.Bottom + 8))
                    $moreInside = ($moreRect.X -ge ($rowRect.X - 8) -and $moreRect.Right -le ($rowRect.Right + 8) -and $moreRect.Y -ge ($rowRect.Y - 8) -and $moreRect.Bottom -le ($rowRect.Bottom + 8))
                    if ($textInside -and $moreInside) {
                        $candidates.Add([pscustomobject]@{ Element = $node; Area = ($rowRect.Width * $rowRect.Height); TextLength = $text.Current.Name.Length }) | Out-Null
                    }
                }
            }
            $node = $walker.GetParent($node)
        }
    }
    if ($candidates.Count -eq 0) { return $null }
    return ($candidates | Sort-Object Area, TextLength | Select-Object -First 1).Element
}
function Find-MoreButton($Card) {
    $named = Find-FirstExact $Card "更多"
    if ($named) {
        try {
            $rect = $named.Current.BoundingRectangle
            if ($named.Current.ControlType.ProgrammaticName -eq "ControlType.Button" -and (Test-OnScreen $named) -and $rect.Width -ge 16 -and $rect.Width -le 180 -and $rect.Height -ge 16 -and $rect.Height -le 80) { return $named }
        } catch {}
    }
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $found = New-Object System.Collections.Generic.List[object]
    $stack = New-Object System.Collections.Stack
    $stack.Push($Card)
    $seen = 0
    while ($stack.Count -gt 0 -and $seen -lt 400) {
        $node = $stack.Pop()
        $seen++
        try {
            if ($node.Current.ControlType.ProgrammaticName -eq "ControlType.Button" -and (Test-OnScreen $node)) {
                $r = $node.Current.BoundingRectangle
                if ($r.Width -ge 16 -and $r.Width -le 180 -and $r.Height -ge 16 -and $r.Height -le 80) { $found.Add($node) | Out-Null }
            }
        } catch {}
        $child = $walker.GetFirstChild($node)
        while ($child) { $stack.Push($child); $child = $walker.GetNextSibling($child) }
    }
    if ($found.Count -lt 3) { return $null }
    return $found | Sort-Object { $_.Current.BoundingRectangle.X } -Descending | Select-Object -First 1
}
function Find-MenuItem([string]$Name) {
    foreach ($w in @(Get-TopWindows | Where-Object { $_.ProcessName -eq "MCStudio" })) {
        $el = Get-Ui $w.Hwnd
        $menu = @(Find-AllExact $el $Name "MenuItem")
        if ($menu.Count -gt 0) { return @{ Element = $menu[0]; Hwnd = $w.Hwnd } }
    }
    foreach ($w in @(Get-TopWindows | Where-Object { $_.ProcessName -eq "MCStudio" })) {
        $isPopup = $w.ClassName -eq "Popup" -or ($w.Title -eq "" -and $w.Width -lt 480 -and $w.Height -lt 640)
        if (-not $isPopup) { continue }
        $el = Get-Ui $w.Hwnd
        $hits = @(Find-AllExact $el $Name)
        if ($hits.Count -gt 0) { return @{ Element = $hits[0]; Hwnd = $w.Hwnd } }
    }
    return $null
}

function Get-MenuLabels {
    $labels = New-Object System.Collections.Generic.List[string]
    foreach ($w in @(Get-TopWindows | Where-Object { $_.ProcessName -eq "MCStudio" })) {
        $el = Get-Ui $w.Hwnd
        $cond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::MenuItem)
        $items = $el.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
        foreach ($item in $items) {
            if (Test-OnScreen $item) {
                $n = [string]$item.Current.Name
                if ($n) { $labels.Add($n) | Out-Null }
            }
        }
    }
    return @($labels | Select-Object -Unique)
}

function Find-LauncherNameSearchEdit($Root) {
    $edits = @(Find-Edits $Root)
    $fallback = $null
    $fallbackWidth = 0
    foreach ($edit in $edits) {
        $label = ""
        try {
            $label = ([string]$edit.Current.Name + " " + [string]$edit.Current.HelpText + " " + [string]$edit.Current.AutomationId).Trim()
            if ($label.Contains("按作品名称搜索")) { return $edit }
            if ($label.Contains("搜索") -and $edit.Current.BoundingRectangle.Width -gt $fallbackWidth) {
                $fallback = $edit
                $fallbackWidth = $edit.Current.BoundingRectangle.Width
            }
        } catch {}
    }
    if ($fallback) { return $fallback }
    if ($edits.Count -eq 1) { return $edits[0] }
    return $null
}

function Get-DevelopmentDynamicsProjectNames($Root) {
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $stack = New-Object System.Collections.Stack
    $stack.Push($Root)
    $items = New-Object System.Collections.Generic.List[object]
    $seen = 0
    $skip = @("开发动态", "导入", "新建", "编辑", "开发测试", "更多", "基岩版地图", "基岩版附加包", "修改", "地图", "附加包")
    while ($stack.Count -gt 0 -and $seen -lt 5000) {
        $node = $stack.Pop()
        $seen++
        try {
            $name = ([string]$node.Current.Name).Trim()
            $type = $node.Current.ControlType.ProgrammaticName
            $r = $node.Current.BoundingRectangle
            if ($name -and $type -eq "ControlType.Text" -and (Test-OnScreen $node) -and $r.Width -ge 70 -and $r.Height -ge 14 -and $r.Height -le 60 -and $name.Length -ge 3 -and $name -notin $skip -and $name -notmatch '分钟前|小时前|天前|修改|^\d{4}[-/]\d{1,2}') {
                $items.Add([pscustomobject]@{ Name = $name; Y = $r.Y }) | Out-Null
            }
        } catch {}
        $child = $walker.GetFirstChild($node)
        while ($child) { $stack.Push($child); $child = $walker.GetNextSibling($child) }
    }
    $unique = @($items | Sort-Object Y | Group-Object Name | ForEach-Object { $_.Group | Select-Object -First 1 })
    return @($unique | Sort-Object Y | Select-Object -First 3 | ForEach-Object { $_.Name })
}

function Search-LauncherProject($Main, [string]$MapTitle, [string]$ProjectType) {
    Show-Target $Main.Hwnd
    Set-Step 34 ("在启动器首页开发动态中定位所选项目：{0}" -f $MapTitle)
    $card = Wait-Until 5 {
        $root = Get-Ui $Main.Hwnd
        if (-not $root) { return $null }
        return (Find-MapCard $root $MapTitle)
    } 120
    if (-not $card) { throw "启动器首页开发动态里没有找到所选项目「$MapTitle」，已停止，没有选择其他项目。" }
    Log ("已在启动器首页开发动态中找到「{0}」" -f $MapTitle)
    return $card
}function Open-MoreMenu($Main, [string]$MapTitle, [string]$ProjectType = "map") {
    $card = $null
    if ($DryRun) {
        $root = Get-Ui $Main.Hwnd
        $card = Find-MapCard $root $MapTitle
        if (-not $card) { Log ("正式运行时会在启动器首页开发动态中匹配「{0}」" -f $MapTitle) }
    } else {
        $card = Search-LauncherProject $Main $MapTitle $ProjectType
    }
    if (-not $card) { throw "在启动器首页开发动态里找不到「$MapTitle」。" }
    $cardTitle = @(Find-TextContains $card $MapTitle)
    if ($cardTitle.Count -eq 0) { throw "锁定到的卡片中没有作品名「$MapTitle」，已停止避免打开其他作品。" }
    $more = Find-MoreButton $card
    if (-not $more) { throw "资源「$MapTitle」卡片内没有找到可确认归属的更多按钮。" }
    $cardRect = $card.Current.BoundingRectangle
    $moreRect = $more.Current.BoundingRectangle
    Log ("已锁定目标卡片「{0}」({1:N0},{2:N0},{3:N0}x{4:N0})，调用其更多按钮 X={5:N0},Y={6:N0}" -f $MapTitle,$cardRect.X,$cardRect.Y,$cardRect.Width,$cardRect.Height,$moreRect.X,$moreRect.Y)
    $script:CachedMore = $more
    if (-not (Invoke-LauncherElement $more "更多" -KeepFocus)) {
        throw "「更多」按钮无法直接调用"
    }
    return $card
}
function Click-MenuDownRight([string]$Name, [switch]$KeepFocus) {
    $item = Find-MenuItem $Name
    if (-not $item) { return $false }
    if ($KeepFocus) { return (Invoke-LauncherElement $item.Element $Name -KeepFocus) }
    return (Invoke-LauncherElement $item.Element $Name)
}

function Get-EditorMainWindow {
    $wins = @(Get-TopWindows | Where-Object {
        $_.ProcessName -eq "MC_Editor" -and $_.Width -gt 500 -and $_.Height -gt 300
    })
    return $wins | Sort-Object { $_.Width * $_.Height } -Descending | Select-Object -First 1
}

function Find-SaveButtonPoint {
    # 这个对话框是编辑器自己画的，按钮没有系统名称。蓝色「保存」的颜色是 55,136,255。
    $win = Get-EditorMainWindow
    if (-not $win) { return $null }
    Show-Target $win.Hwnd
    [void][McWin32]::SetWindowPos($win.Hwnd, [IntPtr](-1), 0, 0, 0, 0, 3)
    Start-Sleep -Milliseconds 180
    $rect = New-Object McWin32+RECT
    [void][McWin32]::GetWindowRect($win.Hwnd, [ref]$rect)
    $left = $rect.Left
    $top = $rect.Top
    $w = $rect.Right - $rect.Left
    $h = $rect.Bottom - $rect.Top
    $point = $null
    if ($w -gt 200 -and $h -gt 200) {
        $bmp = New-Object System.Drawing.Bitmap $w, $h
        $graphics = [System.Drawing.Graphics]::FromImage($bmp)
        $graphics.CopyFromScreen($left, $top, 0, 0, $bmp.Size)
        $graphics.Dispose()
        $bits = $bmp.LockBits(
            (New-Object System.Drawing.Rectangle 0, 0, $w, $h),
            [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $stride = $bits.Stride
        $raw = New-Object byte[] ($stride * $h)
        [System.Runtime.InteropServices.Marshal]::Copy($bits.Scan0, $raw, 0, $raw.Length)
        $bmp.UnlockBits($bits)
        $bmp.Dispose()
        $minX = $w; $minY = $h; $maxX = 0; $maxY = 0; $count = 0
        for ($y = 160; $y -lt $h; $y += 2) {
            $row = $y * $stride
            for ($x = 0; $x -lt $w; $x += 2) {
                $i = $row + ($x * 4)
                $bb = $raw[$i]
                $gg = $raw[$i + 1]
                $rr = $raw[$i + 2]
                if ([Math]::Abs($rr - 55) -le 18 -and [Math]::Abs($gg - 136) -le 18 -and $bb -ge 245) {
                    $count++
                    if ($x -lt $minX) { $minX = $x }
                    if ($y -lt $minY) { $minY = $y }
                    if ($x -gt $maxX) { $maxX = $x }
                    if ($y -gt $maxY) { $maxY = $y }
                }
            }
        }
        $boxW = $maxX - $minX
        $boxH = $maxY - $minY
        if ($count -gt 15 -and $boxW -ge 50 -and $boxW -le 260 -and $boxH -ge 16 -and $boxH -le 80) {
            $point = @{
                X = [int]($left + (($minX + $maxX) / 2))
                Y = [int]($top + (($minY + $maxY) / 2))
            }
        }
    }
    [void][McWin32]::SetWindowPos($win.Hwnd, [IntPtr](-2), 0, 0, 0, 0, 3)
    return $point
}

function Click-Screen([int]$X, [int]$Y, [string]$Label) {
    Log ("{0} [{1}] 鼠标 @ {2},{3}" -f $(if ($DryRun) { "将点击" } else { "点击" }), $Label, $X, $Y)
    if ($DryRun) { return }
    Click-MouseAt $X $Y 220
}

function Close-MapEditor {
    $main = Get-EditorMainWindow
    if (-not $main) {
        Set-Step 18 "编辑器没有打开，跳过保存并退出"
        return
    }
    Set-Step 12 ("正在保存并退出编辑器：{0}" -f $main.Title)
    if ($DryRun) {
        Log "正式运行时会关闭编辑器，并点蓝色的「保存」"
        return
    }
    Show-Target $main.Hwnd
    [void][McWin32]::PostMessage($main.Hwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    Log "已让编辑器关闭，等待「是否保存并退出」"
    $clicked = $false
    $deadline = (Get-Date).AddSeconds(12)
    while ((Get-Date) -lt $deadline) {
        if (-not (Get-Process -Name "MC_Editor" -ErrorAction SilentlyContinue)) {
            Log "编辑器已直接退出"
            return
        }
        $point = Find-SaveButtonPoint
        if ($point) {
            Click-Screen $point.X $point.Y "保存"
            $clicked = $true
            break
        }
        Start-Sleep -Milliseconds 350
    }
    if (-not $clicked) {
        Log "没有看到蓝色的「保存」按钮。若对话框还在，脚本会在退出前继续找"
    }
    Log "等待编辑器退出（大地图保存可能要几分钟）"
    $script:SaveAttempts = 6
    $script:NextSaveScan = [datetime]::MinValue
    $gone = Wait-Until 600 {
        if (-not (Get-Process -Name "MC_Editor" -ErrorAction SilentlyContinue)) { return $true }
        if ($script:SaveAttempts -gt 0 -and (Get-Date) -gt $script:NextSaveScan) {
            $script:SaveAttempts--
            $script:NextSaveScan = (Get-Date).AddSeconds(3)
            $point = Find-SaveButtonPoint
            if ($point) { Click-Screen $point.X $point.Y "保存" }
        }
        return $null
    }
    if (-not $gone) { throw "编辑器 10 分钟内没有退出。请看编辑器上是否还有没点掉的对话框。" }
    Set-Step 22 "编辑器已退出"
    Start-Sleep -Seconds 2
}

function Invoke-UpgradeAndPublish([string]$MapTitle) {
    $main = Get-LauncherMain
    if (-not $main) { throw "没有找到我的世界开发者启动器窗口" }
    Log ("启动器窗口：{0}  {1}x{2}" -f $main.Title, $main.Width, $main.Height)
    Ensure-LauncherBackground $main.Hwnd
    Set-Step 30 "启动器留在后台，直接调用控件"
    # 配置窗口可能还属于上一个项目，不能按“有配置窗口”就直接复用。
    # 先关闭独立的旧配置窗口，再从当前项目卡片重新打开；若配置嵌在主窗口里则安全停止。
    $cfg = Get-ConfigElement
    $closed = $false
    if ($cfg) {
        if ([IntPtr]$cfg.Hwnd -eq [IntPtr]$main.Hwnd) {
            throw "检测到主窗口内已有配置页，无法确认它属于「$MapTitle」；请先关闭该配置页后重试，已停止以避免配置错作品。"
        }
        [void][McWin32]::PostMessage([IntPtr]$cfg.Hwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
        $closed = [bool](Wait-Until 5 { -not (Get-ConfigElement) } 100)
        if (-not $closed) { throw "旧的配置窗口无法关闭，无法确保配置对应「$MapTitle」；已停止。" }
        Set-Step 33 ("已关闭旧配置窗口，重新定位当前项目：{0}" -f $MapTitle)
    }
    Set-Step 36 "从当前项目卡片打开配置"
    Set-FocusGuardPause $true
    Open-MoreMenu $main $MapTitle $ProjectType | Out-Null
    $item = Wait-Until 3 { Find-MenuItem "配置" } 30
    $opened = $false
    if ($item) { $opened = [bool](Click-MenuDownRight "配置") }
    Set-FocusGuardPause $false
    Restore-BackgroundFocus
    if (-not $item) {
        $labels = @(Get-MenuLabels)
        throw ("更多菜单里没有「配置」。当前菜单项：" + ($(if ($labels.Count) { $labels -join "、" } else { "（没有读到菜单）" })))
    }
    if (-not $opened) {
        throw "菜单已经打开，但「配置」无法直接调用。"
    }
    $cfg = Wait-Until 10 { Get-ConfigElement }
    if (-not $cfg) { throw "配置窗口没有出现" }
    Set-Step 46 "调用全部升级"
    $upgrade = Find-FirstExact $cfg.Element "全部升级" "Button"
    if (-not $upgrade) { throw "配置窗口里没有「全部升级」按钮" }
    if (-not (Invoke-LauncherElement $upgrade "全部升级")) {
        throw "「全部升级」无法直接调用"
    }
    if (-not $DryRun) { Start-Sleep -Milliseconds 250 }
    $published = $false
    $cfg = Get-ConfigElement
    if ($cfg) {
        $publishInside = Find-FirstExact $cfg.Element "发布地图"
        if ($publishInside) {
            if (-not (Invoke-LauncherElement $publishInside "发布地图")) {
                throw "「发布地图」无法直接调用"
            }
            $published = $true
        } else {
            Set-Step 54 "确认升级"
            $ok = Find-FirstExact $cfg.Element "确定" "Button"
            if ($ok -and -not (Invoke-LauncherElement $ok "确定")) {
                throw "「确定」无法直接调用"
            }
            Start-Sleep -Milliseconds 100
            $again = Wait-Until 10 {
                foreach ($w in @(Get-TopWindows | Where-Object { $_.ProcessName -eq "MCStudio" -and $_.Width -gt 160 -and $_.Height -gt 80 })) {
                    $el = Get-Ui $w.Hwnd
                    $next = Find-FirstExact $el "确定" "Button"
                    if ($next) { return @{ Element = $next; Hwnd = $w.Hwnd } }
                }
                return $null
            } 100
            if ($again -and -not (Invoke-LauncherElement $again.Element "再次确定")) {
                throw "第二次「确定」无法直接调用"
            }
        }
    }
    if (-not $published) {
        if (-not $main -or -not [McWin32]::IsWindow($main.Hwnd)) { $main = Get-LauncherMain }
        if (-not $main) { throw "没有找到我的世界开发者启动器窗口" }
        Set-Step 62 "回到地图卡片，调用发布"
        Set-FocusGuardPause $true
        Open-MoreMenu $main $MapTitle $ProjectType | Out-Null
        $item = Wait-Until 5 {
            $named = Find-MenuItem "发布地图"
            if ($named) { return $named }
            return (Find-MenuItem "发布")
        } 30
        if (-not $item) {
            $labels = @(Get-MenuLabels)
            Set-FocusGuardPause $false
            throw ("更多菜单里没有「发布地图」。当前菜单项：" + ($(if ($labels.Count) { $labels -join "、" } else { "（没有读到菜单）" })))
        }
        $publishName = "发布"
        if (-not (Find-MenuItem "发布")) { $publishName = "发布地图" }
        if (-not (Click-MenuDownRight $publishName -KeepFocus)) {
            Set-FocusGuardPause $false
            throw "菜单已经打开，但「发布」无法直接调用。"
        }
        $workDlg = Confirm-PublishWork $MapTitle $PublishKeyword
        if (-not $workDlg) { throw "点击发布后没有出现「发布作品」窗口" }
    }
    Restore-BackgroundFocus
}

function Get-AddressValue($Root) {
    foreach ($name in @("地址和搜索栏", "Address and search bar", "在此输入网址")) {
        $edits = @(Find-AllExact $Root $name "Edit")
        if ($edits.Count -eq 0) { continue }
        try {
            $pattern = $edits[0].GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
            return [string]$pattern.Current.Value
        } catch {}
    }
    return ""
}

function Get-BrowserLoadState([IntPtr]$Hwnd) {
    $root = Get-Ui $Hwnd
    if (-not $root) { return "unknown" }
    $top = $root.Current.BoundingRectangle.Y
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Button)
    $buttons = $null
    try { $buttons = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond) } catch { return "unknown" }
    $loading = $false
    $idle = $false
    foreach ($el in $buttons) {
        $name = ""
        $cls = ""
        try {
            $name = ([string]$el.Current.Name).Trim()
            $cls = [string]$el.Current.ClassName
            $y = $el.Current.BoundingRectangle.Y
        } catch { continue }
        if ($y -gt ($top + 180)) { continue }
        if ($cls -match "StopButton" -or $name -match "^(停止|停止加载|停止加载此页面|Stop loading)") { $loading = $true }
        if ($cls -match "ReloadButton" -or $name -match "重新加载|^刷新|Reload") { $idle = $true }
    }
    if ($loading) { return "loading" }
    if ($idle) { return "idle" }
    return "unknown"
}

function Test-PageContentBusy([IntPtr]$Hwnd) {
    if ((Get-BrowserLoadState $Hwnd) -eq "loading") { return $true }
    $root = Get-Ui $Hwnd
    if (-not $root) { return $true }
    $busyNames = @("加载中", "正在加载", "上传中", "解析中", "请稍候", "加载中...")
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $stack = New-Object System.Collections.Stack
    $stack.Push($root)
    $seen = 0
    while ($stack.Count -gt 0 -and $seen -lt 2500) {
        $node = $stack.Pop()
        $seen++
        $name = ""
        $cls = ""
        try {
            $name = ([string]$node.Current.Name).Trim()
            $cls = [string]$node.Current.ClassName
        } catch { continue }
        $classBusy = $cls -match "el-loading|loading-mask|is-loading"
        $nameBusy = $busyNames -contains $name
        if (($classBusy -or $nameBusy) -and (Test-OnScreen $node)) { return $true }
        $child = $walker.GetFirstChild($node)
        while ($child) {
            $stack.Push($child)
            $child = $walker.GetNextSibling($child)
        }
    }
    return $false
}

function Get-ScrollSignature([IntPtr]$Hwnd) {
    $root = Get-Ui $Hwnd
    if (-not $root) { return "" }
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $stack = New-Object System.Collections.Stack
    $stack.Push($root)
    $seen = 0
    $best = ""
    $bestHeight = 0
    while ($stack.Count -gt 0 -and $seen -lt 1500) {
        $node = $stack.Pop()
        $seen++
        try {
            foreach ($pattern in $node.GetSupportedPatterns()) {
                if ($pattern.Id -eq [System.Windows.Automation.ScrollPattern]::Pattern.Id) {
                    $scroll = $node.GetCurrentPattern($pattern)
                    if ($scroll.Current.VerticallyScrollable) {
                        $h = $node.Current.BoundingRectangle.Height
                        if ($h -gt $bestHeight) {
                            $bestHeight = $h
                            $pct = [int]$scroll.Current.VerticalScrollPercent
                            $view = [int]$scroll.Current.VerticalViewSize
                            $best = "{0}|{1}|{2}" -f $pct, $view, [int]$h
                        }
                    }
                }
            }
        } catch {}
        $child = $walker.GetFirstChild($node)
        while ($child) {
            $stack.Push($child)
            $child = $walker.GetNextSibling($child)
        }
    }
    return $best
}

function Find-PublishPage {
    $hosts = @(Get-TopWindows | Where-Object {
        $_.Width -gt 500 -and $_.Height -gt 300 -and (
            $_.ProcessName -match "^(msedge|chrome|firefox)$" -or
            $_.Title -match "开发者内容管理" -or
            ($_.ProcessName -eq "MCStudio" -and $_.ClassName -match "Chrome_WidgetWin")
        )
    })
    foreach ($w in $hosts) {
        if ([McWin32]::IsIconic($w.Hwnd)) { Ensure-LauncherBackground $w.Hwnd }
        $el = Get-Ui $w.Hwnd
        if (-not $el) { continue }
        $self = Find-FirstExact $el "发起自测"
        $save = Find-FirstExact $el "保存" "Button"
        $url = Get-AddressValue $el
        $urlHit = $url -match "mcdev\.webapp\.163\.com" -and $url -match "/pe/edit/"
        if ($self -or $urlHit) {
            return [pscustomobject]@{ Window = $w; Root = $el; Save = $save; SelfTest = $self; Url = $url }
        }
    }
    return $null
}

function Get-OpenPublishUrls {
    $urls = New-Object System.Collections.Generic.List[string]
    foreach ($w in @(Get-TopWindows | Where-Object { $_.ProcessName -match "^(msedge|chrome|firefox)$" -and $_.Width -gt 400 })) {
        $el = Get-Ui $w.Hwnd
        if (-not $el) { continue }
        $url = Get-AddressValue $el
        if ($url) { $urls.Add($url) | Out-Null }
    }
    return @($urls)
}

function Find-PageContains([IntPtr]$Hwnd, [string]$Label) {
    $root = Get-Ui $Hwnd
    if (-not $root) { return $null }
    $hit = Find-FirstContains $root $Label
    if ($hit -and (Test-OnScreen $hit)) { return $hit }
    return $null
}

function Get-ShownResourceName([IntPtr]$Hwnd, [string]$Fallback) {
    $root = Get-Ui $Hwnd
    if (-not $root) { return $Fallback }
    $labels = @(Find-AnyByName $root "资源名称" "Text")
    if ($labels.Count -eq 0) { $labels = @(Find-AnyByName $root "资源名称") }
    if ($labels.Count -eq 0) { return $Fallback }
    $label = $labels[0]
    $lr = $label.Current.BoundingRectangle
    $midY = $lr.Y + ($lr.Height / 2)
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $stack = New-Object System.Collections.Stack
    $stack.Push($root)
    $seen = 0
    $best = ""
    $bestDx = 100000
    while ($stack.Count -gt 0 -and $seen -lt 2500) {
        $node = $stack.Pop()
        $seen++
        $name = ""
        try { $name = ([string]$node.Current.Name).Trim() } catch { continue }
        $rr = $node.Current.BoundingRectangle
        if ($name -and $name -ne "资源名称" -and $name.Length -ge 2 -and $name.Length -le 80 -and (Test-OnScreen $node)) {
            $cy = $rr.Y + ($rr.Height / 2)
            $dx = $rr.X - ($lr.X + $lr.Width)
            if ($dx -ge -8 -and $dx -lt $bestDx -and [Math]::Abs($cy - $midY) -lt 26 -and $rr.Width -gt 16) {
                $best = $name
                $bestDx = $dx
            }
        }
        $child = $walker.GetFirstChild($node)
        while ($child) {
            $stack.Push($child)
            $child = $walker.GetNextSibling($child)
        }
    }
    if ($best) { return $best }
    return $Fallback
}

function Find-ListRow([IntPtr]$Hwnd, [string]$Name, [string]$ItemId) {
    $root = Get-Ui $Hwnd
    if (-not $root) { return $null }
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::DataItem)
    $items = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $best = $null
    $bestText = ""
    $bestScore = 100000
    foreach ($el in $items) {
        $parts = New-Object System.Collections.Generic.List[string]
        $rootName = ""
        $cls = ""
        try {
            $rootName = ([string]$el.Current.Name).Trim()
            $cls = [string]$el.Current.ClassName
        } catch { continue }
        if ($rootName) { $parts.Add($rootName) | Out-Null }
        # The webpage renders the resource name and ID as separate descendants in the same first-column cell.
        # UI Automation may expose those as separate Text nodes instead of one DataItem.Name.
        $stack = New-Object System.Collections.Stack
        $child = $walker.GetFirstChild($el)
        while ($child) {
            $stack.Push(@($child, 0))
            $child = $walker.GetNextSibling($child)
        }
        $seen = 0
        while ($stack.Count -gt 0 -and $seen -lt 300) {
            $pair = $stack.Pop()
            $node = $pair[0]
            $depth = [int]$pair[1]
            $seen++
            if ($depth -gt 12) { continue }
            try {
                $nodeName = ([string]$node.Current.Name).Trim()
                if ($nodeName -and -not $parts.Contains($nodeName)) { $parts.Add($nodeName) | Out-Null }
            } catch {}
            $child = $walker.GetFirstChild($node)
            while ($child) {
                $stack.Push(@($child, ($depth + 1)))
                $child = $walker.GetNextSibling($child)
            }
        }
        $text = ($parts -join " ").Trim()
        if (-not $text) { continue }
        $hitName = $Name -and $text.Contains($Name)
        $hitId = $ItemId -and $text.Contains($ItemId)
        if (-not $hitName -and -not $hitId) { continue }
        $rr = $el.Current.BoundingRectangle
        $score = 50000
        if ($rr.Height -gt 8 -and $rr.Width -gt 8 -and -not [double]::IsInfinity($rr.Height)) { $score = $rr.Y }
        if ($hitName -and $hitId) { $score -= 30000 }
        elseif ($hitId) { $score -= 20000 }
        elseif ($hitName) { $score -= 10000 }
        if ($score -lt $bestScore) {
            $best = $el
            $bestText = $text
            $bestScore = $score
        }
    }
    if (-not $best) { return $null }
    return [pscustomobject]@{ Element = $best; Text = $bestText }
}
function Find-RowDots([IntPtr]$Hwnd, $Row) {
    $rr = $Row.Current.BoundingRectangle
    $mid = $rr.Y + ($rr.Height / 2)
    $root = Get-Ui $Hwnd
    if (-not $root) { return $null }
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Button)
    $buttons = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
    $best = $null
    $bestX = -1
    foreach ($el in $buttons) {
        if (-not (Test-OnScreen $el)) { continue }
        $br = $el.Current.BoundingRectangle
        $by = $br.Y + ($br.Height / 2)
        if ([Math]::Abs($by - $mid) -gt 22) { continue }
        if (($br.X + $br.Width) -lt $rr.X) { continue }
        $name = ""
        try { $name = ([string]$el.Current.Name).Trim() } catch {}
        $isDots = ($name -eq "..." -or $name -eq "…" -or $name -eq "···" -or $name -eq "更多")
        if (-not $isDots -and $br.Width -gt 64) { continue }
        if ($br.X -gt $bestX) { $best = $el; $bestX = $br.X }
    }
    return $best
}

function Find-SelfTestButtonAnywhere([IntPtr]$Hwnd, [string]$ModeLabel = "免机审自测") {
    $hit = Find-SelfTestButton $Hwnd $ModeLabel
    if ($hit) { return $hit }
    foreach ($w in @(Get-TopWindows | Where-Object { $_.ProcessName -eq "msedge" })) {
        if ([int64]$w.Hwnd -eq [int64]$Hwnd) { continue }
        $hit = Find-SelfTestButton $w.Hwnd $ModeLabel
        if ($hit) { return $hit }
    }
    return $null
}

function Get-RowStatusText([IntPtr]$Hwnd, $Row) {
    if (-not $Row) { return "" }
    $rr = $Row.Current.BoundingRectangle
    $mid = $rr.Y + ($rr.Height / 2)
    $root = Get-Ui $Hwnd
    if (-not $root) { return "" }
    $known = @(
        "已发布自测环境", "待提交审核", "系统处理中", "系统校验中", "校验未通过",
        "审核中", "审核未通过", "过审待上架", "已上架", "已下架", "定时上架中"
    )
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $stack = New-Object System.Collections.Stack
    $stack.Push($root)
    $seen = 0
    while ($stack.Count -gt 0 -and $seen -lt 4000) {
        $node = $stack.Pop()
        $seen++
        $name = ""
        try { $name = ([string]$node.Current.Name).Trim() } catch { continue }
        if ($known -contains $name) {
            $br = $node.Current.BoundingRectangle
            $cy = $br.Y + ($br.Height / 2)
            if ([Math]::Abs($cy - $mid) -le 36 -and $br.X -gt ($rr.X - 20)) { return $name }
        }
        $child = $walker.GetFirstChild($node)
        while ($child) {
            $stack.Push($child)
            $child = $walker.GetNextSibling($child)
        }
    }
    return ""
}

function Find-NamedPageButton([IntPtr]$Hwnd, [string]$Label) {
    $hit = Find-PageButton $Hwnd $Label
    if ($hit) { return $hit }
    foreach ($w in @(Get-TopWindows | Where-Object { $_.ProcessName -eq "msedge" })) {
        if ([int64]$w.Hwnd -eq [int64]$Hwnd) { continue }
        $hit = Find-PageButton $w.Hwnd $Label
        if ($hit) { return $hit }
    }
    return $null
}

function Open-RowMenu([IntPtr]$Hwnd, $MoreButton, [string]$ExpectedLabel = '') {
    Show-Target $Hwnd
    $br = $MoreButton.Current.BoundingRectangle
    if ($br.Width -gt 2 -and $br.Height -gt 2) {
        $x = [int][Math]::Round($br.X + ($br.Width / 2))
        $y = [int][Math]::Round($br.Y + ($br.Height / 2))
        Log ("前台移动鼠标到更多按钮 {0},{1}" -f $x, $y)
        Move-MouseSmooth $x $y
        $menuSelfTestLabel = if ($ExpectedLabel -in @("免机审自测", "机审自测")) { $ExpectedLabel } else { "免机审自测" }
        $hovered = Wait-Until 2 {
            if ($ExpectedLabel) {
                $hit = Find-NamedPageButton $Hwnd $ExpectedLabel
                if ($hit) { return $hit }
            }
            $hit = Find-NamedPageButton $Hwnd '取消自测'
            if ($hit) { return $hit }
            return (Find-SelfTestButtonAnywhere $Hwnd $menuSelfTestLabel)
        }
        if ($hovered) { return }
    }
    if (Invoke-PageButton $MoreButton '更多' -InvokeOnly -KeepFocus) {
        if ($ExpectedLabel) {
            $opened = Wait-Until 2 { return (Find-NamedPageButton $Hwnd $ExpectedLabel) }
            if ($opened) { return }
        } else {
            Start-Sleep -Milliseconds 120
            return
        }
    }
    if ($br.Width -gt 2 -and $br.Height -gt 2) {
        Move-MouseSmooth ([int][Math]::Round($br.X + ($br.Width / 2))) ([int][Math]::Round($br.Y + ($br.Height / 2)))
        Start-Sleep -Milliseconds 350
    }
}

function Submit-ListSearch([IntPtr]$Hwnd, [string]$Query) {
    Show-Target $Hwnd
    $searchEdit = Wait-Until 6 {
        $root = Get-Ui $Hwnd
        if (-not $root) { return $null }
        $edits = @(Find-Edits $root)
        foreach ($edit in $edits) {
            $label = ""
            try { $label = ([string]$edit.Current.Name + " " + [string]$edit.Current.HelpText).Trim() } catch {}
            if ($label.Contains("输入模组ID、名称")) { return $edit }
        }
        return $null
    } 200
    if (-not $searchEdit) { throw "等待 6 秒仍没有找到占位文字为「输入模组ID、名称」的搜索框。" }
    if (-not (Set-EditText $searchEdit $Query)) {
        try { $searchEdit.SetFocus() } catch {}
        [System.Windows.Forms.SendKeys]::SendWait("^a")
        [System.Windows.Forms.SendKeys]::SendWait($Query)
    }
    try { $searchEdit.SetFocus() } catch {}
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
    Log "已在作品列表搜索「$Query」并回车"
}
function Invoke-SelfTestOnPage($Page, [string]$MapTitle, [string]$ItemId) {
    $resourceQuery = [string]$PublishKeyword
    if ([string]::IsNullOrWhiteSpace($resourceQuery)) { $resourceQuery = $MapTitle }
    $selfTestLabel = if ($SelfTestMode -eq "review") { "机审自测" } else { "免机审自测" }
    $confirmNeedles = if ($SelfTestMode -eq "review") { @("机审自测", "提交审核") } else { @("提交到自测环境") }
    Set-Step 90 "返回列表，由页面自己提交$selfTestLabel"
    Set-FocusGuardPause $true
    Show-Target $Page.Window.Hwnd
    $back = Find-DomButton $Page.Window.Hwnd "返回" "MC_Style_Grey_2"
    if (-not $back) { throw "没有找到灰色「返回」按钮" }
    if (-not (Invoke-PageButton $back "返回" -InvokeOnly -KeepFocus)) { throw "「返回」无法直接调用" }
    $row = $null
    if ($BoundItemId) {
        $row = Find-ListRow $Page.Window.Hwnd "" $BoundItemId
        if ($row -and -not $row.Text.Contains($resourceQuery)) {
            throw "46 ID $BoundItemId 已显示，但作品名不匹配当前项目「$resourceQuery」：$($row.Text)"
        }
        if (-not $row) {
            Log "当前列表没看到绑定的 46 ID，使用名称/ID 搜索框查询"
            Submit-ListSearch $Page.Window.Hwnd $BoundItemId
            Log "等待绑定 ID 搜索结果"
            $row = Wait-Until 8 {
                return (Find-ListRow $Page.Window.Hwnd "" $BoundItemId)
            } 150
            if (-not $row) { throw "按 46 ID $BoundItemId 搜索后，列表仍没有这项作品；已停止。" }
            if (-not $row.Text.Contains($resourceQuery)) {
                throw "搜索到 46 ID $BoundItemId，但作品名不匹配当前项目「$resourceQuery」：$($row.Text)"
            }
        }
    } else {
        $row = Wait-Until 1 {
            return (Find-ListRow $Page.Window.Hwnd $resourceQuery "")
        } 100
        if (-not $row) {
            if ($ItemId) {
                Log "当前列表没找到作品名「$resourceQuery」，改用编辑页 ID $ItemId 搜索"
                Submit-ListSearch $Page.Window.Hwnd $ItemId
                $row = Wait-Until 8 {
                    return (Find-ListRow $Page.Window.Hwnd "" $ItemId)
                } 150
                if (-not $row) { throw "按编辑页 ID $ItemId 搜索后仍没有找到资源；已停止。" }
                if (-not $row.Text.Contains($resourceQuery)) {
                    throw "按编辑页 ID $ItemId 找到资源，但作品名不匹配「$resourceQuery」：$($row.Text)"
                }
            } else {
                Log "当前列表没找到作品名「$resourceQuery」，改用左上角名称/ID 搜索框查询"
                Submit-ListSearch $Page.Window.Hwnd $resourceQuery
                $row = Wait-Until 8 {
                    return (Find-ListRow $Page.Window.Hwnd $resourceQuery "")
                } 150
                if (-not $row) { throw "按作品名搜索后，列表里仍没有找到「$resourceQuery」；已停止。" }
            }
        }
    }
    $status = Get-RowStatusText $Page.Window.Hwnd $row.Element
    Log ("找到资源 [{0}]，状态：{1}" -f $row.Text, $(if ($status) { $status } else { "未读到" }))
    $more = Find-RowMoreButton $Page.Window.Hwnd $row.Element
    if (-not $more) { throw "没有找到这一行的 ... 按钮。" }
    $needCancel = ($status -eq "已发布自测环境")
    if (-not $status) {
        Log "前台移动鼠标到更多按钮，检查自测状态"
        Open-RowMenu $Page.Window.Hwnd $more "取消自测"
        if (Find-NamedPageButton $Page.Window.Hwnd "取消自测") { $needCancel = $true }
    }
    if ($needCancel) {
        Log "状态是已发布自测环境，先取消自测"
        if (-not (Find-NamedPageButton $Page.Window.Hwnd "取消自测")) {
            Open-RowMenu $Page.Window.Hwnd $more "取消自测"
        }
        $cancel = Wait-Until 4 { return (Find-NamedPageButton $Page.Window.Hwnd "取消自测") }
        if (-not $cancel) { throw "没有展开出「取消自测」。" }
        if (-not (Invoke-PageButton $cancel "取消自测" -InvokeOnly -KeepFocus)) { throw "「取消自测」无法直接调用" }
        $cancelOk = Wait-Until 8 { return (Find-SelfTestConfirm $Page.Window.Hwnd "取消自测") }
        if (-not $cancelOk) { throw "没有出现取消自测的确认框。" }
        if (-not (Invoke-PageButton $cancelOk "确定" -InvokeOnly -KeepFocus)) { throw "取消自测的「确定」无法直接调用" }
        Log "等待状态离开自测环境"
        $row = Wait-Until 20 {
            $again = Find-ListRow $Page.Window.Hwnd $resourceQuery $ItemId
            if (-not $again) { return $null }
            $st = Get-RowStatusText $Page.Window.Hwnd $again.Element
            if ($st -and $st -ne "已发布自测环境" -and $st -ne "系统处理中") { return $again }
            return $null
        }
        if (-not $row) { throw "取消自测后，状态没有变成可以重新免机审。" }
        $more = Find-RowMoreButton $Page.Window.Hwnd $row.Element
        if (-not $more) { throw "取消自测后没有找到 ... 按钮。" }
    }
    $selfTest = Find-SelfTestButtonAnywhere $Page.Window.Hwnd $selfTestLabel
    if (-not $selfTest) {
        Log "前台悬停更多按钮，再查找$selfTestLabel"
        Open-RowMenu $Page.Window.Hwnd $more $selfTestLabel
        $selfTest = Wait-Until 5 { return (Find-SelfTestButtonAnywhere $Page.Window.Hwnd $selfTestLabel) }
    }
    if (-not $selfTest) { throw "菜单没有展开，「$selfTestLabel」仍不在页面上。" }
    if (-not (Invoke-PageButton $selfTest $selfTestLabel -InvokeOnly -KeepFocus)) { throw "「$selfTestLabel」无法直接调用" }
    $confirm = Wait-Until 10 {
        foreach ($needle in $confirmNeedles) {
            $found = Find-SelfTestConfirm $Page.Window.Hwnd $needle
            if ($found) { return $found }
        }
        return $null
    }
    if (-not $confirm) { throw "没有出现「$selfTestLabel」确认框。" }
    if (-not (Invoke-PageButton $confirm "确定" -InvokeOnly -KeepFocus)) { throw "确认框里的「确定」无法直接调用" }
    Set-Step 98 "$selfTestLabel 已提交"
    Set-FocusGuardPause $false
}

function Invoke-WebSaveAndSelfTest {
    param(
        [string]$MapTitle = "",
        [string[]]$UrlsBefore = @(),
        [int64[]]$BrowserHwnds = @(),
        [switch]$HadPage
    )
    if ($DryRun) {
        $page = Find-PublishPage
        if ($page) {
            Log ("已有发布页：{0}  {1}" -f $page.Window.Title, $page.Url)
        } else {
            Log "当前没有打开发布网页。正式运行时会等「发布地图」打开后再点保存和发起自测"
        }
        return
    }
    Set-Step 80 "等待发布网页出现"
    $page = Wait-Until 900 {
        Restore-BackgroundFocus
        $found = Find-PublishPage
        if (-not $found) { return $null }
        $urlChanged = $found.Url -and (@($UrlsBefore) -notcontains $found.Url)
        $newWindow = @($BrowserHwnds) -notcontains ([int64]$found.Window.Hwnd)
        if ($urlChanged -or $newWindow -or (-not $HadPage)) { return $found }
        return $null
    }
    if (-not $page) { throw "15 分钟内没有看到开发者内容管理网页，也没有「发起自测」按钮。" }
    Set-Step 84 ("已打开发布页：{0}" -f $page.Window.Title)
    Maximize-Browser $page.Window.Hwnd
    if ($BoundItemId -and $page.Url -match "/pe/edit/(\d+)") {
        $openedId = $Matches[1]
        if ($openedId -ne $BoundItemId) { throw "打开的编辑页 ID $openedId 与绑定 ID $BoundItemId 不一致，已停止，未保存。" }
    }
    Set-Step 86 "等待页面内容稳定后再保存"
    $saved = $false
    $clicks = 0
    $allowClick = $true
    $idleSince = $null
    $lastSig = $null
    $loggedBusy = $false
    $resourceUploadWarningSeen = $false
    $recoveryCount = 0
    $lastSaveClickAt = $null
    $deadline = (Get-Date).AddMinutes(5)
    while ((Get-Date) -lt $deadline -and -not $saved) {
        Restore-BackgroundFocus
        if (Find-PageContains $page.Window.Hwnd "请稍等，模组/游戏正在提交自测") {
            throw "检测到「请稍等，模组/游戏正在提交自测」，按要求停止本次程序；未继续保存或重复提交。"
        }
        if (Find-PageContains $page.Window.Hwnd "模组/游戏正在审核") {
            throw "检测到「模组/游戏正在审核」警告，按要求停止本次程序；未继续保存。"
        }
        $resourceUploadWarning = Find-PageContains $page.Window.Hwnd "资源包未上传"
        if ($resourceUploadWarning) {
            if (-not $resourceUploadWarningSeen) {
                Log "检测到「资源包未上传，请重新提交」提示；等待提示消失后重新提交保存"
                $resourceUploadWarningSeen = $true
                $deadline = (Get-Date).AddMinutes(1)
            }
            $idleSince = $null
            Start-Sleep -Milliseconds 500
            continue
        }
        if (Find-PageContains $page.Window.Hwnd "保存成功") { $saved = $true; break }
        $busy = Test-PageContentBusy $page.Window.Hwnd
        $sig = Get-ScrollSignature $page.Window.Hwnd
        $save = Find-DomButton $page.Window.Hwnd "保存" "MC_Style_Green_5"
        if (-not $save) { $save = Find-PageButton $page.Window.Hwnd "保存" }
        if ($busy -or -not $save -or $sig -ne $lastSig) {
            if ($busy) {
                if ($clicks -eq 0) { $allowClick = $true }
                if (-not $loggedBusy) {
                    Log "浏览器转圈结束不代表资源展示完成，继续等页面停稳"
                    $loggedBusy = $true
                }
            }
            $lastSig = $sig
            $idleSince = $null
            Start-Sleep -Milliseconds 350
            continue
        }
        $loggedBusy = $false
        if (-not $idleSince) {
            $idleSince = Get-Date
            Start-Sleep -Milliseconds 300
            continue
        }
        if (((Get-Date) - $idleSince).TotalMilliseconds -lt 1500) {
            Start-Sleep -Milliseconds 300
            continue
        }
        if (-not $allowClick -and $lastSaveClickAt -and (((Get-Date) - $lastSaveClickAt).TotalSeconds -ge 8)) {
            if ($clicks -ge 3 -and -not $resourceUploadWarningSeen) { throw "保存按钮调用 3 次后仍没有成功或处理中反馈，已停止。" }
            Log ("调用保存后 8 秒没有反馈，第 {0} 次重试；重新滚到页面顶部" -f ($clicks + 1))
            $allowClick = $true
            $idleSince = $null
            continue
        }
        if (-not $allowClick -or ($clicks -ge 3 -and -not $resourceUploadWarningSeen)) {
            Start-Sleep -Milliseconds 300
            continue
        }
        Log "页面内容已停稳，滚到顶部后调用保存"
        Scroll-BrowserToTop $page.Window.Hwnd
        Start-Sleep -Milliseconds 300
        $save = Find-DomButton $page.Window.Hwnd "保存" "MC_Style_Green_5"
        if (-not $save) { $save = Find-PageButton $page.Window.Hwnd "保存" }
        if (-not $save) { throw "滚到顶部后没有找到「保存」。" }
        $clicks++
        $lastSaveClickAt = Get-Date
        $allowClick = $false
        $idleSince = $null
        $lastSig = $null
        if (-not (Invoke-PageButton $save "保存")) {
            Log "「保存」按钮没能触发"
        }
    }
    if (-not $saved) { throw "页面停稳后调用了保存，仍没有看到「保存成功」。" }
    $itemId = ""
    if ($page.Url -match "/pe/edit/(\d+)") { $itemId = $Matches[1] }
    if (-not $itemId) { throw "发布页地址里没有作品编号，不能提交免机审自测。" }
    if ($BoundItemId -and $itemId -ne $BoundItemId) { throw "发布页 ID $itemId 与绑定 ID $BoundItemId 不一致，已停止。" }
    Invoke-SelfTestOnPage $page $MapTitle $itemId
    Restore-BackgroundFocus
}

function Find-PromptText($Root, [string]$Needle) {
    if (-not $Root -or -not $Needle) { return $null }
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $stack = New-Object System.Collections.Stack
    $stack.Push(@($Root, 0))
    $seen = 0
    while ($stack.Count -gt 0 -and $seen -lt 2500) {
        $pair = $stack.Pop()
        $node = $pair[0]
        $depth = [int]$pair[1]
        $seen++
        if ($depth -gt 16) { continue }
        $name = ""
        try { $name = [string]$node.Current.Name } catch { continue }
        if ($name -and $name.Contains("您确定") -and $name.Contains($Needle) -and $name.Length -le 200 -and (Test-OnScreen $node)) {
            return $node
        }
        $child = $walker.GetFirstChild($node)
        while ($child) {
            $stack.Push(@($child, ($depth + 1)))
            $child = $walker.GetNextSibling($child)
        }
    }
    return $null
}

function Find-SelfTestConfirm([IntPtr]$Hwnd, [string]$Needle = "提交到自测环境") {
    $roots = New-Object System.Collections.Generic.List[object]
    $page = Get-Ui $Hwnd
    if ($page) { $roots.Add($page) | Out-Null }
    foreach ($w in @(Get-TopWindows | Where-Object { $_.ProcessName -eq "msedge" -and $_.Title -match "提示" })) {
        $el = Get-Ui $w.Hwnd
        if ($el) { $roots.Add($el) | Out-Null }
    }
    foreach ($root in $roots) {
        $msg = Find-PromptText $root $Needle
        if (-not $msg) { $msg = Find-FirstContains $root $Needle }
        if (-not $msg -or -not (Test-OnScreen $msg)) { continue }
        $mr = $msg.Current.BoundingRectangle
        $cond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Button)
        $buttons = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
        $best = $null
        $bestDy = 100000
        foreach ($el in $buttons) {
            $name = ""
            try { $name = ([string]$el.Current.Name).Trim() } catch { continue }
            if ($name -ne "确定") { continue }
            $br = $el.Current.BoundingRectangle
            if ($br.Width -lt 8 -or $br.Height -lt 8) { continue }
            if ($br.Y -lt ($mr.Y - 10)) { continue }
            $dy = [Math]::Abs(($br.Y + ($br.Height / 2)) - ($mr.Y + $mr.Height))
            if ($dy -lt $bestDy) { $best = $el; $bestDy = $dy }
        }
        if ($best) { return $best }
    }
    return $null
}

function Find-RowMoreButton([IntPtr]$Hwnd, $Row) {
    $rr = $Row.Current.BoundingRectangle
    $mid = $rr.Y + ($rr.Height / 2)
    $root = Get-Ui $Hwnd
    if (-not $root) { return $null }
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Button)
    $buttons = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
    $known = @("查看", "编辑", "更新", "提交审核", "查看数据", "撤销审核", "筛选", "返回", "保存", "取消", "确定")
    $best = $null
    $bestX = -1
    foreach ($el in $buttons) {
        $name = ""
        $cls = ""
        try {
            $name = ([string]$el.Current.Name).Trim()
            $cls = [string]$el.Current.ClassName
        } catch { continue }
        if (-not $cls.Contains("MC_Style_Grey_2")) { continue }
        if ($known -contains $name) { continue }
        $br = $el.Current.BoundingRectangle
        if ($br.Width -lt 8 -or $br.Height -lt 8) { continue }
        $by = $br.Y + ($br.Height / 2)
        if ([Math]::Abs($by - $mid) -gt 30) { continue }
        if ($br.X -lt $rr.X) { continue }
        if ($br.X -gt $bestX) { $best = $el; $bestX = $br.X }
    }
    return $best
}

function Find-SelfTestButton([IntPtr]$Hwnd, [string]$ModeLabel = "免机审自测") {
    $root = Get-Ui $Hwnd
    if (-not $root) { return $null }
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $stack = New-Object System.Collections.Stack
    $stack.Push($root)
    $seen = 0
    $fallback = $null
    while ($stack.Count -gt 0 -and $seen -lt 8000) {
        $el = $stack.Pop()
        $seen++
        $name = ""
        $cls = ""
        try {
            $name = ([string]$el.Current.Name).Trim()
            $cls = [string]$el.Current.ClassName
        } catch { continue }
        $isMatch = $false
        if ($ModeLabel -eq "机审自测") { $isMatch = ($name -match "(?<!免)机审自测") }
        else { $isMatch = $name.Contains("免机审自测") }
        if ($isMatch) {
            if ($cls.Contains("MC_Style_Grey_2")) { return $el }
            if (-not $fallback) { $fallback = $el }
        }
        $child = $walker.GetFirstChild($el)
        while ($child) {
            $stack.Push($child)
            $child = $walker.GetNextSibling($child)
        }
    }
    return $fallback
}

function Show-DryRun([string]$MapTitle) {
    Log "---- 只检查，不点击 ----"
    $editors = @(Get-TopWindows | Where-Object { $_.ProcessName -eq "MC_Editor" -and $_.Width -gt 400 })
    if ($editors.Count -eq 0) {
        Log "编辑器没开。正式运行时如果编辑器开着，会点关闭，并在「是否保存并退出」里点保存"
    } else {
        foreach ($w in $editors) { Log ("编辑器：{0} {1}x{2}" -f $w.Title, $w.Width, $w.Height) }
    }
    $main = Get-LauncherMain
    if (-not $main) { Log "启动器主窗口没找到"; return }
    Log ("启动器：{0} {1}x{2}" -f $main.Title, $main.Width, $main.Height)
    $cfg = Get-ConfigElement
    if ($cfg) {
        $upgrade = Find-FirstExact $cfg.Element "全部升级" "Button"
        Log ("配置窗口已打开，全部升级：" + $(if ($upgrade) { "能点到" } else { "没找到" }))
    } else {
        Log "配置窗口没开。正式运行时会从地图旁的「更多」打开"
    }
    $root = Get-Ui $main.Hwnd
    $card = Find-MapCard $root $MapTitle
    if ($card) {
        $more = Find-MoreButton $card
        if ($more) {
            $mr = $more.Current.BoundingRectangle
            Log ("地图卡片已在当前页面，更多按钮：[{0}] {1:N0},{2:N0}" -f $more.Current.Name, $mr.X, $mr.Y)
        } else {
            Log "地图卡片已在当前页面，但没有找到更多按钮"
        }
    } else {
        Log "当前页面看不到这张地图卡片。正式运行时会先切到「基岩版组件」再找"
    }
    Invoke-WebSaveAndSelfTest
}

try {
    Set-Step 2 "正在读取项目"
    if ($ProgressFile -and [string]::IsNullOrWhiteSpace([string]$MapName)) { throw "一键窗口没有传入当前选中的项目名称，已停止；请重新选择项目后重试。" }
    $map = Get-LatestMap
    Set-Step 6 ("目标地图：{0}" -f $map.Name)
    if ($map.Dir) { Log ("目录：{0}" -f $map.Dir) }
    if ($map.Updated) { Log ("最近写入：{0}" -f $map.Updated.ToString("yyyy-MM-dd HH:mm:ss")) }
    if ($DryRun) {
        Show-DryRun $map.Name
        Log "检查结束。正式执行请直接运行脚本，不要加 -DryRun"
    } else {
        if ($Countdown -gt 0) {
            Write-Host ""
            Write-Host ("即将处理「{0}」。关闭这个窗口可以取消。" -f $map.Name)
            for ($i = $Countdown; $i -ge 1; $i--) {
                Write-Host ("  {0} ..." -f $i)
                Start-Sleep -Seconds 1
            }
        }
        Set-Step 8 "检查编辑器"
        Remember-BackgroundFocus
        Close-MapEditor
        Start-FocusGuard
        try {
            $urlsBefore = @(Get-OpenPublishUrls)
            $browserHwnds = @(Get-TopWindows | Where-Object { $_.ProcessName -match "^(msedge|chrome|firefox)$" } | ForEach-Object { [int64]$_.Hwnd })
            $hadPage = [bool](Find-PublishPage)
            Invoke-UpgradeAndPublish $map.Name
            Invoke-WebSaveAndSelfTest -MapTitle $map.Name -UrlsBefore $urlsBefore -BrowserHwnds $browserHwnds -HadPage:$hadPage
            Set-Step 100 "全部步骤已完成"
        } finally {
            Stop-FocusGuard
        }
    }
} catch {
    Log ("失败：" + $_.Exception.Message)
    Write-RunProgress $script:StepPercent ("失败：" + $_.Exception.Message)
    Write-Host $_.ScriptStackTrace
    if (-not $NoPause) { [void](Read-Host "按回车关闭") }
    exit 1
}

if (-not $NoPause) { [void](Read-Host "按回车关闭") }
exit 0
