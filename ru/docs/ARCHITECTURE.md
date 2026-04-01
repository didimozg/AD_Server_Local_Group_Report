# Architecture

Этот документ описывает внутреннее устройство `AD_Server_Local_Group_Report` для доработки и безопасного рефакторинга.

## High-Level Flow

Основной путь выполнения выглядит так:

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

Что делает каждый этап:

- основной wrapper-скрипт нормализует CLI-параметры, передаёт `InvocationParameterSetName`, импортирует модуль и вызывает публичную команду
- `Start-ServerLocalGroupReport` управляет execution lifecycle: output paths, runtime context, logging, source inventory, scan pipeline и export
- configuration-слой определяет `InputMode`, `OperationMode`, credential policy и финальный execution config
- scan pipeline создаёт единый `ServerScanConfiguration` и передаёт его вниз до протокольного уровня
- reporting-слой агрегирует scan results и сохраняет CSV/LOG артефакты

## Layers

Текущая файловая структура разделена по ответственности:

- `AD_Server_Local_Group_Report.psm1`
  loader модуля, инициализация модульных констант и export публичных команд
- `Public/Commands.ps1`
  публичные entry points и orchestration верхнего уровня
- `Private/Runtime.ps1`
  runtime context, log writing, console output, CSV export helpers
- `Private/Contracts.ps1`
  фабрики типовых объектов и внутренних result-shape
- `Private/Configuration.ps1`
  interactive/non-interactive input flow, mode derivation, credential resolution
- `Private/ActiveDirectory.ps1`
  получение серверов из AD и stale-фильтрация
- `Private/ScanConnectivity.ps1`
  reachability, retry, transport fallback, CIM error classification
- `Private/ScanMembership.ps1`
  CIM/WinNT membership collection и match/filter logic
- `Private/Reporting.ps1`
  aggregation, status messaging, export итоговых artefact-rows

## Runtime Context

Runtime context используется для передачи кросс-секционных параметров, которые не относятся к бизнес-логике scan-операций:

- `ReportLogPath`
- `IsInteractiveRun`
- `ModulePath`

Ключевые функции:

- `Get-ReportRuntimeContext`
- `Get-DefaultReportRuntimeContext`
- `Resolve-ReportRuntimeContext`
- `Set-ReportRuntimeContext`

Важно:

- default runtime context живёт на уровне модуля как fallback
- scan/config/reporting функции должны предпочитать явный `-RuntimeContext`, а не читать скрытое состояние напрямую

## Core Contracts

Ниже перечислены основные внутренние object-shape, создаваемые в `Private/Contracts.ps1`.

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

Есть несколько важных архитектурных правил:

- wrapper не должен повторно реализовывать business rules модуля
- mode derivation живёт в `Resolve-ExecutionMode`, а wrapper только передаёт `InvocationParameterSetName`
- публичные scan-команды сохраняют старые параметры ради совместимости, но внутри нормализуют их в `ServerScanConfiguration`
- reporting-слой должен принимать уже собранные объекты и не знать деталей CIM/WinNT-опроса
- фабрики из `Contracts.ps1` считаются источником истины для shape-объектов

## Validation Notes

Поставляемая версия проекта намеренно облегчена и не содержит встроенного `tests/`-каталога.

Если в будущем вы будете развивать модуль дальше, имеет смысл отдельно восстановить или создать:

- unit-проверки на contracts, configuration, runtime и aggregation helpers
- wrapper-проверки на CLI-нормализацию и import behavior
- integration-smoke проверки для orchestration-слоя

Наиболее чувствительные к регрессиям зоны:

- mode derivation
- credential resolution
- runtime context behavior
- scan configuration normalization
- error classification for retry/auth
- reporting aggregation contracts
- wrapper success/failure paths

## Safe Extension Rules

Если дальше расширять проект, безопаснее придерживаться таких правил:

- новые shape-объекты сначала добавлять в `Contracts.ps1`
- затем переводить использование на фабрику
- после этого добавлять unit-тест на контракт и только потом менять orchestration

Если добавляется новое поле в результат scan/reporting:

1. обновить factory в `Contracts.ps1`
2. обновить агрегатор/экспорт
3. обновить CSV property order
4. при наличии локального dev-пайплайна обновить проверки
5. обновить `README.md`, если поле пользовательское

## Known Boundaries

Что остаётся сознательно “мягким”, а не жёстко типизированным:

- menu option objects в interactive UI
- часть low-level helper rows в connectivity/membership parsing
- объекты, приходящие из AD/CIM/WMI

Это нормально, потому что они либо транзитные, либо завязаны на внешние системные API. Основная цель контрактного слоя — зафиксировать shape тех объектов, которые проходят между внутренними слоями и попадают в aggregation/export.
