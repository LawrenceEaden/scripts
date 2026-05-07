# chrome-profile-handler.ps1
# Invoked via the chrome-profile:// protocol handler registered by sync-bookmarks.ps1
# URL format: chrome-profile:///<profileDir>/<encodedUrl>
# Profile is in the path (not host) so the Uri parser doesn't lowercase it.
param([string]$Uri)

if (-not $Uri) { return }

$prefix = 'chrome-profile:///'
if (-not $Uri.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { return }

$rest = $Uri.Substring($prefix.Length)
$sep  = $rest.IndexOf('/')
if ($sep -lt 0) { return }

$profileDir = [System.Uri]::UnescapeDataString($rest.Substring(0, $sep))
$url        = [System.Uri]::UnescapeDataString($rest.Substring($sep + 1))

$chromePath = 'chrome.exe'
try {
    $item = Get-Item 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe' -ErrorAction Stop
    $val = $item.GetValue('')
    if ($val) { $chromePath = $val }
} catch {}

Start-Process -FilePath $chromePath -ArgumentList ('--profile-directory="{0}" "{1}"' -f $profileDir, $url)
