function ConvertFrom-WinNTAdsPath {
    param(
        [Parameter(Mandatory)][string]$AdsPath
    )

    $normalizedPath = $AdsPath -replace '^WinNT://', ''
    $segments = @($normalizedPath -split '/' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    $authority = $null
    $name = $null

    if ((Get-SafeCount -InputObject $segments) -ge 3) {
        $segmentsCount = Get-SafeCount -InputObject $segments
        $authority = $segments[$segmentsCount - 2]
        $name = $segments[$segmentsCount - 1]
    }
    elseif ((Get-SafeCount -InputObject $segments) -eq 2) {
        $authority = $segments[0]
        $name = $segments[1]
    }
    elseif ((Get-SafeCount -InputObject $segments) -eq 1) {
        $name = $segments[0]
    }

    $principal = if (-not [string]::IsNullOrWhiteSpace($authority)) {
        '{0}\{1}' -f $authority, $name
    }
    else {
        $name
    }

    return [PSCustomObject]@{
        Authority = $authority
        Name      = $name
        Principal = $principal
    }
}

function Get-WinNTObjectSid {
    param([Parameter(Mandatory)]$WinNTObject)

    try {
        $objectSid = $WinNTObject.GetType().InvokeMember('objectSid', 'GetProperty', $null, $WinNTObject, $null)
        if ($objectSid -is [byte[]]) {
            return ([System.Security.Principal.SecurityIdentifier]::new($objectSid, 0)).Value
        }
    }
    catch {
        return $null
    }

    return $null
}

function Get-WinNTDirectoryEntry {
    param(
        [Parameter(Mandatory)][string]$AdsPath,
        [System.Management.Automation.PSCredential]$Credential
    )

    if ($null -eq $Credential) {
        return [System.DirectoryServices.DirectoryEntry]::new($AdsPath)
    }

    $networkCredential = $Credential.GetNetworkCredential()
    $bindUserName = $Credential.UserName

    if ([string]::IsNullOrWhiteSpace($bindUserName)) {
        $bindUserName = if (-not [string]::IsNullOrWhiteSpace($networkCredential.Domain)) {
            '{0}\{1}' -f $networkCredential.Domain, $networkCredential.UserName
        }
        else {
            $networkCredential.UserName
        }
    }

    return [System.DirectoryServices.DirectoryEntry]::new($AdsPath, $bindUserName, $networkCredential.Password)
}

function Get-MembershipIdentityKey {
    param([Parameter(Mandatory)][psobject]$MembershipRow)

    if (-not [string]::IsNullOrWhiteSpace([string]$MembershipRow.MemberSid)) {
        return ('SID::{0}' -f [string]$MembershipRow.MemberSid).ToUpperInvariant()
    }

    $principal = if (-not [string]::IsNullOrWhiteSpace([string]$MembershipRow.MemberPrincipal)) {
        [string]$MembershipRow.MemberPrincipal
    }
    else {
        [string]$MembershipRow.MemberName
    }

    return ('NAME::{0}::{1}' -f $principal, [string]$MembershipRow.MemberType).ToUpperInvariant()
}

function Merge-LocalGroupMembershipRowSet {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$PrimaryRows,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$FallbackRows
    )

    $mergedRows = New-Object System.Collections.Generic.List[object]
    $seenKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($row in $PrimaryRows) {
        [void]$mergedRows.Add($row)
        [void]$seenKeys.Add((Get-MembershipIdentityKey -MembershipRow $row))
    }

    foreach ($row in $FallbackRows) {
        $identityKey = Get-MembershipIdentityKey -MembershipRow $row
        if ($seenKeys.Add($identityKey)) {
            [void]$mergedRows.Add($row)
        }
    }

    return $mergedRows.ToArray()
}

