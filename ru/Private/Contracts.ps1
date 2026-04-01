function New-ExecutionModeResolutionResult {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure factory function.')]
    param(
        [string]$InputMode,
        [string]$OperationMode
    )

    return [PSCustomObject]@{
        InputMode     = $InputMode
        OperationMode = $OperationMode
    }
}

function New-ExecutionInputConfiguration {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure factory function.')]
    param(
        [Parameter(Mandatory)][string]$InputMode,
        [string]$ServerListPath,
        [Parameter(Mandatory)][string]$OperationMode,
        [string]$SearchIdentity
    )

    return [PSCustomObject]@{
        InputMode      = $InputMode
        ServerListPath = $ServerListPath
        OperationMode  = $OperationMode
        SearchIdentity = $SearchIdentity
    }
}

function New-ExecutionCredentialConfigurationResult {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure factory function.')]
    param(
        [System.Management.Automation.PSCredential]$ADCredential,
        [System.Management.Automation.PSCredential]$ServerCredential,
        [Parameter(Mandatory)][string]$AuthMode
    )

    return [PSCustomObject]@{
        ADCredential        = $ADCredential
        ServerCredential    = $ServerCredential
        CredentialSelection = $AuthMode
    }
}

function New-ExecutionConfigurationResult {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure factory function.')]
    param(
        [Parameter(Mandatory)][string]$InputMode,
        [string]$ServerListPath,
        [Parameter(Mandatory)][string]$OperationMode,
        [string]$SearchIdentity,
        [System.Management.Automation.PSCredential]$ADCredential,
        [System.Management.Automation.PSCredential]$ServerCredential,
        [Parameter(Mandatory)][string]$AuthMode,
        [Parameter(Mandatory)][string]$ADAuthContext,
        [Parameter(Mandatory)][string]$ServerAuthContext
    )

    return [PSCustomObject]@{
        InputMode           = $InputMode
        ServerListPath      = $ServerListPath
        OperationMode       = $OperationMode
        SearchIdentity      = $SearchIdentity
        ADCredential        = $ADCredential
        ServerCredential    = $ServerCredential
        CredentialSelection = $AuthMode
        ADAuthContext       = $ADAuthContext
        ServerAuthContext   = $ServerAuthContext
    }
}

function New-ServerScanConfiguration {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure factory function.')]
    param(
        [string[]]$LocalGroups,
        [System.Management.Automation.PSCredential]$Credential,
        [Parameter(Mandatory)][string]$CimProtocol,
        [Parameter(Mandatory)][int]$ConnectivityTimeoutMs,
        [Parameter(Mandatory)][string]$ReachabilityMode,
        [Parameter(Mandatory)][uint32]$CimOperationTimeoutSec,
        [Parameter(Mandatory)][int]$CimRetryCount,
        [Parameter(Mandatory)][int]$CimRetryDelaySec,
        [bool]$IncludeEmptyGroups = $false,
        [Parameter(Mandatory)][string]$OperationMode,
        [string]$SearchIdentity,
        [Parameter(Mandatory)][int]$ThrottleLimit,
        [string[]]$WellKnownAuthorities,
        [Parameter(Mandatory)][int]$CimSlowQueryWarningSec
    )

    return [PSCustomObject]@{
        LocalGroups            = @($LocalGroups)
        Credential             = $Credential
        CimProtocol            = $CimProtocol
        ConnectivityTimeoutMs  = $ConnectivityTimeoutMs
        ReachabilityMode       = $ReachabilityMode
        CimOperationTimeoutSec = $CimOperationTimeoutSec
        CimRetryCount          = $CimRetryCount
        CimRetryDelaySec       = $CimRetryDelaySec
        IncludeEmptyGroups     = $IncludeEmptyGroups
        OperationMode          = $OperationMode
        SearchIdentity         = $SearchIdentity
        ThrottleLimit          = $ThrottleLimit
        WellKnownAuthorities   = @($WellKnownAuthorities)
        CimSlowQueryWarningSec = $CimSlowQueryWarningSec
    }
}

