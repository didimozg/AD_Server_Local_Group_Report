# Architecture

This document describes the internal structure of `AD_Server_Local_Group_Report` so the project can be extended and refactored safely.

## High-Level Flow

The main execution path looks like this:

1. `Start-ServerLocalGroupReport.ps1`
2. `Invoke-WrapperEntryPoint`
3. `Start-ServerLocalGroupReport`
4. `Resolve-ExecutionConfiguration`
5. `Get-SourceServerInventory`
6. `New-ServerScanConfiguration`
7. `Invoke-ServerScanBatch`
8. `Invoke-ServerScan`
9. `Invoke-ServerScanProtocol`
10. `Get-CimLocalGroupMembership` / `Get-WinNTLocalGroupMembership`
11. `Get-ServerScanResultSet`
12. `Export-*Artifact`

What each stage does:

- the preferred wrapper script normalizes CLI parameters, passes `InvocationParameterSetName`, imports the module, and calls the public command
- `Start-ServerLocalGroupReport` manages the execution lifecycle: output paths, runtime context, logging, source inventory, scan pipeline, and export
- the configuration layer resolves `InputMode`, `OperationMode`, credential policy, and the final execution config
- the scan pipeline builds one `ServerScanConfiguration` object and passes it down to the protocol level
- the reporting layer aggregates scan results and persists CSV/LOG artifacts

## Layers

The current file structure is separated by responsibility:

- `AD_Server_Local_Group_Report.psm1`
  module loader, module constant initialization, and export of public commands
- `Public/Commands.ps1`
  public entry points and top-level orchestration
- `Private/Runtime.ps1`
  runtime context, log writing, console output, CSV export helpers
- `Private/Contracts.ps1`
  factories for common objects and internal result shapes
- `Private/Configuration.ps1`
  interactive/non-interactive input flow, mode derivation, credential resolution
- `Private/ActiveDirectory.ps1`
  server discovery from AD and stale-object filtering
- `Private/ScanConnectivity.ps1`
  reachability, retry, transport fallback, CIM error classification
- `Private/ScanMembership.ps1`
  CIM/WinNT membership collection and match/filter logic
- `Private/Reporting.ps1`
  aggregation, status messaging, and export of final artifact rows

## Runtime Context

Runtime context is used to pass cross-cutting parameters that do not belong to scan business logic:

- `ReportLogPath`
- `IsInteractiveRun`
- `ModulePath`

Key functions:

- `Get-ReportRuntimeContext`
- `Get-DefaultReportRuntimeContext`
- `Resolve-ReportRuntimeContext`
- `Set-ReportRuntimeContext`

Important notes:

- the default runtime context lives at module scope as a fallback
- scan/config/reporting functions should prefer an explicit `-RuntimeContext` over reading hidden state directly

## Core Contracts

The main internal object shapes are created in `Private/Contracts.ps1`.

### Execution contracts

`New-ExecutionModeResolutionResult`

- `InputMode`
- `OperationMode`

`New-ExecutionInputConfiguration`

- `InputMode`
- `ServerListPath`
- `OperationMode`
- `SearchIdentity`

`New-ExecutionCredentialConfigurationResult`

- `ADCredential`
- `ServerCredential`
- `CredentialSelection`

`New-ExecutionConfigurationResult`

- `InputMode`
- `ServerListPath`
- `OperationMode`
- `SearchIdentity`
- `ADCredential`
- `ServerCredential`
- `CredentialSelection`
- `ADAuthContext`
- `ServerAuthContext`

### Inventory contracts

`New-ServerInventoryRow`

- `Name`
- `ConnectionName`
- `DnsHostName`
- `OperatingSystem`
- `OperatingSystemVersion`
- `Enabled`
- `DistinguishedName`
- `PasswordLastSetUtc`
- `LastLogonTimestampUtc`
- `SourceMode`

`New-SourceServerInventoryResult`

