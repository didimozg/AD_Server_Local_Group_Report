function Read-MenuChoice {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][object[]]$Options,
        [int]$DefaultChoice = 1,
        [psobject]$RuntimeContext
    )

    Write-ConsoleLine -RuntimeContext $RuntimeContext
    Write-ConsoleLine -Message $Title -ForegroundColor Green -RuntimeContext $RuntimeContext

    for ($index = 0; $index -lt $Options.Count; $index++) {
        $itemNumber = $index + 1
        Write-ConsoleLine -Message ("  {0}. {1} - {2}" -f $itemNumber, $Options[$index].Label, $Options[$index].Description) -RuntimeContext $RuntimeContext
    }

    while ($true) {
        $selection = Read-Host ("{0} [{1}]" -f $Prompt, $DefaultChoice)
        if ([string]::IsNullOrWhiteSpace($selection)) {
            $selection = [string]$DefaultChoice
        }

        $parsedSelection = 0
        if ([int]::TryParse($selection, [ref]$parsedSelection) -and $parsedSelection -ge 1 -and $parsedSelection -le $Options.Count) {
            return $Options[$parsedSelection - 1].Value
        }

        Write-Warning 'Некорректный выбор. Укажите номер варианта.'
    }
}

function Read-OptionalText {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [string]$DefaultValue
    )

    $fullPrompt = if ([string]::IsNullOrWhiteSpace($DefaultValue)) { $Prompt } else { '{0} [{1}]' -f $Prompt, $DefaultValue }
    $value = Read-Host $fullPrompt

    if ([string]::IsNullOrWhiteSpace($value)) {
        return $DefaultValue
    }

    return $value.Trim()
}

function Read-RequiredText {
    param([Parameter(Mandatory)][string]$Prompt)

    while ($true) {
        $value = Read-Host $Prompt
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value.Trim()
        }

        Write-Warning 'Значение не должно быть пустым.'
    }
}

function Get-InteractiveCredentialSelection {
    param(
        [System.Management.Automation.PSCredential]$ADCredential,
        [System.Management.Automation.PSCredential]$ServerCredential,
        [System.Management.Automation.PSCredential]$SharedCredential,
        [switch]$NonInteractive,
        [psobject]$RuntimeContext
    )

    if ($null -ne $SharedCredential) {
        return 'SharedCredential'
    }

    if ($null -ne $ADCredential -or $null -ne $ServerCredential) {
        return 'ExplicitParameters'
    }

    if ($NonInteractive) {
        return 'CurrentUser'
    }

    return Read-MenuChoice -Title 'Выбор контекста запуска' -Prompt 'Под кем выполнять запросы к AD и серверам?' -DefaultChoice 1 -RuntimeContext $RuntimeContext -Options @(
        [PSCustomObject]@{ Value = 'CurrentUser'; Label = 'Текущий пользователь'; Description = 'Использовать текущую Windows-сессию без дополнительного запроса пароля' },
        [PSCustomObject]@{ Value = 'OtherUser'; Label = 'Другой пользователь'; Description = 'Один раз запросить учётные данные и использовать их для AD и серверов' }
    )
}

function Get-DefaultServerListPath {
    return (Join-Path -Path $script:ModuleRoot -ChildPath 'samples\servers_example.txt')
}

