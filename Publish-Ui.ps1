# 一键保存发布自测的窗口。选项目、改快捷键、看进度。实际步骤仍由 Publish-SelfTest.ps1 执行。
param(
    [switch]$SelfTest,
    [switch]$NoConsole
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne "STA") {
    $argList = @(
        "-NoProfile", "-STA", "-ExecutionPolicy", "Bypass",
        "-File", $PSCommandPath
    )
    if ($SelfTest) { $argList += "-SelfTest" }
    if ($NoConsole) { $argList += "-NoConsole" }
    $child = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $argList -Wait -PassThru
    exit $child.ExitCode
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[void][System.Windows.Forms.Application]::EnableVisualStyles()
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class UiDpi {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool LockSetForegroundWindow(uint uLockCode);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
  [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int valueSize);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, string lParam);
  [DllImport("shell32.dll", CharSet=CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string AppID);
}
"@
[void][UiDpi]::SetCurrentProcessExplicitAppUserModelID("FxShadow.MCSTestHelper")
[void][UiDpi]::SetProcessDPIAware()
function Set-DarkTitleBar([System.Windows.Forms.Form]$Window) {
    try {
        $dark = 0
        $result = [UiDpi]::DwmSetWindowAttribute($Window.Handle, 20, [ref]$dark, 4)
        if ($result -ne 0) { [void][UiDpi]::DwmSetWindowAttribute($Window.Handle, 19, [ref]$dark, 4) }
    } catch {}
}
$script:InstanceMutex = $null
if (-not $SelfTest) {
    $createdNew = $false
    $script:InstanceMutex = New-Object System.Threading.Mutex($true, "Local\MCStudio-OneClickPublish-UI", [ref]$createdNew)
    if (-not $createdNew) {
        $existingWindow = [UiDpi]::FindWindow($null, "MCSTestHelper")
        [void][System.Windows.Forms.MessageBox]::Show(
            "你已经启动了一个进程。",
            "MCSTestHelper",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        if ($existingWindow -ne [IntPtr]::Zero) {
            [void][UiDpi]::ShowWindow($existingWindow, 9)
            [void][UiDpi]::SetForegroundWindow($existingWindow)
        }
        exit 0
    }
}
if ($NoConsole -and -not $SelfTest) {
    $console = [UiDpi]::GetConsoleWindow()
    if ($console -ne [IntPtr]::Zero) { [void][UiDpi]::ShowWindow($console, 0) }
}

Add-Type -ReferencedAssemblies System.Windows.Forms @"
using System;
using System.Windows.Forms;
using System.Runtime.InteropServices;
public class OneClickForm : Form {
    public event EventHandler HotkeyPressed;
    const int WM_HOTKEY = 0x0312;
    [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    public bool BindHotkey(uint mod, uint vk) {
        UnregisterHotKey(this.Handle, 1);
        if (vk == 0) return false;
        return RegisterHotKey(this.Handle, 1, mod | 0x4000, vk);
    }
    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_HOTKEY) {
            EventHandler handler = HotkeyPressed;
            if (handler != null) handler(this, EventArgs.Empty);
        }
        base.WndProc(ref m);
    }
    protected override void OnFormClosed(FormClosedEventArgs e) {
        try { UnregisterHotKey(this.Handle, 1); } catch { }
        base.OnFormClosed(e);
    }
}
"@

$script:WorkRoot = "D:\MCStudioDownload\work"
$script:ConfigPath = Join-Path $PSScriptRoot "ui-config.json"
$script:ProgressPath = Join-Path $PSScriptRoot "run-progress.txt"
$script:LogPath = Join-Path $PSScriptRoot "last-run.log"
$script:Worker = $null
$script:LastLog = ""
$script:Running = $false
$script:RunStartedAt = $null
$script:ProjectIds = @{}
$script:ProjectKeywords = @{}
$script:ProjectModes = @{}
$script:RunSelfTestMode = "review"

function Show-ProjectSettings {
    if ($lv.SelectedItems.Count -lt 1) {
        Set-PhaseLabel 0 "请先选择项目，再打开项目设置" $true
        return
    }
    $selected = $lv.SelectedItems[0]
    $key = Get-SelectedProjectKey
    $projectName = [string]$selected.Tag.Name
    $projectCategory = [string]$selected.SubItems[1].Text
    $settings = New-Object System.Windows.Forms.Form
    $settings.Text = "项目设置"
    $settings.StartPosition = "CenterParent"
    $settings.FormBorderStyle = "FixedDialog"
    $settings.MaximizeBox = $false
    $settings.MinimizeBox = $false
    $settings.ShowInTaskbar = $false
    $settings.ClientSize = New-Object System.Drawing.Size(460, 340)
    $settings.BackColor = [System.Drawing.Color]::White
    $settings.ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
    $settings.Add_Shown({ Set-DarkTitleBar $settings })
    $settings.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
    $clearTip = New-Object System.Windows.Forms.ToolTip

    $title = New-Object System.Windows.Forms.Label
    $title.Text = "项目：$projectName（$projectCategory）"
    $title.AutoEllipsis = $true
    $title.BackColor = [System.Drawing.Color]::Transparent
    $title.Location = New-Object System.Drawing.Point(18, 16)
    $title.Size = New-Object System.Drawing.Size(424, 24)
    $settings.Controls.Add($title)


    $idPanel = New-Object System.Windows.Forms.Panel
    $idPanel.Location = New-Object System.Drawing.Point(18, 64)
    $idPanel.Size = New-Object System.Drawing.Size(424, 34)
    $idPanel.BorderStyle = "FixedSingle"
    $idPanel.BackColor = [System.Drawing.Color]::White
    $settings.Controls.Add($idPanel)
    $idBox = New-Object System.Windows.Forms.TextBox
    $idBox.Location = New-Object System.Drawing.Point(5, 4)
    $idBox.Size = New-Object System.Drawing.Size(380, 20)
    $idBox.BorderStyle = "None"
    $idBox.BackColor = [System.Drawing.Color]::White
    $idBox.ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
    $idBox.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
    $idBox.Text = Get-SelectedBoundId
    $idPanel.Controls.Add($idBox)
    $clearId = New-Object System.Windows.Forms.Button
    $clearId.Text = "×"
    $clearId.Location = New-Object System.Drawing.Point(391, 1)
    $clearId.Size = New-Object System.Drawing.Size(28, 26)
    $clearId.FlatStyle = "Flat"
    $clearId.FlatAppearance.BorderSize = 0
    $clearId.BackColor = [System.Drawing.Color]::White
    $clearId.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
    $clearId.Font = New-Object System.Drawing.Font("Segoe UI Symbol", 11)
    $clearId.Add_Click({ $idBox.Clear(); $idBox.Focus() })
    $clearTip.SetToolTip($clearId, "清除绑定ID")
    $idPanel.Controls.Add($clearId)
    [void][UiDpi]::SendMessage($idBox.Handle, 0x1501, [IntPtr]1, "绑定46ID")

    $keywordPanel = New-Object System.Windows.Forms.Panel
    $keywordPanel.Location = New-Object System.Drawing.Point(18, 124)
    $keywordPanel.Size = New-Object System.Drawing.Size(424, 34)
    $keywordPanel.BorderStyle = "FixedSingle"
    $keywordPanel.BackColor = [System.Drawing.Color]::White
    $settings.Controls.Add($keywordPanel)
    $keywordBox = New-Object System.Windows.Forms.TextBox
    $keywordBox.Location = New-Object System.Drawing.Point(5, 4)
    $keywordBox.Size = New-Object System.Drawing.Size(380, 20)
    $keywordBox.BorderStyle = "None"
    $keywordBox.BackColor = [System.Drawing.Color]::White
    $keywordBox.ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
    $keywordBox.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
    $keywordBox.Text = Get-SelectedPublishKeyword
    $keywordPanel.Controls.Add($keywordBox)
    $clearKeyword = New-Object System.Windows.Forms.Button
    $clearKeyword.Text = "×"
    $clearKeyword.Location = New-Object System.Drawing.Point(391, 1)
    $clearKeyword.Size = New-Object System.Drawing.Size(28, 26)
    $clearKeyword.FlatStyle = "Flat"
    $clearKeyword.FlatAppearance.BorderSize = 0
    $clearKeyword.BackColor = [System.Drawing.Color]::White
    $clearKeyword.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
    $clearKeyword.Font = New-Object System.Drawing.Font("Segoe UI Symbol", 11)
    $clearKeyword.Add_Click({ $keywordBox.Clear(); $keywordBox.Focus() })
    $clearTip.SetToolTip($clearKeyword, "清除关键词")
    $keywordPanel.Controls.Add($clearKeyword)
    [void][UiDpi]::SendMessage($keywordBox.Handle, 0x1501, [IntPtr]1, "发布匹配关键词（留空时使用项目名）")
    $modeLabel = New-Object System.Windows.Forms.Label
    $modeLabel.Text = "自测方式"
    $modeLabel.Location = New-Object System.Drawing.Point(18, 174)
    $modeLabel.Size = New-Object System.Drawing.Size(100, 22)
    $settings.Controls.Add($modeLabel)
    $mode = Get-SelectedSelfTestMode
    $radioNoReview = New-Object System.Windows.Forms.RadioButton
    $radioNoReview.Text = "免机审自测"
    $radioNoReview.Location = New-Object System.Drawing.Point(22, 201)
    $radioNoReview.Size = New-Object System.Drawing.Size(130, 24)
    $radioNoReview.Checked = ($mode -eq "free")
    $settings.Controls.Add($radioNoReview)
    $radioReview = New-Object System.Windows.Forms.RadioButton
    $radioReview.Text = "机审自测"
    $radioReview.Location = New-Object System.Drawing.Point(170, 201)
    $radioReview.Size = New-Object System.Drawing.Size(130, 24)
    $radioReview.Checked = ($mode -eq "review")
    $settings.Controls.Add($radioReview)
    $save = New-Object System.Windows.Forms.Button
    $save.Text = "保存"
    $save.Location = New-Object System.Drawing.Point(270, 282)
    $save.Size = New-Object System.Drawing.Size(80, 30)
    $save.FlatStyle = "Flat"
    $save.FlatAppearance.BorderSize = 0
    $save.BackColor = [System.Drawing.Color]::FromArgb(47, 117, 199)
    $save.ForeColor = [System.Drawing.Color]::White
    $save.Add_Click({
        $id = $idBox.Text.Trim()
        if ($id -and $id -notmatch '^46\d+$') {
            [void][System.Windows.Forms.MessageBox]::Show($settings, "ID 必须是 46 开头的数字。", "项目设置", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        if ($id) { $script:ProjectIds[$key] = $id } else { $script:ProjectIds.Remove($key) | Out-Null }
        $legacyKey = [string]$selected.Tag.Account + "|" + $projectName
        if ($id -or $projectCategory -eq "map") { $script:ProjectIds.Remove($legacyKey) | Out-Null }
        $keyword = $keywordBox.Text.Trim()
        if ($keyword) { $script:ProjectKeywords[$key] = $keyword } else { $script:ProjectKeywords.Remove($key) | Out-Null }
        $script:ProjectModes[$key] = if ($radioReview.Checked) { "review" } else { "free" }
        $selected.SubItems[2].Text = $id
        Save-UiConfig
        Set-PhaseLabel 0 "已保存「$projectName」的项目设置" $false
        $settings.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $settings.Close()
    })
    $settings.Controls.Add($save)
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = "取消"
    $cancel.Location = New-Object System.Drawing.Point(360, 282)
    $cancel.Size = New-Object System.Drawing.Size(82, 30)
    $cancel.FlatStyle = "Flat"
    $cancel.FlatAppearance.BorderSize = 0
    $cancel.BackColor = [System.Drawing.Color]::White
    $cancel.ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $settings.Controls.Add($cancel)
    $settings.AcceptButton = $save
    $settings.CancelButton = $cancel
    [void]$settings.ShowDialog($form)
    $idBox.Dispose(); $keywordBox.Dispose(); $settings.Dispose()
}

function ConvertTo-CmdArg([string]$Text) {
    if ($null -eq $Text) { return '""' }
    # 始终引用参数，避免作品名中的方括号、空格等字符被 PowerShell 命令行解析成语法。
    return '"' + ($Text -replace '"', '\"') + '"'
}

function Get-Vk([string]$Name) {
    if ($Name -match '^F(\d+)$') { return 111 + [int]$Matches[1] }
    if ($Name -and $Name.Length -eq 1) { return [int][char]$Name.ToUpper() }
    return 0
}

function Format-Hotkey([bool]$Ctrl, [bool]$Alt, [bool]$Shift, [bool]$Win, [string]$Key) {
    $parts = New-Object System.Collections.Generic.List[string]
    if ($Ctrl) { $parts.Add("Ctrl") | Out-Null }
    if ($Alt) { $parts.Add("Alt") | Out-Null }
    if ($Shift) { $parts.Add("Shift") | Out-Null }
    if ($Win) { $parts.Add("Win") | Out-Null }
    if ($Key) { $parts.Add($Key) | Out-Null }
    return ($parts -join " + ")
}

function Read-UiConfig {
    $cfg = [pscustomobject]@{
        MapName = ""
        ProjectType = "map"
        Ctrl = $true
        Alt = $true
        Shift = $false
        Win = $false
        Key = "F8"
        WorkRoot = $script:WorkRoot
        ProjectIds = @{}
        ProjectKeywords = @{}
        ProjectModes = @{}
    }
    if (-not (Test-Path $script:ConfigPath)) { return $cfg }
    try {
        $raw = [System.IO.File]::ReadAllText($script:ConfigPath, [System.Text.Encoding]::UTF8)
        $json = $raw | ConvertFrom-Json
        if ($json.MapName) { $cfg.MapName = [string]$json.MapName }
        if ($json.ProjectType -in @("map", "addon")) { $cfg.ProjectType = [string]$json.ProjectType }
        if ($null -ne $json.Ctrl) { $cfg.Ctrl = [bool]$json.Ctrl }
        if ($null -ne $json.Alt) { $cfg.Alt = [bool]$json.Alt }
        if ($null -ne $json.Shift) { $cfg.Shift = [bool]$json.Shift }
        if ($null -ne $json.Win) { $cfg.Win = [bool]$json.Win }
        if ($json.Key) { $cfg.Key = [string]$json.Key }
        if ($json.WorkRoot) { $cfg.WorkRoot = [string]$json.WorkRoot }
        if ($json.ProjectKeywords) {
            foreach ($prop in $json.ProjectKeywords.PSObject.Properties) {
                $value = ([string]$prop.Value).Trim()
                if ($value) { $cfg.ProjectKeywords[$prop.Name] = $value }
            }
        }
        if ($json.ProjectModes) {
            foreach ($prop in $json.ProjectModes.PSObject.Properties) {
                $value = [string]$prop.Value
                if ($value -in @("free", "review")) { $cfg.ProjectModes[$prop.Name] = $value }
            }
        }
        if ($json.ProjectIds) {
            foreach ($prop in $json.ProjectIds.PSObject.Properties) {
                $value = [string]$prop.Value
                if ($value -match '^46\d+$') { $cfg.ProjectIds[$prop.Name] = $value }
            }
        }
    } catch {}
    return $cfg
}

function Get-SelectedProjectKey {
    if ($lv.SelectedItems.Count -lt 1) { return "" }
    return [string]$lv.SelectedItems[0].Name
}

function Get-SelectedBoundId {
    $key = Get-SelectedProjectKey
    if (-not $key) { return "" }
    $id = [string]$script:ProjectIds[$key]
    if (-not $id -and $lv.SelectedItems.Count -gt 0 -and $lv.SelectedItems[0].SubItems[1].Text -eq "map") {
        $legacyKey = [string]$lv.SelectedItems[0].Tag.Account + "|" + [string]$lv.SelectedItems[0].Tag.Name
        $id = [string]$script:ProjectIds[$legacyKey]
    }
    return $id
}

function Get-SelectedPublishKeyword {
    $key = Get-SelectedProjectKey
    if (-not $key) { return "" }
    return [string]$script:ProjectKeywords[$key]
}

function Get-SelectedSelfTestMode {
    $key = Get-SelectedProjectKey
    if (-not $key) { return "review" }
    $mode = [string]$script:ProjectModes[$key]
    if ($mode -notin @("free", "review")) { return "review" }
    return $mode
}

function Save-UiConfig {
    if ($script:SuppressSave) { return }
    $cfg = [ordered]@{
        MapName = ""
        ProjectType = "map"
        Ctrl = [bool]$chkCtrl.Checked
        Alt = [bool]$chkAlt.Checked
        Shift = [bool]$chkShift.Checked
        Win = [bool]$chkWin.Checked
        Key = [string]$cmbKey.SelectedItem
        ProjectIds = $script:ProjectIds
        ProjectKeywords = $script:ProjectKeywords
        ProjectModes = $script:ProjectModes
        WorkRoot = $script:WorkRoot
    }
    if ($lv.SelectedItems.Count -gt 0) {
        $cfg.MapName = [string]$lv.SelectedItems[0].Tag.Name
        $cfg.ProjectType = [string]$lv.SelectedItems[0].SubItems[1].Text
    }
    $json = ($cfg | ConvertTo-Json)
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($script:ConfigPath, $json, $utf8)
}

function Get-ProjectList {
    $list = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path $script:WorkRoot)) { return $list }
    foreach ($account in @(Get-ChildItem $script:WorkRoot -Directory -ErrorAction SilentlyContinue)) {
        foreach ($kind in @(@{ Folder = "AddOn"; Label = "addon" }, @{ Folder = "Map"; Label = "map" })) {
            $projectRoot = Join-Path (Join-Path $account.FullName "Cpp") $kind.Folder
            if (-not (Test-Path $projectRoot)) { continue }
            foreach ($projectDir in @(Get-ChildItem $projectRoot -Directory -ErrorAction SilentlyContinue)) {
                $cfgPath = Join-Path $projectDir.FullName "work.mcscfg"
                if (-not (Test-Path $cfgPath)) { continue }
                try {
                    $json = [System.IO.File]::ReadAllText($cfgPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
                } catch { continue }
                if (-not $json.Name) { continue }
                $updated = [datetime]::MinValue
                if ($json.UpdateTime) {
                    try { $updated = [datetime]$json.UpdateTime } catch { $updated = (Get-Item $cfgPath).LastWriteTime }
                } else {
                    $updated = (Get-Item $cfgPath).LastWriteTime
                }
                $list.Add([pscustomobject]@{
                    Name = [string]$json.Name
                    Account = $account.Name
                    Category = [string]$kind.Label
                    BindingKey = ([string]$account.Name + "|" + [string]$kind.Label + "|" + [string]$projectDir.Name)
                    Updated = $updated
                    Dir = $projectDir.FullName
                }) | Out-Null
            }
        }
    }
    return @($list | Sort-Object Updated -Descending)
}
function Read-SharedText([string]$Path) {
    if (-not (Test-Path $Path)) { return "" }
    $fs = $null
    $sr = $null
    try {
        $fs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
        return $sr.ReadToEnd()
    } catch {
        return ""
    } finally {
        if ($sr) { $sr.Dispose() } elseif ($fs) { $fs.Dispose() }
    }
}

function Get-PhaseText([int]$Percent) {
    if ($Percent -ge 100) { return "完成" }
    if ($Percent -ge 90) {
        $modeLabel = if ($script:RunSelfTestMode -eq "review") { "机审自测" } else { "免机审自测" }
        return "5/5  $modeLabel"
    }
    if ($Percent -ge 78) { return "4/5  网页保存" }
    if ($Percent -ge 62) { return "3/5  发布作品" }
    if ($Percent -ge 26) { return "2/5  启动器配置" }
    if ($Percent -ge 8) { return "1/5  编辑器保存" }
    return "准备"
}

function Set-PhaseLabel([int]$Percent, [string]$Detail, [bool]$Failed) {
    $phase = Get-PhaseText $Percent
    if ($Failed) {
        $lblPhase.Text = $Detail
        $lblPhase.ForeColor = [System.Drawing.Color]::FromArgb(255, 117, 117)
    } else {
        $lblPhase.Text = "{0}    {1}" -f $phase, $Detail
        if ($Percent -ge 100) {
            $lblPhase.ForeColor = [System.Drawing.Color]::FromArgb(83, 205, 144)
        } else {
            $lblPhase.ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
        }
    }
    $bar.Value = [Math]::Max(0, [Math]::Min(100, $Percent))
}

function Update-ProjectList([string]$PreferName, [string]$PreferType = "map") {
    $script:SuppressSave = $true
    $lv.BeginUpdate()
    $lv.Items.Clear()
    $projects = @(Get-ProjectList | Select-Object -First 3)
    $select = $null
    foreach ($project in $projects) {
        $item = New-Object System.Windows.Forms.ListViewItem($project.Name)
        $when = ""
        if ($project.Updated -gt [datetime]::MinValue) { $when = $project.Updated.ToString("yyyy-MM-dd HH:mm") }
        $projectKey = [string]$project.BindingKey
        $boundId = [string]$script:ProjectIds[$projectKey]
        if (-not $boundId -and $project.Category -eq "map") { $boundId = [string]$script:ProjectIds[[string]$project.Account + "|" + [string]$project.Name] }
        [void]$item.SubItems.Add($project.Category)
        [void]$item.SubItems.Add($boundId)
        [void]$item.SubItems.Add($when)
        
        $item.Name = $project.BindingKey
        $item.Tag = [pscustomobject]@{ Name = $project.Name; Account = $project.Account }
        [void]$lv.Items.Add($item)
        if ($PreferName -and $project.Name -eq $PreferName -and $project.Category -eq $PreferType -and -not $select) { $select = $item }
    }
    # 没有匹配到上次选中的项目时保持未选中，避免误把列表第一项当作用户选择。
    if ($select) {
        $select.Selected = $true
        $select.Focused = $true
        $select.EnsureVisible()
    }
    $lv.EndUpdate()
    Set-ProjectColumnWidths
    $script:SuppressSave = $false
    if ($lv.Items.Count -eq 0) {
        $lblPhase.Text = "项目目录里没有 addon 或 map"
    }
}

function Set-ProjectColumnWidths {
    if (-not $lv -or $lv.Columns.Count -lt 4) { return }
    $categoryWidth = 100
    $boundIdWidth = 300
    $recentWidth = 190
    $scrollbarWidth = [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth
    $nameWidth = [Math]::Max(260, $lv.ClientSize.Width - $categoryWidth - $boundIdWidth - $recentWidth - $scrollbarWidth - 4)
    $lv.Columns[0].Width = $nameWidth
    $lv.Columns[1].Width = $categoryWidth
    $lv.Columns[2].Width = $boundIdWidth
    $lv.Columns[3].Width = $recentWidth
}

function Set-RunButtons([bool]$Running) {
    $script:Running = $Running
    $bar.Visible = $Running
    $btnStart.Enabled = $true
    if ($Running) {
        $btnStart.Text = "■"
        $btnStart.ForeColor = [System.Drawing.Color]::FromArgb(196, 64, 58)
        $runButtonTip.SetToolTip($btnStart, "停止任务")
    } else {
        $btnStart.Text = "▶"
        $btnStart.ForeColor = [System.Drawing.Color]::FromArgb(32, 150, 96)
        $runButtonTip.SetToolTip($btnStart, "开始任务")
    }
    $btnRefresh.Enabled = -not $Running
    $btnProjectSettings.Enabled = -not $Running
    $btnAppSettings.Enabled = -not $Running
    $btnWorkRoot.Enabled = -not $Running
    $lv.Enabled = -not $Running
}

function Set-ForegroundLock([bool]$Locked) {
    $code = 2
    if ($Locked) { $code = 1 }
    try { [void][UiDpi]::LockSetForegroundWindow([uint32]$code) } catch {}
}

function Start-Run {
    if ($script:Worker -and -not $script:Worker.HasExited) { return }
    if ($lv.SelectedItems.Count -lt 1) {
        Set-PhaseLabel 0 "请先在列表里选中一个项目" $true
        return
    }
    $name = [string]$lv.SelectedItems[0].Tag.Name
    $projectType = [string]$lv.SelectedItems[0].SubItems[1].Text
    $boundId = Get-SelectedBoundId
    if ($boundId -notmatch '^46\d+$') {
        Set-PhaseLabel 0 "此项目尚未绑定有效的46ID，请先完成绑定后再启动。" $true
        [void](Show-ProjectSettings)
        $boundId = Get-SelectedBoundId
        if ($boundId -notmatch '^46\d+$') {
            Set-PhaseLabel 0 "启动已阻止：此项目必须先绑定46开头的作品ID。" $true
            return
        }
        Set-PhaseLabel 0 "已保存46ID绑定，请再次点击开始。" $false
        return
    }
    $publishKeyword = Get-SelectedPublishKeyword
    $selfTestMode = Get-SelectedSelfTestMode
    $script:RunSelfTestMode = $selfTestMode
    Save-UiConfig
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($script:ProgressPath, "2|正在启动", $utf8)
    $script:LastLog = ""
    $txtLog.Clear()
    Set-ForegroundLock $true
    Set-PhaseLabel 2 "正在启动「$name」" $false
    Set-RunButtons $true
    $argText = @(
        (ConvertTo-CmdArg "-NoProfile"),
        (ConvertTo-CmdArg "-STA"),
        (ConvertTo-CmdArg "-ExecutionPolicy"),
        (ConvertTo-CmdArg "Bypass"),
        (ConvertTo-CmdArg "-File"),
        (ConvertTo-CmdArg (Join-Path $PSScriptRoot "Publish-SelfTest.ps1")),
        (ConvertTo-CmdArg "-NoPause"),
        (ConvertTo-CmdArg "-Countdown"),
        (ConvertTo-CmdArg "0"),
        (ConvertTo-CmdArg "-ProgressFile"),
        (ConvertTo-CmdArg $script:ProgressPath),
        (ConvertTo-CmdArg "-MapName"),
        (ConvertTo-CmdArg $name),
        (ConvertTo-CmdArg "-ProjectType"),
        (ConvertTo-CmdArg $projectType),
        (ConvertTo-CmdArg "-WorkRoot"),
        (ConvertTo-CmdArg $script:WorkRoot)
    ) -join " "
    if ($boundId) { $argText += " -BoundItemId " + (ConvertTo-CmdArg $boundId) }
    if ($publishKeyword) { $argText += " -PublishKeyword " + (ConvertTo-CmdArg $publishKeyword) }
    $argText += " -SelfTestMode " + (ConvertTo-CmdArg $selfTestMode)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $psi.Arguments = $argText
    $psi.WorkingDirectory = $PSScriptRoot
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $script:Worker = [System.Diagnostics.Process]::Start($psi)
    $script:RunStartedAt = Get-Date
    $form.WindowState = [System.Windows.Forms.FormWindowState]::Minimized
}

function Stop-Run {
    if (-not $script:Running) { return }
    if ($script:Worker -and -not $script:Worker.HasExited) {
        try { $script:Worker.Kill() } catch {}
        try { $script:Worker.WaitForExit(3000) } catch {}
    }
    $script:Worker = $null
    Set-ForegroundLock $false
    Set-RunButtons $false
    $elapsed = Get-RunDuration
    Set-PhaseLabel $bar.Value "已停止" $true
    $bar.Value = 0
    $script:LastLog = "已停止；本次耗时：$elapsed"
    $txtLog.Text = $script:LastLog
    $script:RunStartedAt = $null
}

function Update-Hotkey {
    $key = [string]$cmbKey.SelectedItem
    $vk = Get-Vk $key
    $mod = 0
    if ($chkCtrl.Checked) { $mod = $mod -bor 2 }
    if ($chkAlt.Checked) { $mod = $mod -bor 1 }
    if ($chkShift.Checked) { $mod = $mod -bor 4 }
    if ($chkWin.Checked) { $mod = $mod -bor 8 }
    $shown = Format-Hotkey $chkCtrl.Checked $chkAlt.Checked $chkShift.Checked $chkWin.Checked $key
    if ($vk -eq 0) {
        $lblHotkey.Text = "请选择一个按键"
        $lblHotkey.ForeColor = [System.Drawing.Color]::FromArgb(190, 55, 55)
        return $false
    }
    if ($vk -lt 112 -and $mod -eq 0) {
        $lblHotkey.Text = "字母键需要配合 Ctrl、Alt、Shift 或 Win"
        $lblHotkey.ForeColor = [System.Drawing.Color]::FromArgb(190, 55, 55)
        return $false
    }
    $ok = $form.BindHotkey([uint32]$mod, [uint32]$vk)
    if (-not $ok) {
        $lblHotkey.Text = "快捷键 $shown 被占用了，换一个"
        $lblHotkey.ForeColor = [System.Drawing.Color]::FromArgb(190, 55, 55)
        return $false
    }
    $lblHotkey.Text = "快捷键已应用：$shown"
    $lblHotkey.ForeColor = [System.Drawing.Color]::FromArgb(34, 150, 96)
    Save-UiConfig
    return $true
}
function Update-HotkeyPreview {
    $key = [string]$cmbKey.SelectedItem
    if (-not $key) { $key = "?" }
    $shown = Format-Hotkey $chkCtrl.Checked $chkAlt.Checked $chkShift.Checked $chkWin.Checked $key
    $lblHotkey.Text = "按键预览：$shown"
    $lblHotkey.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
}

function Get-RunDuration {
    if (-not $script:RunStartedAt) { return "00:00:00" }
    $elapsed = (Get-Date) - $script:RunStartedAt
    $hours = [int][Math]::Floor($elapsed.TotalHours)
    return ("{0:00}:{1:00}:{2:00}" -f $hours, $elapsed.Minutes, $elapsed.Seconds)
}
function Show-CompletionNotification([bool]$Success, [string]$Message) {
    if (-not $script:NotifyIcon) { return }
    $script:NotifyIcon.BalloonTipTitle = if ($Success) { "一键保存发布自测：完成" } else { "一键保存发布自测：失败" }
    if (-not $Message) { $Message = if ($Success) { "所有步骤已完成。" } else { "任务失败，请打开小程序查看日志。" } }
    if ($Message.Length -gt 220) { $Message = $Message.Substring(0, 220) + "…" }
    $script:NotifyIcon.BalloonTipText = $Message
    $script:NotifyIcon.BalloonTipIcon = if ($Success) { [System.Windows.Forms.ToolTipIcon]::Info } else { [System.Windows.Forms.ToolTipIcon]::Error }
    $script:NotifyIcon.ShowBalloonTip(7000)
}

function Sync-Progress {
    if ($script:Worker -and $script:Worker.HasExited) {
        $code = $script:Worker.ExitCode
        $script:Worker = $null
        Set-ForegroundLock $false
        Set-RunButtons $false
        $tail = Read-SharedText $script:ProgressPath
        $pct = $bar.Value
        $detail = ""
        if ($tail -match '^(\d+)\|(.*)$') {
            $pct = [int]$Matches[1]
            $detail = $Matches[2]
        }
        $elapsed = Get-RunDuration
        if ($code -eq 0) {
            if (-not $detail) { $detail = "全部步骤已完成" }
            Set-PhaseLabel 100 $detail $false
            Show-CompletionNotification $true ("本次耗时：{0}；{1}" -f $elapsed, $detail)
            $script:LastLog = "任务完成；本次耗时：$elapsed"
        } else {
            if (-not $detail) { $detail = "失败，退出码 $code" }
            Set-PhaseLabel $pct $detail $true
            Show-CompletionNotification $false ("本次耗时：{0}；{1}" -f $elapsed, $detail)
            $script:LastLog = "任务失败；本次耗时：$elapsed"
        }
        $txtLog.Text = $script:LastLog
        $script:RunStartedAt = $null
        $bar.Value = 0
    } elseif ($script:Running) {
        $tail = Read-SharedText $script:ProgressPath
        if ($tail -match '^(\d+)\|(.*)$') {
            $failed = $Matches[2].StartsWith("失败")
            Set-PhaseLabel ([int]$Matches[1]) $Matches[2] $failed
        }
    }
    if ($script:Running) {
        $log = Read-SharedText $script:LogPath
        if ($log -and $log -ne $script:LastLog) {
            $script:LastLog = $log
            $txtLog.Text = $log.TrimEnd()
            $txtLog.SelectionStart = $txtLog.TextLength
            $txtLog.ScrollToCaret()
        }
    }
}

$cfg = Read-UiConfig
$script:WorkRoot = [string]$cfg.WorkRoot

$form = New-Object OneClickForm
$form.Text = "MCSTestHelper"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(1180, 700)
$form.MinimumSize = New-Object System.Drawing.Size(1120, 620)
$form.BackColor = [System.Drawing.Color]::White
$form.ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
$form.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
$script:AppIcon = $null
$iconPath = Join-Path $PSScriptRoot "MCSTestHelper.ico"
if (Test-Path -LiteralPath $iconPath) {
    try {
        $script:AppIcon = New-Object System.Drawing.Icon($iconPath)
        $form.Icon = $script:AppIcon
    } catch {
        $script:AppIcon = $null
    }
}
$script:NotifyIcon = New-Object System.Windows.Forms.NotifyIcon
$script:NotifyIcon.Icon = if ($script:AppIcon) { $script:AppIcon } else { [System.Drawing.SystemIcons]::Application }
$script:NotifyIcon.Text = "MCSTestHelper"
$script:NotifyIcon.Visible = $true
$script:NotifyIcon.Add_DoubleClick({
    $form.Show()
    $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    $form.Activate()
})

$header = New-Object System.Windows.Forms.Panel
$header.Dock = "Top"
$header.Height = 60
$header.BackColor = [System.Drawing.Color]::FromArgb(31, 31, 36)
$form.Controls.Add($header)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "MCSTestHelper"
$lblTitle.ForeColor = [System.Drawing.Color]::White
$lblTitle.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 16, [System.Drawing.FontStyle]::Bold)
$lblTitle.AutoSize = $true
$lblTitle.Location = New-Object System.Drawing.Point(20, 12)
$header.Controls.Add($lblTitle)
$btnAppSettings = New-Object System.Windows.Forms.Button
$btnAppSettings.Text = "⌨"
$btnAppSettings.Size = New-Object System.Drawing.Size(34, 34)
$btnAppSettings.Location = New-Object System.Drawing.Point(310, 12)
$btnAppSettings.FlatStyle = "Flat"
$btnAppSettings.FlatAppearance.BorderSize = 0
$btnAppSettings.BackColor = [System.Drawing.Color]::FromArgb(31, 31, 36)
$btnAppSettings.ForeColor = [System.Drawing.Color]::White
$btnAppSettings.Font = New-Object System.Drawing.Font("Segoe UI Symbol", 12)
$appToolTip = New-Object System.Windows.Forms.ToolTip
$appToolTip.SetToolTip($btnAppSettings, "快捷键设置")
$header.Controls.Add($btnAppSettings)
$btnWorkRoot = New-Object System.Windows.Forms.Button
$btnWorkRoot.Text = "⚙"
$btnWorkRoot.Size = New-Object System.Drawing.Size(34, 34)
$btnWorkRoot.Location = New-Object System.Drawing.Point(350, 12)
$btnWorkRoot.FlatStyle = "Flat"
$btnWorkRoot.FlatAppearance.BorderSize = 0
$btnWorkRoot.BackColor = [System.Drawing.Color]::FromArgb(31, 31, 36)
$btnWorkRoot.ForeColor = [System.Drawing.Color]::White
$btnWorkRoot.Font = New-Object System.Drawing.Font("Segoe UI Symbol", 12)
$btnWorkRoot.AccessibleName = "设置"
$workRootToolTip = New-Object System.Windows.Forms.ToolTip
$workRootToolTip.SetToolTip($btnWorkRoot, "设置")
$header.Controls.Add($btnWorkRoot)
$btnHelp = New-Object System.Windows.Forms.Button
$btnHelp.Text = "?"
$btnHelp.Size = New-Object System.Drawing.Size(34, 34)
$btnHelp.Location = New-Object System.Drawing.Point(390, 12)
$btnHelp.FlatStyle = "Flat"
$btnHelp.FlatAppearance.BorderSize = 0
$btnHelp.BackColor = [System.Drawing.Color]::FromArgb(31, 31, 36)
$btnHelp.ForeColor = [System.Drawing.Color]::White
$btnHelp.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$header.Controls.Add($btnHelp)


$body = New-Object System.Windows.Forms.Panel
$body.Dock = "Fill"
$body.Padding = New-Object System.Windows.Forms.Padding(16, 12, 16, 12)
$body.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($body)
$body.BringToFront()

$top = New-Object System.Windows.Forms.Panel
$top.Dock = "Top"
$top.Height = 220
$top.BackColor = [System.Drawing.Color]::White
$body.Controls.Add($top)

$lblPick = New-Object System.Windows.Forms.Label
$lblPick.Text = "开发动态"
$lblPick.AutoSize = $true
$lblPick.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9, [System.Drawing.FontStyle]::Bold)
$lblPick.ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
$lblPick.BackColor = [System.Drawing.Color]::Transparent
$lblPick.Location = New-Object System.Drawing.Point(0, 0)
$top.Controls.Add($lblPick)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "↻"
$btnRefresh.Size = New-Object System.Drawing.Size(32, 26)
$btnRefresh.Anchor = "Top,Right"
$btnRefresh.FlatStyle = "Flat"
$btnRefresh.BackColor = [System.Drawing.Color]::White
$btnRefresh.ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
$btnRefresh.Font = New-Object System.Drawing.Font("Segoe UI Symbol", 12)
$btnRefresh.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
$refreshButtonTip = New-Object System.Windows.Forms.ToolTip
$refreshButtonTip.SetToolTip($btnRefresh, "刷新项目列表")
$top.Controls.Add($btnRefresh)
$btnProjectSettings = New-Object System.Windows.Forms.Button
$btnProjectSettings.Text = "✎"
$btnProjectSettings.Size = New-Object System.Drawing.Size(32, 26)
$btnProjectSettings.Visible = $false
$btnProjectSettings.Anchor = "Top,Right"
$btnProjectSettings.FlatStyle = "Flat"
$btnProjectSettings.BackColor = [System.Drawing.Color]::White
$btnProjectSettings.ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
$btnProjectSettings.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
$btnProjectSettings.Font = New-Object System.Drawing.Font("Segoe UI Symbol", 10)
$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.SetToolTip($btnProjectSettings, "编辑所选项目设置")
$top.Controls.Add($btnProjectSettings)

$lv = New-Object System.Windows.Forms.ListView
$lv.View = "Details"
$lv.FullRowSelect = $true
$lv.HideSelection = $false
$lv.MultiSelect = $false
$lv.GridLines = $false
$lv.BorderStyle = "FixedSingle"
$lv.OwnerDraw = $true
$lv.BackColor = [System.Drawing.Color]::White
$lv.ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
$lv.HeaderStyle = "Nonclickable"
$lv.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
$lv.Anchor = "Top,Left,Right"
$lv.Location = New-Object System.Drawing.Point(0, 28)
$lv.Size = New-Object System.Drawing.Size(670, 125)
[void]$lv.Columns.Add("项目", 300)
[void]$lv.Columns.Add("分类", 100)
[void]$lv.Columns.Add("绑定46ID", 300)
[void]$lv.Columns.Add("最近保存", 190)

$top.Controls.Add($lv)
$lv.Add_DrawColumnHeader({
    param($sender, $e)
    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $e.Graphics.FillRectangle($brush, $e.Bounds)
    $brush.Dispose()
    $rect = $e.Bounds
    $rect.X += 8
    $rect.Width -= 12
    $flags = [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::Left -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis -bor [System.Windows.Forms.TextFormatFlags]::NoPrefix
    [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $e.Header.Text, $lv.Font, $rect, [System.Drawing.Color]::FromArgb(32, 32, 32), $flags)
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(210, 210, 210))
    $e.Graphics.DrawLine($pen, $e.Bounds.Left, $e.Bounds.Bottom - 1, $e.Bounds.Right, $e.Bounds.Bottom - 1)
    $pen.Dispose()
})
$lv.Add_DrawItem({ param($sender, $e) })
$lv.Add_DrawSubItem({
    param($sender, $e)
    if ($e.Item.Selected) {
        $back = [System.Drawing.Color]::FromArgb(43, 91, 133)
        $fore = [System.Drawing.Color]::White
    } elseif (($e.ItemIndex % 2) -eq 0) {
        $back = [System.Drawing.Color]::White
        $fore = [System.Drawing.Color]::FromArgb(32, 32, 32)
    } else {
        $back = [System.Drawing.Color]::FromArgb(245, 245, 245)
        $fore = [System.Drawing.Color]::FromArgb(32, 32, 32)
    }
    $brush = New-Object System.Drawing.SolidBrush($back)
    $e.Graphics.FillRectangle($brush, $e.Bounds)
    $brush.Dispose()
    $rect = $e.Bounds
    $rect.X += 8
    $rect.Width -= 12
    $flags = [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::Left -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis -bor [System.Windows.Forms.TextFormatFlags]::NoPrefix
    [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $e.SubItem.Text, $lv.Font, $rect, $fore, $flags)
})

$appSettings = New-Object System.Windows.Forms.Form
$appSettings.Text = "快捷键设置"
$appSettings.StartPosition = "CenterParent"
$appSettings.FormBorderStyle = "FixedDialog"
$appSettings.MaximizeBox = $false
$appSettings.MinimizeBox = $false
$appSettings.ShowInTaskbar = $false
$appSettings.ClientSize = New-Object System.Drawing.Size(470, 220)
$appSettings.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
$appSettings.BackColor = [System.Drawing.Color]::White
$appSettings.ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
$appSettings.Add_Shown({ Set-DarkTitleBar $appSettings })

$lblKey = New-Object System.Windows.Forms.Label
$lblKey.Text = "启动快捷键"
$lblKey.AutoSize = $true
$lblKey.BackColor = [System.Drawing.Color]::Transparent
$lblKey.ForeColor = $appSettings.ForeColor
$lblKey.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10, [System.Drawing.FontStyle]::Bold)
$lblKey.Location = New-Object System.Drawing.Point(20, 18)
$appSettings.Controls.Add($lblKey)

$chkCtrl = New-Object System.Windows.Forms.CheckBox
$chkCtrl.Text = "Ctrl"
$chkCtrl.AutoSize = $true
$chkCtrl.BackColor = $appSettings.BackColor
$chkCtrl.ForeColor = $appSettings.ForeColor
$chkCtrl.Location = New-Object System.Drawing.Point(20, 54)
$chkCtrl.Checked = [bool]$cfg.Ctrl
$appSettings.Controls.Add($chkCtrl)

$chkAlt = New-Object System.Windows.Forms.CheckBox
$chkAlt.Text = "Alt"
$chkAlt.AutoSize = $true
$chkAlt.BackColor = $appSettings.BackColor
$chkAlt.ForeColor = $appSettings.ForeColor
$chkAlt.Location = New-Object System.Drawing.Point(84, 54)
$chkAlt.Checked = [bool]$cfg.Alt
$appSettings.Controls.Add($chkAlt)

$chkShift = New-Object System.Windows.Forms.CheckBox
$chkShift.Text = "Shift"
$chkShift.AutoSize = $true
$chkShift.BackColor = $appSettings.BackColor
$chkShift.ForeColor = $appSettings.ForeColor
$chkShift.Location = New-Object System.Drawing.Point(148, 54)
$chkShift.Checked = [bool]$cfg.Shift
$appSettings.Controls.Add($chkShift)

$chkWin = New-Object System.Windows.Forms.CheckBox
$chkWin.Text = "Win"
$chkWin.AutoSize = $true
$chkWin.BackColor = $appSettings.BackColor
$chkWin.ForeColor = $appSettings.ForeColor
$chkWin.Location = New-Object System.Drawing.Point(220, 54)
$chkWin.Checked = [bool]$cfg.Win
$appSettings.Controls.Add($chkWin)

$cmbKey = New-Object System.Windows.Forms.ComboBox
$cmbKey.DropDownStyle = "DropDownList"
$cmbKey.BackColor = [System.Drawing.Color]::White
$cmbKey.ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
$cmbKey.Location = New-Object System.Drawing.Point(300, 50)
$cmbKey.Size = New-Object System.Drawing.Size(110, 28)
$keyNames = @()
1..12 | ForEach-Object { $keyNames += "F$_" }
65..90 | ForEach-Object { $keyNames += [string][char]$_ }
$cmbKey.Items.AddRange($keyNames)
$picked = $cfg.Key
if (-not $picked -or -not $cmbKey.Items.Contains($picked)) { $picked = "F8" }
$cmbKey.SelectedItem = $picked
$appSettings.Controls.Add($cmbKey)

$lblHotkey = New-Object System.Windows.Forms.Label
$lblHotkey.AutoSize = $false
$lblHotkey.BackColor = [System.Drawing.Color]::Transparent
$lblHotkey.Location = New-Object System.Drawing.Point(20, 96)
$lblHotkey.Size = New-Object System.Drawing.Size(427, 24)
$lblHotkey.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
$appSettings.Controls.Add($lblHotkey)

$btnHotkey = New-Object System.Windows.Forms.Button
$btnHotkey.Text = "应用快捷键"
$btnHotkey.Size = New-Object System.Drawing.Size(130, 32)
$btnHotkey.Location = New-Object System.Drawing.Point(20, 130)
$btnHotkey.FlatStyle = "Flat"
$btnHotkey.BackColor = [System.Drawing.Color]::FromArgb(41, 111, 214)
$btnHotkey.ForeColor = [System.Drawing.Color]::White
$btnHotkey.FlatAppearance.BorderSize = 0
$appSettings.Controls.Add($btnHotkey)

$btnSettingsClose = New-Object System.Windows.Forms.Button
$btnSettingsClose.Text = "关闭"
$btnSettingsClose.Size = New-Object System.Drawing.Size(82, 30)
$btnSettingsClose.Location = New-Object System.Drawing.Point(365, 175)
$btnSettingsClose.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$btnSettingsClose.FlatStyle = "Flat"
$btnSettingsClose.FlatAppearance.BorderSize = 0
$btnSettingsClose.BackColor = [System.Drawing.Color]::White
$btnSettingsClose.ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
$appSettings.Controls.Add($btnSettingsClose)
$appSettings.CancelButton = $btnSettingsClose
$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "▶"
$btnStart.Size = New-Object System.Drawing.Size(42, 36)
$btnStart.Location = New-Object System.Drawing.Point(0, 169)
$btnStart.FlatStyle = "Flat"
$btnStart.FlatAppearance.BorderSize = 0
$btnStart.FlatAppearance.MouseOverBackColor = $top.BackColor
$btnStart.BackColor = $top.BackColor
$btnStart.ForeColor = [System.Drawing.Color]::FromArgb(32, 150, 96)
$btnStart.Font = New-Object System.Drawing.Font("Segoe UI Symbol", 17, [System.Drawing.FontStyle]::Bold)
$top.Controls.Add($btnStart)
$runButtonTip = New-Object System.Windows.Forms.ToolTip
$runButtonTip.SetToolTip($btnStart, "开始任务")
$bar = New-Object System.Windows.Forms.ProgressBar
$bar.Location = New-Object System.Drawing.Point(54, 176)
$bar.Size = New-Object System.Drawing.Size(240, 22)
$bar.Visible = $false
$bar.Anchor = "Top,Left"
$bar.Minimum = 0
$bar.Maximum = 100
$bar.BackColor = [System.Drawing.Color]::White
$bar.ForeColor = [System.Drawing.Color]::FromArgb(34, 160, 107)
$top.Controls.Add($bar)

$lblPhase = New-Object System.Windows.Forms.Label
$lblPhase.AutoSize = $false
$lblPhase.Dock = "Top"
$lblPhase.Height = 28
$lblPhase.TextAlign = "MiddleLeft"
$lblPhase.BackColor = [System.Drawing.Color]::White
$lblPhase.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9, [System.Drawing.FontStyle]::Bold)
$lblPhase.Text = "就绪。选中项目后点击开始。"
$body.Controls.Add($lblPhase)
$lblPhase.BringToFront()

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Dock = "Fill"
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = "Vertical"
$txtLog.BorderStyle = "FixedSingle"
$txtLog.BackColor = [System.Drawing.Color]::White
$txtLog.ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
$txtLog.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
$txtLog.HideSelection = $false
$body.Controls.Add($txtLog)
$txtLog.BringToFront()

