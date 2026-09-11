<#
.SYNOPSIS
    Hardened Remote Patch Failure Triage & Diagnostic Bundle Collector.
.DESCRIPTION
    Executes in-memory/in-session diagnostic collection on target Windows endpoints over WinRM,
    capturing active CBS logs, rotated CBS persist logs, DISM logs, decoded WindowsUpdate logs,
    installer error events, and DISM package state into a compressed local archive.
    Eliminates protocol fragmentation by executing locally on the guest and streaming back artifacts.
.PARAMETER TargetComputer
    Hostname or IP address of the target Windows machine.
.PARAMETER LocalDestinationRoot
    Local directory where extracted diagnostic logs will be stored (defaults to C:\PatchDiagnostics).
.PARAMETER NonInteractive
    Suppresses any interactive pause prompts.
.PARAMETER AutoRemediate
    Attempts automatic service recovery on critical servicing daemons during triage.
.EXAMPLE
    .\Invoke-RemotePatchDiagnosticCollector.ps1 -TargetComputer "SRV-APP-01"
.EXAMPLE
    .\Invoke-RemotePatchDiagnosticCollector.ps1 -TargetComputer "WKSTN-102" -AutoRemediate -NonInteractive
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$TargetComputer,

    [Parameter(Mandatory = $false)]
    [string]$LocalDestinationRoot = "C:\PatchDiagnostics",

    [Parameter(Mandatory = $false)]
    [switch]$NonInteractive,

    [Parameter(Mandatory = $false)]
    [switch]$AutoRemediate
)

$ErrorActionPreference = "Stop"

# Fast .NET TCP Probe for rapid connectivity verification
function Test-PortFast {
    param([string]$Computer, [int]$Port, [int]$TimeoutMs = 1000)
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $iar = $tcpClient.BeginConnect($Computer, $Port, $null, $null)
        $wait = $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if (-not $wait) {
            $tcpClient.Close()
            return $false
        }
        $tcpClient.EndConnect($iar)
        $tcpClient.Close()
        return $true
    }
    catch {
        return $false
    }
}

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$TargetOutputDir = Join-Path -Path $LocalDestinationRoot -ChildPath "$($TargetComputer)_$Timestamp"
if (-not (Test-Path $TargetOutputDir)) {
    New-Item -Path $TargetOutputDir -ItemType Directory -Force | Out-Null
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Hardened Patch Triage Collector: $TargetComputer" -ForegroundColor Cyan
Write-Host " Local Output: $TargetOutputDir" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Connectivity Pre-flight
Write-Host "[*] Probing WinRM (5985) and SMB (445)..." -ForegroundColor Cyan
$winrmOpen = Test-PortFast -Computer $TargetComputer -Port 5985 -TimeoutMs 1500
$smbOpen   = Test-PortFast -Computer $TargetComputer -Port 445  -TimeoutMs 1500

if (-not $winrmOpen) {
    Write-Error "WinRM (Port 5985) is unreachable on $TargetComputer. Enable PSRemoting or verify firewall rules."
    return
}

# 2. Remote In-Guest Collection & Triage Block
$RemoteCollectorBlock = {
    param([bool]$Remediate)

    $diagRoot = "$env:TEMP\PatchDiag_$((Get-Date).ToString('yyyyMMdd_HHmmss'))"
    New-Item -Path $diagRoot -ItemType Directory -Force | Out-Null

    $summary = @{
        ComputerName   = $env:COMPUTERNAME
        Timestamp      = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Services       = @{}
        RebootPending  = $false
        PendingReasons = @()
        DismErrors     = @()
    }

    # Verify Servicing Services
    $coreServices = @("wuauserv", "bits", "cryptsvc", "trustedinstaller")
    foreach ($s in $coreServices) {
        $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
        if ($null -eq $svc) {
            $summary.Services[$s] = "NotInstalled"
        } else {
            $summary.Services[$s] = $svc.Status.ToString()
            if ($Remediate -and $svc.Status -ne "Running" -and $s -ne "trustedinstaller") {
                Set-Service -Name $s -StartupType Automatic -ErrorAction SilentlyContinue
                Start-Service -Name $s -ErrorAction SilentlyContinue
            }
        }
    }

    # Evaluate Comprehensive Pending Reboot Matrix
    $cbsPending = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
    $cbsPack    = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending"
    $wuPending  = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    $fileRename = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations

    if ($cbsPending) { $summary.RebootPending = $true; $summary.PendingReasons += "CBS\RebootPending" }
    if ($cbsPack)    { $summary.RebootPending = $true; $summary.PendingReasons += "CBS\PackagesPending" }
    if ($wuPending)  { $summary.RebootPending = $true; $summary.PendingReasons += "WindowsUpdate\RebootRequired" }
    if ($fileRename) { $summary.RebootPending = $true; $summary.PendingReasons += "PendingFileRenameOperations" }

    # Copy Servicing Logs (Active + Rotated Persist logs)
    $cbsDir = "$env:SystemRoot\Logs\CBS"
    if (Test-Path $cbsDir) {
        Get-ChildItem -Path $cbsDir -Filter "CBS*.log" -File | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination (Join-Path $diagRoot $_.Name) -Force -ErrorAction SilentlyContinue
        }
        Get-ChildItem -Path $cbsDir -Filter "CbsPersist*.log" -File | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination (Join-Path $diagRoot $_.Name) -Force -ErrorAction SilentlyContinue
        }
    }

    $dismLog = "$env:SystemRoot\Logs\DISM\dism.log"
    if (Test-Path $dismLog) {
        Copy-Item -Path $dismLog -Destination (Join-Path $diagRoot "dism.log") -Force -ErrorAction SilentlyContinue
    }

    # Modern WindowsUpdate ETL Log Decoding
    try {
        if (Get-Command Get-WindowsUpdateLog -ErrorAction SilentlyContinue) {
            Get-WindowsUpdateLog -LogPath "$diagRoot\Decoded_WindowsUpdate.log" -ErrorAction SilentlyContinue | Out-Null
        }
    } catch {}

    # Dump MSI Logs from System & User Temp
    $tempMsiDir = Join-Path $diagRoot "MSI_Logs"
    New-Item -Path $tempMsiDir -ItemType Directory -Force | Out-Null
    Get-ChildItem -Path "$env:SystemRoot\Temp" -Filter "*.log" -File -ErrorAction SilentlyContinue |
        ForEach-Object { Copy-Item $_.FullName (Join-Path $tempMsiDir $_.Name) -Force -ErrorAction SilentlyContinue }

    # Export Operational Windows Update & Error Events
    try {
        Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-WindowsUpdateClient/Operational'} -MaxEvents 300 -ErrorAction SilentlyContinue |
            Select-Object TimeCreated, Id, LevelDisplayName, Message |
            Export-Csv -Path "$diagRoot\WindowsUpdateClient_Operational.csv" -NoTypeInformation
    } catch {}

    try {
        Get-WinEvent -FilterHashtable @{LogName='Application'; Level=1,2; StartTime=(Get-Date).AddDays(-3)} -MaxEvents 200 -ErrorAction SilentlyContinue |
            Select-Object TimeCreated, ProviderName, Id, Message |
            Export-Csv -Path "$diagRoot\Application_Critical_Errors.csv" -NoTypeInformation
    } catch {}

    # DISM Package State (Ground Truth)
    try {
        Get-WindowsPackage -Online -ErrorAction SilentlyContinue |
            Select-Object PackageName, PackageState, ReleaseType, InstallTime |
            Export-Csv -Path "$diagRoot\DISM_Packages_State.csv" -NoTypeInformation
    } catch {}

    # Dump Summary JSON
    $summary | ConvertTo-Json -Depth 3 | Set-Content -Path "$diagRoot\TriageSummary.json"

    # Zip Diagnostic Bundle
    $zipPath = "$env:TEMP\PatchDiag_$($env:COMPUTERNAME).zip"
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    [System.IO.Compression.ZipFile]::CreateFromDirectory($diagRoot, $zipPath)
    Remove-Item -Path $diagRoot -Recurse -Force -ErrorAction SilentlyContinue

    return $zipPath
}