function New-ServerInventoryRow {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure factory function.')]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$ConnectionName,
        [string]$DnsHostName,
        [string]$OperatingSystem,
        [string]$OperatingSystemVersion,
        $Enabled = $null,
        [string]$DistinguishedName,
        [AllowNull()][Nullable[datetime]]$PasswordLastSetUtc,
        [AllowNull()][Nullable[datetime]]$LastLogonTimestampUtc,
        [Parameter(Mandatory)][string]$SourceMode
    )

    $normalizedDnsHostName = if ([string]::IsNullOrWhiteSpace($DnsHostName)) { $null } else { $DnsHostName }
    $normalizedOperatingSystem = if ([string]::IsNullOrWhiteSpace($OperatingSystem)) { $null } else { $OperatingSystem }
    $normalizedOperatingSystemVersion = if ([string]::IsNullOrWhiteSpace($OperatingSystemVersion)) { $null } else { $OperatingSystemVersion }
    $normalizedDistinguishedName = if ([string]::IsNullOrWhiteSpace($DistinguishedName)) { $null } else { $DistinguishedName }

    return [PSCustomObject]@{
        Name                   = $Name
        ConnectionName         = $ConnectionName
        DnsHostName            = $normalizedDnsHostName
        OperatingSystem        = $normalizedOperatingSystem
        OperatingSystemVersion = $normalizedOperatingSystemVersion
        Enabled                = $Enabled
        DistinguishedName      = $normalizedDistinguishedName
        PasswordLastSetUtc     = $PasswordLastSetUtc
        LastLogonTimestampUtc  = $LastLogonTimestampUtc
        SourceMode             = $SourceMode
    }
}

function New-SourceServerInventoryResult {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure factory function.')]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Servers,
        [Parameter(Mandatory)][string]$LogMessage
    )

    return [PSCustomObject]@{
        Servers    = @($Servers)
        LogMessage = $LogMessage
    }
}

function New-SourceServerReviewResult {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure factory function.')]
    param(
        [AllowEmptyCollection()][object[]]$Servers = @(),
        [bool]$Cancelled = $false,
        [bool]$ReviewPerformed = $false,
        [bool]$Reloaded = $false
    )

    return [PSCustomObject]@{
        Servers         = @($Servers)
        Cancelled       = $Cancelled
        ReviewPerformed = $ReviewPerformed
        Reloaded        = $Reloaded
    }
}

function New-ReportArtifactPathSet {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure factory function.')]
    param([Parameter(Mandatory)][string]$OutputDirectory)

    return [PSCustomObject]@{
        ServerCsvPath        = Join-Path -Path $OutputDirectory -ChildPath 'server_source_list.csv'
        ServerTxtPath        = Join-Path -Path $OutputDirectory -ChildPath 'server_source_list.txt'
        MembershipCsvPath    = Join-Path -Path $OutputDirectory -ChildPath 'server_local_group_members.csv'
        SummaryCsvPath       = Join-Path -Path $OutputDirectory -ChildPath 'server_local_group_summary.csv'
        IdentityMatchCsvPath = Join-Path -Path $OutputDirectory -ChildPath 'identity_search_matches.csv'
        StatusCsvPath        = Join-Path -Path $OutputDirectory -ChildPath 'server_membership_status.csv'
    }
}

function New-ReachabilityResult {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure factory function.')]
    param(
        $PingSucceeded,
        [AllowEmptyCollection()][int[]]$OpenPorts = @(),
        [AllowEmptyCollection()][string[]]$ReachableProtocols = @(),
        [AllowEmptyCollection()][string[]]$RecommendedProtocolOrder = @(),
        [Parameter(Mandatory)][bool]$CanAttemptCim,
        [Parameter(Mandatory)][string]$ReachabilitySummary
    )

    return [PSCustomObject]@{
        PingSucceeded            = $PingSucceeded
        OpenPorts                = @($OpenPorts)
        ReachableProtocols       = @($ReachableProtocols)
        RecommendedProtocolOrder = @($RecommendedProtocolOrder)
        CanAttemptCim            = $CanAttemptCim
        ReachabilitySummary      = $ReachabilitySummary
    }
}

