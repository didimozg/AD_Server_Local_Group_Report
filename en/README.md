# AD Server Local Group Report

PowerShell tool for inventorying Windows Server machines and collecting local group membership across them.

Preferred public entry point:

- [Start-ServerLocalGroupReport.ps1](./Start-ServerLocalGroupReport.ps1)
- legacy compatibility wrapper: [get_windows_server_local_group_report.ps1](./get_windows_server_local_group_report.ps1)

The project can:

- get a server list from Active Directory or from a TXT/CSV file
- connect to each server over CIM using `DCOM` or `WSMan`
- export direct members of local groups, including domain users and domain groups
- search for a specific user, group, SID, or wildcard pattern and show on which server and in which local group it was found
- produce operational logs, status reports, detailed membership exports, and summary CSV files

The script is designed for mixed Windows Server environments, including older servers where `DCOM` is still the most practical transport.

## License

This project is licensed under the MIT License.

See [LICENSE](./LICENSE).

## Why This Exists

In many Windows environments, local groups on servers contain a mix of:

- local accounts
- domain users
- domain groups
- built-in and well-known service identities

Manually checking those memberships server by server is slow and error-prone. This project automates that audit and provides repeatable CSV outputs that are suitable for:

- security reviews
- access audits
- migration planning
- decommissioning checks
- troubleshooting unexpected local admin or RDP access

## What The Tool Does

The tool supports two source modes and two operation modes.

Source modes:

- `AD`: discover Windows Server computer objects from Active Directory
- `File`: read servers from a TXT or CSV file

Operation modes:

- `AllMembers`: export direct members of local groups
- `FindIdentity`: search for one identity across all scanned servers

In interactive mode the script guides the operator through:

- source selection
- operation selection
- whether to use the current Windows session or alternate credentials

In non-interactive mode the script can infer mode from the active parameter set or from the supplied arguments.

## Key Features

- wrapper script with interactive and non-interactive usage
- module-based implementation with public/private split
- PowerShell 5.1 and PowerShell 7+ support
- parallel server scanning in PowerShell 7+
- `DCOM` / `WSMan` transport selection with automatic fallback
- configurable reachability strategy: `Probe`, `Direct`, `PingOnly`, `None`
- retry handling for transient CIM/WMI issues
- `WinNT` fallback to recover missing group members when CIM data is incomplete
- optional AD stale-object filtering using `pwdLastSet` and `lastLogonTimestamp`
- optional inclusion of empty local groups
- CSV and TXT source inventory exports
- execution log file with per-run timestamp
- compact deliverable layout without a required dev/test layer

## Supported Environment

Admin workstation:

- Windows PowerShell `5.1+`
- PowerShell `7+` recommended for parallel scanning

Remote servers:

- Windows Server `2008` through modern releases such as `2022/2025`
- remote PowerShell version on the target server is not the key dependency
- the script does not require running remote PowerShell code on target servers for normal collection

Dependencies by mode:

- `AD` mode requires the `ActiveDirectory` module and access to a domain controller
- `File` mode does not require the `ActiveDirectory` module
- `PSScriptAnalyzer` and `Pester 5` may be used as optional development tools, but they are not required for normal operational use

## How It Works

High-level flow:

1. Resolve execution mode and credentials.
2. Get the source server list from AD or file.
3. Normalize and export the source inventory.
4. For each server, determine whether CIM attempts should be made.
5. Try the preferred transport first, then fallback transport if needed.
6. Enumerate local groups.
7. Enumerate direct members of each local group.
8. Merge CIM results with `WinNT` fallback results when needed.
9. Export status, detailed membership rows, summaries, and search matches.

The implementation lives in:

- [Start-ServerLocalGroupReport.ps1](./Start-ServerLocalGroupReport.ps1): preferred CLI entry point with help and parameter sets
- [get_windows_server_local_group_report.ps1](./get_windows_server_local_group_report.ps1): legacy compatibility wrapper
- [AD_Server_Local_Group_Report.psm1](./AD_Server_Local_Group_Report.psm1): module loader
- [Public/Commands.ps1](./Public/Commands.ps1): public entry points
- [Private/](./Private): configuration, connectivity, membership, reporting, runtime, contracts
- [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md): internal architecture notes

## Authentication Model

The tool supports three practical authentication patterns:

1. Current Windows session
2. Separate `ADCredential` and `ServerCredential`
3. One shared `PSCredential` via `-Credential` / `-SharedCredential`

Interactive mode starts with a simple choice:

- use the current Windows session
- prompt once for another user and reuse that credential for AD and servers

Non-interactive default:

- if explicit credentials are not passed, the current Windows session is used

## Input Sources

### Active Directory

In `AD` mode the project queries computer objects whose operating system contains `Windows Server`.

Optional AD filters:

- `-DomainServer`
- `-SearchBase`
- `-MaxComputerPasswordAgeDays`
- `-MaxLastLogonAgeDays`
- `-IncludeDisabledComputers`

### File Mode

Supported file formats:

- `TXT`: one server per line
- `CSV`: one column contains the server name

