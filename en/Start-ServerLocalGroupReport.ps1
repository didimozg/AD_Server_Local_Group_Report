<#
.SYNOPSIS
Collects a Windows Server inventory and builds local group membership reports or searches for a specific identity.

.DESCRIPTION
The script can get a server list from Active Directory or from an input file, then connect to servers over CIM
using DCOM/WSMan, automatically switch transport when necessary, and save the results to CSV files.
Two modes are supported: a full export of direct local-group members, including domain users and domain
 groups, and a targeted search for a specific user or group showing the server and local group where the match was found.
In interactive mode the operator is first asked whether to use the current Windows session or prompt for
alternate credentials. If credentials are not passed in non-interactive mode, the current Windows session is used by default.
For non-interactive automation it is safer to construct `PSCredential` by using `SecretManagement`, `Import-Clixml`,
or another secure secret-storage mechanism instead of storing passwords in plain text.

.PARAMETER OutputDirectory
Folder for output CSV files and the execution text log.

.PARAMETER InputMode
Server list source: `AD` or `File`. If omitted, the wrapper can derive it from the active parameter set
or let the module ask interactively.

.PARAMETER ServerListPath
Path to a TXT or CSV file with the server list. Used in `File` mode.

.PARAMETER DomainServer
Specific domain controller or AD server to query. Used in `AD` mode.

.PARAMETER SearchBase
Base DN that limits the Active Directory search scope.

.PARAMETER OperationMode
Operation mode: `AllMembers` for a full export or `FindIdentity` to search for one identity. If omitted,
the wrapper can derive it from the active parameter set.

.PARAMETER SearchIdentity
User, group, SID, or wildcard pattern to search for on the servers. Used in `FindIdentity` mode.

.PARAMETER ADCredential
Credentials for Active Directory access. If omitted, the current Windows session can be used.

.PARAMETER ServerCredential
Credentials for connecting to target servers. If omitted, the current Windows session can be used.

.PARAMETER SharedCredential
Shared credentials when the same account should be used for both AD and servers. In interactive mode,
the same shared `PSCredential` is requested once if the operator chooses to run as another user.

.PARAMETER LocalGroups
List of local groups to inspect. If omitted, all local groups are scanned.

.PARAMETER CsvServerColumn
Explicit server-column name in the input CSV file. Used in `File` mode.

.PARAMETER CimProtocol
Preferred CIM transport: `Dcom` or `Wsman`.

.PARAMETER ConnectivityTimeoutMs
Timeout for pre-checking host reachability and CIM-related ports in milliseconds.

.PARAMETER ReachabilityMode
Reachability strategy before attempting CIM:
`Probe` - ping plus relevant port checks,
`Direct` - try CIM immediately,
`PingOnly` - rely on ICMP only,
`None` - skip all pre-checks.

.PARAMETER CimOperationTimeoutSec
Timeout for CIM queries in seconds.

.PARAMETER CimRetryCount
Number of retry attempts for transient CIM/WMI errors.

.PARAMETER CimRetryDelaySec
Delay between CIM retry attempts in seconds.

.PARAMETER ThrottleLimit
Maximum number of parallel server scans in PowerShell 7+.

.PARAMETER MaxComputerPasswordAgeDays
Excludes AD computer objects whose `pwdLastSet` is older than the specified number of days.

.PARAMETER MaxLastLogonAgeDays
Excludes AD computer objects whose `lastLogonTimestamp` is older than the specified number of days.

.PARAMETER WellKnownAuthorities
List of authorities that should be classified as `WellKnown` in reports. If omitted, the module default is used.

.PARAMETER CimSlowQueryWarningSec
Threshold in seconds after which a long `ASSOCIATORS` query is logged as a warning.

.PARAMETER IncludeDisabledComputers
Includes disabled computer objects from Active Directory.

.PARAMETER IncludeEmptyGroups
Adds empty local groups to the report.

.PARAMETER NonInteractive
Disables interactive prompts. If credentials are not supplied explicitly, the current Windows session is used.

.EXAMPLE
.\get_windows_server_local_group_report.ps1

Interactive run with prompts, including the choice between the current user and another user.

.EXAMPLE
.\get_windows_server_local_group_report.ps1 `
    -ServerListPath ".\samples\servers_example.csv" `
    -CsvServerColumn "FQDN" `
    -NonInteractive

Full export of local-group members from a CSV server list under the current Windows session.

.EXAMPLE
$adCred = Get-Credential
$serverCred = Get-Credential
.\get_windows_server_local_group_report.ps1 `
    -ADCredential $adCred `
    -ServerCredential $serverCred `
    -SearchIdentity "DOMAIN\User1" `
    -NonInteractive

Searches for one identity on servers from AD. `AD` and `FindIdentity` are derived automatically.

.EXAMPLE
$serverCred = Get-Credential
.\get_windows_server_local_group_report.ps1 `
    -ServerListPath ".\samples\servers_example.csv" `
    -CsvServerColumn "FQDN" `
    -ReachabilityMode Direct `
    -ServerCredential $serverCred `
    -NonInteractive

