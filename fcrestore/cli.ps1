# FC Restore CLI Download and Run Script
# For Windows PowerShell

param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Base URL for downloads
$BaseUrl = "https://github.com/frappe/fc-scripts/raw/develop/fcrestore/dist"

# Detect architecture
$Arch = $env:PROCESSOR_ARCHITECTURE
switch ($Arch) {
    "AMD64" { $Arch = "amd64" }
    "ARM64" { $Arch = "arm64" }
    default {
        Write-Host "Unsupported architecture: $Arch" -ForegroundColor Red
        Write-Host "Please report this issue at https://support.frappe.io" -ForegroundColor Yellow
        Write-Host "Include the following information:" -ForegroundColor Yellow
        Write-Host "  OS: Windows" -ForegroundColor Yellow
        Write-Host "  Architecture: $Arch" -ForegroundColor Yellow
        exit 1
    }
}

# Construct binary name and download URL
$BinaryName = "fcrestore-windows-${Arch}.exe"
$DownloadUrl = "${BaseUrl}/${BinaryName}"
$LocalPath = Join-Path $env:TEMP $BinaryName

Write-Host "Detected system: Windows/${Arch}" -ForegroundColor Cyan
Write-Host "Downloading fcrestore CLI..." -ForegroundColor Cyan

try {
    # Download the binary
    $ProgressPreference = 'SilentlyContinue'  # Disable progress bar for faster download
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $LocalPath -ErrorAction Stop
    
    Write-Host "Download complete!" -ForegroundColor Green
    Write-Host ""
    
    # Run the binary with all passed arguments
    if ($Arguments) {
        & $LocalPath @Arguments
    } else {
        & $LocalPath
    }
}
catch {
    Write-Host "Failed to download fcrestore binary" -ForegroundColor Red
    Write-Host "URL attempted: $DownloadUrl" -ForegroundColor Red
    Write-Host ""
    Write-Host "This could mean:" -ForegroundColor Yellow
    Write-Host "  • The binary for your platform (Windows/${Arch}) is not available" -ForegroundColor Yellow
    Write-Host "  • There's a network connectivity issue" -ForegroundColor Yellow
    Write-Host "  • Windows Defender or antivirus blocked the download" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Please report this issue at https://support.frappe.io" -ForegroundColor Yellow
    Write-Host "Include the following information:" -ForegroundColor Yellow
    Write-Host "  OS: Windows" -ForegroundColor Yellow
    Write-Host "  Architecture: $Arch" -ForegroundColor Yellow
    Write-Host "  URL: $DownloadUrl" -ForegroundColor Yellow
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Yellow
    exit 1
}