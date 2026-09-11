# 3rd-Party Patch Management & Silent Packaging Matrix

## Silent Installer Parameter Matrix

| Installer Type | Silent Switch | Verbose Logging Switch | Suppress Reboot Switch |
| :--- | :--- | :--- | :--- |
| **Microsoft MSI** | `/qn` or `/quiet` | `/l*v "<PathToLog>"` | `REBOOT=ReallySuppress` or `/norestart` |
| **WiX / Burn Bundle** | `/quiet` | `/log "<PathToLog>"` | `/norestart` |
| **InnoSetup** | `/VERYSILENT /SUPPRESSMSGBOXES` | `/LOG="<PathToLog>"` | `/NORESTART` |
| **Nullsoft NSIS** | `/S` (Case-sensitive uppercase) | N/A (Build-dependent) | N/A |
| **InstallShield** | `/s /v"/qn"` | `/v"/l*v "<PathToLog>""` | `/v"REBOOT=ReallySuppress"` |

## Common Enterprise Software Silent Deployments

```powershell
# Google Chrome Enterprise (MSI)
msiexec.exe /i "googlechromestandaloneenterprise64.msi" /qn /norestart /l*v "C:\ProgramData\PatchLogs\chrome.log"

# Mozilla Firefox (Silent EXE)
Firefox_Setup.exe -ms

# Adobe Acrobat Reader (MSI + MST Transform)
msiexec.exe /i "AcroRead.msi" TRANSFORMS="AcroRead.mst" /qn /norestart /l*v "C:\ProgramData\PatchLogs\acrobat.log"

# 7-Zip (MSI)
msiexec.exe /i "7z2408-x64.msi" /qn /norestart /l*v "C:\ProgramData\PatchLogs\7zip.log"

# Git for Windows (InnoSetup)
Git-Setup.exe /VERYSILENT /NORESTART /LOADINF="git-install-config.inf" /LOG="C:\ProgramData\PatchLogs\git.log"
```

## Critical MSI Exit Codes
- `0`: Success
- `3010`: Success, restart required (deferred reboot)
- `1641`: Success, restart initiated
- `1618`: Another installation is in progress (MSI Mutex lock)
- `1603`: Fatal error during installation (Requires verbose log analysis)
- `1602`: User cancelled installation