function Resolve-ExecutionMode {
    param(
        [string]$ParameterSetName,
        [hashtable]$BoundParameters
    )

    $effectiveBoundParameters = @{}
    if ($null -ne $BoundParameters) {
        foreach ($entry in $BoundParameters.GetEnumerator()) {
            $effectiveBoundParameters[$entry.Key] = $entry.Value
        }
    }

    $resolvedInputMode = if ($effectiveBoundParameters.ContainsKey('InputMode')) { [string]$effectiveBoundParameters['InputMode'] } else { $null }
    $resolvedOperationMode = if ($effectiveBoundParameters.ContainsKey('OperationMode')) { [string]$effectiveBoundParameters['OperationMode'] } else { $null }
    $derivedInputMode = $null
    $derivedOperationMode = $null

    if ($ParameterSetName -match '^(AD|File)_(AllMembers|FindIdentity)$') {
        $derivedInputMode = $Matches[1]
        $derivedOperationMode = $Matches[2]
    }
    else {
        $hasFileHints = $effectiveBoundParameters.ContainsKey('ServerListPath') -or $effectiveBoundParameters.ContainsKey('CsvServerColumn')
        $hasADHints = $effectiveBoundParameters.ContainsKey('ADCredential') -or
            $effectiveBoundParameters.ContainsKey('DomainServer') -or
            $effectiveBoundParameters.ContainsKey('SearchBase') -or
            $effectiveBoundParameters.ContainsKey('MaxComputerPasswordAgeDays') -or
            $effectiveBoundParameters.ContainsKey('MaxLastLogonAgeDays') -or
            $effectiveBoundParameters.ContainsKey('IncludeDisabledComputers')

        if ($hasFileHints -and $hasADHints) {
            throw 'Переданы одновременно признаки режимов AD и File. Уточните сценарий или явно задайте -InputMode.'
        }

        if ($hasFileHints) {
            $derivedInputMode = 'File'
        }
        elseif ($hasADHints) {
            $derivedInputMode = 'AD'
        }

        if ($effectiveBoundParameters.ContainsKey('SearchIdentity')) {
            $derivedOperationMode = 'FindIdentity'
        }
        elseif (-not [string]::IsNullOrWhiteSpace($derivedInputMode)) {
            $derivedOperationMode = 'AllMembers'
        }

        if ([string]::IsNullOrWhiteSpace($derivedInputMode) -and [string]::IsNullOrWhiteSpace($derivedOperationMode)) {
            Write-Verbose ("Режимы не удалось вывести автоматически. ParameterSetName = '{0}'." -f $ParameterSetName)
            return (New-ExecutionModeResolutionResult -InputMode $resolvedInputMode -OperationMode $resolvedOperationMode)
        }

        Write-Verbose ("Режимы выведены по набору аргументов. ParameterSetName = '{0}'." -f $ParameterSetName)
    }

    if (-not [string]::IsNullOrWhiteSpace($resolvedInputMode) -and $resolvedInputMode -ne $derivedInputMode) {
        throw ("Параметр -InputMode имеет значение '{0}', но активный сценарий требует '{1}'." -f $resolvedInputMode, $derivedInputMode)
    }

    if (-not [string]::IsNullOrWhiteSpace($resolvedOperationMode) -and $resolvedOperationMode -ne $derivedOperationMode) {
        throw ("Параметр -OperationMode имеет значение '{0}', но активный сценарий требует '{1}'." -f $resolvedOperationMode, $derivedOperationMode)
    }

    if ([string]::IsNullOrWhiteSpace($resolvedInputMode) -and -not [string]::IsNullOrWhiteSpace($derivedInputMode)) {
        $resolvedInputMode = $derivedInputMode
        Write-Verbose ("Автоматически определён InputMode = '{0}'." -f $resolvedInputMode)
    }

    if ([string]::IsNullOrWhiteSpace($resolvedOperationMode) -and -not [string]::IsNullOrWhiteSpace($derivedOperationMode)) {
        $resolvedOperationMode = $derivedOperationMode
        Write-Verbose ("Автоматически определён OperationMode = '{0}'." -f $resolvedOperationMode)
    }

    return (New-ExecutionModeResolutionResult -InputMode $resolvedInputMode -OperationMode $resolvedOperationMode)
}

function Read-InteractiveExecutionInput {
    param(
        [string]$InputMode,
        [string]$ServerListPath,
        [string]$OperationMode,
        [string]$SearchIdentity,
        [psobject]$RuntimeContext
    )

    $resolvedInputMode = $InputMode
    $resolvedServerListPath = $ServerListPath
    $resolvedOperationMode = $OperationMode
    $resolvedSearchIdentity = $SearchIdentity

    if ([string]::IsNullOrWhiteSpace($resolvedInputMode)) {
        $resolvedInputMode = Read-MenuChoice -Title 'Выбор источника серверов' -Prompt 'Откуда брать список серверов?' -DefaultChoice 1 -RuntimeContext $RuntimeContext -Options @(
            [PSCustomObject]@{ Value = 'AD'; Label = 'Сканировать AD'; Description = 'Получить список серверов Windows Server из Active Directory' },
            [PSCustomObject]@{ Value = 'File'; Label = 'Читать файл'; Description = 'Использовать заранее подготовленный список серверов' }
        )
    }

    if ($resolvedInputMode -eq 'File' -and [string]::IsNullOrWhiteSpace($resolvedServerListPath)) {
        $resolvedServerListPath = Read-OptionalText -Prompt 'Введите путь к файлу со списком серверов' -DefaultValue (Get-DefaultServerListPath)
    }

    if ([string]::IsNullOrWhiteSpace($resolvedOperationMode)) {
        $resolvedOperationMode = Read-MenuChoice -Title 'Выбор режима работы' -Prompt 'Что нужно сделать?' -DefaultChoice 1 -RuntimeContext $RuntimeContext -Options @(
            [PSCustomObject]@{ Value = 'AllMembers'; Label = 'Выгрузить всё'; Description = 'Собрать всех пользователей и группы из локальных групп серверов' },
            [PSCustomObject]@{ Value = 'FindIdentity'; Label = 'Найти учётку'; Description = 'Найти конкретного пользователя или группу на серверах' }
        )
    }

    if ($resolvedOperationMode -eq 'FindIdentity' -and [string]::IsNullOrWhiteSpace($resolvedSearchIdentity)) {
        $resolvedSearchIdentity = Read-RequiredText -Prompt 'Введите пользователя или группу для поиска'
    }

    return (New-ExecutionInputConfiguration -InputMode $resolvedInputMode -ServerListPath $resolvedServerListPath -OperationMode $resolvedOperationMode -SearchIdentity $resolvedSearchIdentity)
}