function New-ProtocolScanResult {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure factory function.')]
    param(
        [Parameter(Mandatory)][string]$QueryStatus,
        [string]$CimProtocol,
        [int]$GroupsCollected = 0,
        [int]$MembersCollected = 0,
        [int]$MatchesFound = 0,
        [string]$ErrorMessage,
        [AllowEmptyCollection()][object[]]$Members = @(),
        [AllowEmptyCollection()][object[]]$MatchedRows = @()
    )

    return [PSCustomObject]@{
        QueryStatus      = $QueryStatus
        CimProtocol      = $CimProtocol
        GroupsCollected  = $GroupsCollected
        MembersCollected = $MembersCollected
        MatchesFound     = $MatchesFound
        ErrorMessage     = $ErrorMessage
        Members          = @($Members)
        Matches          = @($MatchedRows)
    }
}

function New-ServerStatusRow {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure factory function.')]
    param(
        [Parameter(Mandatory)][string]$Server,
        [string]$DnsHostName,
        [Parameter(Mandatory)][string]$QueryStatus,
        [string]$RequestedCimProtocol,
        [string]$EffectiveCimProtocol,
        [string]$AttemptedCimProtocols,
        [bool]$FallbackUsed = $false,
        [string]$ReachabilityMode,
        $PingSucceeded = $null,
        [string]$ReachabilitySummary,
        [int]$GroupsCollected = 0,
        [int]$MembersCollected = 0,
        [int]$MatchesFound = 0,
        [string]$ErrorMessage
    )

    return [PSCustomObject]@{
        Server                = $Server
        DnsHostName           = $DnsHostName
        QueryStatus           = $QueryStatus
        RequestedCimProtocol  = $RequestedCimProtocol
        EffectiveCimProtocol  = $EffectiveCimProtocol
        AttemptedCimProtocols = $AttemptedCimProtocols
        FallbackUsed          = $FallbackUsed
        ReachabilityMode      = $ReachabilityMode
        PingSucceeded         = $PingSucceeded
        ReachabilitySummary   = $ReachabilitySummary
        GroupsCollected       = $GroupsCollected
        MembersCollected      = $MembersCollected
        MatchesFound          = $MatchesFound
        ErrorMessage          = $ErrorMessage
    }
}

function New-ServerScanResult {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure factory function.')]
    param(
        [Parameter(Mandatory)][psobject]$Status,
        [AllowEmptyCollection()][object[]]$Members = @(),
        [AllowEmptyCollection()][object[]]$MatchedRows = @()
    )

    return [PSCustomObject]@{
        Status  = $Status
        Members = @($Members)
        Matches = @($MatchedRows)
    }
}

function New-MembershipSummaryRow {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure factory function.')]
    param(
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][string]$LocalGroup,
        [string]$LocalGroupCaption,
        [string]$LocalGroupSid,
        [Parameter(Mandatory)][int]$MemberCount
    )

    return [PSCustomObject]@{
        Server            = $Server
        LocalGroup        = $LocalGroup
        LocalGroupCaption = $LocalGroupCaption
        LocalGroupSid     = $LocalGroupSid
        MemberCount       = $MemberCount
    }
}

function New-ServerScanResultSet {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure factory function.')]
    param(
        [AllowNull()][AllowEmptyCollection()][object[]]$StatusRows = @(),
        [AllowNull()][AllowEmptyCollection()][object[]]$MembershipRows = @(),
        [AllowNull()][AllowEmptyCollection()][object[]]$IdentityMatchRows = @()
    )

    return [PSCustomObject]@{
        StatusRows        = @($StatusRows | Where-Object { $null -ne $_ })
        MembershipRows    = @($MembershipRows | Where-Object { $null -ne $_ })
        IdentityMatchRows = @($IdentityMatchRows | Where-Object { $null -ne $_ })
    }
}

