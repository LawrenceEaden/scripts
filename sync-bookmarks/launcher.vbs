' launcher.vbs - invokes chrome-profile-handler.ps1 with no visible console window.
' powershell.exe -WindowStyle Hidden still briefly flashes a console host;
' wscript.exe with WshShell.Run windowStyle=0 is genuinely silent.

Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
handler   = scriptDir & "\chrome-profile-handler.ps1"

uri = ""
If WScript.Arguments.Count > 0 Then uri = WScript.Arguments(0)

cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & handler & """ """ & uri & """"
sh.Run cmd, 0, False