function Resolve-NonInteractiveExecutionInput {
    param(
        [string]$InputMode,
        [string]$ServerListPath,
        [string]$OperationMode,
        [string]$SearchIdentity
    )

    if ([string]::IsNullOrWhiteSpace($InputMode)) {
        throw 'В режиме -NonInteractive необходимо указать параметр -InputMode.'
    }

    $resolvedServerListPath = $ServerListPath
    $resolvedSearchIdentity = $SearchIdentity

    if ($InputMode -eq 'File' -and [string]::IsNullOrWhiteSpace($resolvedServerListPath)) {
        throw 'В режиме -NonInteractive при -InputMode File необходимо указать -ServerListPath.'
    }

    if ([string]::IsNullOrWhiteSpace($OperationMode)) {
        throw 'В режиме -NonInteractive необходимо указать параметр -OperationMode.'
    }

    if ($OperationMode -eq 'FindIdentity' -and [string]::IsNullOrWhiteSpace($resolvedSearchIdentity)) {
        throw 'В режиме -NonInteractive при -OperationMode FindIdentity необходимо указать -SearchIdentity.'
    }

    return (New-ExecutionInputConfiguration -InputMode $InputMode -ServerListPath $resolvedServerListPath -OperationMode $OperationMode -SearchIdentity $resolvedSearchIdentity)
}

function Resolve-ExecutionCredentialConfiguration {
    param(
        [Parameter(Mandatory)][string]$InputMode,
        [System.Management.Automation.PSCredential]$ADCredential,
        [System.Management.Automation.PSCredential]$ServerCredential,
        [System.Management.Automation.PSCredential]$SharedCredential,
        [switch]$Interactive,
        [psobject]$RuntimeContext
    )

    $resolvedADCredential = $ADCredential
    $resolvedServerCredential = $ServerCredential
    $resolvedSharedCredential = $SharedCredential
    $credentialSelection = if ($Interactive) {
        Get-InteractiveCredentialSelection -ADCredential $ADCredential -ServerCredential $ServerCredential -SharedCredential $SharedCredential -RuntimeContext $RuntimeContext
    }
    elseif ($null -ne $SharedCredential) {
        'SharedCredential'
    }
    elseif ($null -ne $ADCredential -or $null -ne $ServerCredential) {
        'ExplicitParameters'
    }
    else {
        'CurrentUser'
    }

    if ($credentialSelection -eq 'OtherUser') {
        Write-ConsoleLine -RuntimeContext $RuntimeContext
        Write-ConsoleLine -Message 'Запрос учётных данных другого пользователя для доступа к AD и серверам.' -ForegroundColor Green -RuntimeContext $RuntimeContext
        $resolvedSharedCredential = Get-Credential -Message 'Введите учётные данные другого пользователя'
    }

    if ($InputMode -eq 'AD' -and $null -eq $resolvedADCredential -and $null -ne $resolvedSharedCredential) {
        $resolvedADCredential = $resolvedSharedCredential
    }

    if ($null -eq $resolvedServerCredential -and $null -ne $resolvedSharedCredential) {
        $resolvedServerCredential = $resolvedSharedCredential
    }

    return (New-ExecutionCredentialConfigurationResult -ADCredential $resolvedADCredential -ServerCredential $resolvedServerCredential -AuthMode $credentialSelection)
}

