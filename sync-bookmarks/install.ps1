# install.ps1 - one-paste installer for sync-bookmarks
# Usage: iwr https://raw.githubusercontent.com/LawrenceEaden/scripts/main/sync-bookmarks/install.ps1 | iex

$ErrorActionPreference = 'Stop'

$dst   = "$env:LOCALAPPDATA\Programs\sync-bookmarks"
$base  = 'https://raw.githubusercontent.com/LawrenceEaden/scripts/main/sync-bookmarks'
$files = @(
    'sync-bookmarks.ps1',
    'sync-bookmarks.bat',
    'sync-bookmarks.ico',
    'chrome-profile-handler.ps1'
)

Write-Host "Installing sync-bookmarks to $dst"
New-Item -Path $dst -ItemType Directory -Force | Out-Null

foreach ($f in $files) {
    Write-Host "  downloading $f"
    Invoke-WebRequest "$base/$f" -OutFile "$dst\$f" -UseBasicParsing
    Unblock-File "$dst\$f"
}

# Start Menu shortcut so they can re-run sync any time
$startMenu = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\sync-bookmarks.lnk"
$wsh = New-Object -ComObject WScript.Shell
$lnk = $wsh.CreateShortcut($startMenu)
$lnk.TargetPath       = "$dst\sync-bookmarks.bat"
$lnk.IconLocation     = "$dst\sync-bookmarks.ico"
$lnk.WorkingDirectory = $dst
$lnk.Save()

Write-Host ""
Write-Host "Installed. Launching first-time profile setup..."
Write-Host ""
& "$dst\sync-bookmarks.bat"
