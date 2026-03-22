# sync-bookmarks.ps1
# Syncs Chrome bookmarks (Google account-synced) to PowerToys Command Palette
# Usage: sync-bookmarks.ps1 [-Silent]
#   Default: stops/restarts CmdPal (use when running manually mid-session)
#   -Silent: just writes the file, no CmdPal restart (use for startup task)

param([switch]$Silent)

# --- Config ---
# Top-level folder names to exclude entirely (case-insensitive)
$ExcludeFolders = @("Archive")
# --------------

$chromePath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\AccountBookmarks"
$cmdpalPath = "$env:LOCALAPPDATA\Packages\Microsoft.CommandPalette_8wekyb3d8bbwe\LocalState\bookmarks.json"

if (-not (Test-Path $chromePath)) {
    if (-not $Silent) {
        Write-Error "Chrome AccountBookmarks not found at: $chromePath"
        Read-Host "Press Enter to exit"
    }
    exit 1
}

# Recursively flatten bookmark URLs, building a folder path as namespace
function Get-BookmarkUrls($node, $path = "") {
    if ($node.type -eq "url") {
        $name = if ($path) { "$path / $($node.name)" } else { $node.name }
        [PSCustomObject]@{
            Id       = [System.Guid]::NewGuid().ToString()
            Name     = $name
            Bookmark = $node.url
        }
    }
    if ($node.children) {
        $newPath = if ($path) { "$path / $($node.name)" } else { $node.name }
        foreach ($child in $node.children) {
            Get-BookmarkUrls $child $newPath
        }
    }
}

$chrome = Get-Content $chromePath -Raw | ConvertFrom-Json

$bookmarks = @()
foreach ($rootKey in @("bookmark_bar", "other", "synced")) {
    if (-not $chrome.roots.$rootKey) { continue }
    foreach ($child in $chrome.roots.$rootKey.children) {
        # Skip excluded top-level folders
        if ($child.type -eq "folder" -and $ExcludeFolders -contains $child.name) { continue }
        $bookmarks += @(Get-BookmarkUrls $child)
    }
}

# Write bookmarks.json
# In silent mode: just write the file (CmdPal reads it fresh on next launch)
# In normal mode: stop CmdPal first so it doesn't overwrite our changes on exit
if (-not $Silent) {
    $cmdpalProc = Get-Process -Name "Microsoft.CmdPal.UI" -ErrorAction SilentlyContinue
    if ($cmdpalProc) {
        Write-Host "Stopping Command Palette..."
        Stop-Process -InputObject $cmdpalProc -Force
        # Wait until the process is fully gone so it can't overwrite our file on exit
        $cmdpalProc.WaitForExit(5000) | Out-Null
    }
}

$output = [PSCustomObject]@{ Data = $bookmarks }
$output | ConvertTo-Json -Depth 4 | Set-Content $cmdpalPath -Encoding UTF8

if (-not $Silent) {
    Write-Host "Synced $($bookmarks.Count) bookmarks to Command Palette."
    Write-Host "Restarting Command Palette..."
    Start-Process "shell:AppsFolder\Microsoft.CommandPalette_8wekyb3d8bbwe!App"
    Start-Sleep -Milliseconds 500
}