Auto-detected CSV column names:

- `ConnectionName`
- `Server`
- `ComputerName`
- `Name`
- `DnsHostName`
- `Host`
- `Hostname`

If the column name is custom, use `-CsvServerColumn`.

Examples included in the repo:

- [samples/servers_example.txt](./samples/servers_example.txt)
- [samples/servers_example.csv](./samples/servers_example.csv)

## Collection Logic

### Reachability

Before CIM collection, the tool can optionally probe each server:

- `Probe`: ICMP plus relevant ports
- `Direct`: skip probe and go straight to CIM
- `PingOnly`: ICMP only
- `None`: no pre-check at all

This is controlled by `-ReachabilityMode`.

### Transport

Preferred transport is controlled by `-CimProtocol`:

- `Dcom`
- `Wsman`

If the preferred protocol fails, the tool automatically tries the other one. The final report records:

- requested protocol
- effective protocol
- whether fallback was used

### Membership Enumeration

Primary data source:

- CIM / WMI classes such as `Win32_Group` and `Win32_GroupUser`

Fallback path:

- `WinNT` / ADSI enumeration

The fallback exists because some environments return incomplete member lists through CIM alone. The project merges both result sets and removes duplicates.

## Output Files

The default output folder is `output/`, but you can override it with `-OutputDirectory`.

Always produced:

- `server_source_list.csv`
- `server_source_list.txt`
- `server_membership_status.csv`
- `execution_YYYYMMDD_HHMMSS.log`

Produced in `AllMembers` mode:

- `server_local_group_members.csv`
- `server_local_group_summary.csv`

Produced in `FindIdentity` mode:

- `identity_search_matches.csv`

### `server_source_list.csv`

Normalized source inventory. Depending on source mode, it can include:

- `ConnectionName`
- `DnsHostName`
- `OperatingSystem`
- `Enabled`
- `PasswordLastSetUtc`
- `LastLogonTimestampUtc`

### `server_membership_status.csv`

One row per server. Useful columns:

- `QueryStatus`: `Success`, `Offline`, `Error`
- `RequestedCimProtocol`
- `EffectiveCimProtocol`
- `AttemptedCimProtocols`
- `FallbackUsed`
- `ReachabilityMode`
- `ReachabilitySummary`
- `GroupsCollected`
- `MembersCollected`
- `MatchesFound`
- `ErrorMessage`

### `server_local_group_members.csv`

One row per direct local-group member. Important columns:

- `Server`
- `CimProtocol`
- `LocalGroup`
- `LocalGroupCaption`
- `LocalGroupSid`
- `MemberName`
- `MemberType`
- `MemberClass`
- `MemberPrincipal`
- `MemberCaption`
- `MemberScope`
- `MemberAuthority`
- `MemberSource`
- `MemberLocalAccount`
- `MemberSid`
- `MemberPath`

### `server_local_group_summary.csv`

One row per local group with aggregated counts.

### `identity_search_matches.csv`

Subset of membership rows that matched the requested identity, plus:

- `SearchIdentity`

## Search Behavior

`FindIdentity` mode supports matching against:

- principal name such as `DOMAIN\\User1`
- leaf name such as `User1`
- SID
- wildcard pattern such as `*Admin*`

Matching is performed against membership properties such as:

- `MemberName`
- `MemberPrincipal`
- `MemberCaption`
- `MemberSid`
- `MemberPath`

## Usage

### Interactive

```powershell
.\Start-ServerLocalGroupReport.ps1
```

### File Source, Full Export

```powershell
.\Start-ServerLocalGroupReport.ps1 `
    -ServerListPath ".\samples\servers_example.txt" `
    -NonInteractive
```

### File Source, CSV With Explicit Column

```powershell
.\Start-ServerLocalGroupReport.ps1 `
    -ServerListPath ".\samples\servers_example.csv" `
    -CsvServerColumn "FQDN" `
    -NonInteractive
```

### AD Source, Full Export

```powershell
$adCred = Get-Credential
$serverCred = Get-Credential

.\Start-ServerLocalGroupReport.ps1 `
    -ADCredential $adCred `
    -ServerCredential $serverCred `
    -NonInteractive
```

### Search For One User Or Group

```powershell
$adCred = Get-Credential
$serverCred = Get-Credential

.\Start-ServerLocalGroupReport.ps1 `
    -ADCredential $adCred `
    -ServerCredential $serverCred `
    -SearchIdentity "CONTOSO\\User1" `
    -NonInteractive
```

### Shared Credential

```powershell
$cred = Get-Credential

.\Start-ServerLocalGroupReport.ps1 `
    -Credential $cred `
    -ServerListPath ".\samples\servers_example.txt" `
    -NonInteractive
```

### Restrict To Specific Local Groups

```powershell
.\Start-ServerLocalGroupReport.ps1 `
    -ServerListPath ".\samples\servers_example.txt" `
    -LocalGroups "Administrators","Remote Desktop Users" `
    -NonInteractive
```

### Skip Pre-Probe And Go Directly To CIM

