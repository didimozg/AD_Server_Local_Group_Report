function Get-MembershipSummary {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$MembershipRows)

    if ((Get-SafeCount -InputObject $MembershipRows) -eq 0) {
        return @()
    }

    $summary = foreach ($groupBucket in ($MembershipRows | Group-Object -Property Server, LocalGroup)) {
        $firstRow = $groupBucket.Group[0]
        $memberCount = @($groupBucket.Group | Where-Object { -not [string]::IsNullOrWhiteSpace($_.MemberName) }).Count

        New-MembershipSummaryRow -Server $firstRow.Server -LocalGroup $firstRow.LocalGroup -LocalGroupCaption $firstRow.LocalGroupCaption -LocalGroupSid $firstRow.LocalGroupSid -MemberCount $memberCount
    }

    return @($summary | Sort-Object -Property Server, LocalGroup)
}

function Get-ReportArtifactPathSet {
    param([Parameter(Mandatory)][string]$OutputDirectory)

    return (New-ReportArtifactPathSet -OutputDirectory $OutputDirectory)
}

function Get-SourceServerInventory {
    param(
        [Parameter(Mandatory)][psobject]$ExecutionConfiguration,
        [string]$DomainServer,
        [string]$SearchBase,
        [string]$CsvServerColumn,
        [switch]$IncludeDisabledComputers,
        [ValidateRange(0, 3650)][int]$MaxComputerPasswordAgeDays = 0,
        [ValidateRange(0, 3650)][int]$MaxLastLogonAgeDays = 0,
        [psobject]$RuntimeContext
    )

    if ($ExecutionConfiguration.InputMode -eq 'AD') {
        return (
            New-SourceServerInventoryResult `
                -Servers @(Get-WindowsServerListFromAD -DomainServer $DomainServer -SearchBase $SearchBase -Credential $ExecutionConfiguration.ADCredential -IncludeDisabledComputers:$IncludeDisabledComputers -MaxComputerPasswordAgeDays $MaxComputerPasswordAgeDays -MaxLastLogonAgeDays $MaxLastLogonAgeDays -RuntimeContext $RuntimeContext) `
                -LogMessage 'The server list will be obtained from Active Directory.'
        )
    }

    return (
        New-SourceServerInventoryResult `
            -Servers @(Get-WindowsServerListFromFile -ServerListPath $ExecutionConfiguration.ServerListPath -CsvServerColumn $CsvServerColumn) `
            -LogMessage ("The server list will be obtained from file: {0}" -f $ExecutionConfiguration.ServerListPath)
    )
}

function Export-SourceServerArtifact {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Servers,
        [Parameter(Mandatory)][psobject]$ArtifactPathSet,
        [psobject]$RuntimeContext
    )

    Export-ReportCsv -Data @($Servers) -Path $ArtifactPathSet.ServerCsvPath -PropertyOrder @(
        'Name', 'ConnectionName', 'DnsHostName', 'OperatingSystem', 'OperatingSystemVersion', 'Enabled', 'DistinguishedName', 'PasswordLastSetUtc', 'LastLogonTimestampUtc', 'SourceMode'
    )

    $Servers.ConnectionName |
        Sort-Object |
        Set-Content -Path $ArtifactPathSet.ServerTxtPath -Encoding UTF8

    Write-ReportLog -Message ("Normalized server list saved: {0}" -f $ArtifactPathSet.ServerCsvPath) -RuntimeContext $RuntimeContext
    Write-ReportLog -Message ("Text server list saved: {0}" -f $ArtifactPathSet.ServerTxtPath) -RuntimeContext $RuntimeContext
}

function Test-ShouldOfferSourceServerReview {
    param(
        [Parameter(Mandatory)][psobject]$ExecutionConfiguration,
        [psobject]$RuntimeContext
    )

    $effectiveRuntimeContext = Resolve-ReportRuntimeContext -RuntimeContext $RuntimeContext
    return ($ExecutionConfiguration.InputMode -eq 'AD' -and $effectiveRuntimeContext.IsInteractiveRun)
}

function Open-SourceServerReviewTarget {
    param(
        [Parameter(Mandatory)][string]$Path,
        [psobject]$RuntimeContext
    )

    try {
        Invoke-Item -Path $Path -ErrorAction Stop
        Write-ReportLog -Message ("Opened server-list review target: {0}" -f $Path) -RuntimeContext $RuntimeContext
        return $true
    }
    catch {
        Write-ReportLog -Message ("Failed to open path '{0}': {1}" -f $Path, $_.Exception.Message) -Level 'WARN' -RuntimeContext $RuntimeContext
        return $false
    }
}

