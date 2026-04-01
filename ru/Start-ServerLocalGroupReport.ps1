<#
.SYNOPSIS
Собирает список серверов Windows Server и формирует отчёты по локальным группам или ищет конкретную учётную запись.

.DESCRIPTION
Скрипт может получать список серверов из Active Directory или из входного файла, затем подключается к серверам по CIM
с поддержкой DCOM/WSMan, автоматически переключает транспорт при необходимости и сохраняет результаты в CSV-файлы.
Поддерживаются два режима: полная выгрузка прямых членов локальных групп, включая доменных пользователей и доменные
группы, и поиск конкретного пользователя или группы с указанием сервера и локальной группы, где найдено совпадение.
В интерактивном запуске в начале предлагается выбрать, использовать ли текущую Windows-сессию или запросить
учётные данные другого пользователя. Если креды не переданы в неинтерактивном режиме, по умолчанию используется
текущая Windows-сессия.
Для неинтерактивной автоматизации безопаснее формировать `PSCredential` через `SecretManagement`, `Import-Clixml`
или другой защищённый механизм хранения секретов, а не хранить пароль в открытом виде в тексте сценария.

.PARAMETER OutputDirectory
Папка для выходных CSV-файлов и текстового лога выполнения.

.PARAMETER InputMode
Источник списка серверов: `AD` или `File`. Если параметр не указан, wrapper может вывести его из активного набора
параметров или запросить интерактивно внутри модуля.

.PARAMETER ServerListPath
Путь к TXT- или CSV-файлу со списком серверов. Используется для режима `File`.

.PARAMETER DomainServer
Конкретный контроллер домена или AD-сервер для выполнения запроса. Используется для режима `AD`.

.PARAMETER SearchBase
Базовый DN для ограничения области поиска серверов в Active Directory.

.PARAMETER OperationMode
Режим работы: `AllMembers` для полной выгрузки или `FindIdentity` для поиска одной учётной записи. Если параметр не
задан, wrapper может вывести его из активного набора параметров.

.PARAMETER SearchIdentity
Пользователь, группа, SID или шаблон для поиска на серверах. Используется в режиме `FindIdentity`.

.PARAMETER ADCredential
Учётные данные для доступа к Active Directory. Если параметр не задан, может использоваться текущая Windows-сессия.

.PARAMETER ServerCredential
Учётные данные для подключения к целевым серверам. Если параметр не задан, может использоваться текущая Windows-сессия.

.PARAMETER SharedCredential
Общие учётные данные, если один и тот же аккаунт должен использоваться и для AD, и для серверов. В интерактивном
режиме аналогичный общий `PSCredential` запрашивается один раз, если выбран вариант запуска под другим пользователем.

.PARAMETER LocalGroups
Список локальных групп, которые нужно проверять. Если параметр не задан, проверяются все локальные группы.

.PARAMETER CsvServerColumn
Явное имя столбца с серверами во входном CSV-файле. Используется в режиме `File`.

.PARAMETER CimProtocol
Предпочтительный CIM-транспорт: `Dcom` или `Wsman`.

.PARAMETER ConnectivityTimeoutMs
Таймаут предварительной сетевой проверки доступности узла и CIM-портов в миллисекундах.

.PARAMETER ReachabilityMode
Стратегия предварительной проверки доступности сервера перед CIM-подключением:
`Probe` — ping + проверка релевантных портов,
`Direct` — сразу пытаться подключаться по CIM,
`PingOnly` — ориентироваться только на ICMP,
`None` — полностью отключить предварительные проверки.

.PARAMETER CimOperationTimeoutSec
Таймаут выполнения CIM-запросов в секундах.

.PARAMETER CimRetryCount
Количество попыток для временных CIM/WMI-ошибок.

.PARAMETER CimRetryDelaySec
Пауза между повторными попытками CIM-запросов в секундах.

.PARAMETER ThrottleLimit
Максимальное число параллельных опросов серверов в PowerShell 7+.

.PARAMETER MaxComputerPasswordAgeDays
Исключает AD-объекты серверов, у которых `pwdLastSet` старше указанного количества дней.

.PARAMETER MaxLastLogonAgeDays
Исключает AD-объекты серверов, у которых `lastLogonTimestamp` старше указанного количества дней.

.PARAMETER WellKnownAuthorities
Список authorities, которые нужно классифицировать как `WellKnown` в отчётах. Если параметр не задан, используется
значение по умолчанию из модуля.

.PARAMETER CimSlowQueryWarningSec
Порог в секундах, после которого долгий `ASSOCIATORS`-запрос логируется как warning.

.PARAMETER IncludeDisabledComputers
Включает отключённые компьютерные объекты из Active Directory.

.PARAMETER IncludeEmptyGroups
Добавляет в отчёт пустые локальные группы.

.PARAMETER NonInteractive
Отключает интерактивные запросы. Если креды не переданы явно, используется текущая Windows-сессия.