function Get-WinNTLocalGroupMembership {
    param(
        [Parameter(Mandatory)][string]$ServerName,
        [Parameter(Mandatory)][psobject]$Group,
        [Parameter(Mandatory)][string]$CimProtocol,
        [Parameter(Mandatory)][System.Collections.Generic.HashSet[string]]$WellKnownAuthorityLookup,
        [System.Management.Automation.PSCredential]$Credential
    )

    $groupEntry = $null

    try {
        $groupAdsPath = 'WinNT://{0}/{1},group' -f $ServerName, [string]$Group.Name
        $groupEntry = Get-WinNTDirectoryEntry -AdsPath $groupAdsPath -Credential $Credential
        $memberObjects = @($groupEntry.psbase.Invoke('Members'))

        return @(
            foreach ($memberObject in $memberObjects) {
                $adsPath = [string]$memberObject.GetType().InvokeMember('ADsPath', 'GetProperty', $null, $memberObject, $null)
                $name = [string]$memberObject.GetType().InvokeMember('Name', 'GetProperty', $null, $memberObject, $null)
                $className = [string]$memberObject.GetType().InvokeMember('Class', 'GetProperty', $null, $memberObject, $null)
                $sid = Get-WinNTObjectSid -WinNTObject $memberObject
                $parsedIdentity = ConvertFrom-WinNTAdsPath -AdsPath $adsPath
                $authority = $parsedIdentity.Authority

                $isLocalAccount = (
                    -not [string]::IsNullOrWhiteSpace($authority) -and
                    (
                        $authority.Equals($ServerName, [System.StringComparison]::OrdinalIgnoreCase) -or
                        $authority.Equals([string]$Group.Domain, [System.StringComparison]::OrdinalIgnoreCase)
                    )
                )

                $memberType = switch -Regex ($className) {
                    '^group$' { 'Group' }
                    '^user$' { 'User' }
                    default {
                        if ([string]::IsNullOrWhiteSpace($className)) {
                            'Unknown'
                        }
                        else {
                            $className
                        }
                    }
                }

                $memberScope = if ($isLocalAccount) {
                    'Local'
                }
                elseif (-not [string]::IsNullOrWhiteSpace($authority) -and $WellKnownAuthorityLookup.Contains($authority)) {
                    'WellKnown'
                }
                else {
                    'Domain'
                }

                [PSCustomObject]@{
                    Server             = $ServerName
                    CimProtocol        = $CimProtocol
                    LocalGroup         = [string]$Group.Name
                    LocalGroupCaption  = [string]$Group.Caption
                    LocalGroupSid      = [string]$Group.SID
                    MemberName         = if (-not [string]::IsNullOrWhiteSpace($parsedIdentity.Name)) { $parsedIdentity.Name } else { $name }
                    MemberType         = $memberType
                    MemberClass        = if ([string]::IsNullOrWhiteSpace($className)) { 'WinNT_Unknown' } else { 'WinNT_{0}' -f $className }
                    MemberPrincipal    = $parsedIdentity.Principal
                    MemberCaption      = $parsedIdentity.Principal
                    MemberScope        = $memberScope
                    MemberAuthority    = $authority
                    MemberSource       = $authority
                    MemberLocalAccount = $isLocalAccount
                    MemberSid          = $sid
                    MemberPath         = $adsPath
                }
            }
        )
    }
    catch {
        Write-Verbose ("[{0}] WinNT fallback for group '{1}' failed: {2}" -f $ServerName, $Group.Name, $_.Exception.Message)
        return @()
    }
    finally {
        if ($null -ne $groupEntry) {
            $groupEntry.Dispose()
        }
    }
}