function Invoke-SourceServerListReview {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Servers,
        [Parameter(Mandatory)][psobject]$ExecutionConfiguration,
        [Parameter(Mandatory)][psobject]$ArtifactPathSet,
        [psobject]$RuntimeContext
    )

    $effectiveServers = @($Servers)
    if (-not (Test-ShouldOfferSourceServerReview -ExecutionConfiguration $ExecutionConfiguration -RuntimeContext $RuntimeContext)) {
        return (New-SourceServerReviewResult -Servers $effectiveServers)
    }

    Write-ConsoleLine -RuntimeContext $RuntimeContext
    Write-ConsoleLine -Message 'The AD server list has been created. You can review and adjust it before the main server scan starts.' -ForegroundColor Green -RuntimeContext $RuntimeContext

    $initialChoice = Read-MenuChoice -Title 'Review AD server list' -Prompt 'What do you want to do with the generated server list?' -DefaultChoice 1 -RuntimeContext $RuntimeContext -Options @(
        [PSCustomObject]@{ Value = 'Continue'; Label = 'Continue'; Description = 'Proceed directly to the server scan without manual review' },
        [PSCustomObject]@{ Value = 'OpenTxt'; Label = 'Open TXT'; Description = 'Open server_source_list.txt for review and possible editing' },
        [PSCustomObject]@{ Value = 'OpenFolder'; Label = 'Open folder'; Description = 'Open the output folder that contains the generated server list' },
        [PSCustomObject]@{ Value = 'Stop'; Label = 'Stop'; Description = 'Stop after the server list has been created' }
    )

    switch ($initialChoice) {
        'Continue' {
            return (New-SourceServerReviewResult -Servers $effectiveServers)
        }
        'Stop' {
            return (New-SourceServerReviewResult -Servers $effectiveServers -Cancelled $true -ReviewPerformed $true)
        }
        'OpenTxt' {
            [void](Open-SourceServerReviewTarget -Path $ArtifactPathSet.ServerTxtPath -RuntimeContext $RuntimeContext)
        }
        'OpenFolder' {
            [void](Open-SourceServerReviewTarget -Path (Split-Path -Path $ArtifactPathSet.ServerTxtPath -Parent) -RuntimeContext $RuntimeContext)
        }
    }

    while ($true) {
        $postReviewChoice = Read-MenuChoice -Title 'Review AD server list' -Prompt 'After reviewing the list, what should happen next?' -DefaultChoice 1 -RuntimeContext $RuntimeContext -Options @(
            [PSCustomObject]@{ Value = 'ContinueReload'; Label = 'Continue'; Description = 'Reload server_source_list.txt and continue with the server scan' },
            [PSCustomObject]@{ Value = 'OpenTxt'; Label = 'Open TXT'; Description = 'Open server_source_list.txt again for more edits' },
            [PSCustomObject]@{ Value = 'OpenFolder'; Label = 'Open folder'; Description = 'Open the output folder again' },
            [PSCustomObject]@{ Value = 'Stop'; Label = 'Stop'; Description = 'Stop without scanning the servers' }
        )

        switch ($postReviewChoice) {
            'ContinueReload' {
                $reloadedServers = @(Get-WindowsServerListFromFile -ServerListPath $ArtifactPathSet.ServerTxtPath)
                Write-ReportLog -Message ("Server list reloaded after manual review: {0}. Servers to scan: {1}." -f $ArtifactPathSet.ServerTxtPath, (Get-SafeCount -InputObject $reloadedServers)) -RuntimeContext $RuntimeContext
                return (New-SourceServerReviewResult -Servers $reloadedServers -ReviewPerformed $true -Reloaded $true)
            }
            'OpenTxt' {
                [void](Open-SourceServerReviewTarget -Path $ArtifactPathSet.ServerTxtPath -RuntimeContext $RuntimeContext)
            }
            'OpenFolder' {
                [void](Open-SourceServerReviewTarget -Path (Split-Path -Path $ArtifactPathSet.ServerTxtPath -Parent) -RuntimeContext $RuntimeContext)
            }
            'Stop' {
                return (New-SourceServerReviewResult -Servers $effectiveServers -Cancelled $true -ReviewPerformed $true)
            }
        }
    }
}