Full export of local-group members from a CSV server list without pre-run ping/port probing. `File` and `AllMembers` are derived automatically.

.EXAMPLE
$adCred = Get-Credential
$serverCred = Get-Credential
.\get_windows_server_local_group_report.ps1 `
    -ADCredential $adCred `
    -ServerCredential $serverCred `
    -MaxComputerPasswordAgeDays 90 `
    -MaxLastLogonAgeDays 90 `
    -NonInteractive

Exports only "live" servers from AD by filtering stale computer objects.
#>
#Requires -Version 5.1
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'Wrapper delegates ShouldProcess handling to Start-ServerLocalGroupReport.')]
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Interactive')]
param(
    [string]$OutputDirectory = (Join-Path -Path $PSScriptRoot -ChildPath 'output'),
    [ValidateSet('AD', 'File')]
    [string]$InputMode,
    [ValidateSet('AllMembers', 'FindIdentity')]
    [string]$OperationMode,
    [System.Management.Automation.PSCredential]$ServerCredential,
    [Alias('Credential')]
    [System.Management.Automation.PSCredential]$SharedCredential,
    [string[]]$LocalGroups,
    [ValidateSet('Dcom', 'Wsman')]
    [string]$CimProtocol = 'Dcom',
    [ValidateRange(250, 30000)]
    [int]$ConnectivityTimeoutMs = 1500,
    [ValidateSet('Probe', 'Direct', 'PingOnly', 'None')]
    [string]$ReachabilityMode = 'Probe',
    [ValidateRange(5, 300)]
    [uint32]$CimOperationTimeoutSec = 20,
    [ValidateRange(1, 5)]
    [int]$CimRetryCount = 2,
    [ValidateRange(1, 30)]
    [int]$CimRetryDelaySec = 2,
    [ValidateRange(1, 64)]
    [int]$ThrottleLimit = 8,
    [string[]]$WellKnownAuthorities,
    [ValidateRange(1, 600)]
    [int]$CimSlowQueryWarningSec = 15,
    [switch]$IncludeEmptyGroups,
    [switch]$NonInteractive,

    [Parameter(ParameterSetName = 'Interactive')]
    [Parameter(ParameterSetName = 'File_AllMembers', Mandatory)]
    [Parameter(ParameterSetName = 'File_FindIdentity', Mandatory)]
    [string]$ServerListPath,

    [Parameter(ParameterSetName = 'Interactive')]
    [Parameter(ParameterSetName = 'AD_AllMembers')]
    [Parameter(ParameterSetName = 'AD_FindIdentity')]
    [string]$DomainServer,

    [Parameter(ParameterSetName = 'Interactive')]
    [Parameter(ParameterSetName = 'AD_AllMembers')]
    [Parameter(ParameterSetName = 'AD_FindIdentity')]
    [string]$SearchBase,

    [Parameter(ParameterSetName = 'Interactive')]
    [Parameter(ParameterSetName = 'AD_FindIdentity', Mandatory)]
    [Parameter(ParameterSetName = 'File_FindIdentity', Mandatory)]
    [string]$SearchIdentity,

    [Parameter(ParameterSetName = 'Interactive')]
    [Parameter(ParameterSetName = 'AD_AllMembers')]
    [Parameter(ParameterSetName = 'AD_FindIdentity')]
    [System.Management.Automation.PSCredential]$ADCredential,

    [Parameter(ParameterSetName = 'Interactive')]
    [Parameter(ParameterSetName = 'File_AllMembers')]
    [Parameter(ParameterSetName = 'File_FindIdentity')]
    [string]$CsvServerColumn,

    [Parameter(ParameterSetName = 'Interactive')]
    [Parameter(ParameterSetName = 'AD_AllMembers')]
    [Parameter(ParameterSetName = 'AD_FindIdentity')]
    [ValidateRange(0, 3650)]
    [int]$MaxComputerPasswordAgeDays = 0,

    [Parameter(ParameterSetName = 'Interactive')]
    [Parameter(ParameterSetName = 'AD_AllMembers')]
    [Parameter(ParameterSetName = 'AD_FindIdentity')]
    [ValidateRange(0, 3650)]
    [int]$MaxLastLogonAgeDays = 0,

    [Parameter(ParameterSetName = 'Interactive')]
    [Parameter(ParameterSetName = 'AD_AllMembers')]
    [Parameter(ParameterSetName = 'AD_FindIdentity')]
    [switch]$IncludeDisabledComputers
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-ModuleParameterHashtable {
    param([Parameter(Mandatory)][hashtable]$BoundParameters)

    $moduleParameters = @{}
    foreach ($entry in $BoundParameters.GetEnumerator()) {
        if ($entry.Value -is [string] -and [string]::IsNullOrWhiteSpace($entry.Value)) {
            Write-Verbose ("Blank string parameter value '{0}' is not passed to the module." -f $entry.Key)
            continue
        }

        $moduleParameters[$entry.Key] = $entry.Value
    }

    if ($moduleParameters.ContainsKey('Credential') -and -not $moduleParameters.ContainsKey('SharedCredential')) {
        $moduleParameters['SharedCredential'] = $moduleParameters['Credential']
        $moduleParameters.Remove('Credential')
        Write-Verbose "Alias 'Credential' was normalized to parameter 'SharedCredential'."
    }

    return $moduleParameters
}

function Resolve-WrapperModuleParameterSet {
    param(
        [Parameter(Mandatory)][string]$ParameterSetName,
        [Parameter(Mandatory)][hashtable]$BoundParameters
    )

    $moduleParameters = ConvertTo-ModuleParameterHashtable -BoundParameters $BoundParameters
    if (-not [string]::IsNullOrWhiteSpace($ParameterSetName)) {
        $moduleParameters['InvocationParameterSetName'] = $ParameterSetName
        Write-Verbose ("Wrapper passes InvocationParameterSetName = '{0}' to the module for centralized mode resolution." -f $ParameterSetName)
    }

    return $moduleParameters
}

function Get-WrapperModulePath {
    param([Parameter(Mandatory)][string]$ScriptRoot)

    return (Join-Path -Path $ScriptRoot -ChildPath 'AD_Server_Local_Group_Report.psm1')
}

function Import-WrapperReportModule {
    param([Parameter(Mandatory)][string]$ModulePath)

    Write-Verbose ("Expected module path: {0}" -f $ModulePath)

    if (-not (Test-Path -LiteralPath $ModulePath -PathType Leaf)) {
        Write-Error -Message 'Module file AD_Server_Local_Group_Report.psm1 was not found in the script folder. Make sure all project files were copied correctly.' -ErrorAction Stop
    }

    Write-Verbose ("Importing module from '{0}'." -f $ModulePath)
    try {
        Import-Module -Name $ModulePath -Force -DisableNameChecking -ErrorAction Stop
    }
    catch {
        Write-Error -Message ("Failed to import module '{0}'. Check file integrity, ExecutionPolicy, and access rights. Technical error: {1}" -f $ModulePath, $_.Exception.Message) -ErrorAction Stop
    }
}

function Invoke-WrapperEntryPoint {
    param(
        [Parameter(Mandatory)][string]$ParameterSetName,
        [Parameter(Mandatory)][hashtable]$BoundParameters,
        [Parameter(Mandatory)][string]$ScriptRoot
    )

    Write-Verbose ("Selected parameter set: {0}" -f $ParameterSetName)
    $moduleParameters = Resolve-WrapperModuleParameterSet -ParameterSetName $ParameterSetName -BoundParameters $BoundParameters
    $modulePath = Get-WrapperModulePath -ScriptRoot $ScriptRoot
    Import-WrapperReportModule -ModulePath $modulePath

    Write-Verbose 'Passing parameters to Start-ServerLocalGroupReport.'
    return (Start-ServerLocalGroupReport @moduleParameters)
}

function Invoke-WrapperMain {
    param(
        [Parameter(Mandatory)][string]$ParameterSetName,
        [Parameter(Mandatory)][hashtable]$BoundParameters,
        [Parameter(Mandatory)][string]$ScriptRoot
    )

    try {
        return (Invoke-WrapperEntryPoint -ParameterSetName $ParameterSetName -BoundParameters $BoundParameters -ScriptRoot $ScriptRoot)
    }
    catch {
        Write-Verbose ("Wrapper ended with a terminating error: {0}" -f $_.Exception.Message)
        throw [System.InvalidOperationException]::new(("Critical wrapper-script failure: {0}" -f $_.Exception.Message), $_.Exception)
    }
}

Invoke-WrapperMain -ParameterSetName $PSCmdlet.ParameterSetName -BoundParameters $PSBoundParameters -ScriptRoot $PSScriptRoot