function Get-CimLocalGroupMembership {
    param(
        [Parameter(Mandatory)][Microsoft.Management.Infrastructure.CimSession]$CimSession,
        [Parameter(Mandatory)][string]$ServerName,
        [Parameter(Mandatory)][psobject]$Group,
        [Parameter(Mandatory)][string]$CimProtocol,
        [Parameter(Mandatory)][System.Collections.Generic.HashSet[string]]$WellKnownAuthorityLookup,
        [System.Management.Automation.PSCredential]$Credential,
        [ValidateRange(5, 300)][uint32]$OperationTimeoutSec = 20,
        [ValidateRange(1, 5)][int]$RetryCount = 2,
        [ValidateRange(1, 30)][int]$RetryDelaySec = 2,
        [ValidateRange(1, 600)][int]$SlowQueryWarningSec = 15,
        [switch]$IncludeEmptyGroups,
        [psobject]$RuntimeContext
    )

    $escapedDomain = ([string]$Group.Domain).Replace("'", "''")
    $escapedName = ([string]$Group.Name).Replace("'", "''")
    $query = "ASSOCIATORS OF {Win32_Group.Domain='$escapedDomain',Name='$escapedName'} WHERE AssocClass=Win32_GroupUser Role=GroupComponent"
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $memberRecords = @(Invoke-CimQueryWithRetry -CimSession $CimSession -Query $query -OperationTimeoutSec $OperationTimeoutSec -RetryCount $RetryCount -RetryDelaySec $RetryDelaySec)
    }
    finally {
        $stopwatch.Stop()
    }

    $memberRecords = @($memberRecords | Where-Object { $null -ne $_ })

    if ($stopwatch.Elapsed.TotalSeconds -ge $SlowQueryWarningSec) {
        Write-ReportLog -Message ("Сервер {0}, группа {1}: ASSOCIATORS-запрос выполнялся {2:N1} c." -f $ServerName, $Group.Name, $stopwatch.Elapsed.TotalSeconds) -Level 'WARN' -RuntimeContext $RuntimeContext
    }

    $cimRows = @(
        if ((Get-SafeCount -InputObject $memberRecords) -eq 0) {
            if ($IncludeEmptyGroups) {
                Get-EmptyGroupMembershipRow -ServerName $ServerName -CimProtocol $CimProtocol -Group $Group
            }
            else {
                @()
            }
        }
        else {
            foreach ($memberRecord in $memberRecords) {
                ConvertTo-LocalGroupMembershipRow -ServerName $ServerName -CimProtocol $CimProtocol -Group $Group -MemberRecord $memberRecord -WellKnownAuthorityLookup $WellKnownAuthorityLookup
            }
        }
    )

    $cimRows = @($cimRows | Where-Object { $null -ne $_ })
    $winNTRows = @(Get-WinNTLocalGroupMembership -ServerName $ServerName -Group $Group -CimProtocol $CimProtocol -WellKnownAuthorityLookup $WellKnownAuthorityLookup -Credential $Credential | Where-Object { $null -ne $_ })
    $mergedRows = @(Merge-LocalGroupMembershipRowSet -PrimaryRows @($cimRows) -FallbackRows @($winNTRows) | Where-Object { $null -ne $_ })
    $addedRowsCount = (Get-SafeCount -InputObject $mergedRows) - (Get-SafeCount -InputObject $cimRows)

    if ($addedRowsCount -gt 0) {
        Write-ReportLog -Message ("Сервер {0}, группа {1}: WinNT fallback добавил недостающих участников: {2}." -f $ServerName, $Group.Name, $addedRowsCount) -Level 'WARN' -RuntimeContext $RuntimeContext
    }

    return $mergedRows
}

