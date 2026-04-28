# ====================================================================
# Gabooth Assistant - Build Script
# ====================================================================
#
# Modeled on gabooth_selfphoto/build.ps1 but trimmed for this project
# (no sentry, no debug-symbol upload, no auto-updater).
#
# Prerequisites:
#   1. Flutter SDK installed and in PATH
#   2. Inno Setup 6 (ISCC.exe) installed in PATH or a common path
#
# Usage:
#   .\build.ps1
#   .\build.ps1 -SkipClean         # Reuse existing build dir
#   .\build.ps1 -SkipDependencies  # Skip flutter pub get
#   .\build.ps1 -SkipInstaller     # Build the app only, no installer
#
# ====================================================================

param(
    [switch]$SkipClean = $false,
    [switch]$SkipDependencies = $false,
    [switch]$SkipInstaller = $false,
    [string]$BuildMode = "release"
)

function Write-Step {
    param([string]$Message)
    Write-Host "`n[STEP] $Message" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning-Custom {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor White
}

Write-Host "`n" -NoNewline
Write-Host ("=" * 70) -ForegroundColor Magenta
Write-Host "  GABOOTH ASSISTANT - BUILD" -ForegroundColor Magenta
Write-Host ("=" * 70) -ForegroundColor Magenta
Write-Host ""

# Read version from pubspec.yaml
Write-Step "Reading version from pubspec.yaml"
$pubspecContent = Get-Content -Path "pubspec.yaml" -Raw
if ($pubspecContent -match 'version:\s*(\d+\.\d+\.\d+)') {
    $version = $matches[1]
    Write-Success "Version: $version"
} else {
    Write-Error-Custom "Failed to read version from pubspec.yaml"
    exit 1
}

# Step 1: Clean previous build
if (!$SkipClean) {
    Write-Step "Cleaning previous build artifacts"
    if (Test-Path "build") {
        Remove-Item -Path "build" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Success "Cleaned build directory"
    }

    flutter clean
    Write-Success "Flutter clean completed"
} else {
    Write-Info "Skipping clean step"
}

# Step 2: Get dependencies
if (!$SkipDependencies) {
    Write-Step "Getting Flutter dependencies"
    flutter pub get
    if ($LASTEXITCODE -ne 0) {
        Write-Error-Custom "Failed to get dependencies"
        exit 1
    }
    Write-Success "Dependencies updated"
} else {
    Write-Info "Skipping dependencies step"
}

# Step 3: Build Windows app
Write-Step "Building Windows app ($BuildMode)"
Write-Host "Executing: flutter build windows --$BuildMode" -ForegroundColor Gray
Write-Host ""

& flutter build windows "--$BuildMode"

if ($LASTEXITCODE -ne 0) {
    Write-Error-Custom "Flutter build failed!"
    exit 1
}

Write-Success "Windows app built successfully"

# Step 4: Create installer with Inno Setup
if (!$SkipInstaller) {
    Write-Step "Creating installer with Inno Setup"

    $innoSetupPath = $null

    Write-Info "Searching for Inno Setup Compiler..."
    $isccCommand = Get-Command "iscc" -ErrorAction SilentlyContinue
    if ($isccCommand) {
        $innoSetupPath = $isccCommand.Source
        Write-Info "Found in PATH: $innoSetupPath"
    }

    if (!$innoSetupPath) {
        $commonPaths = @(
            "D:\Inno Setup 6\ISCC.exe",
            "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
            "C:\Program Files\Inno Setup 6\ISCC.exe",
            "D:\Inno Setup 5\ISCC.exe",
            "C:\Program Files (x86)\Inno Setup 5\ISCC.exe",
            "C:\Program Files\Inno Setup 5\ISCC.exe"
        )

        foreach ($path in $commonPaths) {
            if (Test-Path $path) {
                $innoSetupPath = $path
                Write-Info "Found at: $innoSetupPath"
                break
            }
        }
    }

    if ($innoSetupPath) {
        Write-Success "Inno Setup Compiler found"

        Write-Info "Updating version in build_inno.iss to $version..."
        $innoContent = Get-Content "build_inno.iss" -Raw
        $innoContent = $innoContent -replace '#define MyAppVersion ".*"', "#define MyAppVersion `"$version`""
        Set-Content "build_inno.iss" -Value $innoContent -NoNewline

        Write-Host ""
        Write-Host "Executing: `"$innoSetupPath`" /O+ build_inno.iss" -ForegroundColor Gray
        Write-Host ""

        & $innoSetupPath /O+ "build_inno.iss"

        if ($LASTEXITCODE -eq 0) {
            Write-Success "Installer compiled successfully"

            Write-Host ""
            Write-Info "Renaming installer with version info..."
            if (Test-Path "outputs\GaboothAssistant.exe") {
                $newInstallerName = "GaboothAssistant-$version-Installer.exe"
                if (Test-Path "outputs\$newInstallerName") {
                    Remove-Item "outputs\$newInstallerName" -Force
                }
                Rename-Item "outputs\GaboothAssistant.exe" $newInstallerName
                Write-Success "Renamed to: $newInstallerName"

                $installerPath = "outputs\$newInstallerName"
                if (Test-Path $installerPath) {
                    $installerSize = (Get-Item $installerPath).Length / 1MB
                    Write-Success "Installer: $installerPath"
                    Write-Info "Size: $([math]::Round($installerSize, 2)) MB"
                }
            } else {
                Write-Warning-Custom "Generated installer not found at outputs\GaboothAssistant.exe"
            }
        } else {
            Write-Error-Custom "Installer creation failed"
            exit 1
        }
    } else {
        Write-Warning-Custom "Inno Setup Compiler (ISCC.exe) not found"
        Write-Host ""
        Write-Info "Install Inno Setup from: https://jrsoftware.org/isdl.php"
        Write-Info "Alternative: Open build_inno.iss manually in Inno Setup IDE and compile there"
    }
} else {
    Write-Info "Skipping installer creation (--SkipInstaller flag set)"
}

Write-Host ""
Write-Host ("=" * 70) -ForegroundColor Green
Write-Host "  BUILD COMPLETED" -ForegroundColor Green
Write-Host ("=" * 70) -ForegroundColor Green
Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  - Version: $version" -ForegroundColor White
Write-Host "  - Executable: build\windows\x64\runner\Release\gabooth_assistant.exe" -ForegroundColor White

if (!$SkipInstaller -and (Test-Path "outputs\GaboothAssistant-$version-Installer.exe")) {
    Write-Host "  - Installer: outputs\GaboothAssistant-$version-Installer.exe" -ForegroundColor White
}

Write-Host ""