- `Servers`
- `LogMessage`

### Reporting path contracts

`New-ReportArtifactPathSet`

- `ServerCsvPath`
- `ServerTxtPath`
- `MembershipCsvPath`
- `SummaryCsvPath`
- `IdentityMatchCsvPath`
- `StatusCsvPath`

### Scan pipeline contracts

`New-ServerScanConfiguration`

- `LocalGroups`
- `Credential`
- `CimProtocol`
- `ConnectivityTimeoutMs`
- `ReachabilityMode`
- `CimOperationTimeoutSec`
- `CimRetryCount`
- `CimRetryDelaySec`
- `IncludeEmptyGroups`
- `OperationMode`
- `SearchIdentity`
- `ThrottleLimit`
- `WellKnownAuthorities`
- `CimSlowQueryWarningSec`

`New-ReachabilityResult`

- `PingSucceeded`
- `OpenPorts`
- `ReachableProtocols`
- `RecommendedProtocolOrder`
- `CanAttemptCim`
- `ReachabilitySummary`

`New-ProtocolScanResult`

- `QueryStatus`
- `CimProtocol`
- `GroupsCollected`
- `MembersCollected`
- `MatchesFound`
- `ErrorMessage`
- `Members`
- `Matches`

`New-ServerStatusRow`

- `Server`
- `DnsHostName`
- `QueryStatus`
- `RequestedCimProtocol`
- `EffectiveCimProtocol`
- `AttemptedCimProtocols`
- `FallbackUsed`
- `ReachabilityMode`
- `PingSucceeded`
- `ReachabilitySummary`
- `GroupsCollected`
- `MembersCollected`
- `MatchesFound`
- `ErrorMessage`

`New-ServerScanResult`

- `Status`
- `Members`
- `Matches`

### Aggregation contracts

`New-MembershipSummaryRow`

- `Server`
- `LocalGroup`
- `LocalGroupCaption`
- `LocalGroupSid`
- `MemberCount`

`New-ServerScanResultSet`

- `StatusRows`
- `MembershipRows`
- `IdentityMatchRows`

## Data Flow Notes

There are a few important architectural rules:

- the wrapper should not re-implement module business rules
- mode derivation lives in `Resolve-ExecutionMode`, while the wrapper only passes `InvocationParameterSetName`
- public scan commands keep legacy parameters for compatibility, but normalize them internally into `ServerScanConfiguration`
- the reporting layer should work with collected objects only and should not know CIM/WinNT collection details
- factories in `Contracts.ps1` are the source of truth for shape objects

## Validation Notes

The delivered project is intentionally trimmed down and does not include a built-in `tests/` folder.

If you continue developing the module later, it still makes sense to maintain or recreate:

- unit coverage for contracts, configuration, runtime, and aggregation helpers
- wrapper validation for CLI normalization and import behavior
- integration-smoke coverage for orchestration paths

The most regression-sensitive areas remain:

- mode derivation
- credential resolution
- runtime context behavior
- scan configuration normalization
- error classification for retry/auth
- reporting aggregation contracts
- wrapper success/failure paths

## Safe Extension Rules

If you continue to extend the project, the safest approach is:

- add new shape objects to `Contracts.ps1` first
- then migrate usage to the factory
- only after that add unit tests for the contract and change orchestration

If you add a new field to scan/reporting output:

1. update the factory in `Contracts.ps1`
2. update aggregation/export
3. update CSV property order
4. update local validation checks if you maintain a dev pipeline
5. update `README.md` if the field is user-facing

## Known Boundaries

What intentionally remains soft rather than strongly typed:

- menu option objects in the interactive UI
- some low-level helper rows in connectivity/membership parsing
- objects returned by AD/CIM/WMI

That is acceptable because those objects are either transient or bound to external system APIs. The main goal of the contract layer is to lock down the shape of objects that move between internal layers and eventually reach aggregation/export.
