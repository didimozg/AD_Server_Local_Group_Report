function Test-IdentityMatch {
    param(
        [Parameter(Mandatory)][psobject]$MembershipRow,
        [Parameter(Mandatory)][string]$SearchIdentity
    )

    $normalizedSearch = $SearchIdentity.Trim()
    if ([string]::IsNullOrWhiteSpace($normalizedSearch)) {
        return $false
    }

    $searchUsesWildcard = ($normalizedSearch.Contains('*') -or $normalizedSearch.Contains('?'))
    $leafSearch = $null
    if (-not $searchUsesWildcard -and $normalizedSearch -notmatch '[\\/]') {
        $leafSearch = $normalizedSearch
    }

    foreach ($propertyName in @('MemberName', 'MemberPrincipal', 'MemberCaption', 'MemberSid', 'MemberPath')) {
        $candidateValue = [string]$MembershipRow.$propertyName
        if ([string]::IsNullOrWhiteSpace($candidateValue)) {
            continue
        }

        $trimmedValue = $candidateValue.Trim()

        if ($searchUsesWildcard) {
            if ($trimmedValue -like $normalizedSearch) {
                return $true
            }
        }
        elseif ($trimmedValue -ieq $normalizedSearch) {
            return $true
        }

        if ($null -ne $leafSearch) {
            $leafValue = $trimmedValue -replace '^.*[\\/]', ''
            if ($leafValue -ieq $leafSearch) {
                return $true
            }
        }
    }

    return $false
}

function Get-CimProtocolOrder {
    param(
        [ValidateSet('Dcom', 'Wsman')]
        [string]$PreferredProtocol = 'Dcom'
    )

    if ($PreferredProtocol -eq 'Dcom') {
        return @('Dcom', 'Wsman')
    }

    return @('Wsman', 'Dcom')
}

function Get-CimProtocolProbePort {
    param(
        [ValidateSet('Dcom', 'Wsman')]
        [string]$CimProtocol
    )

    switch ($CimProtocol) {
        'Dcom' { return @(135) }
        'Wsman' { return @(5985, 5986) }
    }
}

function Test-TcpPortReachability {
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][int]$Port,
        [ValidateRange(250, 30000)][int]$TimeoutMs = 1500
    )

    $tcpClient = [System.Net.Sockets.TcpClient]::new()

    try {
        $connectTask = $tcpClient.ConnectAsync($ComputerName, $Port)
        if (-not $connectTask.Wait($TimeoutMs)) {
            return $false
        }

        return $tcpClient.Connected
    }
    catch {
        return $false
    }
    finally {
        $tcpClient.Dispose()
    }
}