function New-ServerStalenessState {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure factory function.')]
    param(
        [Parameter(Mandatory)][bool]$IsStale,
        [AllowNull()][Nullable[datetime]]$PasswordLastSetUtc,
        [AllowNull()][Nullable[datetime]]$LastLogonTimestampUtc,
        [AllowEmptyCollection()][string[]]$Reasons = @(),
        [string]$ReasonText
    )

    return [PSCustomObject]@{
        IsStale               = $IsStale
        PasswordLastSetUtc    = $PasswordLastSetUtc
        LastLogonTimestampUtc = $LastLogonTimestampUtc
        Reasons               = @($Reasons)
        ReasonText            = $ReasonText
    }
}

function New-CimErrorFactSet {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure factory function.')]
    param(
        [string]$FullyQualifiedErrorId,
        [string]$CategoryReason,
        [string]$MessageText,
        [AllowEmptyCollection()][string[]]$ExceptionTypeNames = @(),
        [AllowEmptyCollection()][int[]]$HResults = @(),
        [AllowEmptyCollection()][int[]]$NativeErrorCodes = @(),
        [string]$SearchText
    )

    return [PSCustomObject]@{
        FullyQualifiedErrorId = $FullyQualifiedErrorId
        CategoryReason        = $CategoryReason
        MessageText           = $MessageText
        ExceptionTypeNames    = @($ExceptionTypeNames)
        HResults              = @($HResults)
        NativeErrorCodes      = @($NativeErrorCodes)
        SearchText            = $SearchText
    }
}

function New-LocalGroupMembershipRow {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure factory function.')]
    param(
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][string]$CimProtocol,
        [Parameter(Mandatory)][string]$LocalGroup,
        [string]$LocalGroupCaption,
        [string]$LocalGroupSid,
        [string]$MemberName,
        [string]$MemberType,
        [string]$MemberClass,
        [string]$MemberPrincipal,
        [string]$MemberCaption,
        [string]$MemberScope,
        [string]$MemberAuthority,
        [string]$MemberSource,
        $MemberLocalAccount = $null,
        [string]$MemberSid,
        [string]$MemberPath
    )

    return [PSCustomObject]@{
        Server             = $Server
        CimProtocol        = $CimProtocol
        LocalGroup         = $LocalGroup
        LocalGroupCaption  = $LocalGroupCaption
        LocalGroupSid      = $LocalGroupSid
        MemberName         = $MemberName
        MemberType         = $MemberType
        MemberClass        = $MemberClass
        MemberPrincipal    = $MemberPrincipal
        MemberCaption      = $MemberCaption
        MemberScope        = $MemberScope
        MemberAuthority    = $MemberAuthority
        MemberSource       = $MemberSource
        MemberLocalAccount = $MemberLocalAccount
        MemberSid          = $MemberSid
        MemberPath         = $MemberPath
    }
}

function New-IdentityMatchRow {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure factory function.')]
    param(
        [Parameter(Mandatory)][string]$SearchIdentity,
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][string]$CimProtocol,
        [Parameter(Mandatory)][string]$LocalGroup,
        [string]$LocalGroupCaption,
        [string]$LocalGroupSid,
        [string]$MemberName,
        [string]$MemberType,
        [string]$MemberClass,
        [string]$MemberPrincipal,
        [string]$MemberCaption,
        [string]$MemberScope,
        [string]$MemberAuthority,
        [string]$MemberSource,
        $MemberLocalAccount = $null,
        [string]$MemberSid,
        [string]$MemberPath
    )

    return [PSCustomObject]@{
        SearchIdentity     = $SearchIdentity
        Server             = $Server
        CimProtocol        = $CimProtocol
        LocalGroup         = $LocalGroup
        LocalGroupCaption  = $LocalGroupCaption
        LocalGroupSid      = $LocalGroupSid
        MemberName         = $MemberName
        MemberType         = $MemberType
        MemberClass        = $MemberClass
        MemberPrincipal    = $MemberPrincipal
        MemberCaption      = $MemberCaption
        MemberScope        = $MemberScope
        MemberAuthority    = $MemberAuthority
        MemberSource       = $MemberSource
        MemberLocalAccount = $MemberLocalAccount
        MemberSid          = $MemberSid
        MemberPath         = $MemberPath
    }
}
