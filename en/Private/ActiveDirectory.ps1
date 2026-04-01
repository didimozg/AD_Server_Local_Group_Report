function Import-ActiveDirectoryModule {
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw 'ActiveDirectory module was not found. Install RSAT: Active Directory module for Windows PowerShell.'
    }

    Import-Module ActiveDirectory -ErrorAction Stop
}

function ConvertFrom-ADFileTime {
    param([AllowNull()]$Value)

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [DateTime]) {
        return ([DateTime]$Value).ToUniversalTime()
    }

    try {
        $fileTime = [Int64]$Value
        if ($fileTime -le 0) {
            return $null
        }

        return [DateTime]::FromFileTimeUtc($fileTime)
    }
    catch {
        return $null
    }
}

function Get-ServerStalenessState {
    param(
        [Parameter(Mandatory)][psobject]$ComputerObject,
        [ValidateRange(0, 3650)][int]$MaxComputerPasswordAgeDays = 0,
        [ValidateRange(0, 3650)][int]$MaxLastLogonAgeDays = 0
    )

    $passwordLastSetUtc = ConvertFrom-ADFileTime -Value $ComputerObject.pwdLastSet
    $lastLogonTimestampUtc = ConvertFrom-ADFileTime -Value $ComputerObject.lastLogonTimestamp
    $reasons = New-Object System.Collections.Generic.List[string]
    $utcNow = [DateTime]::UtcNow

    if ($MaxComputerPasswordAgeDays -gt 0) {
        if ($null -eq $passwordLastSetUtc) {
            [void]$reasons.Add('pwdLastSet is empty')
        }
        elseif ($passwordLastSetUtc -lt $utcNow.AddDays(-$MaxComputerPasswordAgeDays)) {
            [void]$reasons.Add(("pwdLastSet older than {0} days ({1:u})" -f $MaxComputerPasswordAgeDays, $passwordLastSetUtc))
        }
    }

    if ($MaxLastLogonAgeDays -gt 0) {
        if ($null -eq $lastLogonTimestampUtc) {
            [void]$reasons.Add('lastLogonTimestamp is empty')
        }
        elseif ($lastLogonTimestampUtc -lt $utcNow.AddDays(-$MaxLastLogonAgeDays)) {
            [void]$reasons.Add(("lastLogonTimestamp older than {0} days ({1:u})" -f $MaxLastLogonAgeDays, $lastLogonTimestampUtc))
        }
    }

    return (
        New-ServerStalenessState `
            -IsStale ((Get-SafeCount -InputObject $reasons) -gt 0) `
            -PasswordLastSetUtc $passwordLastSetUtc `
            -LastLogonTimestampUtc $lastLogonTimestampUtc `
            -Reasons $reasons.ToArray() `
            -ReasonText ($reasons -join '; ')
    )
}

function Get-ADQueryParameter {
    param(
        [string]$DomainServer,
        [string]$SearchBase,
        [System.Management.Automation.PSCredential]$Credential
    )

    $params = @{
        LDAPFilter = '(&(objectCategory=computer)(operatingSystem=*Windows Server*))'
        Properties = @('DNSHostName', 'DistinguishedName', 'Enabled', 'OperatingSystem', 'OperatingSystemVersion', 'pwdLastSet', 'lastLogonTimestamp')
    }

    if (-not [string]::IsNullOrWhiteSpace($DomainServer)) {
        $params['Server'] = $DomainServer
    }

    if (-not [string]::IsNullOrWhiteSpace($SearchBase)) {
        $params['SearchBase'] = $SearchBase
    }

    if ($null -ne $Credential) {
        $params['Credential'] = $Credential
    }

    return $params
}

function Get-WindowsServerListFromAD {
    param(
        [string]$DomainServer,
        [string]$SearchBase,
        [System.Management.Automation.PSCredential]$Credential,
        [switch]$IncludeDisabledComputers,
        [ValidateRange(0, 3650)][int]$MaxComputerPasswordAgeDays = 0,
        [ValidateRange(0, 3650)][int]$MaxLastLogonAgeDays = 0,
        [psobject]$RuntimeContext
    )

    Write-ReportLog -Message 'Importing the ActiveDirectory module and querying Windows Server objects from AD.' -RuntimeContext $RuntimeContext
    Import-ActiveDirectoryModule

    $queryParams = Get-ADQueryParameter -DomainServer $DomainServer -SearchBase $SearchBase -Credential $Credential
    $adServers = @(Get-ADComputer @queryParams)
    $filteredByStalePolicyCount = 0

    $servers = foreach ($server in ($adServers | Sort-Object -Property Name)) {
        if (-not $IncludeDisabledComputers -and -not $server.Enabled) {
            continue
        }

        $staleness = Get-ServerStalenessState -ComputerObject $server -MaxComputerPasswordAgeDays $MaxComputerPasswordAgeDays -MaxLastLogonAgeDays $MaxLastLogonAgeDays
        if ($staleness.IsStale) {
            $filteredByStalePolicyCount++
            Write-Verbose ("Skipping server '{0}' from AD because of the stale-object policy: {1}" -f $server.Name, $staleness.ReasonText)
            continue
        }

        New-ServerInventoryRow -Name $server.Name -ConnectionName $server.Name -DnsHostName $server.DNSHostName -OperatingSystem $server.OperatingSystem -OperatingSystemVersion $server.OperatingSystemVersion -Enabled $server.Enabled -DistinguishedName $server.DistinguishedName -PasswordLastSetUtc $staleness.PasswordLastSetUtc -LastLogonTimestampUtc $staleness.LastLogonTimestampUtc -SourceMode 'AD'
    }

    if ($MaxComputerPasswordAgeDays -gt 0 -or $MaxLastLogonAgeDays -gt 0) {
        Write-ReportLog -Message ("AD stale-object filtering is active. Excluded objects: {0}. MaxComputerPasswordAgeDays={1}; MaxLastLogonAgeDays={2}." -f $filteredByStalePolicyCount, $MaxComputerPasswordAgeDays, $MaxLastLogonAgeDays) -RuntimeContext $RuntimeContext
    }

    return @($servers)
}

function Get-WindowsServerListFromFile {
    param(
        [Parameter(Mandatory)][string]$ServerListPath,
        [string]$CsvServerColumn
    )

    if (-not (Test-Path -LiteralPath $ServerListPath)) {
        throw ("Server list file was not found: {0}" -f $ServerListPath)
    }

    $resolvedPath = (Resolve-Path -LiteralPath $ServerListPath -ErrorAction Stop).Path
    $extension = [System.IO.Path]::GetExtension($resolvedPath)

    if ($extension -ieq '.csv') {
        $rows = @(Import-Csv -Path $resolvedPath)
        if ((Get-SafeCount -InputObject $rows) -eq 0) {
            throw ("CSV server list file is empty: {0}" -f $resolvedPath)
        }

        $propertyNames = @($rows[0].PSObject.Properties.Name)
        if (-not [string]::IsNullOrWhiteSpace($CsvServerColumn)) {
            if ($propertyNames -notcontains $CsvServerColumn) {
                throw ("CSV file does not contain column '{0}'. Available columns: {1}" -f $CsvServerColumn, ($propertyNames -join ', '))
            }

            $serverColumn = $CsvServerColumn
        }
        else {
            $serverColumnCandidates = @('ConnectionName', 'Server', 'ComputerName', 'Name', 'DnsHostName', 'Host', 'Hostname')
            $serverColumn = $serverColumnCandidates | Where-Object { $propertyNames -icontains $_ } | Select-Object -First 1
        }

        if ([string]::IsNullOrWhiteSpace($serverColumn)) {
            throw 'No server-name column was found in the CSV. Use ConnectionName, Server, ComputerName, Name, DnsHostName, Host, Hostname, or specify -CsvServerColumn explicitly.'
        }

        Write-Verbose ("CSV server source: using column '{0}'." -f $serverColumn)

        $servers = foreach ($row in $rows) {
            $connectionName = [string]$row.$serverColumn
            if ([string]::IsNullOrWhiteSpace($connectionName)) {
                continue
            }

            New-ServerInventoryRow -Name $(if ($propertyNames -icontains 'Name' -and -not [string]::IsNullOrWhiteSpace([string]$row.Name)) { [string]$row.Name } else { $connectionName }) -ConnectionName $connectionName.Trim() -DnsHostName $(if ($propertyNames -icontains 'DnsHostName' -and -not [string]::IsNullOrWhiteSpace([string]$row.DnsHostName)) { [string]$row.DnsHostName } else { $null }) -OperatingSystem $(if ($propertyNames -icontains 'OperatingSystem' -and -not [string]::IsNullOrWhiteSpace([string]$row.OperatingSystem)) { [string]$row.OperatingSystem } else { $null }) -OperatingSystemVersion $(if ($propertyNames -icontains 'OperatingSystemVersion' -and -not [string]::IsNullOrWhiteSpace([string]$row.OperatingSystemVersion)) { [string]$row.OperatingSystemVersion } else { $null }) -Enabled $(if ($propertyNames -icontains 'Enabled') { $row.Enabled } else { $null }) -DistinguishedName $(if ($propertyNames -icontains 'DistinguishedName' -and -not [string]::IsNullOrWhiteSpace([string]$row.DistinguishedName)) { [string]$row.DistinguishedName } else { $null }) -PasswordLastSetUtc $(if ($propertyNames -icontains 'PasswordLastSetUtc' -and -not [string]::IsNullOrWhiteSpace([string]$row.PasswordLastSetUtc)) { [DateTime]$row.PasswordLastSetUtc } else { $null }) -LastLogonTimestampUtc $(if ($propertyNames -icontains 'LastLogonTimestampUtc' -and -not [string]::IsNullOrWhiteSpace([string]$row.LastLogonTimestampUtc)) { [DateTime]$row.LastLogonTimestampUtc } else { $null }) -SourceMode 'File'
        }

        return @(
            $servers |
                Group-Object -Property ConnectionName |
                ForEach-Object { $_.Group[0] } |
                Sort-Object -Property ConnectionName
        )
    }

    $servers = foreach ($line in (Get-Content -Path $resolvedPath -Encoding UTF8)) {
        $serverName = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($serverName) -or $serverName.StartsWith('#')) {
            continue
        }

        New-ServerInventoryRow -Name $serverName -ConnectionName $serverName -SourceMode 'File'
    }

    return @(
        $servers |
            Group-Object -Property ConnectionName |
            ForEach-Object { $_.Group[0] } |
            Sort-Object -Property ConnectionName
    )
}









