# sync-bookmarks.ps1
# Syncs Chrome bookmarks to PowerToys Command Palette
# Usage: sync-bookmarks.ps1 [-Silent]
#   Default: interactive profile select, then stops/restarts CmdPal
#   -Silent: uses saved profile selection, just writes the file (for startup task)

param([switch]$Silent)

# --- Config ---
# Top-level folder names to exclude entirely (case-insensitive)
$ExcludeFolders = @("Archive")
# --------------

$configPath  = "$PSScriptRoot\selected-profiles.json"
$cmdpalPath  = "$env:LOCALAPPDATA\Packages\Microsoft.CommandPalette_8wekyb3d8bbwe\LocalState\bookmarks.json"
$chromeRoot  = "$env:LOCALAPPDATA\Google\Chrome\User Data"

# Discover all Chrome profiles that have a bookmarks file
function Get-ChromeProfiles {
    $results = @()
    if (-not (Test-Path $chromeRoot)) { return $results }
    foreach ($dir in Get-ChildItem $chromeRoot -Directory | Where-Object { $_.Name -match "^(Default|Profile \d+)$" }) {
        $bookmarksFile = $null
        if     (Test-Path "$($dir.FullName)\AccountBookmarks") { $bookmarksFile = "$($dir.FullName)\AccountBookmarks" }
        elseif (Test-Path "$($dir.FullName)\Bookmarks")        { $bookmarksFile = "$($dir.FullName)\Bookmarks" }
        else { continue }

        $displayName = $dir.Name
        $email       = ""
        $prefPath    = "$($dir.FullName)\Preferences"
        if (Test-Path $prefPath) {
            try {
                $pref = Get-Content $prefPath -Raw | ConvertFrom-Json
                if ($pref.profile.name)                       { $displayName = $pref.profile.name }
                if ($pref.account_info -and $pref.account_info.Count -gt 0 -and $pref.account_info[0].email) {
                    $email = $pref.account_info[0].email
                }
            } catch {}
        }

        $results += [PSCustomObject]@{
            Id            = $dir.Name
            DisplayName   = $displayName
            Email         = $email
            BookmarksFile = $bookmarksFile
        }
    }
    return $results
}

# Register chrome-profile:// protocol handler for the current user (no admin required)
function Register-ChromeProfileProtocol {
    $handlerPath = "$PSScriptRoot\chrome-profile-handler.ps1"
    $cmd = "powershell.exe -WindowStyle Hidden -NonInteractive -NoProfile -ExecutionPolicy Bypass -File `"$handlerPath`" `"%1`""
    $regBase = "HKCU:\Software\Classes\chrome-profile"
    New-Item -Path $regBase -Force | Out-Null
    Set-ItemProperty -Path $regBase -Name "(default)" -Value "URL:Chrome Profile"
    New-ItemProperty -Path $regBase -Name "URL Protocol" -Value "" -Force | Out-Null
    New-Item -Path "$regBase\shell\open\command" -Force | Out-Null
    Set-ItemProperty -Path "$regBase\shell\open\command" -Name "(default)" -Value $cmd
}

# Recursively flatten bookmark URLs, building a folder path as namespace
function Get-BookmarkUrls($node, $path = "", $profileId = "") {
    if ($node.type -eq "url") {
        $name = if ($path) { "$path / $($node.name)" } else { $node.name }
        $url  = if ($profileId) {
            "chrome-profile://$profileId/$([System.Uri]::EscapeDataString($node.url))"
        } else {
            $node.url
        }
        [PSCustomObject]@{
            Id       = [System.Guid]::NewGuid().ToString()
            Name     = $name
            Bookmark = $url
        }
    }
    if ($node.children) {
        $newPath = if ($path) { "$path / $($node.name)" } else { $node.name }
        foreach ($child in $node.children) {
            Get-BookmarkUrls $child $newPath $profileId
        }
    }
}

$allProfiles = Get-ChromeProfiles

if ($allProfiles.Count -eq 0) {
    if (-not $Silent) {
        Write-Error "No Chrome profiles with bookmarks found under: $chromeRoot"
        Read-Host "Press Enter to exit"
    }
    exit 1
}

