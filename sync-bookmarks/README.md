# sync-bookmarks

Syncs your Chrome bookmarks into the [PowerToys Command Palette](https://learn.microsoft.com/en-us/windows/powertoys/command-palette/overview) so you can fuzzy-search them with the same shortcut you use for everything else.

Multi-profile aware: if you sync more than one Chrome profile, each bookmark opens in the correct profile via a `chrome-profile://` protocol handler that registers itself in your user-scope registry (no admin needed).

## Requirements

- Windows 10/11
- Google Chrome
- [PowerToys Command Palette](https://learn.microsoft.com/en-us/windows/powertoys/install) installed (Microsoft Store; usually allowed without admin)

## Install (one paste)

Open **PowerShell** (Win+X → "Terminal" or "Windows PowerShell") and paste:

```powershell
iwr https://raw.githubusercontent.com/LawrenceEaden/scripts/main/sync-bookmarks/install.ps1 | iex
```

That will:

1. Download the scripts to `%LOCALAPPDATA%\Programs\sync-bookmarks\`
2. Create a **sync-bookmarks** Start Menu shortcut
3. Launch the first-time profile picker

No admin rights required at any step.

## Using it

- **Re-sync after adding new bookmarks**: Start Menu → "sync-bookmarks" (or just run it again from PowerShell). Tick/untick profiles by typing their number, hit Enter to confirm.
- **Rename a profile**: in the picker, type `r<n>` (e.g. `r2`) to set a custom display name. Useful when Chrome's profile name is locked by enterprise policy. Blank input resets to the email-domain default.
- **Search bookmarks**: open Command Palette and type to filter. Bookmarks appear under the profile name when you have more than one selected.
- **Exclude folders**: edit `$ExcludeFolders` near the top of `sync-bookmarks.ps1`. Defaults to excluding `Archive`.

Only the **Bookmarks bar** is synced — "Other Bookmarks" and "Synced" are skipped. Drop anything you want available in Command Palette onto the bar.

### Folder nesting

Folders on the bookmarks bar become searchable namespaces, joined with `›`. Nesting is preserved at any depth.

Chrome bookmarks bar:

```
Work/
├── Tools/
│   ├── Jira
│   └── Confluence
└── Docs/
    └── Onboarding
Personal/
└── Banking
Inbox    (a loose bookmark, no folder)
```

Becomes in Command Palette (with one synced profile):

```
Work › Tools › Jira
Work › Tools › Confluence
Work › Docs › Onboarding
Personal › Banking
Inbox
```

When you sync **multiple profiles** the profile name is prepended (e.g. `eaden.co.uk › Work › Tools › Jira`) so identical bookmarks across profiles stay distinct.

Top-level folders listed in `$ExcludeFolders` (default: `Archive`) are skipped entirely along with everything inside them — useful for keeping a hide-but-don't-delete area on the bar.

## Update

Re-run the install command — it overwrites the scripts in place and keeps your saved profile selection and aliases.

```powershell
iwr https://raw.githubusercontent.com/LawrenceEaden/scripts/main/sync-bookmarks/install.ps1 | iex
```

## Uninstall

```powershell
Remove-Item -Recurse "$env:LOCALAPPDATA\Programs\sync-bookmarks"
Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\sync-bookmarks.lnk"
Remove-Item -Recurse "HKCU:\Software\Classes\chrome-profile" -ErrorAction SilentlyContinue
Remove-Item "$env:LOCALAPPDATA\Packages\Microsoft.CommandPalette_8wekyb3d8bbwe\LocalState\bookmarks.json" -ErrorAction SilentlyContinue
```