function Test-ServerReachability {
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][string[]]$ProtocolOrder,
        [ValidateRange(250, 30000)][int]$TimeoutMs = 1500,
        [ValidateSet('Probe', 'Direct', 'PingOnly', 'None')][string]$ReachabilityMode = 'Probe'
    )

    if ($ReachabilityMode -eq 'Direct') {
        return (New-ReachabilityResult -PingSucceeded $null -CanAttemptCim $true -RecommendedProtocolOrder @($ProtocolOrder) -ReachabilitySummary 'Mode=Direct; Ping=not-tested; OpenPorts=not-tested')
    }

    if ($ReachabilityMode -eq 'None') {
        return (New-ReachabilityResult -PingSucceeded $null -CanAttemptCim $true -RecommendedProtocolOrder @($ProtocolOrder) -ReachabilitySummary 'Mode=None; Ping=not-tested; OpenPorts=not-tested')
    }

    $pingSucceeded = Test-Connection -ComputerName $ComputerName -Count 1 -Quiet -ErrorAction SilentlyContinue

    if ($ReachabilityMode -eq 'PingOnly') {
        return (New-ReachabilityResult -PingSucceeded $pingSucceeded -CanAttemptCim $pingSucceeded -RecommendedProtocolOrder @($ProtocolOrder) -ReachabilitySummary ("Mode=PingOnly; Ping={0}; OpenPorts=not-tested" -f $pingSucceeded))
    }

    $protocolsWithOpenPorts = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $openPorts = New-Object System.Collections.Generic.List[int]

    foreach ($protocol in ($ProtocolOrder | Select-Object -Unique)) {
        foreach ($port in (Get-CimProtocolProbePort -CimProtocol $protocol)) {
            if (Test-TcpPortReachability -ComputerName $ComputerName -Port $port -TimeoutMs $TimeoutMs) {
                if (-not $openPorts.Contains($port)) {
                    [void]$openPorts.Add($port)
                }

                [void]$protocolsWithOpenPorts.Add($protocol)
            }
        }
    }

    $openPortsArray = $openPorts.ToArray() | Sort-Object
    $reachableProtocols = @(
        foreach ($protocol in $ProtocolOrder) {
            if ($protocolsWithOpenPorts.Contains($protocol)) {
                $protocol
            }
        }
    )

    $recommendedProtocolOrder = if ($pingSucceeded -or (Get-SafeCount -InputObject $reachableProtocols) -eq 0) {
        @($ProtocolOrder)
    }
    else {
        @(
            $reachableProtocols
            foreach ($protocol in $ProtocolOrder) {
                if ($reachableProtocols -notcontains $protocol) {
                    $protocol
                }
            }
        )
    }

    $canAttemptCim = $pingSucceeded -or (Get-SafeCount -InputObject $openPortsArray) -gt 0
    $reachabilitySummary = "Mode=Probe; Ping={0}; OpenPorts={1}" -f $pingSucceeded, ($(if ((Get-SafeCount -InputObject $openPortsArray) -gt 0) { $openPortsArray -join ',' } else { 'none' }))

    return (New-ReachabilityResult -PingSucceeded $pingSucceeded -OpenPorts $openPortsArray -ReachableProtocols $reachableProtocols -RecommendedProtocolOrder $recommendedProtocolOrder -CanAttemptCim $canAttemptCim -ReachabilitySummary $reachabilitySummary)
}