# Load saved selection
$savedIds = @()
if (Test-Path $configPath) {
    try { $savedIds = @(Get-Content $configPath -Raw | ConvertFrom-Json) } catch {}
}

if ($Silent) {
    $profilesToSync = $allProfiles | Where-Object { $savedIds -contains $_.Id }
    if (-not $profilesToSync) {
        exit 0
    }
} else {
    # Interactive multi-select - pre-tick saved selection (or all if first run)
    $selected = @{}
    foreach ($p in $allProfiles) {
        $selected[$p.Id] = if ($savedIds.Count -gt 0) { $savedIds -contains $p.Id } else { $true }
    }

    while ($true) {
        Clear-Host
        Write-Host "Sync Chrome bookmarks to Command Palette"
        Write-Host "=========================================`n"
        Write-Host "Type a number to toggle a profile, then press Enter to confirm.`n"
        $i = 1
        foreach ($p in $allProfiles) {
            $check = if ($selected[$p.Id]) { "[X]" } else { "[ ]" }
            $label = if ($p.Email) { "$($p.DisplayName) <$($p.Email)>" } else { $p.DisplayName }
            Write-Host "  $i. $check  $label"
            $i++
        }
        Write-Host ""
        $raw = Read-Host "Toggle (1-$($allProfiles.Count)) or Enter to confirm"
        if ($raw -eq "") { break }
        $num = $raw -as [int]
        if ($num -ge 1 -and $num -le $allProfiles.Count) {
            $id = $allProfiles[$num - 1].Id
            $selected[$id] = -not $selected[$id]
        }
    }

    # Persist selection
    $newIds = @($allProfiles | Where-Object { $selected[$_.Id] } | ForEach-Object { $_.Id })
    $newIds | ConvertTo-Json | Set-Content $configPath -Encoding UTF8

    $profilesToSync = $allProfiles | Where-Object { $selected[$_.Id] }

    if (-not $profilesToSync) {
        Write-Host "No profiles selected - nothing to sync."
        Read-Host "Press Enter to exit"
        exit 0
    }
}

# Build bookmark list from all selected profiles.
# When multiple profiles are selected, prefix names with profile display name
# and use chrome-profile:// URLs so each bookmark opens in the correct profile.
$multiProfile = @($profilesToSync).Count -gt 1
$bookmarks = @()

if ($multiProfile) { Register-ChromeProfileProtocol }

foreach ($chromeProfile in $profilesToSync) {
    $chrome = Get-Content $chromeProfile.BookmarksFile -Raw | ConvertFrom-Json
    $profilePrefix = if ($multiProfile) { $chromeProfile.DisplayName } else { "" }
    $profileId     = if ($multiProfile) { $chromeProfile.Id } else { "" }

    foreach ($rootKey in @("bookmark_bar", "other", "synced")) {
        if (-not $chrome.roots.$rootKey) { continue }
        foreach ($child in $chrome.roots.$rootKey.children) {
            if ($child.type -eq "folder" -and $ExcludeFolders -icontains $child.name) { continue }
            $bookmarks += @(Get-BookmarkUrls $child $profilePrefix $profileId)
        }
    }
}

# Stop CmdPal before writing so it can't overwrite the file on exit
if (-not $Silent) {
    $cmdpalProc = Get-Process -Name "Microsoft.CmdPal.UI" -ErrorAction SilentlyContinue
    if ($cmdpalProc) {
        Write-Host "Stopping Command Palette..."
        Stop-Process -InputObject $cmdpalProc -Force
        $cmdpalProc.WaitForExit(5000) | Out-Null
    }
}

$output = [PSCustomObject]@{ Data = $bookmarks }
$output | ConvertTo-Json -Depth 4 | Set-Content $cmdpalPath -Encoding UTF8

if (-not $Silent) {
    Write-Host "Synced $($bookmarks.Count) bookmarks from $(@($profilesToSync).Count) profile(s)."
    Write-Host "Restarting Command Palette..."
    Start-Process "shell:AppsFolder\Microsoft.CommandPalette_8wekyb3d8bbwe!App"
    Start-Sleep -Milliseconds 500
}