function Get-ServerScanResultSet {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$ScanResults)

    $statusRows = @($ScanResults | ForEach-Object { $_.Status } | Where-Object { $null -ne $_ })
    $membershipRows = @($ScanResults | ForEach-Object { @($_.Members) } | Where-Object { $null -ne $_ })
    $identityMatchRows = @($ScanResults | ForEach-Object { @($_.Matches) } | Where-Object { $null -ne $_ })

    return (
        New-ServerScanResultSet `
            -StatusRows $statusRows `
            -MembershipRows $membershipRows `
            -IdentityMatchRows $identityMatchRows
    )
}

function Write-ServerScanStatusMessage {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$StatusRows,
        [psobject]$RuntimeContext
    )

    foreach ($fallbackStatus in @($StatusRows | Where-Object { $_.QueryStatus -eq 'Success' -and $_.FallbackUsed })) {
        Write-ReportLog -Message ("Server {0} was processed successfully through fallback protocol {1}. Original choice: {2}." -f $fallbackStatus.Server, $fallbackStatus.EffectiveCimProtocol, $fallbackStatus.RequestedCimProtocol) -Level 'WARN' -RuntimeContext $RuntimeContext
    }

    foreach ($offlineStatus in @($StatusRows | Where-Object { $_.QueryStatus -eq 'Offline' })) {
        Write-ReportLog -Message ("Server {0} was skipped as offline. {1}" -f $offlineStatus.Server, $offlineStatus.ReachabilitySummary) -Level 'WARN' -RuntimeContext $RuntimeContext
    }

    foreach ($errorStatus in @($StatusRows | Where-Object { $_.QueryStatus -eq 'Error' -and -not [string]::IsNullOrWhiteSpace($_.ErrorMessage) })) {
        Write-ReportLog -Message ("Error while processing server {0}: {1}" -f $errorStatus.Server, $errorStatus.ErrorMessage) -Level 'WARN' -RuntimeContext $RuntimeContext
    }
}

function Get-ServerStatusCategory {
    param([Parameter(Mandatory)][psobject]$StatusRow)

    switch ([string]$StatusRow.QueryStatus) {
        'Success' { return 'Success' }
        'Offline' { return 'Offline' }
    }

    $errorMessage = [string]$StatusRow.ErrorMessage
    if ([string]::IsNullOrWhiteSpace($errorMessage)) {
        return 'Other'
    }

    if (
        $errorMessage -match 'WinRM' -or
        $errorMessage -match 'WS-Management' -or
        $errorMessage -match 'winrm quickconfig' -or
        $errorMessage -match 'The WinRM client cannot process the request' -or
        $errorMessage -match 'cannot connect to the destination specified in the request'
    ) {
        return 'WinRM'
    }

    if (Test-IsAuthenticationCimError -InputObject $errorMessage) {
        return 'AccessDenied'
    }

    return 'Other'
}

function Get-ServerStatusCategorySummary {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$StatusRows)

    $summary = [ordered]@{
        Success      = 0
        Offline      = 0
        AccessDenied = 0
        WinRM        = 0
        Other        = 0
    }

    foreach ($statusRow in @($StatusRows | Where-Object { $null -ne $_ })) {
        $summary[(Get-ServerStatusCategory -StatusRow $statusRow)]++
    }

    return [PSCustomObject]$summary
}

function Write-ServerStatusCategorySummary {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$StatusRows,
        [psobject]$RuntimeContext
    )

    $summary = Get-ServerStatusCategorySummary -StatusRows $StatusRows
    Write-ReportLog -Message ("Category summary: Success={0}; Offline={1}; AccessDenied={2}; WinRM={3}; Other={4}." -f $summary.Success, $summary.Offline, $summary.AccessDenied, $summary.WinRM, $summary.Other) -RuntimeContext $RuntimeContext
}

function Export-ServerStatusArtifact {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$StatusRows,
        [Parameter(Mandatory)][psobject]$ArtifactPathSet,
        [psobject]$RuntimeContext
    )

    Export-ReportCsv -Data $StatusRows -Path $ArtifactPathSet.StatusCsvPath -PropertyOrder @(
        'Server', 'DnsHostName', 'QueryStatus', 'RequestedCimProtocol', 'EffectiveCimProtocol', 'AttemptedCimProtocols', 'FallbackUsed', 'ReachabilityMode', 'PingSucceeded', 'ReachabilitySummary', 'GroupsCollected', 'MembersCollected', 'MatchesFound', 'ErrorMessage'
    )

    Write-ReportLog -Message ("Server processing status saved: {0}" -f $ArtifactPathSet.StatusCsvPath) -RuntimeContext $RuntimeContext
}

function Export-AllMembersArtifact {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$MembershipRows,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$StatusRows,
        [Parameter(Mandatory)][psobject]$ArtifactPathSet,
        [Parameter(Mandatory)][int]$ServerCount,
        [psobject]$RuntimeContext
    )

    Export-ReportCsv -Data $MembershipRows -Path $ArtifactPathSet.MembershipCsvPath -PropertyOrder @(
        'Server', 'CimProtocol', 'LocalGroup', 'LocalGroupCaption', 'LocalGroupSid', 'MemberName', 'MemberType', 'MemberClass', 'MemberPrincipal', 'MemberCaption', 'MemberScope', 'MemberAuthority', 'MemberSource', 'MemberLocalAccount', 'MemberSid', 'MemberPath'
    )

    $membershipSummary = @(Get-MembershipSummary -MembershipRows $MembershipRows)
    Export-ReportCsv -Data $membershipSummary -Path $ArtifactPathSet.SummaryCsvPath -PropertyOrder @('Server', 'LocalGroup', 'LocalGroupCaption', 'LocalGroupSid', 'MemberCount')

    Write-ReportLog -Message ("Detailed local-group membership report saved: {0}" -f $ArtifactPathSet.MembershipCsvPath) -RuntimeContext $RuntimeContext
    Write-ReportLog -Message ("Local-group summary report saved: {0}" -f $ArtifactPathSet.SummaryCsvPath) -RuntimeContext $RuntimeContext
    Write-ReportLog -Message ("Completed. Servers found: {0}. Successfully processed: {1}. Errors: {2}." -f $ServerCount, (@($StatusRows | Where-Object { $_.QueryStatus -eq 'Success' }).Count), (@($StatusRows | Where-Object { $_.QueryStatus -eq 'Error' }).Count)) -RuntimeContext $RuntimeContext
    Write-ServerStatusCategorySummary -StatusRows $StatusRows -RuntimeContext $RuntimeContext
}

function Show-IdentitySearchMatch {
    param(
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$IdentityMatchRows,
        [psobject]$RuntimeContext
    )

    $effectiveIdentityMatchRows = @($IdentityMatchRows | Where-Object { $null -ne $_ })
    if ((Get-SafeCount -InputObject $effectiveIdentityMatchRows) -eq 0) {
        return
    }

    Write-ConsoleLine -RuntimeContext $RuntimeContext
    Write-ConsoleLine -Message 'Matches found:' -ForegroundColor Green -RuntimeContext $RuntimeContext
    $effectiveIdentityMatchRows |
        Sort-Object -Property Server, LocalGroup, MemberPrincipal, MemberName |
        Select-Object Server, LocalGroup, MemberPrincipal, MemberName, MemberType |
        Format-Table -AutoSize |
        Out-String |
        ForEach-Object { Write-ConsoleLine -Message $_ -RuntimeContext $RuntimeContext }
}

function Export-IdentitySearchArtifact {
    param(
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$IdentityMatchRows,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$StatusRows,
        [Parameter(Mandatory)][string]$SearchIdentity,
        [Parameter(Mandatory)][psobject]$ArtifactPathSet,
        [psobject]$RuntimeContext
    )

    $effectiveIdentityMatchRows = @($IdentityMatchRows | Where-Object { $null -ne $_ })

    Export-ReportCsv -Data $effectiveIdentityMatchRows -Path $ArtifactPathSet.IdentityMatchCsvPath -PropertyOrder @(
        'SearchIdentity', 'Server', 'CimProtocol', 'LocalGroup', 'LocalGroupCaption', 'LocalGroupSid', 'MemberName', 'MemberType', 'MemberClass', 'MemberPrincipal', 'MemberCaption', 'MemberScope', 'MemberAuthority', 'MemberSource', 'MemberLocalAccount', 'MemberSid', 'MemberPath'
    )

    $matchedServersCount = @(
        $effectiveIdentityMatchRows |
            ForEach-Object { $_.Server } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    ).Count
    Write-ReportLog -Message ("Search results saved: {0}" -f $ArtifactPathSet.IdentityMatchCsvPath) -RuntimeContext $RuntimeContext

    if ((Get-SafeCount -InputObject $effectiveIdentityMatchRows) -gt 0) {
        Show-IdentitySearchMatch -IdentityMatchRows $effectiveIdentityMatchRows -RuntimeContext $RuntimeContext
    }
    else {
        Write-ReportLog -Message ("No matches were found for '{0}'." -f $SearchIdentity) -Level 'WARN' -RuntimeContext $RuntimeContext
    }

    Write-ReportLog -Message ("Search for '{0}' completed. Matches found: {1}. Servers with matches: {2}." -f $SearchIdentity, (Get-SafeCount -InputObject $effectiveIdentityMatchRows), $matchedServersCount) -RuntimeContext $RuntimeContext
    Write-ServerStatusCategorySummary -StatusRows $StatusRows -RuntimeContext $RuntimeContext
}















