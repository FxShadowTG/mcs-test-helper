# MCSTestHelper

我的世界 MCStudio 自测助手，用于自动保存、发布项目并启动自测。

## 启动

1. 在 Windows 上安装并登录 MCStudio。
2. 将仓库目录放在本机固定位置，双击 `Start-Ui.vbs` 启动图形界面。
3. 首次运行后，在项目设置中为项目绑定以 `46` 开头的作品 ID，再开始任务。

程序默认读取 `D:\MCStudioDownload\work` 下的项目。若目录不同，点击窗口顶部的文件夹图标，在快捷键和使用说明按钮之间选择 MCStudio 工作目录；设置会自动保存。

需要 Windows PowerShell 5.1（系统自带）、Windows Forms 与 UI Automation。运行时配置和日志保存在程序目录中，但不会提交到 Git：`ui-config.json`、`last-run.log`、`run-progress.txt`。

## 文件

- `Start-Ui.vbs`：隐藏 PowerShell 控制台并启动界面。
- `Publish-Ui.ps1`：图形界面、项目设置和快捷键。
- `Publish-SelfTest.ps1`：保存、发布和启动自测的自动化流程。
- `MCSTestHelper.ico` / `MCSTestHelper.png`：程序图标及预览图。

## 使用提示

自动化过程依赖 MCStudio 当前版本的界面和控件；请在任务运行前确认所选项目及绑定 ID 正确。检测到“正在自测”或“正在审核”提示时，任务会停止以避免继续操作。
