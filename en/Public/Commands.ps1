<#
.SYNOPSIS
Sets the module runtime context used for logging and interactive output.
#>
function Set-ReportRuntimeContext {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Updates in-memory module runtime context only.')]
    param(
        [string]$ReportLogPath,
        [bool]$IsInteractiveRun = $true
    )

    $script:DefaultRuntimeContext = Get-ReportRuntimeContext -ReportLogPath $ReportLogPath -IsInteractiveRun $IsInteractiveRun -ModulePath $script:ModuleFilePath
    return $script:DefaultRuntimeContext
}

<#
.SYNOPSIS
Creates or returns the effective server-scan configuration.
#>
function Get-EffectiveServerScanConfiguration {
    param(
        [psobject]$ScanConfiguration,
        [string[]]$LocalGroups,
        [System.Management.Automation.PSCredential]$Credential,
        [ValidateSet('Dcom', 'Wsman')][string]$CimProtocol = 'Dcom',
        [ValidateRange(250, 30000)][int]$ConnectivityTimeoutMs = 1500,
        [ValidateSet('Probe', 'Direct', 'PingOnly', 'None')][string]$ReachabilityMode = 'Probe',
        [ValidateRange(5, 300)][uint32]$CimOperationTimeoutSec = 20,
        [ValidateRange(1, 5)][int]$CimRetryCount = 2,
        [ValidateRange(1, 30)][int]$CimRetryDelaySec = 2,
        [switch]$IncludeEmptyGroups,
        [ValidateSet('AllMembers', 'FindIdentity')][string]$OperationMode,
        [string]$SearchIdentity,
        [ValidateRange(1, 64)][int]$ThrottleLimit = 8,
        [string[]]$WellKnownAuthorities = $script:DefaultWellKnownAuthorities,
        [ValidateRange(1, 600)][int]$CimSlowQueryWarningSec = 15
    )

    if ($null -ne $ScanConfiguration) {
        return $ScanConfiguration
    }

    $effectiveOperationMode = if ([string]::IsNullOrWhiteSpace($OperationMode)) { 'AllMembers' } else { $OperationMode }

    return (
        New-ServerScanConfiguration `
            -LocalGroups $LocalGroups `
            -Credential $Credential `
            -CimProtocol $CimProtocol `
            -ConnectivityTimeoutMs $ConnectivityTimeoutMs `
            -ReachabilityMode $ReachabilityMode `
            -CimOperationTimeoutSec $CimOperationTimeoutSec `
            -CimRetryCount $CimRetryCount `
            -CimRetryDelaySec $CimRetryDelaySec `
            -IncludeEmptyGroups:$IncludeEmptyGroups `
            -OperationMode $effectiveOperationMode `
            -SearchIdentity $SearchIdentity `
            -ThrottleLimit $ThrottleLimit `
            -WellKnownAuthorities $WellKnownAuthorities `
            -CimSlowQueryWarningSec $CimSlowQueryWarningSec
    )
}

function Get-ServerReachabilityState {
    param(
        [Parameter(Mandatory)][psobject]$Server,
        [Parameter(Mandatory)][psobject]$ScanConfiguration
    )

    $protocolOrder = @(Get-CimProtocolOrder -PreferredProtocol $ScanConfiguration.CimProtocol)
    $reachability = Test-ServerReachability -ComputerName $Server.ConnectionName -ProtocolOrder $protocolOrder -TimeoutMs $ScanConfiguration.ConnectivityTimeoutMs -ReachabilityMode $ScanConfiguration.ReachabilityMode
    $recommendedProtocolOrder = @($reachability.RecommendedProtocolOrder)

    Write-Verbose ("[{0}] Reachability check: {1}" -f $Server.ConnectionName, $reachability.ReachabilitySummary)

    return [PSCustomObject]@{
        Reachability  = $reachability
        ProtocolOrder = $recommendedProtocolOrder
    }
}

