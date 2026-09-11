<#
.SYNOPSIS
    Fleet-Wide Patch Health & Diagnostic Triage Script.
.DESCRIPTION
    Compatible across Windows 7 SP1, 8.1, 10, 11, and Windows Server 2008 R2–2025.
    Evaluates comprehensive pending reboot flags, Windows Update Agent (WUA) status,
    last installed hotfix, and system drive free space.
.EXAMPLE
    .\Invoke-WindowsPatchTriage.ps1
#>

[CmdletBinding()]
param()

function Get-PatchHealthReport {
    [CmdletBinding()]
    param()

    $report = New-Object -TypeName PSObject

    # OS Info via WMI for legacy and modern OS backward compatibility
    $os = Get-WmiObject -Class Win32_OperatingSystem
    Add-Member -InputObject $report -MemberType NoteProperty -Name "ComputerName" -Value $env:COMPUTERNAME
    Add-Member -InputObject $report -MemberType NoteProperty -Name "OSCaption" -Value $os.Caption
    Add-Member -InputObject $report -MemberType NoteProperty -Name "OSVersion" -Value $os.Version
    Add-Member -InputObject $report -MemberType NoteProperty -Name "OSBuild" -Value $os.BuildNumber
    Add-Member -InputObject $report -MemberType NoteProperty -Name "OSArchitecture" -Value $os.OSArchitecture

    # Comprehensive Pending Reboot Flags
    $rebootPending = $false
    $rebootReasons = @()

    $keys = @(
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"; Name = "CBS\RebootPending" },
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending"; Name = "CBS\PackagesPending" },
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"; Name = "WindowsUpdate\RebootRequired" }
    )
    foreach ($k in $keys) {
        if (Test-Path $k.Path) {
            $rebootPending = $true
            $rebootReasons += $k.Name
        }
    }
    
    $pendingRenames = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue).PendingFileRenameOperations
    if ($pendingRenames) {
        $rebootPending = $true
        $rebootReasons += "PendingFileRenameOperations"
    }

    Add-Member -InputObject $report -MemberType NoteProperty -Name "RebootPending" -Value $rebootPending
    Add-Member -InputObject $report -MemberType NoteProperty -Name "RebootReasons" -Value ($rebootReasons -join ", ")

    # Windows Update Service Status
    $wua = Get-Service -Name "wuauserv" -ErrorAction SilentlyContinue
    if ($null -ne $wua) {
        Add-Member -InputObject $report -MemberType NoteProperty -Name "WuauservStatus" -Value ($wua.Status.ToString())
        Add-Member -InputObject $report -MemberType NoteProperty -Name "WuauservStartup" -Value ($wua.StartType.ToString())
    } else {
        Add-Member -InputObject $report -MemberType NoteProperty -Name "WuauservStatus" -Value "NotInstalled"
        Add-Member -InputObject $report -MemberType NoteProperty -Name "WuauservStartup" -Value "Unknown"
    }

    # Last Successful Hotfix
    $lastHotfix = Get-WmiObject -Class Win32_QuickFixEngineering -ErrorAction SilentlyContinue |
        Sort-Object InstalledOn -Descending |
        Select-Object -First 1

    if ($null -ne $lastHotfix) {
        Add-Member -InputObject $report -MemberType NoteProperty -Name "LastHotfixID" -Value $lastHotfix.HotFixID
        Add-Member -InputObject $report -MemberType NoteProperty -Name "LastHotfixDate" -Value $lastHotfix.InstalledOn
    } else {
        Add-Member -InputObject $report -MemberType NoteProperty -Name "LastHotfixID" -Value "None"
        Add-Member -InputObject $report -MemberType NoteProperty -Name "LastHotfixDate" -Value "None"
    }

    # Disk Free Space on System Drive (GB)
    $sysDrive = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'" -ErrorAction SilentlyContinue
    if ($null -ne $sysDrive) {
        $freeGb = [math]::Round(($sysDrive.FreeSpace / 1GB), 2)
        Add-Member -InputObject $report -MemberType NoteProperty -Name "SystemDriveFreeGB" -Value $freeGb
    } else {
        Add-Member -InputObject $report -MemberType NoteProperty -Name "SystemDriveFreeGB" -Value 0
    }

    return $report
}

$health = Get-PatchHealthReport
$health | Format-List