function Get-ResolvedExecutionConfiguration {
    param(
        [Parameter(Mandatory)][psobject]$InputConfiguration,
        [Parameter(Mandatory)][psobject]$CredentialConfiguration
    )

    return (
        New-ExecutionConfigurationResult `
            -InputMode $InputConfiguration.InputMode `
            -ServerListPath $InputConfiguration.ServerListPath `
            -OperationMode $InputConfiguration.OperationMode `
            -SearchIdentity $InputConfiguration.SearchIdentity `
            -ADCredential $CredentialConfiguration.ADCredential `
            -ServerCredential $CredentialConfiguration.ServerCredential `
            -AuthMode $CredentialConfiguration.CredentialSelection `
            -ADAuthContext $(if ($null -eq $CredentialConfiguration.ADCredential) { 'Текущая Windows-сессия' } else { 'Явно переданный PSCredential' }) `
            -ServerAuthContext $(if ($null -eq $CredentialConfiguration.ServerCredential) { 'Текущая Windows-сессия' } else { 'Явно переданный PSCredential' })
    )
}

function Resolve-ExecutionConfiguration {
    param(
        [string]$InputMode,
        [string]$ServerListPath,
        [string]$OperationMode,
        [string]$SearchIdentity,
        [string]$DomainServer,
        [string]$SearchBase,
        [string]$CsvServerColumn,
        [System.Management.Automation.PSCredential]$ADCredential,
        [System.Management.Automation.PSCredential]$ServerCredential,
        [System.Management.Automation.PSCredential]$SharedCredential,
        [ValidateRange(0, 3650)][int]$MaxComputerPasswordAgeDays = 0,
        [ValidateRange(0, 3650)][int]$MaxLastLogonAgeDays = 0,
        [string]$InvocationParameterSetName,
        [switch]$IncludeDisabledComputers,
        [switch]$NonInteractive,
        [hashtable]$BoundParameters,
        [psobject]$RuntimeContext
    )

    $effectiveBoundParameters = @{}
    if ($null -ne $BoundParameters) {
        foreach ($entry in $BoundParameters.GetEnumerator()) {
            $effectiveBoundParameters[$entry.Key] = $entry.Value
        }
    }

    $parameterHintMap = [ordered]@{
        InputMode      = $InputMode
        ServerListPath = $ServerListPath
        OperationMode  = $OperationMode
        SearchIdentity = $SearchIdentity
        DomainServer   = $DomainServer
        SearchBase     = $SearchBase
        CsvServerColumn = $CsvServerColumn
        ADCredential   = $ADCredential
    }

    foreach ($entry in $parameterHintMap.GetEnumerator()) {
        if (-not $effectiveBoundParameters.ContainsKey($entry.Key) -and -not [string]::IsNullOrWhiteSpace([string]$entry.Value)) {
            $effectiveBoundParameters[$entry.Key] = $entry.Value
        }
    }

    if (-not $effectiveBoundParameters.ContainsKey('MaxComputerPasswordAgeDays') -and $MaxComputerPasswordAgeDays -gt 0) {
        $effectiveBoundParameters['MaxComputerPasswordAgeDays'] = $MaxComputerPasswordAgeDays
    }

    if (-not $effectiveBoundParameters.ContainsKey('MaxLastLogonAgeDays') -and $MaxLastLogonAgeDays -gt 0) {
        $effectiveBoundParameters['MaxLastLogonAgeDays'] = $MaxLastLogonAgeDays
    }

    if (-not $effectiveBoundParameters.ContainsKey('IncludeDisabledComputers') -and $IncludeDisabledComputers) {
        $effectiveBoundParameters['IncludeDisabledComputers'] = $true
    }

    $modeResolution = Resolve-ExecutionMode -ParameterSetName $InvocationParameterSetName -BoundParameters $effectiveBoundParameters
    $InputMode = $modeResolution.InputMode
    $OperationMode = $modeResolution.OperationMode

    $inputConfiguration = if ($NonInteractive) {
        Resolve-NonInteractiveExecutionInput -InputMode $InputMode -ServerListPath $ServerListPath -OperationMode $OperationMode -SearchIdentity $SearchIdentity
    }
    else {
        Read-InteractiveExecutionInput -InputMode $InputMode -ServerListPath $ServerListPath -OperationMode $OperationMode -SearchIdentity $SearchIdentity -RuntimeContext $RuntimeContext
    }

    $credentialConfiguration = Resolve-ExecutionCredentialConfiguration -InputMode $inputConfiguration.InputMode -ADCredential $ADCredential -ServerCredential $ServerCredential -SharedCredential $SharedCredential -Interactive:(-not $NonInteractive) -RuntimeContext $RuntimeContext

    return (Get-ResolvedExecutionConfiguration -InputConfiguration $inputConfiguration -CredentialConfiguration $credentialConfiguration)
}
