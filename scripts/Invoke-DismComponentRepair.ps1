<#
.SYNOPSIS
    Automated DISM Health Check & Source-Aware Component Store Repair.
.DESCRIPTION
    Executes staged DISM servicing: CheckHealth, ScanHealth, RestoreHealth (supporting
    offline WIM payload mapping to overcome missing payload errors 0x800F081F), and
    component store cleanup with base reset.
.PARAMETER CustomWimPath
    Optional path to an install.wim file for offline payload source resolution.
.PARAMETER WimIndex
    WIM image index corresponding to the target OS edition (defaults to 1).
.EXAMPLE
    .\Invoke-DismComponentRepair.ps1
.EXAMPLE
    .\Invoke-DismComponentRepair.ps1 -CustomWimPath "D:\sources\install.wim" -WimIndex 2
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$CustomWimPath = "",

    [Parameter(Mandatory = $false)]
    [int]$WimIndex = 1
)

Write-Host "[*] Step 1: Checking Component Store Corruption..." -ForegroundColor Cyan
$check = DISM.exe /Online /Cleanup-Image /CheckHealth
Write-Host $check

Write-Host "`n[*] Step 2: Scanning Component Store Integrity..." -ForegroundColor Cyan
$scan = DISM.exe /Online /Cleanup-Image /ScanHealth
Write-Host $scan

Write-Host "`n[*] Step 3: Executing RestoreHealth..." -ForegroundColor Cyan
if ([string]::IsNullOrEmpty($CustomWimPath)) {
    $restore = DISM.exe /Online /Cleanup-Image /RestoreHealth
} else {
    Write-Host "Using offline image payload: WIM:$CustomWimPath:$WimIndex" -ForegroundColor Yellow
    $restore = DISM.exe /Online /Cleanup-Image /RestoreHealth /Source:"WIM:$CustomWimPath:$WimIndex" /LimitAccess
}
Write-Host $restore

Write-Host "`n[*] Step 4: Component Store Cleanup & Base Reset..." -ForegroundColor Cyan
DISM.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase

Write-Host "`n[+] Component store repair sequence complete." -ForegroundColor Green