function New-OfflineServerScanResult {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure factory/helper function that only shapes scan results.')]
    param(
        [Parameter(Mandatory)][psobject]$Server,
        [Parameter(Mandatory)][psobject]$ScanConfiguration,
        [Parameter(Mandatory)][psobject]$ReachabilityState
    )

    return (
        New-ServerScanResult `
            -Status (New-ServerStatusRow -Server $Server.ConnectionName -DnsHostName $Server.DnsHostName -QueryStatus 'Offline' -RequestedCimProtocol $ScanConfiguration.CimProtocol -AttemptedCimProtocols ($ReachabilityState.ProtocolOrder -join ' -> ') -FallbackUsed $false -ReachabilityMode $ScanConfiguration.ReachabilityMode -PingSucceeded $ReachabilityState.Reachability.PingSucceeded -ReachabilitySummary $ReachabilityState.Reachability.ReachabilitySummary -ErrorMessage 'Server did not respond to ICMP and no CIM-related ports were reachable.')
    )
}

function Get-ProtocolScanConfiguration {
    param(
        [Parameter(Mandatory)][psobject]$ScanConfiguration,
        [Parameter(Mandatory)][ValidateSet('Dcom', 'Wsman')][string]$CimProtocol
    )

    return (
        New-ServerScanConfiguration `
            -LocalGroups $ScanConfiguration.LocalGroups `
            -Credential $ScanConfiguration.Credential `
            -CimProtocol $CimProtocol `
            -ConnectivityTimeoutMs $ScanConfiguration.ConnectivityTimeoutMs `
            -ReachabilityMode $ScanConfiguration.ReachabilityMode `
            -CimOperationTimeoutSec $ScanConfiguration.CimOperationTimeoutSec `
            -CimRetryCount $ScanConfiguration.CimRetryCount `
            -CimRetryDelaySec $ScanConfiguration.CimRetryDelaySec `
            -IncludeEmptyGroups:$ScanConfiguration.IncludeEmptyGroups `
            -OperationMode $ScanConfiguration.OperationMode `
            -SearchIdentity $ScanConfiguration.SearchIdentity `
            -ThrottleLimit $ScanConfiguration.ThrottleLimit `
            -WellKnownAuthorities $ScanConfiguration.WellKnownAuthorities `
            -CimSlowQueryWarningSec $ScanConfiguration.CimSlowQueryWarningSec
    )
}

function Invoke-ServerProtocolScan {
    param(
        [Parameter(Mandatory)][psobject]$Server,
        [Parameter(Mandatory)][psobject]$ScanConfiguration,
        [Parameter(Mandatory)][psobject]$ReachabilityState,
        [psobject]$RuntimeContext
    )

    $attemptErrors = New-Object System.Collections.Generic.List[string]

    foreach ($protocol in $ReachabilityState.ProtocolOrder) {
        $protocolScanConfiguration = Get-ProtocolScanConfiguration -ScanConfiguration $ScanConfiguration -CimProtocol $protocol
        Write-Verbose ("[{0}] Trying CIM protocol '{1}'." -f $Server.ConnectionName, $protocol)
        $protocolResult = Invoke-ServerScanProtocol -Server $Server -ScanConfiguration $protocolScanConfiguration -RuntimeContext $RuntimeContext

        if ($protocolResult.QueryStatus -eq 'Success') {
            return (
                New-ServerScanResult `
                    -Status (New-ServerStatusRow -Server $Server.ConnectionName -DnsHostName $Server.DnsHostName -QueryStatus 'Success' -RequestedCimProtocol $ScanConfiguration.CimProtocol -EffectiveCimProtocol $protocol -AttemptedCimProtocols ($ReachabilityState.ProtocolOrder -join ' -> ') -FallbackUsed ($protocol -ne $ScanConfiguration.CimProtocol) -ReachabilityMode $ScanConfiguration.ReachabilityMode -PingSucceeded $ReachabilityState.Reachability.PingSucceeded -ReachabilitySummary $ReachabilityState.Reachability.ReachabilitySummary -GroupsCollected $protocolResult.GroupsCollected -MembersCollected $protocolResult.MembersCollected -MatchesFound $protocolResult.MatchesFound) `
                    -Members $protocolResult.Members `
                    -MatchedRows $protocolResult.Matches
            )
        }

        [void]$attemptErrors.Add(("{0}: {1}" -f $protocol, $protocolResult.ErrorMessage))
    }

    return (
        New-ServerScanResult `
            -Status (New-ServerStatusRow -Server $Server.ConnectionName -DnsHostName $Server.DnsHostName -QueryStatus 'Error' -RequestedCimProtocol $ScanConfiguration.CimProtocol -AttemptedCimProtocols ($ReachabilityState.ProtocolOrder -join ' -> ') -FallbackUsed $false -ReachabilityMode $ScanConfiguration.ReachabilityMode -PingSucceeded $ReachabilityState.Reachability.PingSucceeded -ReachabilitySummary $ReachabilityState.Reachability.ReachabilitySummary -ErrorMessage ($attemptErrors -join ' | '))
    )
}

<#
.SYNOPSIS
Scans one server and returns its status, group members, and any matches found.
#>
function Invoke-ServerScan {
    param(
        [Parameter(Mandatory)][psobject]$Server,
        [psobject]$ScanConfiguration,
        [string[]]$LocalGroups,
        [System.Management.Automation.PSCredential]$Credential,
        [ValidateSet('Dcom', 'Wsman')][string]$CimProtocol = 'Dcom',
        [ValidateRange(250, 30000)][int]$ConnectivityTimeoutMs = 1500,
        [ValidateSet('Probe', 'Direct', 'PingOnly', 'None')][string]$ReachabilityMode = 'Probe',
        [ValidateRange(5, 300)][uint32]$CimOperationTimeoutSec = 20,
        [ValidateRange(1, 5)][int]$CimRetryCount = 2,
        [ValidateRange(1, 30)][int]$CimRetryDelaySec = 2,
        [switch]$IncludeEmptyGroups,
        [ValidateSet('AllMembers', 'FindIdentity')][string]$OperationMode,
        [string]$SearchIdentity,
        [string[]]$WellKnownAuthorities = $script:DefaultWellKnownAuthorities,
        [ValidateRange(1, 600)][int]$CimSlowQueryWarningSec = 15,
        [psobject]$RuntimeContext
    )

    $scanConfigurationParameters = @{
        ScanConfiguration      = $ScanConfiguration
        LocalGroups            = $LocalGroups
        Credential             = $Credential
        CimProtocol            = $CimProtocol
        ConnectivityTimeoutMs  = $ConnectivityTimeoutMs
        ReachabilityMode       = $ReachabilityMode
        CimOperationTimeoutSec = $CimOperationTimeoutSec
        CimRetryCount          = $CimRetryCount
        CimRetryDelaySec       = $CimRetryDelaySec
        IncludeEmptyGroups     = [bool]$IncludeEmptyGroups
        WellKnownAuthorities   = $WellKnownAuthorities
        CimSlowQueryWarningSec = $CimSlowQueryWarningSec
    }

    if (-not [string]::IsNullOrWhiteSpace($OperationMode)) {
        $scanConfigurationParameters['OperationMode'] = $OperationMode
    }

    if (-not [string]::IsNullOrWhiteSpace($SearchIdentity)) {
        $scanConfigurationParameters['SearchIdentity'] = $SearchIdentity
    }

    $effectiveScanConfiguration = Get-EffectiveServerScanConfiguration @scanConfigurationParameters
    $reachabilityState = Get-ServerReachabilityState -Server $Server -ScanConfiguration $effectiveScanConfiguration

    if (-not $reachabilityState.Reachability.CanAttemptCim) {
        return (New-OfflineServerScanResult -Server $Server -ScanConfiguration $effectiveScanConfiguration -ReachabilityState $reachabilityState)
    }

    return (Invoke-ServerProtocolScan -Server $Server -ScanConfiguration $effectiveScanConfiguration -ReachabilityState $reachabilityState -RuntimeContext $RuntimeContext)
}

<#
.SYNOPSIS
Runs a batch server scan sequentially or in parallel depending on the PowerShell version.
#>
function Invoke-ServerScanBatch {
    param(
        [Parameter(Mandatory)][object[]]$Servers,
        [psobject]$ScanConfiguration,
        [string[]]$LocalGroups,
        [System.Management.Automation.PSCredential]$Credential,
        [ValidateSet('Dcom', 'Wsman')][string]$CimProtocol = 'Dcom',
        [ValidateRange(250, 30000)][int]$ConnectivityTimeoutMs = 1500,
        [ValidateSet('Probe', 'Direct', 'PingOnly', 'None')][string]$ReachabilityMode = 'Probe',
        [ValidateRange(5, 300)][uint32]$CimOperationTimeoutSec = 20,
        [ValidateRange(1, 5)][int]$CimRetryCount = 2,
        [ValidateRange(1, 30)][int]$CimRetryDelaySec = 2,
        [switch]$IncludeEmptyGroups,
        [ValidateSet('AllMembers', 'FindIdentity')][string]$OperationMode,
        [string]$SearchIdentity,
        [ValidateRange(1, 64)][int]$ThrottleLimit = 8,
        [string[]]$WellKnownAuthorities = $script:DefaultWellKnownAuthorities,
        [ValidateRange(1, 600)][int]$CimSlowQueryWarningSec = 15,
        [psobject]$RuntimeContext = (Get-ReportRuntimeContext)
    )

    $Servers = @($Servers | Where-Object { $null -ne $_ })
    $scanConfigurationParameters = @{
        ScanConfiguration      = $ScanConfiguration
        LocalGroups            = $LocalGroups
        Credential             = $Credential
        CimProtocol            = $CimProtocol
        ConnectivityTimeoutMs  = $ConnectivityTimeoutMs
        ReachabilityMode       = $ReachabilityMode
        CimOperationTimeoutSec = $CimOperationTimeoutSec
        CimRetryCount          = $CimRetryCount
        CimRetryDelaySec       = $CimRetryDelaySec
        IncludeEmptyGroups     = [bool]$IncludeEmptyGroups
        ThrottleLimit          = $ThrottleLimit
        WellKnownAuthorities   = $WellKnownAuthorities
        CimSlowQueryWarningSec = $CimSlowQueryWarningSec
    }

    if (-not [string]::IsNullOrWhiteSpace($OperationMode)) {
        $scanConfigurationParameters['OperationMode'] = $OperationMode
    }

    if (-not [string]::IsNullOrWhiteSpace($SearchIdentity)) {
        $scanConfigurationParameters['SearchIdentity'] = $SearchIdentity
    }

    $effectiveScanConfiguration = Get-EffectiveServerScanConfiguration @scanConfigurationParameters

    if ((Get-SafeCount -InputObject $Servers) -eq 0) {
        return @()
    }

    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-ReportLog -Message 'PowerShell 7+ was not detected. Using sequential CIM scanning without parallelism.' -Level 'WARN' -RuntimeContext $RuntimeContext
        $sequentialResults = New-Object System.Collections.Generic.List[object]
        $totalServers = Get-SafeCount -InputObject $Servers
        $currentIndex = 0

        foreach ($server in $Servers) {
            $currentIndex++
            $percentComplete = [Math]::Round(($currentIndex / $totalServers) * 100, 2)
            Write-Progress -Activity 'Sequential CIM server scan' -Status ("{0} ({1}/{2})" -f $server.ConnectionName, $currentIndex, $totalServers) -PercentComplete $percentComplete

            [void]$sequentialResults.Add(
                (Invoke-ServerScan -Server $server -ScanConfiguration $effectiveScanConfiguration -RuntimeContext $RuntimeContext)
            )
        }

        Write-Progress -Activity 'Sequential CIM server scan' -Completed
        return $sequentialResults.ToArray()
    }

    $effectiveRuntimeContext = Resolve-ReportRuntimeContext -RuntimeContext $RuntimeContext
    $parallelRuntimeContext = $effectiveRuntimeContext
    $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($effectiveRuntimeContext.ModulePath)
    Write-ReportLog -Message ("Starting parallel CIM server scan. Protocol: {0}. ReachabilityMode: {1}. Servers: {2}. ThrottleLimit: {3}." -f $effectiveScanConfiguration.CimProtocol, $effectiveScanConfiguration.ReachabilityMode, (Get-SafeCount -InputObject $Servers), $effectiveScanConfiguration.ThrottleLimit) -RuntimeContext $effectiveRuntimeContext
    Write-Progress -Activity 'Parallel CIM server scan' -Status ("Jobs started: {0}. Waiting for completion..." -f (Get-SafeCount -InputObject $Servers)) -PercentComplete 0

    $parallelResults = @(
        $Servers | ForEach-Object -Parallel {
            $runtimeContext = $using:parallelRuntimeContext

            if (-not (Get-Module -Name $using:moduleName)) {
                Import-Module -Name $runtimeContext.ModulePath -Force -DisableNameChecking | Out-Null
            }

            Invoke-ServerScan -Server $_ -ScanConfiguration $using:effectiveScanConfiguration -RuntimeContext $runtimeContext
        } -ThrottleLimit $effectiveScanConfiguration.ThrottleLimit
    )

    Write-Progress -Activity 'Parallel CIM server scan' -Completed
    return $parallelResults
}

function Initialize-ReportExecution {
    param(
        [Parameter(Mandatory)][string]$OutputDirectory,
        [Parameter(Mandatory)][bool]$IsInteractiveRun
    )

    $artifactPathSet = Get-ReportArtifactPathSet -OutputDirectory $OutputDirectory
    $runtimeContext = Get-ReportRuntimeContext -ReportLogPath $null -IsInteractiveRun $IsInteractiveRun -ModulePath $script:ModuleFilePath

    New-DirectoryIfMissing -Path $OutputDirectory
    $runtimeContext = Initialize-ReportLog -DirectoryPath $OutputDirectory -RuntimeContext $runtimeContext

    return [PSCustomObject]@{
        ArtifactPathSet = $artifactPathSet
        RuntimeContext  = $runtimeContext
    }
}

function Get-ReportExecutionPlan {
    param(
        [string]$InputMode,
        [string]$ServerListPath,
        [string]$DomainServer,
        [string]$SearchBase,
        [string]$OperationMode,
        [string]$SearchIdentity,
        [System.Management.Automation.PSCredential]$ADCredential,
        [System.Management.Automation.PSCredential]$ServerCredential,
        [System.Management.Automation.PSCredential]$SharedCredential,
        [string[]]$LocalGroups,
        [string]$CsvServerColumn,
        [ValidateSet('Dcom', 'Wsman')][string]$CimProtocol = 'Dcom',
        [ValidateRange(250, 30000)][int]$ConnectivityTimeoutMs = 1500,
        [ValidateSet('Probe', 'Direct', 'PingOnly', 'None')][string]$ReachabilityMode = 'Probe',
        [ValidateRange(5, 300)][uint32]$CimOperationTimeoutSec = 20,
        [ValidateRange(1, 5)][int]$CimRetryCount = 2,
        [ValidateRange(1, 30)][int]$CimRetryDelaySec = 2,
        [ValidateRange(1, 64)][int]$ThrottleLimit = 8,
        [ValidateRange(0, 3650)][int]$MaxComputerPasswordAgeDays = 0,
        [ValidateRange(0, 3650)][int]$MaxLastLogonAgeDays = 0,
        [string[]]$WellKnownAuthorities = $script:DefaultWellKnownAuthorities,
        [ValidateRange(1, 600)][int]$CimSlowQueryWarningSec = 15,
        [switch]$IncludeDisabledComputers,
        [switch]$IncludeEmptyGroups,
        [string]$InvocationParameterSetName,
        [switch]$NonInteractive,
        [Parameter(Mandatory)][hashtable]$BoundParameters,
        [psobject]$RuntimeContext
    )

    $executionConfiguration = Resolve-ExecutionConfiguration -InputMode $InputMode -ServerListPath $ServerListPath -OperationMode $OperationMode -SearchIdentity $SearchIdentity -DomainServer $DomainServer -SearchBase $SearchBase -CsvServerColumn $CsvServerColumn -ADCredential $ADCredential -ServerCredential $ServerCredential -SharedCredential $SharedCredential -MaxComputerPasswordAgeDays $MaxComputerPasswordAgeDays -MaxLastLogonAgeDays $MaxLastLogonAgeDays -InvocationParameterSetName $InvocationParameterSetName -IncludeDisabledComputers:$IncludeDisabledComputers -NonInteractive:$NonInteractive -BoundParameters $BoundParameters -RuntimeContext $RuntimeContext
    Write-ReportLog -Message ("Access context: AD = {0}; servers = {1}." -f $executionConfiguration.ADAuthContext, $executionConfiguration.ServerAuthContext) -RuntimeContext $RuntimeContext

    $sourceInventory = Get-SourceServerInventory -ExecutionConfiguration $executionConfiguration -DomainServer $DomainServer -SearchBase $SearchBase -CsvServerColumn $CsvServerColumn -IncludeDisabledComputers:$IncludeDisabledComputers -MaxComputerPasswordAgeDays $MaxComputerPasswordAgeDays -MaxLastLogonAgeDays $MaxLastLogonAgeDays -RuntimeContext $RuntimeContext
    $servers = @($sourceInventory.Servers)
    $scanConfiguration = New-ServerScanConfiguration -LocalGroups $LocalGroups -Credential $executionConfiguration.ServerCredential -CimProtocol $CimProtocol -ConnectivityTimeoutMs $ConnectivityTimeoutMs -ReachabilityMode $ReachabilityMode -CimOperationTimeoutSec $CimOperationTimeoutSec -CimRetryCount $CimRetryCount -CimRetryDelaySec $CimRetryDelaySec -IncludeEmptyGroups:$IncludeEmptyGroups -OperationMode $executionConfiguration.OperationMode -SearchIdentity $executionConfiguration.SearchIdentity -ThrottleLimit $ThrottleLimit -WellKnownAuthorities $WellKnownAuthorities -CimSlowQueryWarningSec $CimSlowQueryWarningSec

    return [PSCustomObject]@{
        ExecutionConfiguration = $executionConfiguration
        SourceInventory        = $sourceInventory
        Servers                = $servers
        ScanConfiguration      = $scanConfiguration
    }
}

function Assert-ReportServerInventory {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Servers)

    if ((Get-SafeCount -InputObject $Servers) -eq 0) {
        throw 'No servers were found for processing.'
    }
}

function Invoke-ReportScan {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Servers,
        [Parameter(Mandatory)][psobject]$ScanConfiguration,
        [Parameter(Mandatory)][psobject]$ArtifactPathSet,
        [psobject]$RuntimeContext
    )

    $scanResults = @(Invoke-ServerScanBatch -Servers $Servers -ScanConfiguration $ScanConfiguration -RuntimeContext $RuntimeContext)
    $scanResultSet = Get-ServerScanResultSet -ScanResults $scanResults

    Write-ServerScanStatusMessage -StatusRows $scanResultSet.StatusRows -RuntimeContext $RuntimeContext
    Export-ServerStatusArtifact -StatusRows $scanResultSet.StatusRows -ArtifactPathSet $ArtifactPathSet -RuntimeContext $RuntimeContext

    return $scanResultSet
}

function Export-ReportResult {
    param(
        [Parameter(Mandatory)][psobject]$ExecutionConfiguration,
        [Parameter(Mandatory)][psobject]$ScanResultSet,
        [Parameter(Mandatory)][psobject]$ArtifactPathSet,
        [Parameter(Mandatory)][int]$ServerCount,
        [psobject]$RuntimeContext
    )

    if ($ExecutionConfiguration.OperationMode -eq 'AllMembers') {
        Export-AllMembersArtifact -MembershipRows $ScanResultSet.MembershipRows -StatusRows $ScanResultSet.StatusRows -ArtifactPathSet $ArtifactPathSet -ServerCount $ServerCount -RuntimeContext $RuntimeContext
        return
    }

    Export-IdentitySearchArtifact -IdentityMatchRows $ScanResultSet.IdentityMatchRows -StatusRows $ScanResultSet.StatusRows -SearchIdentity $ExecutionConfiguration.SearchIdentity -ArtifactPathSet $ArtifactPathSet -RuntimeContext $RuntimeContext
}

<#
.SYNOPSIS
Entry point for interactive or non-interactive local-group reporting.
#>
function Start-ServerLocalGroupReport {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$OutputDirectory = (Join-Path -Path $script:ModuleRoot -ChildPath 'output'),

        [ValidateSet('AD', 'File')]
        [string]$InputMode,

        [string]$ServerListPath,
        [string]$DomainServer,
        [string]$SearchBase,

        [ValidateSet('AllMembers', 'FindIdentity')]
        [string]$OperationMode,

        [string]$SearchIdentity,
        [System.Management.Automation.PSCredential]$ADCredential,
        [System.Management.Automation.PSCredential]$ServerCredential,

        [Alias('Credential')]
        [System.Management.Automation.PSCredential]$SharedCredential,

        [string[]]$LocalGroups,
        [string]$CsvServerColumn,
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
        [ValidateRange(0, 3650)]
        [int]$MaxComputerPasswordAgeDays = 0,
        [ValidateRange(0, 3650)]
        [int]$MaxLastLogonAgeDays = 0,
        [string[]]$WellKnownAuthorities = $script:DefaultWellKnownAuthorities,
        [ValidateRange(1, 600)]
        [int]$CimSlowQueryWarningSec = 15,
        [switch]$IncludeDisabledComputers,
        [switch]$IncludeEmptyGroups,
        [string]$InvocationParameterSetName,
        [switch]$NonInteractive
    )

    if (-not $PSCmdlet.ShouldProcess($OutputDirectory, 'Generate local group membership reports')) {
        return
    }

    $reportExecution = Initialize-ReportExecution -OutputDirectory $OutputDirectory -IsInteractiveRun (-not $NonInteractive)
    $artifactPathSet = $reportExecution.ArtifactPathSet
    $runtimeContext = $reportExecution.RuntimeContext

    try {
        Write-ReportLog -Message ("Execution log: {0}" -f $runtimeContext.ReportLogPath) -RuntimeContext $runtimeContext
        $reportPlan = Get-ReportExecutionPlan -InputMode $InputMode -ServerListPath $ServerListPath -DomainServer $DomainServer -SearchBase $SearchBase -OperationMode $OperationMode -SearchIdentity $SearchIdentity -ADCredential $ADCredential -ServerCredential $ServerCredential -SharedCredential $SharedCredential -LocalGroups $LocalGroups -CsvServerColumn $CsvServerColumn -CimProtocol $CimProtocol -ConnectivityTimeoutMs $ConnectivityTimeoutMs -ReachabilityMode $ReachabilityMode -CimOperationTimeoutSec $CimOperationTimeoutSec -CimRetryCount $CimRetryCount -CimRetryDelaySec $CimRetryDelaySec -ThrottleLimit $ThrottleLimit -MaxComputerPasswordAgeDays $MaxComputerPasswordAgeDays -MaxLastLogonAgeDays $MaxLastLogonAgeDays -WellKnownAuthorities $WellKnownAuthorities -CimSlowQueryWarningSec $CimSlowQueryWarningSec -IncludeDisabledComputers:$IncludeDisabledComputers -IncludeEmptyGroups:$IncludeEmptyGroups -InvocationParameterSetName $InvocationParameterSetName -NonInteractive:$NonInteractive -BoundParameters $PSBoundParameters -RuntimeContext $runtimeContext
        Write-ReportLog -Message $reportPlan.SourceInventory.LogMessage -RuntimeContext $runtimeContext
        Assert-ReportServerInventory -Servers $reportPlan.Servers
        Export-SourceServerArtifact -Servers $reportPlan.Servers -ArtifactPathSet $artifactPathSet -RuntimeContext $runtimeContext

        $sourceServerReview = Invoke-SourceServerListReview -Servers $reportPlan.Servers -ExecutionConfiguration $reportPlan.ExecutionConfiguration -ArtifactPathSet $artifactPathSet -RuntimeContext $runtimeContext
        if ($sourceServerReview.Cancelled) {
            Write-ReportLog -Message 'Execution was stopped by the operator after the server list was created.' -Level 'WARN' -RuntimeContext $runtimeContext
            return
        }

        $effectiveServers = @($sourceServerReview.Servers)
        Assert-ReportServerInventory -Servers $effectiveServers

        if ($sourceServerReview.Reloaded) {
            Export-SourceServerArtifact -Servers $effectiveServers -ArtifactPathSet $artifactPathSet -RuntimeContext $runtimeContext
            Write-ReportLog -Message ("Final scan target list was updated after manual review. Servers to scan: {0}." -f (Get-SafeCount -InputObject $effectiveServers)) -RuntimeContext $runtimeContext
        }

        $scanResultSet = Invoke-ReportScan -Servers $effectiveServers -ScanConfiguration $reportPlan.ScanConfiguration -ArtifactPathSet $artifactPathSet -RuntimeContext $runtimeContext
        Export-ReportResult -ExecutionConfiguration $reportPlan.ExecutionConfiguration -ScanResultSet $scanResultSet -ArtifactPathSet $artifactPathSet -ServerCount (Get-SafeCount -InputObject $effectiveServers) -RuntimeContext $runtimeContext
    }
    catch {
        Write-ReportLog -Message $_.Exception.Message -Level 'ERROR' -RuntimeContext $runtimeContext
        throw
    }
}













