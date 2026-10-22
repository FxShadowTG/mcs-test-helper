Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("Wscript.Shell")
scriptPath = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "Publish-Ui.ps1")
sh.Run "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File """ & scriptPath & """ -NoConsole", 0, False
