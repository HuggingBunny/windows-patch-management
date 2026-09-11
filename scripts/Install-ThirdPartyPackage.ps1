<#
.SYNOPSIS
    Hardened 3rd-Party Silent Software Deployment Wrapper.
.DESCRIPTION
    Executes silent installations with MSI mutex lock avoidance (Error 1618),
    verbose logging, strict timeout limits, and explicit exit code translation (including 3010 reboot requests).
.PARAMETER InstallerPath
    Path to the MSI or EXE installer file.
.PARAMETER Arguments
    Command-line arguments to pass to the installer.
.PARAMETER TimeoutSeconds
    Execution timeout in seconds before killing stalled processes (default 600s).
.EXAMPLE
    .\Install-ThirdPartyPackage.ps1 -InstallerPath "C:\Installers\7z2408-x64.msi" -Arguments "/qn /norestart"
.EXAMPLE
    .\Install-ThirdPartyPackage.ps1 -InstallerPath "C:\Installers\ChromeStandaloneSetup64.exe" -Arguments "/silent /install"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallerPath,

    [Parameter(Mandatory = $false)]
    [string]$Arguments = "",

    [Parameter(Mandatory = $false)]
    [int]$TimeoutSeconds = 600
)

function Wait-ForMsiMutex {
    param([int]$MaxWaitSeconds = 120)
    $waited = 0
    while ($waited -lt $MaxWaitSeconds) {
        $msiRunning = Get-Process -Name "msiexec" -ErrorAction SilentlyContinue |
            Where-Object { $_.MainWindowTitle -eq "" -and $_.SessionId -eq 0 }

        if (-not $msiRunning) { return $true }
        Write-Host "[*] Waiting for active msiexec lock to clear... ($waited/$MaxWaitSeconds s)" -ForegroundColor Yellow
        Start-Sleep -Seconds 5
        $waited += 5
    }
    return $false
}

if (-not (Test-Path $InstallerPath)) {
    Write-Error "Installer file not found: $InstallerPath"
    exit 1
}

$ext = [System.IO.Path]::GetExtension($InstallerPath).ToLower()
$logDir = "$env:ProgramData\PatchLogs"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$logPath = Join-Path -Path $logDir -ChildPath "$([System.IO.Path]::GetFileNameWithoutExtension($InstallerPath))_$timestamp.log"

if ($ext -eq ".msi") {
    $canProceed = Wait-ForMsiMutex -MaxWaitSeconds 180
    if (-not $canProceed) {
        Write-Error "MSI Mutex deadlock: An existing msiexec process is stuck. Aborting."
        exit 1618
    }
    $exe = "msiexec.exe"
    $fullArgs = "/i `"$InstallerPath`" $Arguments /l*v `"$logPath`""
} else {
    $exe = $InstallerPath
    $fullArgs = $Arguments
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Executing Silent Deployment: $InstallerPath" -ForegroundColor Cyan
Write-Host " Log File: $logPath" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$process = Start-Process -FilePath $exe -ArgumentList $fullArgs -PassThru -NoNewWindow
$timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)

if ($timedOut) {
    Write-Warning "Process exceeded timeout ($TimeoutSeconds s). Terminating process tree..."
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    exit 1460 # ERROR_TIMEOUT
}

$exitCode = $process.ExitCode
Write-Host "Process finished with Exit Code: $exitCode" -ForegroundColor Cyan

switch ($exitCode) {
    0 {
        Write-Host "[+] Installation succeeded." -ForegroundColor Green
        exit 0
    }
    3010 {
        Write-Host "[!] Installation succeeded. REBOOT REQUIRED (Exit Code 3010)." -ForegroundColor Yellow
        exit 3010
    }
    1641 {
        Write-Host "[!] Installation initiated system restart (Exit Code 1641)." -ForegroundColor Yellow
        exit 1641
    }
    1618 {
        Write-Host "[-] ERROR 1618: Another installation is already in progress." -ForegroundColor Red
        exit 1618
    }
    1603 {
        Write-Host "[-] ERROR 1603: Fatal error during installation. Review verbose log at $logPath" -ForegroundColor Red
        exit 1603
    }
    default {
        Write-Host "[-] Installation exited with status: $exitCode. Review log: $logPath" -ForegroundColor Red
        exit $exitCode
    }
}
