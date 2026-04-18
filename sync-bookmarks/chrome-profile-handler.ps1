param([string]$Uri)

# Parses chrome-profile://<ProfileDir>/<encoded-url> and opens in the correct Chrome profile
$parsed     = [System.Uri]$Uri
$profileDir = $parsed.Host
$encodedUrl = $parsed.PathAndQuery.TrimStart('/')
$url        = [System.Uri]::UnescapeDataString($encodedUrl)

$chromePath = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe" -ErrorAction SilentlyContinue).'(default)'
if (-not $chromePath -or -not (Test-Path $chromePath)) { $chromePath = "chrome.exe" }

Start-Process $chromePath "--profile-directory=`"$profileDir`" `"$url`""
