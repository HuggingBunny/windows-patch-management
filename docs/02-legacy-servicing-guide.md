# Legacy Windows Servicing & PowerShell 2.0/3.0 Guide

## Scope & Target Platforms
- Windows 7 SP1 (x86 / x64)
- Windows 8.1
- Windows Server 2008 R2 SP1
- Windows Server 2012 & 2012 R2

## Strict Backward-Compatible PowerShell Guardrails

When targeting legacy nodes with un-upgraded Windows Management Framework (WMF), avoid PowerShell 4.0/5.1 features:

1. **Avoid `[PSCustomObject]@{...}`**: Use `New-Object -TypeName PSObject` followed by `Add-Member`.
2. **Avoid `Get-CimInstance`**: Use `Get-WmiObject` with `-Class` parameter.
3. **Avoid `Test-NetConnection`**: Use .NET `[System.Net.Sockets.TcpClient]`.
4. **Avoid Advanced Pipeline Operators**: Do not use `??`, `?.`, or inline ternary syntax.

## Legacy Scripting Patterns

### 1. Fast .NET Socket Probe
```powershell
function Test-PortLegacySafe {
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
```

### 2. Native WUA API v2 COM Automation
```powershell
$updateSession = New-Object -ComObject "Microsoft.Update.Session"
$updateSearcher = $updateSession.CreateUpdateSearcher()
$searchResult = $updateSearcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")

$updatesToDownload = New-Object -ComObject "Microsoft.Update.UpdateColl"
foreach ($update in $searchResult.Updates) {
    $updatesToDownload.Add($update) | Out-Null
}

$downloader = $updateSession.CreateUpdateDownloader()
$downloader.Updates = $updatesToDownload
$downloader.Download()

$updatesToInstall = New-Object -ComObject "Microsoft.Update.UpdateColl"
foreach ($update in $searchResult.Updates) {
    if ($update.IsDownloaded) {
        $updatesToInstall.Add($update) | Out-Null
    }
}

$installer = $updateSession.CreateUpdateInstaller()
$installer.Updates = $updatesToInstall
$installResult = $installer.Install()
```

### 3. Offline MSU Expansion & DISM Package Injection
```powershell
# Expand MSU container to extract CAB package
expand -F:* "C:\Patches\Windows6.1-KB4474419-v3-x64.msu" "C:\Patches\Expanded\"

# Inject CAB using legacy DISM
dism.exe /Online /Add-Package /PackagePath:"C:\Patches\Expanded\Windows6.1-KB4474419-v3-x64.cab" /NoRestart /Quiet
```