.EXAMPLE
.\get_windows_server_local_group_report.ps1

Интерактивный запуск со всеми подсказками в консоли, включая выбор: текущий пользователь или другой пользователь.

.EXAMPLE
.\get_windows_server_local_group_report.ps1 `
    -ServerListPath ".\samples\servers_example.csv" `
    -CsvServerColumn "FQDN" `
    -NonInteractive

Полная выгрузка членов локальных групп по списку серверов из CSV под текущей Windows-сессией.

.EXAMPLE
$adCred = Get-Credential
$serverCred = Get-Credential
.\get_windows_server_local_group_report.ps1 `
    -ADCredential $adCred `
    -ServerCredential $serverCred `
    -SearchIdentity "DOMAIN\User1" `
    -NonInteractive

Поиск одной учётной записи на серверах из AD. Режимы `AD` и `FindIdentity` будут определены автоматически.

.EXAMPLE
$serverCred = Get-Credential
.\get_windows_server_local_group_report.ps1 `
    -ServerListPath ".\samples\servers_example.csv" `
    -CsvServerColumn "FQDN" `
    -ReachabilityMode Direct `
    -ServerCredential $serverCred `
    -NonInteractive

Полная выгрузка членов локальных групп по списку серверов из CSV без предварительного ping/port-probe. Режимы `File` и `AllMembers` будут определены автоматически.

.EXAMPLE
$adCred = Get-Credential
$serverCred = Get-Credential
.\get_windows_server_local_group_report.ps1 `
    -ADCredential $adCred `
    -ServerCredential $serverCred `
    -MaxComputerPasswordAgeDays 90 `
    -MaxLastLogonAgeDays 90 `
    -NonInteractive

Выгрузка только по "живым" серверам из AD с фильтрацией устаревших компьютерных объектов.
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
            Write-Verbose ("Пустое строковое значение параметра '{0}' не передаётся в модуль." -f $entry.Key)
            continue
        }

        $moduleParameters[$entry.Key] = $entry.Value
    }

    if ($moduleParameters.ContainsKey('Credential') -and -not $moduleParameters.ContainsKey('SharedCredential')) {
        $moduleParameters['SharedCredential'] = $moduleParameters['Credential']
        $moduleParameters.Remove('Credential')
        Write-Verbose "Псевдоним 'Credential' нормализован к параметру 'SharedCredential'."
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
        Write-Verbose ("Wrapper передаёт InvocationParameterSetName = '{0}' в модуль для централизованного вывода режимов." -f $ParameterSetName)
    }

    return $moduleParameters
}

function Get-WrapperModulePath {
    param([Parameter(Mandatory)][string]$ScriptRoot)

    return (Join-Path -Path $ScriptRoot -ChildPath 'AD_Server_Local_Group_Report.psm1')
}

function Import-WrapperReportModule {
    param([Parameter(Mandatory)][string]$ModulePath)

    Write-Verbose ("Ожидаемый путь модуля: {0}" -f $ModulePath)

    if (-not (Test-Path -LiteralPath $ModulePath -PathType Leaf)) {
        Write-Error -Message 'Файл модуля AD_Server_Local_Group_Report.psm1 не найден в папке со скриптом. Пожалуйста, убедитесь, что все файлы решения загружены корректно.' -ErrorAction Stop
    }

    Write-Verbose ("Импорт модуля из '{0}'." -f $ModulePath)
    try {
        Import-Module -Name $ModulePath -Force -DisableNameChecking -ErrorAction Stop
    }
    catch {
        Write-Error -Message ("Не удалось импортировать модуль '{0}'. Проверьте целостность файла, ExecutionPolicy и права доступа. Техническая ошибка: {1}" -f $ModulePath, $_.Exception.Message) -ErrorAction Stop
    }
}

function Invoke-WrapperEntryPoint {
    param(
        [Parameter(Mandatory)][string]$ParameterSetName,
        [Parameter(Mandatory)][hashtable]$BoundParameters,
        [Parameter(Mandatory)][string]$ScriptRoot
    )

    Write-Verbose ("Выбран набор параметров: {0}" -f $ParameterSetName)
    $moduleParameters = Resolve-WrapperModuleParameterSet -ParameterSetName $ParameterSetName -BoundParameters $BoundParameters
    $modulePath = Get-WrapperModulePath -ScriptRoot $ScriptRoot
    Import-WrapperReportModule -ModulePath $modulePath

    Write-Verbose 'Передаю параметры в Start-ServerLocalGroupReport.'
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
        Write-Verbose ("Wrapper завершился с terminating error: {0}" -f $_.Exception.Message)
        throw [System.InvalidOperationException]::new(("Критический сбой выполнения wrapper-скрипта: {0}" -f $_.Exception.Message), $_.Exception)
    }
}

Invoke-WrapperMain -ParameterSetName $PSCmdlet.ParameterSetName -BoundParameters $PSBoundParameters -ScriptRoot $PSScriptRoot