Write-Host "[*] Executing remote diagnostic bundle generation inside WinRM session..." -ForegroundColor Cyan
$remoteZip = Invoke-Command -ComputerName $TargetComputer -ScriptBlock $RemoteCollectorBlock -ArgumentList ([bool]$AutoRemediate)

Write-Host "[+] Target archive created at: $remoteZip" -ForegroundColor Green

# 3. Pull Archive Back (Prefer SMB if available, fallback to WinRM byte stream)
$localZipFile = Join-Path $TargetOutputDir "PatchDiag_$TargetComputer.zip"

if ($smbOpen) {
    Write-Host "[*] Transferring zip archive over SMB..." -ForegroundColor Cyan
    $uncPath = "\\$TargetComputer\" + $remoteZip.Replace(":", "$")
    Copy-Item -Path $uncPath -Destination $localZipFile -Force
} else {
    Write-Host "[*] SMB closed. Streaming archive payload directly over WinRM session..." -ForegroundColor Yellow
    $bytes = Invoke-Command -ComputerName $TargetComputer -ScriptBlock {
        param($path)
        [System.IO.File]::ReadAllBytes($path)
    } -ArgumentList $remoteZip
    [System.IO.File]::WriteAllBytes($localZipFile, $bytes)
}

# Cleanup remote temp zip
Invoke-Command -ComputerName $TargetComputer -ScriptBlock { param($p) Remove-Item $p -Force -ErrorAction SilentlyContinue } -ArgumentList $remoteZip

# Extract locally
[System.IO.Compression.ZipFile]::ExtractToDirectory($localZipFile, $TargetOutputDir)
Remove-Item $localZipFile -Force

Write-Host "[+] Triage package successfully extracted to: $TargetOutputDir" -ForegroundColor Green
if (Test-Path "$TargetOutputDir\TriageSummary.json") {
    Get-Content "$TargetOutputDir\TriageSummary.json" | ConvertFrom-Json | Format-List
}
