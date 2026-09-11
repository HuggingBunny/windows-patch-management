# Modern Windows Servicing & Unified Update Platform (UUP)

## Scope & Target Platforms
- Windows 10 (21H2, 22H2)
- Windows 11 (22H2, 23H2, 24H2)
- Windows Server 2016, 2019, 2022, 2025

## Key Architectural Enhancements
1. **Unified Update Platform (UUP)**: Smaller delta downloads, client-side differential composition, seamless Servicing Stack Update (SSU) and Latest Cumulative Update (LCU) packaging.
2. **Delivery Optimization (DO)**: Peer-to-peer cloud/LAN content caching.
3. **Hotpatching**: In-memory patching of running processes on supported Server editions without requiring an immediate reboot.
4. **Update Session Orchestrator (USO)**: Replaces legacy `wuauclt.exe` with `usoclient.exe`.

## Modern Automation Patterns

### 1. Update Orchestration via USO CLI
```powershell
# Initiate background scan
Start-Process -FilePath "$env:SystemRoot\System32\usoclient.exe" -ArgumentList "StartScan" -NoNewWindow

# Initiate download
Start-Process -FilePath "$env:SystemRoot\System32\usoclient.exe" -ArgumentList "StartDownload" -NoNewWindow

# Initiate installation
Start-Process -FilePath "$env:SystemRoot\System32\usoclient.exe" -ArgumentList "StartInstall" -NoNewWindow
```

### 2. Decoding Binary Windows Update ETL Logs
```powershell
# Decode ETL traces into a human-readable text log
Get-WindowsUpdateLog -LogPath "$env:TEMP\WindowsUpdate.log" -SymbolServer "https://msdl.microsoft.com/download/symbols"
```

### 3. Delivery Optimization Cache Diagnostics
```powershell
# Query DO cache efficiency and peer distribution metrics
Get-DeliveryOptimizationStatus | Select-Object FileId, FileSize, TotalBytesDownloaded, BytesFromPeers, PercentPeerCaching
```