$toastPanel = New-Object System.Windows.Forms.Panel
$toastPanel.Size = New-Object System.Drawing.Size(260, 56)
$toastPanel.BackColor = [System.Drawing.Color]::White
$toastPanel.BorderStyle = "FixedSingle"
$toastPanel.Visible = $false
$toastPanel.Anchor = "None"
$toastAccent = New-Object System.Windows.Forms.Panel
$toastAccent.Location = New-Object System.Drawing.Point(0, 0)
$toastAccent.Size = New-Object System.Drawing.Size(5, 54)
$toastAccent.BackColor = [System.Drawing.Color]::FromArgb(34, 160, 107)
$toastPanel.Controls.Add($toastAccent)
$toastIcon = New-Object System.Windows.Forms.Label
$toastIcon.Text = "✓"
$toastIcon.AutoSize = $false
$toastIcon.TextAlign = "MiddleCenter"
$toastIcon.Location = New-Object System.Drawing.Point(16, 12)
$toastIcon.Size = New-Object System.Drawing.Size(30, 30)
$toastIcon.ForeColor = [System.Drawing.Color]::FromArgb(34, 160, 107)
$toastIcon.Font = New-Object System.Drawing.Font("Segoe UI Symbol", 16, [System.Drawing.FontStyle]::Bold)
$toastIcon.BackColor = [System.Drawing.Color]::Transparent
$toastPanel.Controls.Add($toastIcon)
$toastMessage = New-Object System.Windows.Forms.Label
$toastMessage.Text = "项目列表已刷新"
$toastMessage.AutoSize = $false
$toastMessage.TextAlign = "MiddleLeft"
$toastMessage.Location = New-Object System.Drawing.Point(54, 12)
$toastMessage.Size = New-Object System.Drawing.Size(190, 30)
$toastMessage.ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
$toastMessage.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10, [System.Drawing.FontStyle]::Bold)
$toastMessage.BackColor = [System.Drawing.Color]::Transparent
$toastPanel.Controls.Add($toastMessage)
$form.Controls.Add($toastPanel)
$toastTimer = New-Object System.Windows.Forms.Timer
$toastTimer.Interval = 1500
$toastTimer.Add_Tick({
    $toastTimer.Stop()
    $toastPanel.Visible = $false
})

