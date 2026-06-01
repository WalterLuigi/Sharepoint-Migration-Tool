#Requires -Version 7.0
# Build Script for SharePoint Migration Tool
# Creates a clean distribution folder with runtime files in app/ subfolder

param(
    [switch]$Run
)

$ErrorActionPreference = "Stop"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "SharePoint Migration Tool - Build Script" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$projectPath = $PSScriptRoot
$publishPath = Join-Path $projectPath "bin\Release\net8.0-windows\win-x64\publish"
$distPath = Join-Path $projectPath "dist"
$appPath = Join-Path $distPath "app"

# Build the project (self-contained)
Write-Host "Building self-contained application..." -ForegroundColor Yellow
& dotnet publish -c Release -r win-x64 --self-contained true

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "BUILD FAILED!" -ForegroundColor Red
    exit 1
}

Write-Host "Build completed successfully!" -ForegroundColor Green
Write-Host ""

# Create distribution folder
Write-Host "Creating clean distribution package..." -ForegroundColor Yellow

# Remove old dist folder
if (Test-Path $distPath) {
    Remove-Item -Path $distPath -Recurse -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}

# Create directory structure
New-Item -ItemType Directory -Path $distPath -Force | Out-Null
New-Item -ItemType Directory -Path $appPath -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $distPath "PowerShell\modules") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $distPath "config") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $distPath "certs") -Force | Out-Null

# Copy all runtime files to app/ subfolder (EXE, DLLs, language folders)
Get-ChildItem -Path $publishPath | ForEach-Object {
    Copy-Item $_.FullName $appPath -Recurse -Force
}

# Copy PowerShell scripts to root PowerShell/ folder
$powerShellSource = Join-Path $projectPath "PowerShell"
Copy-Item -Path "$powerShellSource\*.ps1" -Destination (Join-Path $distPath "PowerShell") -Force
Copy-Item -Path "$powerShellSource\modules\*.ps1" -Destination (Join-Path $distPath "PowerShell\modules") -Force

# Create config template
$configTemplate = Join-Path $distPath "config\migration-config.json"
@'
{
  "sourceTenant": {
    "tenantId": "",
    "appId": "",
    "thumbprint": ""
  },
  "targetTenant": {
    "tenantId": "",
    "appId": "",
    "thumbprint": ""
  },
  "migration": {
    "sourceSiteUrl": "",
    "targetSiteUrl": "",
    "libraryName": "Documents",
    "tempPath": "./temp"
  }
}
'@ | Out-File -FilePath $configTemplate -Encoding UTF8

# Create launcher batch file
$launcherContent = @'
@echo off
REM SharePoint Migration Tool Launcher
cd /d "%~dp0app"
start "" "SharePointMigrationTool.exe"
'@
$launcherContent | Out-File -FilePath (Join-Path $distPath "SharePoint Migration Tool.bat") -Encoding ASCII

# Create README
@'
# SharePoint Migration Tool

## Quick Start

Double-click `SharePoint Migration Tool.bat` to run the application.

## Folder Structure

```
dist/
├── SharePoint Migration Tool.bat  (run this)
├── README.txt
├── PowerShell/                    (scripts - required)
├── config/                        (configuration)
├── certs/                         (certificate storage)
└── app/                          (runtime files)
    ├── SharePointMigrationTool.exe
    └── *.dll files
```

## Requirements

1. PowerShell 7+ - Download from: https://github.com/PowerShell/PowerShell/releases
2. PnP PowerShell module - Auto-installs from the app

## Distribution

Copy the entire folder. All files and subfolders are required.

## Troubleshooting

If the batch file doesn't work, navigate to the `app` folder and run `SharePointMigrationTool.exe` directly.
'@ | Out-File -FilePath (Join-Path $distPath "README.txt") -Encoding UTF8

# Calculate sizes
$appSize = (Get-ChildItem -Path $appPath -Recurse | Measure-Object -Property Length -Sum).Sum
$totalSize = (Get-ChildItem -Path $distPath -Recurse | Measure-Object -Property Length -Sum).Sum

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "DISTRIBUTION CREATED" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Output: $distPath" -ForegroundColor White
Write-Host ""
Write-Host "Clean folder structure:" -ForegroundColor White
Write-Host "  Root folder:" -ForegroundColor Gray
Write-Host "    - SharePoint Migration Tool.bat  (launcher)" -ForegroundColor Gray
Write-Host "    - README.txt" -ForegroundColor Gray
Write-Host "    - PowerShell/, config/, certs/ folders" -ForegroundColor Gray
Write-Host ""
Write-Host "  app/ folder:" -ForegroundColor Gray
Write-Host "    - SharePointMigrationTool.exe" -ForegroundColor Gray
Write-Host "    - Runtime DLLs and language folders" -ForegroundColor Gray
Write-Host ""
Write-Host "App size: $([math]::Round($appSize / 1MB, 2)) MB" -ForegroundColor White
Write-Host "Total size: $([math]::Round($totalSize / 1MB, 2)) MB" -ForegroundColor White
Write-Host ""
Write-Host "To run: Double-click 'SharePoint Migration Tool.bat'" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Green

if ($Run) {
    Write-Host ""
    Write-Host "Starting application..." -ForegroundColor Yellow
    & (Join-Path $distPath "SharePoint Migration Tool.bat")
}