function Invoke-ServerScanProtocol {
    param(
        [Parameter(Mandatory)][psobject]$Server,
        [psobject]$ScanConfiguration,
        [string[]]$LocalGroups,
        [System.Management.Automation.PSCredential]$Credential,
        [ValidateSet('Dcom', 'Wsman')][string]$CimProtocol = 'Dcom',
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
        ConnectivityTimeoutMs  = 1500
        ReachabilityMode       = 'Probe'
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
    $groupsLookup = Get-LocalGroupLookup -LocalGroups $effectiveScanConfiguration.LocalGroups
    $wellKnownAuthorityLookup = Get-WellKnownAuthorityLookup -WellKnownAuthorities $effectiveScanConfiguration.WellKnownAuthorities
    $authenticationAttempts = New-Object System.Collections.Generic.List[object]
    [void]$authenticationAttempts.Add([PSCustomObject]@{
        Label      = if ($null -ne $effectiveScanConfiguration.Credential) { 'ExplicitCredential' } else { 'CurrentSession' }
        Credential = $effectiveScanConfiguration.Credential
    })

    if ($null -ne $effectiveScanConfiguration.Credential) {
        [void]$authenticationAttempts.Add([PSCustomObject]@{
            Label      = 'CurrentSession'
            Credential = $null
        })
    }

    $attemptErrors = New-Object System.Collections.Generic.List[string]

    foreach ($authenticationAttempt in $authenticationAttempts) {
        $session = $null
        $members = New-Object System.Collections.Generic.List[object]
        $matchedRows = New-Object System.Collections.Generic.List[object]
        $membersCollected = 0

        try {
            $sessionOption = New-CimSessionOption -Protocol $effectiveScanConfiguration.CimProtocol
            $sessionParams = @{
                ComputerName        = $Server.ConnectionName
                SessionOption       = $sessionOption
                OperationTimeoutSec = $effectiveScanConfiguration.CimOperationTimeoutSec
            }

            if ($null -ne $authenticationAttempt.Credential) {
                $sessionParams['Credential'] = $authenticationAttempt.Credential
            }

            $session = New-CimSession @sessionParams
            $groups = @(Get-CimLocalGroupList -CimSession $session -GroupsLookup $groupsLookup -OperationTimeoutSec $effectiveScanConfiguration.CimOperationTimeoutSec -RetryCount $effectiveScanConfiguration.CimRetryCount -RetryDelaySec $effectiveScanConfiguration.CimRetryDelaySec -ServerName $Server.ConnectionName -CimProtocol $effectiveScanConfiguration.CimProtocol | Where-Object { $null -ne $_ })

            foreach ($group in $groups) {
                $groupRows = @(Get-CimLocalGroupMembership -CimSession $session -ServerName $Server.ConnectionName -Group $group -CimProtocol $effectiveScanConfiguration.CimProtocol -WellKnownAuthorityLookup $wellKnownAuthorityLookup -Credential $authenticationAttempt.Credential -OperationTimeoutSec $effectiveScanConfiguration.CimOperationTimeoutSec -RetryCount $effectiveScanConfiguration.CimRetryCount -RetryDelaySec $effectiveScanConfiguration.CimRetryDelaySec -SlowQueryWarningSec $effectiveScanConfiguration.CimSlowQueryWarningSec -IncludeEmptyGroups:$effectiveScanConfiguration.IncludeEmptyGroups -RuntimeContext $RuntimeContext | Where-Object { $null -ne $_ })

                foreach ($memberRow in $groupRows) {
                    if (-not [string]::IsNullOrWhiteSpace($memberRow.MemberName)) {
                        $membersCollected++
                    }

                    if ($effectiveScanConfiguration.OperationMode -eq 'AllMembers') {
                        [void]$members.Add($memberRow)
                        continue
                    }

                    if (Test-IdentityMatch -MembershipRow $memberRow -SearchIdentity $effectiveScanConfiguration.SearchIdentity) {
                        [void]$matchedRows.Add((Get-IdentityMatchRow -SearchIdentity $effectiveScanConfiguration.SearchIdentity -MemberRow $memberRow))
                    }
                }
            }

            $membersArray = @($members.ToArray() | Where-Object { $null -ne $_ })
            $matchesArray = @($matchedRows.ToArray() | Where-Object { $null -ne $_ })

            if ($authenticationAttempt.Label -eq 'CurrentSession' -and $null -ne $effectiveScanConfiguration.Credential) {
                Write-ReportLog -Message ("Сервер {0}: явные учётные данные не подошли, сбор успешно продолжен под текущей Windows-сессией." -f $Server.ConnectionName) -Level 'WARN' -RuntimeContext $RuntimeContext
            }

            return (
                New-ProtocolScanResult `
                    -QueryStatus 'Success' `
                    -CimProtocol $effectiveScanConfiguration.CimProtocol `
                    -GroupsCollected (Get-SafeCount -InputObject $groups) `
                    -MembersCollected $membersCollected `
                    -MatchesFound $(if ($effectiveScanConfiguration.OperationMode -eq 'FindIdentity') { Get-SafeCount -InputObject $matchesArray } else { 0 }) `
                    -ErrorMessage $null `
                    -Members $(if ($effectiveScanConfiguration.OperationMode -eq 'AllMembers') { $membersArray } else { @() }) `
                    -MatchedRows $(if ($effectiveScanConfiguration.OperationMode -eq 'FindIdentity') { $matchesArray } else { @() })
            )
        }
        catch {
            $attemptMessage = $_.Exception.Message
            [void]$attemptErrors.Add(("{0}: {1}" -f $authenticationAttempt.Label, $attemptMessage))

            $shouldTryCurrentSession = (
                $authenticationAttempt.Label -eq 'ExplicitCredential' -and
                $null -ne $effectiveScanConfiguration.Credential -and
                (Test-IsAuthenticationCimError -InputObject $_)
            )

            if ($shouldTryCurrentSession) {
                Write-ReportLog -Message ("Сервер {0}: явные учётные данные не прошли ({1}). Пробую текущую Windows-сессию." -f $Server.ConnectionName, $attemptMessage) -Level 'WARN' -RuntimeContext $RuntimeContext
                continue
            }
        }
        finally {
            if ($null -ne $session) {
                $session | Remove-CimSession
            }
        }
    }

    return (New-ProtocolScanResult -QueryStatus 'Error' -CimProtocol $effectiveScanConfiguration.CimProtocol -ErrorMessage ($attemptErrors -join ' | '))
}