```powershell
.\Start-ServerLocalGroupReport.ps1 `
    -ServerListPath ".\samples\servers_example.txt" `
    -ReachabilityMode Direct `
    -NonInteractive
```

### AD Stale Object Filtering

```powershell
.\Start-ServerLocalGroupReport.ps1 `
    -DomainServer "dc01.contoso.local" `
    -MaxComputerPasswordAgeDays 90 `
    -MaxLastLogonAgeDays 90 `
    -NonInteractive
```

## Parameters

The wrapper script supports these major parameters:

- `-InputMode`: `AD` or `File`
- `-OperationMode`: `AllMembers` or `FindIdentity`
- `-ServerListPath`: TXT or CSV file with servers
- `-CsvServerColumn`: explicit CSV column name
- `-SearchIdentity`: identity to search for
- `-DomainServer`: explicit DC / AD endpoint
- `-SearchBase`: LDAP search base
- `-ADCredential`: credential for AD access
- `-ServerCredential`: credential for server access
- `-Credential` / `-SharedCredential`: one credential for both
- `-LocalGroups`: optional list of local groups to limit enumeration
- `-CimProtocol`: `Dcom` or `Wsman`
- `-ReachabilityMode`: `Probe`, `Direct`, `PingOnly`, `None`
- `-ConnectivityTimeoutMs`: reachability timeout
- `-CimOperationTimeoutSec`: CIM operation timeout
- `-CimRetryCount`: retry attempts
- `-CimRetryDelaySec`: retry delay
- `-ThrottleLimit`: parallelism in PowerShell 7+
- `-MaxComputerPasswordAgeDays`: filter stale AD computer objects
- `-MaxLastLogonAgeDays`: filter stale AD computer objects
- `-WellKnownAuthorities`: custom well-known authority classification
- `-CimSlowQueryWarningSec`: warn on slow group-member enumeration
- `-IncludeDisabledComputers`: include disabled AD computer objects
- `-IncludeEmptyGroups`: emit placeholder rows for empty local groups
- `-OutputDirectory`: target folder for artifacts
- `-NonInteractive`: disable prompts

Built-in help:

```powershell
Get-Help .\Start-ServerLocalGroupReport.ps1 -Detailed
```

## Repository Layout

```text
AD_Server_Local_Group_Report_en/
├─ AD_Server_Local_Group_Report.psd1
├─ AD_Server_Local_Group_Report.psm1
├─ Start-ServerLocalGroupReport.ps1
├─ get_windows_server_local_group_report.ps1
├─ LICENSE
├─ README.md
├─ README.en.md
├─ README.ru.md
├─ docs/
│  └─ ARCHITECTURE.md
├─ Private/
├─ Public/
└─ samples/
```

`Start-ServerLocalGroupReport.ps1` is the preferred script name for publication and operator usage. The older
`get_windows_server_local_group_report.ps1` file remains in the repository for backward compatibility.

## Optional Development Tooling

The delivered project is intentionally trimmed down and does not include the built-in `tests/` folder or quality-runner
scripts.

If you want to extend the project further or build your own quality gate, you can optionally install:

```powershell
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module -Name Pester -RequiredVersion 5.7.1 -Scope CurrentUser -Force -SkipPublisherCheck
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force
```

Check which versions are available:

```powershell
Get-Module -ListAvailable Pester | Sort-Object Version -Descending
Get-Module -ListAvailable PSScriptAnalyzer
```

## Practical Operational Notes

- After building the source list in `AD` mode, interactive execution intentionally pauses and offers to open `server_source_list.txt` or the `output` folder so the operator can review and adjust the final scan scope.
- If the operator chooses to continue after review, the tool reloads the final server list from `server_source_list.txt` instead of relying only on the original AD query result.
- `FindIdentity` handles the zero-match scenario as a valid outcome, not as an error. In that case the tool still creates `identity_search_matches.csv` with headers and no data rows.
- Warnings such as `WinNT fallback added missing members` are informational and indicate improved completeness of the collected membership data, not a script failure.
- At the end of execution the log now includes a category summary: `Success`, `Offline`, `AccessDenied`, `WinRM`, `Other`. This makes it easier to separate connectivity and permissions issues from tool logic issues.
- `Offline`, `AccessDenied`, and `WinRM` statuses in the final reports usually point to target-side reachability or permission conditions, not to a crash in the wrapper itself.
- In mixed PowerShell/CIM environments some providers return scalar objects instead of arrays; the current project already guards against common `.Count` and empty-collection edge cases caused by that behavior.

## Important Limitations

- The report contains direct local-group members only.
- Nested domain groups are not expanded to final users.
- Successful enumeration depends on network reachability and permissions.
- `WinNT` fallback is best-effort and exists to improve completeness, not to guarantee parity in every legacy edge case.
- Some environments block ICMP while still allowing CIM, so `ReachabilityMode Direct` may be preferable.
- `WSMan` is not always available on older servers; `Dcom` is often the safest default in mixed estates.

## License Summary

Distributed under the MIT License. See [LICENSE](./LICENSE) for the full text.