function Show-RefreshToast {
    $toastTimer.Stop()
    $toastPanel.Left = [Math]::Max(0, [int](($form.ClientSize.Width - $toastPanel.Width) / 2))
    $toastPanel.Top = [Math]::Max(0, [int](($form.ClientSize.Height - $toastPanel.Height) / 2))
    $toastPanel.Visible = $true
    $toastPanel.BringToFront()
    $toastTimer.Start()
}

$btnRefresh.Add_Click({
    $prefer = ""
    $preferType = "map"
    if ($lv.SelectedItems.Count -gt 0) {
        $prefer = [string]$lv.SelectedItems[0].Tag.Name
        $preferType = [string]$lv.SelectedItems[0].SubItems[1].Text
    }
    Update-ProjectList $prefer $preferType
    Set-PhaseLabel 0 "项目列表已刷新" $false
    Show-RefreshToast
})
$btnStart.Add_Click({
    if ($script:Running) { Stop-Run } else { Start-Run }
})
$btnHotkey.Add_Click({ [void](Update-Hotkey) })
$chkCtrl.Add_CheckedChanged({ Update-HotkeyPreview })
$chkAlt.Add_CheckedChanged({ Update-HotkeyPreview })
$chkShift.Add_CheckedChanged({ Update-HotkeyPreview })
$chkWin.Add_CheckedChanged({ Update-HotkeyPreview })
$cmbKey.Add_SelectedIndexChanged({ Update-HotkeyPreview })
$btnHelp.Add_Click({
    $helpForm = New-Object System.Windows.Forms.Form
    $helpForm.Text = "使用说明"
    $helpForm.StartPosition = "CenterParent"
    $helpForm.FormBorderStyle = "FixedDialog"
    $helpForm.MaximizeBox = $false
    $helpForm.MinimizeBox = $false
    $helpForm.ShowInTaskbar = $false
    $helpForm.ClientSize = New-Object System.Drawing.Size(1040, 520)
    $helpForm.BackColor = [System.Drawing.Color]::White
    $helpForm.ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
    $helpForm.Add_Shown({ Set-DarkTitleBar $helpForm })
    $helpRich = New-Object System.Windows.Forms.RichTextBox
    $helpRich.Location = New-Object System.Drawing.Point(36, 36)
    $helpRich.Size = New-Object System.Drawing.Size(968, 356)
    $helpRich.ReadOnly = $true
    $helpRich.BorderStyle = "None"
    $helpRich.BackColor = $helpForm.BackColor
    $helpRich.Rtf = '{\rtf1\ansi\deff0{\fonttbl{\f0\fnil Microsoft YaHei UI;}{\f1\fnil Segoe UI Symbol;}}{\colortbl ;\red32\green150\blue96;\red196\green64\blue58;\red32\green32\blue32;}\viewkind4\uc1\pard\f0\fs28\b\cf3 我的世界MCStudio自测助手\b0\fs20\par\par 本软件用于自动保存、发布 MCStudio 项目并发起自测。\par\par 选中项目并绑定 46 开头的作品 ID 后，点击 \f1\b\cf1 \u9654? \f0\b0\cf3 开始任务；运行时点击 \f1\b\cf2 \u9632? \f0\b0\cf3 停止任务。\par\par 项目设置可选择“免机审自测”或“机审自测”。\par\par 项目设置中的发布匹配关键词用于在发布作品列表里匹配实际作品名称。当启动器项目名和作品资源名不同时，填写能搜到该作品的关键词；留空时使用项目名。\par\par 点击键盘图标可设置快捷键。\par\par 点击设置图标可配置 MCStudio 工作目录。\par\par 作者：FxShadow\par}'
    $helpForm.Controls.Add($helpRich)
    $helpClose = New-Object System.Windows.Forms.Button
    $helpClose.Text = "关闭"
    $helpClose.Size = New-Object System.Drawing.Size(164, 60)
    $helpClose.Location = New-Object System.Drawing.Point(840, 428)
    $helpClose.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $helpClose.FlatStyle = "Flat"
    $helpClose.FlatAppearance.BorderSize = 0
    $helpClose.BackColor = [System.Drawing.Color]::White
    $helpClose.ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
    $helpForm.Controls.Add($helpClose)
    $helpForm.AcceptButton = $helpClose
    [void]$helpForm.ShowDialog($form)
})

