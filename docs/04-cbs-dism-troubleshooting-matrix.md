# Failed Patch Diagnostics & CBS/DISM Troubleshooting Matrix

## Common Error Code Matrix

| Error Code | Hex / Symbolic | Root Cause | Automated Remediation Sequence |
| :--- | :--- | :--- | :--- |
| `0x800F081F` | `CBS_E_SOURCE_MISSING` | Component store payload missing or pruned from WinSxS. | Run DISM RestoreHealth with offline WIM source (`/Source:WIM:install.wim:1 /LimitAccess`). |
| `0x80073712` | `ERROR_SXS_COMPONENT_STORE_CORRUPT` | Component store metadata/manifest corrupted. | Run `DISM /Online /Cleanup-Image /RestoreHealth` followed by `sfc /scannow`. |
| `0x80070002` | `ERROR_FILE_NOT_FOUND` | Windows Update cache inconsistency (`SoftwareDistribution`). | Stop `wuauserv` & `bits`, rename `SoftwareDistribution` and `catroot2`, restart services. |
| `0x8024200B` | `WU_E_UH_INSTALL_FAILED` | Internal update handler installation failure. | Check `CBS.log` for locking components or previous pending reboot blocks. |
| `0x80070BC9` | `ERROR_FAIL_REBOOT_REQUIRED` | Servicing operation cannot proceed while a reboot is pending. | Clear pending lock flags or orchestrate host restart. |
| `0x800705B9` | `ERROR_XML_PARSE_ERROR` | Servicing manifest XML structure corrupted. | Restore manifest from healthy reference machine or run DISM RestoreHealth. |
| `0x8024402F` | `WU_E_PT_ECP_SUCCEEDED_WITH_ERRORS` | Proxy / TLS handshake failure with update endpoint. | Reset proxy configuration via `netsh winhttp reset proxy` and reset Winsock catalog. |

## 6 Comprehensive Pending Reboot Registry Vectors

1. `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending`
2. `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending`
3. `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\SessionsPending`
4. `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired`
5. `HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations`
6. `HKLM:\SOFTWARE\Microsoft\ServerManager\CurrentState` (Flags: `RebootRequired`)
