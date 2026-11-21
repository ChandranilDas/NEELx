<#
.SYNOPSIS
    NEELx for Windows 11 — Official 1-Click Complete Installer & Upgrade-Safe Updater.

.DESCRIPTION
    Downloads the official all-in-one NEELx Windows 11 standalone package from GitHub Releases,
    verifies its public SHA-256 file checksum before extracting, installs app binaries into
    %LOCALAPPDATA%\NEELx-App (zero admin privileges needed), clears Windows Defender Mark-of-the-Web,
    creates a Start Menu shortcut, and explicitly preserves 100% of your DPAPI-encrypted biometric vault
    in %LOCALAPPDATA%\NEELx across every upgrade. Zero secondary downloads required.

.EXAMPLE
    irm https://chandranildas.github.io/NEELx/install.ps1 | iex
#>
[CmdletBinding()]
param(
    [string]$Version = "",
    [switch]$NoLaunch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Repo = "ChandranilDas/NEELx"
$InstallDir = Join-Path $env:LOCALAPPDATA "NEELx-App"
$VaultDir = Join-Path $env:LOCALAPPDATA "NEELx"
$TempDir = Join-Path $env:TEMP ("neelx-install-" + [Guid]::NewGuid().ToString("N"))

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   NEELx for Windows 11 — Installer" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

try {
    # 1. Resolve latest release tag from GitHub API (SemVer-aware with fallback)
    $FallbackVersion = "v2.0.0-beta.11"
    $targetRelease = $null
    if ([string]::IsNullOrWhiteSpace($Version)) {
        Write-Host "Checking latest NEELx release..."
        $headers = @{ "User-Agent" = "NEELx-Windows-Installer"; "Accept" = "application/vnd.github+json" }
        try {
            $latest = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers $headers -ErrorAction SilentlyContinue
            if ($latest -and -not $latest.draft -and $latest.assets.Count -gt 0) {
                $targetRelease = $latest
                $Version = $latest.tag_name
            }
        } catch {}

        if (-not $targetRelease) {
            try {
                $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases?per_page=20" -Headers $headers -ErrorAction SilentlyContinue
                if ($releases) {
                    $validReleases = @($releases | Where-Object { -not $_.draft -and $_.assets.Count -gt 0 })
                    if ($validReleases.Count -gt 0) {
                        $targetRelease = $validReleases | Sort-Object {
                            if ($_.tag_name -match 'v?(\d+)\.(\d+)\.(\d+)(?:-beta\.?(\d+))?') {
                                [int]$matches[1] * 1000000 + [int]$matches[2] * 10000 + [int]$matches[3] * 100 + [int]($matches[4] -as [int])
                            } else { 0 }
                        } -Descending | Select-Object -First 1
                        if ($targetRelease) {
                            $Version = $targetRelease.tag_name
                        }
                    }
                }
            } catch {}
        }

        if (-not $targetRelease -or [string]::IsNullOrWhiteSpace($Version)) {
            $Version = $FallbackVersion
        }
    }

    $targetAsset = $targetRelease.assets | Where-Object { $_.name -like "NEELx-*-windows-x64*.zip" -and $_.name -notlike "*-lite*" } | Select-Object -First 1
    if ($targetAsset) {
        $ZipName = $targetAsset.name
    } else {
        $ZipName = "NEELx-$Version-windows-x64.zip"
    }
    $ShaName = "NEELx-$Version-windows-SHA256SUMS.txt"
    $BaseUrl = "https://github.com/$Repo/releases/download/$Version"

    New-Item -ItemType Directory -Force -Path $TempDir | Out-Null
    $ZipPath = Join-Path $TempDir $ZipName
    $ShaPath = Join-Path $TempDir $ShaName

    Write-Host "Downloading $ZipName ($Version)..." -ForegroundColor White
    Invoke-WebRequest -Uri "$BaseUrl/$ZipName" -OutFile $ZipPath -UseBasicParsing

    # 2. Verify public SHA-256 checksum before extracting
    Write-Host "Verifying SHA-256 integrity checksum..." -ForegroundColor White
    Invoke-WebRequest -Uri "$BaseUrl/$ShaName" -OutFile $ShaPath -UseBasicParsing
    $expectedLine = Get-Content $ShaPath | Where-Object { $_ -match [regex]::Escape($ZipName) } | Select-Object -First 1
    if (-not $expectedLine) {
        throw "Checksum entry for $ZipName not found in $ShaName. Aborting for safety."
    }
    $expectedHash = ($expectedLine.Trim() -split '\s+')[0].ToLowerInvariant()
    $actualHash = (Get-FileHash -Path $ZipPath -Algorithm SHA256).Hash.ToLowerInvariant()

    if ($actualHash -ne $expectedHash) {
        throw "SHA-256 verification FAILED! Expected $expectedHash but got $actualHash. Installation aborted."
    }
    Write-Host "SHA-256 verified: $actualHash" -ForegroundColor Green

    # 3. Stop running NEELx instance cleanly (never touches %LOCALAPPDATA%\NEELx vault)
    Get-Process -Name "NEELx.Windows" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 300

    # 4. Replace app binaries only; preserve DPAPI vault & ONNX models completely
    New-Item -ItemType Directory -Force -Path $VaultDir | Out-Null
    if (Test-Path $InstallDir) {
        Remove-Item -Path $InstallDir -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

    Write-Host "Extracting to $InstallDir..."
    Expand-Archive -Path $ZipPath -DestinationPath $InstallDir -Force

    # Strips Windows Defender Mark-of-the-Web (Zone.Identifier) so SmartScreen never blocks launch
    Write-Host "Unblocking files (clearing SmartScreen Mark-of-the-Web)..."
    Get-ChildItem -Path $InstallDir -Recurse | ForEach-Object { Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue }

    $ExePath = Join-Path $InstallDir "NEELx.Windows.exe"
    if (-not (Test-Path $ExePath)) {
        throw "Expected executable not found at $ExePath."
    }

    # 5. Create Start Menu shortcut with official NEELx icon
    $ProgramsDir = [Environment]::GetFolderPath("Programs")
    $ShortcutPath = Join-Path $ProgramsDir "NEELx.lnk"
    $wsh = New-Object -ComObject WScript.Shell
    $sc = $wsh.CreateShortcut($ShortcutPath)
    $sc.TargetPath = $ExePath
    $sc.WorkingDirectory = $InstallDir
    $sc.IconLocation = "$ExePath,0"
    $sc.Description = "NEELx — Offline 3D Biometric Face Unlock for Windows 11"
    $sc.Save()

    Write-Host ""
    Write-Host "Installed NEELx $Version successfully!" -ForegroundColor Green
    Write-Host "  App binaries : $InstallDir"
    Write-Host "  DPAPI Vault  : $VaultDir (preserved across upgrades)"
    Write-Host "  Start Menu   : $ShortcutPath"
    Write-Host ""

    if (-not $NoLaunch) {
        Write-Host "Launching NEELx..." -ForegroundColor Cyan
        Start-Process -FilePath $ExePath
    }
}
finally {
    if (Test-Path $TempDir) {
        Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