$lv.Add_SelectedIndexChanged({
    $btnProjectSettings.Visible = ($lv.SelectedItems.Count -gt 0)
    Save-UiConfig
})
$btnProjectSettings.Add_Click({ Show-ProjectSettings })
$btnAppSettings.Add_Click({ [void]$appSettings.ShowDialog($form) })
$btnWorkRoot.Add_Click({
    $workSettings = New-Object System.Windows.Forms.Form
    $workSettings.Text = "设置"
    $workSettings.StartPosition = "CenterParent"
    $workSettings.FormBorderStyle = "FixedDialog"
    $workSettings.MaximizeBox = $false
    $workSettings.MinimizeBox = $false
    $workSettings.ShowInTaskbar = $false
    $workSettings.ClientSize = New-Object System.Drawing.Size(600, 170)
    $workSettings.BackColor = [System.Drawing.Color]::White
    $workSettings.ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
    $workSettings.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
    $workSettings.Add_Shown({ Set-DarkTitleBar $workSettings })

    $pathLabel = New-Object System.Windows.Forms.Label
    $pathLabel.Text = "MCStudio 工作目录"
    $pathLabel.Location = New-Object System.Drawing.Point(20, 18)
    $pathLabel.Size = New-Object System.Drawing.Size(250, 24)
    $workSettings.Controls.Add($pathLabel)

    $pathBox = New-Object System.Windows.Forms.TextBox
    $pathBox.Text = $script:WorkRoot
    $pathBox.Location = New-Object System.Drawing.Point(20, 48)
    $pathBox.Size = New-Object System.Drawing.Size(450, 28)
    $pathBox.BackColor = [System.Drawing.Color]::White
    $pathBox.ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
    $workSettings.Controls.Add($pathBox)

    $browsePath = New-Object System.Windows.Forms.Button
    $browsePath.Text = "浏览..."
    $browsePath.Location = New-Object System.Drawing.Point(480, 46)
    $browsePath.Size = New-Object System.Drawing.Size(100, 30)
    $browsePath.Add_Click({
        $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderDialog.Description = "选择 MCStudio 工作目录（包含账号文件夹的目录）"
        $folderDialog.ShowNewFolderButton = $false
        if (Test-Path -LiteralPath $pathBox.Text -PathType Container) { $folderDialog.SelectedPath = $pathBox.Text }
        if ($folderDialog.ShowDialog($workSettings) -eq [System.Windows.Forms.DialogResult]::OK) { $pathBox.Text = $folderDialog.SelectedPath }
        $folderDialog.Dispose()
    })
    $workSettings.Controls.Add($browsePath)

    $pathHint = New-Object System.Windows.Forms.Label
    $pathHint.Text = "工作目录只需包含 MCStudio 账号文件夹，项目会由软件自动查找。"
    $pathHint.Location = New-Object System.Drawing.Point(20, 82)
    $pathHint.Size = New-Object System.Drawing.Size(560, 22)
    $pathHint.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
    $workSettings.Controls.Add($pathHint)

    $saveWorkSettings = New-Object System.Windows.Forms.Button
    $saveWorkSettings.Text = "保存"
    $saveWorkSettings.Location = New-Object System.Drawing.Point(390, 120)
    $saveWorkSettings.Size = New-Object System.Drawing.Size(88, 30)
    $saveWorkSettings.BackColor = [System.Drawing.Color]::FromArgb(47, 117, 199)
    $saveWorkSettings.ForeColor = [System.Drawing.Color]::White
    $saveWorkSettings.Add_Click({
        $selectedPath = $pathBox.Text.Trim()
        if (-not (Test-Path -LiteralPath $selectedPath -PathType Container)) {
            [void][System.Windows.Forms.MessageBox]::Show("请选择一个已存在的工作目录。", "路径无效", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        $prefer = ""
        $preferType = "map"
        if ($lv.SelectedItems.Count -gt 0) {
            $prefer = [string]$lv.SelectedItems[0].Tag.Name
            $preferType = [string]$lv.SelectedItems[0].SubItems[1].Text
        }
        $script:WorkRoot = [System.IO.Path]::GetFullPath($selectedPath)
        $workRootToolTip.SetToolTip($btnWorkRoot, "设置`r`n工作目录：$script:WorkRoot")
        Save-UiConfig
        Update-ProjectList $prefer $preferType
        Set-PhaseLabel 0 "工作目录已更新" $false
        $toastMessage.Text = "设置已保存"
        Show-RefreshToast
        $workSettings.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $workSettings.Close()
    })
    $workSettings.Controls.Add($saveWorkSettings)

    $cancelWorkSettings = New-Object System.Windows.Forms.Button
    $cancelWorkSettings.Text = "取消"
    $cancelWorkSettings.Location = New-Object System.Drawing.Point(490, 120)
    $cancelWorkSettings.Size = New-Object System.Drawing.Size(88, 30)
    $cancelWorkSettings.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $workSettings.Controls.Add($cancelWorkSettings)
    $workSettings.AcceptButton = $saveWorkSettings
    $workSettings.CancelButton = $cancelWorkSettings
    [void]$workSettings.ShowDialog($form)
    $workSettings.Dispose()
})
$lv.Add_DoubleClick({ Start-Run })
$form.Add_HotkeyPressed({ Start-Run })
$form.Add_FormClosing({ Save-UiConfig })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 300
$timer.Add_Tick({ Sync-Progress })
$timer.Start()
$form.Add_FormClosed({
    $timer.Stop()
    $toastTimer.Stop()
    $toastTimer.Dispose()
    Set-ForegroundLock $false
    if ($script:NotifyIcon) {
        $script:NotifyIcon.Visible = $false
        $script:NotifyIcon.Dispose()
        $script:NotifyIcon = $null
        if ($script:AppIcon) { $script:AppIcon.Dispose(); $script:AppIcon = $null }
    }
})

$form.Add_Shown({
    Set-DarkTitleBar $form
    $btnRefresh.Left = $top.ClientSize.Width - $btnRefresh.Width
    $btnProjectSettings.Left = $btnRefresh.Left - $btnProjectSettings.Width - 6
    $lv.Width = [Math]::Max(420, $top.ClientSize.Width - $lv.Left - 8)
    Set-ProjectColumnWidths
    $bar.Width = 240
    if ($SelfTest) {
        $script:SuppressSave = $true
        Update-ProjectList ""
        $form.Tag = "{0}|{1}|{2}" -f $lv.Items.Count, $lv.Height, $txtLog.Height
        $form.Close()
        return
    }
    $script:ProjectIds = $cfg.ProjectIds
    $script:ProjectKeywords = $cfg.ProjectKeywords
    $script:ProjectModes = $cfg.ProjectModes
    Update-ProjectList $cfg.MapName $cfg.ProjectType
    [void](Update-Hotkey)
})
$top.Add_Resize({
    $btnRefresh.Left = $top.ClientSize.Width - $btnRefresh.Width
    $btnProjectSettings.Left = $btnRefresh.Left - $btnProjectSettings.Width - 6
    $lv.Width = [Math]::Max(420, $top.ClientSize.Width - $lv.Left - 8)
    Set-ProjectColumnWidths
    $bar.Width = 240
})

if ($SelfTest) {
    $form.Opacity = 0
    $form.ShowInTaskbar = $false
}
[System.Windows.Forms.Application]::Run($form)
if ($script:InstanceMutex) {
    try { $script:InstanceMutex.ReleaseMutex() } catch {}
    $script:InstanceMutex.Dispose()
    $script:InstanceMutex = $null
}
if ($SelfTest) {
    $parts = ([string]$form.Tag) -split '\|'
    $count = 0
    $listH = 0
    $logH = 0
    if ($parts.Length -ge 3) {
        $count = [int]$parts[0]
        $listH = [int]$parts[1]
        $logH = [int]$parts[2]
    }
    $form.Dispose()
    if ($count -lt 1) { throw "没有读到项目" }
    if ($listH -lt 40 -or $logH -lt 40) { throw "窗口布局不正确 list=$listH log=$logH" }
    Write-Output ("projects=" + $count + " list=" + $listH + " log=" + $logH)
    exit 0
}