function Get-CimErrorFactSet {
    param([Alias('Message')][AllowNull()]$InputObject)

    $errorRecord = $null
    $exception = $null
    $fallbackText = $null

    if ($InputObject -is [System.Management.Automation.ErrorRecord]) {
        $errorRecord = [System.Management.Automation.ErrorRecord]$InputObject
        $exception = $errorRecord.Exception
    }
    elseif ($InputObject -is [System.Exception]) {
        $exception = [System.Exception]$InputObject
    }
    elseif ($null -ne $InputObject) {
        $fallbackText = [string]$InputObject
    }

    $messageParts = New-Object System.Collections.Generic.List[string]
    $typeNames = New-Object System.Collections.Generic.List[string]
    $hresults = New-Object System.Collections.Generic.List[int]
    $nativeErrorCodes = New-Object System.Collections.Generic.List[int]

    if ($errorRecord -and -not [string]::IsNullOrWhiteSpace([string]$errorRecord.FullyQualifiedErrorId)) {
        [void]$messageParts.Add([string]$errorRecord.FullyQualifiedErrorId)
    }

    if ($errorRecord -and $null -ne $errorRecord.CategoryInfo -and -not [string]::IsNullOrWhiteSpace([string]$errorRecord.CategoryInfo.Reason)) {
        [void]$messageParts.Add([string]$errorRecord.CategoryInfo.Reason)
    }

    $currentException = $exception
    while ($null -ne $currentException) {
        if (-not [string]::IsNullOrWhiteSpace($currentException.Message)) {
            [void]$messageParts.Add($currentException.Message)
        }

        [void]$typeNames.Add($currentException.GetType().FullName)
        [void]$hresults.Add($currentException.HResult)
        if ($currentException -is [System.ComponentModel.Win32Exception]) {
            [void]$nativeErrorCodes.Add(([System.ComponentModel.Win32Exception]$currentException).NativeErrorCode)
        }
        $currentException = $currentException.InnerException
    }

    if (-not [string]::IsNullOrWhiteSpace($fallbackText)) {
        [void]$messageParts.Add($fallbackText)
    }

    $uniqueMessageParts = @($messageParts | Select-Object -Unique)
    $uniqueTypeNames = @($typeNames | Select-Object -Unique)
    $uniqueHResults = @($hresults | Select-Object -Unique)
    $uniqueNativeErrorCodes = @($nativeErrorCodes | Select-Object -Unique)
    $searchText = $uniqueMessageParts -join ' | '

    return (
        New-CimErrorFactSet `
            -FullyQualifiedErrorId $(if ($errorRecord) { [string]$errorRecord.FullyQualifiedErrorId } else { $null }) `
            -CategoryReason $(if ($errorRecord -and $null -ne $errorRecord.CategoryInfo) { [string]$errorRecord.CategoryInfo.Reason } else { $null }) `
            -MessageText $searchText `
            -ExceptionTypeNames $uniqueTypeNames `
            -HResults $uniqueHResults `
            -NativeErrorCodes $uniqueNativeErrorCodes `
            -SearchText $searchText
    )
}

function Test-ShouldRetryCimError {
    param([Alias('Message')][AllowNull()]$InputObject)

    $factSet = Get-CimErrorFactSet -InputObject $InputObject
    if ([string]::IsNullOrWhiteSpace($factSet.SearchText) -and (Get-SafeCount -InputObject $factSet.HResults) -eq 0 -and (Get-SafeCount -InputObject $factSet.ExceptionTypeNames) -eq 0) {
        return $false
    }

    if ($factSet.ExceptionTypeNames -contains 'System.TimeoutException') {
        return $true
    }

    if (@($factSet.HResults | Where-Object { $_ -in @(-2147023174, -2147024775, -2147023436) }).Count -gt 0) {
        return $true
    }

    if (@($factSet.NativeErrorCodes | Where-Object { $_ -in @(1722, 121, 1460) }).Count -gt 0) {
        return $true
    }

    if ($factSet.FullyQualifiedErrorId -match '0x800706BA|0x80070079|0x800705B4|OperationTimeout|TimeoutException|CimJob_BrokenCimSession|CimJob_OperationTimeout') {
        return $true
    }

    return (
        $factSet.SearchText -match 'RPC server is unavailable' -or
        $factSet.SearchText -match 'The semaphore timeout period has expired' -or
        $factSet.SearchText -match 'WinRM client cannot complete the operation' -or
        $factSet.SearchText -match 'quota' -or
        $factSet.SearchText -match 'timed out' -or
        $factSet.SearchText -match 'A retry should be performed'
    )
}

function Test-IsAuthenticationCimError {
    param([Alias('Message')][AllowNull()]$InputObject)

    $factSet = Get-CimErrorFactSet -InputObject $InputObject
    if ([string]::IsNullOrWhiteSpace($factSet.SearchText) -and (Get-SafeCount -InputObject $factSet.HResults) -eq 0 -and (Get-SafeCount -InputObject $factSet.ExceptionTypeNames) -eq 0) {
        return $false
    }

    if ($factSet.ExceptionTypeNames -contains 'System.UnauthorizedAccessException') {
        return $true
    }

    if (@($factSet.HResults | Where-Object { $_ -in @(-2147024891, -2147023570, -2147023569) }).Count -gt 0) {
        return $true
    }

    if (@($factSet.NativeErrorCodes | Where-Object { $_ -in @(5, 1326, 1327) }).Count -gt 0) {
        return $true
    }

    if ($factSet.FullyQualifiedErrorId -match '0x80070005|0x8007052E|0x8007052F|UnauthorizedAccess|AccessDenied|LogonFailure') {
        return $true
    }

    return (
        $factSet.SearchText -match 'Access is denied' -or
        $factSet.SearchText -match 'Отказано в доступе' -or
        $factSet.SearchText -match 'The user name or password is incorrect' -or
        $factSet.SearchText -match 'Неверное имя пользователя или пароль' -or
        $factSet.SearchText -match 'Logon failure' -or
        $factSet.SearchText -match 'account restrictions' -or
        $factSet.SearchText -match 'ограничений учетной записи' -or
        $factSet.SearchText -match 'authentication error' -or
        $factSet.SearchText -match 'The WinRM client cannot process the request'
    )
}

function Invoke-CimQueryWithRetry {
    param(
        [Parameter(Mandatory)][Microsoft.Management.Infrastructure.CimSession]$CimSession,
        [string]$ClassName,
        [string]$Filter,
        [string]$Query,
        [ValidateRange(5, 300)][uint32]$OperationTimeoutSec = 20,
        [ValidateRange(1, 5)][int]$RetryCount = 2,
        [ValidateRange(1, 30)][int]$RetryDelaySec = 2
    )

    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        try {
            $queryParameters = @{
                CimSession          = $CimSession
                OperationTimeoutSec = $OperationTimeoutSec
            }

            if (-not [string]::IsNullOrWhiteSpace($ClassName)) {
                $queryParameters['ClassName'] = $ClassName
            }

            if (-not [string]::IsNullOrWhiteSpace($Filter)) {
                $queryParameters['Filter'] = $Filter
            }

            if (-not [string]::IsNullOrWhiteSpace($Query)) {
                $queryParameters['Query'] = $Query
            }

            Write-Verbose ("CIM query attempt {0}/{1}: ClassName='{2}' Filter='{3}' Query='{4}'" -f $attempt, $RetryCount, $ClassName, $Filter, $Query)
            return @(Get-CimInstance @queryParameters)
        }
        catch {
            $errorMessage = $_.Exception.Message
            $shouldRetry = $attempt -lt $RetryCount -and (Test-ShouldRetryCimError -InputObject $_)

            if (-not $shouldRetry) {
                throw
            }

            Write-Verbose ("Transient CIM error. Retry in {0}s. Message: {1}" -f $RetryDelaySec, $errorMessage)
            Start-Sleep -Seconds $RetryDelaySec
        }
    }
}

function Get-WellKnownAuthorityLookup {
    param([string[]]$WellKnownAuthorities)

    $lookup = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($authority in $WellKnownAuthorities) {
        if (-not [string]::IsNullOrWhiteSpace($authority)) {
            [void]$lookup.Add($authority.Trim())
        }
    }

    return $lookup
}

function Get-LocalGroupLookup {
    param([string[]]$LocalGroups)

    if ($null -eq $LocalGroups -or (Get-SafeCount -InputObject $LocalGroups) -eq 0) {
        return $null
    }

    $groupsLookup = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($groupName in $LocalGroups) {
        if (-not [string]::IsNullOrWhiteSpace($groupName)) {
            [void]$groupsLookup.Add($groupName.Trim())
        }
    }

    return $groupsLookup
}

function Get-LocalGroupWqlFilter {
    param([System.Collections.Generic.HashSet[string]]$GroupsLookup)

    $wqlFilter = 'LocalAccount=True'
    if ($null -eq $GroupsLookup -or (Get-SafeCount -InputObject $GroupsLookup) -eq 0) {
        return $wqlFilter
    }

    $groupNamesFilter = @(
        foreach ($groupName in $GroupsLookup) {
            "Name='{0}'" -f $groupName.Replace("'", "''")
        }
    ) -join ' OR '

    return "{0} AND ({1})" -f $wqlFilter, $groupNamesFilter
}

function Get-CimLocalGroupList {
    param(
        [Parameter(Mandatory)][Microsoft.Management.Infrastructure.CimSession]$CimSession,
        [System.Collections.Generic.HashSet[string]]$GroupsLookup,
        [ValidateRange(5, 300)][uint32]$OperationTimeoutSec = 20,
        [ValidateRange(1, 5)][int]$RetryCount = 2,
        [ValidateRange(1, 30)][int]$RetryDelaySec = 2,
        [Parameter(Mandatory)][string]$ServerName,
        [Parameter(Mandatory)][string]$CimProtocol
    )

    $wqlFilter = Get-LocalGroupWqlFilter -GroupsLookup $GroupsLookup
    Write-Verbose ("[{0}] Attempting CIM protocol {1} with filter: {2}" -f $ServerName, $CimProtocol, $wqlFilter)

    return @(
        Invoke-CimQueryWithRetry -CimSession $CimSession -ClassName 'Win32_Group' -Filter $wqlFilter -OperationTimeoutSec $OperationTimeoutSec -RetryCount $RetryCount -RetryDelaySec $RetryDelaySec |
            Sort-Object -Property Name
    )
}

function Get-EmptyGroupMembershipRow {
    param(
        [Parameter(Mandatory)][string]$ServerName,
        [Parameter(Mandatory)][string]$CimProtocol,
        [Parameter(Mandatory)][psobject]$Group
    )

    return (
        New-LocalGroupMembershipRow `
            -Server $ServerName `
            -CimProtocol $CimProtocol `
            -LocalGroup ([string]$Group.Name) `
            -LocalGroupCaption ([string]$Group.Caption) `
            -LocalGroupSid ([string]$Group.SID) `
            -MemberName $null `
            -MemberType $null `
            -MemberClass $null `
            -MemberPrincipal $null `
            -MemberCaption $null `
            -MemberScope 'EmptyGroup' `
            -MemberAuthority $null `
            -MemberSource $null `
            -MemberLocalAccount $null `
            -MemberSid $null `
            -MemberPath $null
    )
}

function ConvertTo-LocalGroupMembershipRow {
    param(
        [Parameter(Mandatory)][string]$ServerName,
        [Parameter(Mandatory)][string]$CimProtocol,
        [Parameter(Mandatory)][psobject]$Group,
        [Parameter(Mandatory)][psobject]$MemberRecord,
        [Parameter(Mandatory)][System.Collections.Generic.HashSet[string]]$WellKnownAuthorityLookup
    )

    $className = if ($null -ne $MemberRecord.CimClass) { [string]$MemberRecord.CimClass.CimClassName } else { $null }
    $memberAuthority = [string]$MemberRecord.Domain
    $memberCaption = [string]$MemberRecord.Caption

    if ([string]::IsNullOrWhiteSpace($memberCaption)) {
        if (-not [string]::IsNullOrWhiteSpace($memberAuthority) -and -not [string]::IsNullOrWhiteSpace([string]$MemberRecord.Name)) {
            $memberCaption = '{0}\{1}' -f $memberAuthority, $MemberRecord.Name
        }
        else {
            $memberCaption = [string]$MemberRecord.Name
        }
    }

    $isLocalAccount = $false
    if ($null -ne $MemberRecord.LocalAccount) {
        $isLocalAccount = [bool]$MemberRecord.LocalAccount
    }

    $memberType = switch ($className) {
        'Win32_Group' { 'Group' }
        'Win32_UserAccount' { 'User' }
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
    elseif ($WellKnownAuthorityLookup.Contains($memberAuthority)) {
        'WellKnown'
    }
    else {
        'Domain'
    }

    return (
        New-LocalGroupMembershipRow `
            -Server $ServerName `
            -CimProtocol $CimProtocol `
            -LocalGroup ([string]$Group.Name) `
            -LocalGroupCaption ([string]$Group.Caption) `
            -LocalGroupSid ([string]$Group.SID) `
            -MemberName ([string]$MemberRecord.Name) `
            -MemberType $memberType `
            -MemberClass $className `
            -MemberPrincipal $memberCaption `
            -MemberCaption $memberCaption `
            -MemberScope $memberScope `
            -MemberAuthority $memberAuthority `
            -MemberSource $memberAuthority `
            -MemberLocalAccount $isLocalAccount `
            -MemberSid ([string]$MemberRecord.SID) `
            -MemberPath $null
    )
}

function Get-IdentityMatchRow {
    param(
        [Parameter(Mandatory)][string]$SearchIdentity,
        [Parameter(Mandatory)][psobject]$MemberRow
    )

    return (
        New-IdentityMatchRow `
            -SearchIdentity $SearchIdentity `
            -Server $MemberRow.Server `
            -CimProtocol $MemberRow.CimProtocol `
            -LocalGroup $MemberRow.LocalGroup `
            -LocalGroupCaption $MemberRow.LocalGroupCaption `
            -LocalGroupSid $MemberRow.LocalGroupSid `
            -MemberName $MemberRow.MemberName `
            -MemberType $MemberRow.MemberType `
            -MemberClass $MemberRow.MemberClass `
            -MemberPrincipal $MemberRow.MemberPrincipal `
            -MemberCaption $MemberRow.MemberCaption `
            -MemberScope $MemberRow.MemberScope `
            -MemberAuthority $MemberRow.MemberAuthority `
            -MemberSource $MemberRow.MemberSource `
            -MemberLocalAccount $MemberRow.MemberLocalAccount `
            -MemberSid $MemberRow.MemberSid `
            -MemberPath $MemberRow.MemberPath
    )
}
