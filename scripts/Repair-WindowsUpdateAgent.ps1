<#
.SYNOPSIS
    Deterministic complete teardown and re-initialization of Windows Update components.
.DESCRIPTION
    Stops servicing daemons, resets BITS and WUA security descriptors, renames corrupted
    SoftwareDistribution and catroot2 caches, resets Winsock/WinHTTP proxies, re-registers
    dynamic libraries, and triggers System File Checker (sfc /scannow).
.PARAMETER SkipSfc
    Skips the execution of sfc.exe /scannow if run in time-constrained maintenance windows.
.EXAMPLE
    .\Repair-WindowsUpdateAgent.ps1
.EXAMPLE
    .\Repair-WindowsUpdateAgent.ps1 -SkipSfc
#>

[CmdletBinding()]
param(
    [switch]$SkipSfc
)

Write-Host "[*] Stopping core update and background servicing daemons..." -ForegroundColor Cyan
$services = @("wuauserv", "bits", "cryptsvc", "trustedinstaller", "msiserver")
foreach ($svc in $services) {
    Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
}

# Reset Security Descriptors on BITS and WUA
Write-Host "[*] Resetting service security descriptors..." -ForegroundColor Cyan
sc.exe sdset bits "D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWLOCRRC;;;PU)" | Out-Null
sc.exe sdset wuauserv "D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWLOCRRC;;;PU)" | Out-Null

# Rename Caches
$timestamp = (Get-Date).ToString("yyyyMMddHHmmss")
$sd = "$env:SystemRoot\SoftwareDistribution"
$cat = "$env:SystemRoot\System32\catroot2"

if (Test-Path $sd) {
    Write-Host "[*] Renaming SoftwareDistribution to SoftwareDistribution.bak.$timestamp" -ForegroundColor Yellow
    Rename-Item -Path $sd -NewName "SoftwareDistribution.bak.$timestamp" -Force -ErrorAction SilentlyContinue
}
if (Test-Path $cat) {
    Write-Host "[*] Renaming catroot2 to catroot2.bak.$timestamp" -ForegroundColor Yellow
    Rename-Item -Path $cat -NewName "catroot2.bak.$timestamp" -Force -ErrorAction SilentlyContinue
}

# Reset WinSock & WinHTTP Proxy
Write-Host "[*] Resetting Winsock and Network Proxy Configuration..." -ForegroundColor Cyan
netsh winsock reset | Out-Null
netsh winhttp reset proxy | Out-Null

# Re-register Core Servicing COM DLLs
Write-Host "[*] Re-registering dynamic libraries..." -ForegroundColor Cyan
$dlls = @("wups2.dll", "wups.dll", "wuaueng.dll", "wuapi.dll", "wucltux.dll", "qmgr.dll", "qmgrprxy.dll")
foreach ($dll in $dlls) {
    regsvr32.exe /s "$env:SystemRoot\System32\$dll"
}

# Restart Services
Write-Host "[*] Restarting services..." -ForegroundColor Green
Start-Service -Name "cryptsvc" -ErrorAction SilentlyContinue
Start-Service -Name "bits" -ErrorAction SilentlyContinue
Start-Service -Name "wuauserv" -ErrorAction SilentlyContinue

if (-not $SkipSfc) {
    Write-Host "[*] Executing System File Integrity Verification (sfc /scannow)..." -ForegroundColor Cyan
    sfc.exe /scannow
}

Write-Host "[+] Windows Update Engine successfully reset." -ForegroundColor Green
