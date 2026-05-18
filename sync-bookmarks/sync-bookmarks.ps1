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

        $email    = ""
        $prefPath = "$($dir.FullName)\Preferences"
        if (Test-Path $prefPath) {
            try {
                $pref = Get-Content $prefPath -Raw | ConvertFrom-Json
                if ($pref.account_info -and $pref.account_info.Count -gt 0 -and $pref.account_info[0].email) {
                    $email = $pref.account_info[0].email
                }
            } catch {}
        }

        # profile.name is unreliable: enterprise policy can lock it to the email or a placeholder, so derive default from the email domain instead.
        $defaultName = if ($email -match "@(.+)$") { $Matches[1] } else { $dir.Name }

        $results += [PSCustomObject]@{
            Id            = $dir.Name
            DefaultName   = $defaultName
            Email         = $email
            BookmarksFile = $bookmarksFile
        }
    }
    return $results
}

# Register chrome-profile:// protocol handler for the current user (no admin required)
function Register-ChromeProfileProtocol {
    $handlerPath = "$PSScriptRoot\chrome-profile-handler.ps1"
    $cmd = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$handlerPath`" `"%1`""
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
        $name = if ($path) { "$path › $($node.name)" } else { $node.name }
        $url  = if ($profileId) {
            "chrome-profile:///$([System.Uri]::EscapeDataString($profileId))/$([System.Uri]::EscapeDataString($node.url))"
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
        $newPath = if ($path) { "$path › $($node.name)" } else { $node.name }
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

# Load saved config. Supported formats:
#   legacy: ["Default", "Profile 1"]                                  (array of selected ids)
#   current: { "Default": { "name": "Work" }, "Profile 1": { ... } }  (selected id -> { name })
$savedIds   = @()
$savedNames = @{}
if (Test-Path $configPath) {
    try {
        $raw = Get-Content $configPath -Raw | ConvertFrom-Json
        if ($raw -is [System.Array]) {
            $savedIds = @($raw)
        } elseif ($raw) {
            foreach ($prop in $raw.PSObject.Properties) {
                $savedIds += $prop.Name
                if ($prop.Value -and $prop.Value.name) { $savedNames[$prop.Name] = [string]$prop.Value.name }
            }
        }
    } catch {}
}

$aliases = @{}
foreach ($k in $savedNames.Keys) { $aliases[$k] = $savedNames[$k] }

# Effective display name: alias overrides default-from-domain
function Get-EffectiveName($profile, $aliases) {
    if ($aliases[$profile.Id]) { return $aliases[$profile.Id] }
    return $profile.DefaultName
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
        Write-Host "Type a number to toggle a profile, 'r<n>' to rename, Enter to confirm.`n"
        $i = 1
        foreach ($p in $allProfiles) {
            $check = if ($selected[$p.Id]) { "[X]" } else { "[ ]" }
            $name  = Get-EffectiveName $p $aliases
            $label = if ($p.Email) { "$name <$($p.Email)>" } else { $name }
            Write-Host "  $i. $check  $label"
            $i++
        }
        Write-Host ""
        $rawInput = Read-Host "Toggle (1-$($allProfiles.Count)), r<n> to rename, Enter to confirm"
        if ($rawInput -eq "") { break }
        if ($rawInput -match "^\s*r\s*(\d+)\s*$") {
            $num = [int]$Matches[1]
            if ($num -ge 1 -and $num -le $allProfiles.Count) {
                $target  = $allProfiles[$num - 1]
                $current = Get-EffectiveName $target $aliases
                Write-Host ""
                $new = Read-Host "New name for profile $num (currently '$current'; blank to reset to domain default)"
                if ($new -eq "") { $aliases.Remove($target.Id) | Out-Null } else { $aliases[$target.Id] = $new }
            }
            continue
        }
        $num = $rawInput -as [int]
        if ($num -ge 1 -and $num -le $allProfiles.Count) {
            $id = $allProfiles[$num - 1].Id
            $selected[$id] = -not $selected[$id]
        }
    }

    # Persist as { id: { name } } for every selected profile
    $configOut = [ordered]@{}
    foreach ($p in $allProfiles) {
        if ($selected[$p.Id]) {
            $entry = [ordered]@{}
            if ($aliases[$p.Id]) { $entry["name"] = $aliases[$p.Id] }
            $configOut[$p.Id] = $entry
        }
    }
    ([PSCustomObject]$configOut) | ConvertTo-Json -Depth 4 | Set-Content $configPath -Encoding UTF8

    $profilesToSync = $allProfiles | Where-Object { $selected[$_.Id] }

    if (-not $profilesToSync) {
        Write-Host "No profiles selected - nothing to sync."
        Read-Host "Press Enter to exit"
        exit 0
    }
}

# Use chrome-profile:// URLs whenever multiple Chrome profiles exist, so bookmarks always open in the right profile (not whichever window is focused).
$multiProfile = @($allProfiles).Count -gt 1
$bookmarks = @()

if ($multiProfile) { Register-ChromeProfileProtocol }

foreach ($chromeProfile in $profilesToSync) {
    $chrome = Get-Content $chromeProfile.BookmarksFile -Raw | ConvertFrom-Json
    $profilePrefix = if ($multiProfile -and @($profilesToSync).Count -gt 1) { Get-EffectiveName $chromeProfile $aliases } else { "" }
    $profileId     = if ($multiProfile) { $chromeProfile.Id } else { "" }

    # Only sync the bookmarks bar - "Other Bookmarks" and "Synced" tend to accumulate orphan URLs that aren't intentionally curated.
    if ($chrome.roots.bookmark_bar) {
        foreach ($child in $chrome.roots.bookmark_bar.children) {
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


