function Get-SafeCount {
    param([AllowNull()]$InputObject)

    return @($InputObject | Where-Object { $null -ne $_ }).Count
}

function Get-ReportRuntimeContext {
    param(
        [string]$ReportLogPath,
        [bool]$IsInteractiveRun = $true,
        [string]$ModulePath = $script:ModuleFilePath
    )

    return [PSCustomObject]@{
        ReportLogPath    = $ReportLogPath
        IsInteractiveRun = $IsInteractiveRun
        ModulePath       = $ModulePath
    }
}

function Get-DefaultReportRuntimeContext {
    if ($null -eq $script:DefaultRuntimeContext) {
        $script:DefaultRuntimeContext = Get-ReportRuntimeContext -ReportLogPath $null -IsInteractiveRun $true -ModulePath $script:ModuleFilePath
    }

    return $script:DefaultRuntimeContext
}

function Resolve-ReportRuntimeContext {
    param([psobject]$RuntimeContext)

    $defaultRuntimeContext = Get-DefaultReportRuntimeContext

    if ($null -eq $RuntimeContext) {
        return $defaultRuntimeContext
    }

    $reportLogPath = if ($RuntimeContext.PSObject.Properties.Name -contains 'ReportLogPath') { [string]$RuntimeContext.ReportLogPath } else { [string]$defaultRuntimeContext.ReportLogPath }
    $isInteractiveRun = if ($RuntimeContext.PSObject.Properties.Name -contains 'IsInteractiveRun') { [bool]$RuntimeContext.IsInteractiveRun } else { [bool]$defaultRuntimeContext.IsInteractiveRun }
    $modulePath = if ($RuntimeContext.PSObject.Properties.Name -contains 'ModulePath' -and -not [string]::IsNullOrWhiteSpace([string]$RuntimeContext.ModulePath)) { [string]$RuntimeContext.ModulePath } else { [string]$defaultRuntimeContext.ModulePath }

    return (Get-ReportRuntimeContext -ReportLogPath $reportLogPath -IsInteractiveRun $isInteractiveRun -ModulePath $modulePath)
}

function Write-ConsoleLine {
    param(
        [AllowEmptyString()]
        [string]$Message = '',
        [System.ConsoleColor]$ForegroundColor,
        [psobject]$RuntimeContext
    )

    $effectiveRuntimeContext = Resolve-ReportRuntimeContext -RuntimeContext $RuntimeContext

    if (-not $effectiveRuntimeContext.IsInteractiveRun) {
        Write-Information -MessageData $Message -Tags @('InteractiveOutput') -InformationAction Continue
        return
    }

    try {
        if ($PSBoundParameters.ContainsKey('ForegroundColor')) {
            $originalColor = $Host.UI.RawUI.ForegroundColor
            try {
                $Host.UI.RawUI.ForegroundColor = $ForegroundColor
                $Host.UI.WriteLine($Message)
            }
            finally {
                $Host.UI.RawUI.ForegroundColor = $originalColor
            }

            return
        }

        $Host.UI.WriteLine($Message)
    }
    catch {
        Write-Information -MessageData $Message -Tags @('InteractiveOutput') -InformationAction Continue
    }
}

function Get-ReportLogMutexName {
    param([string]$ReportLogPath)

    if ([string]::IsNullOrWhiteSpace($ReportLogPath)) {
        return $null
    }

    $normalizedPath = [System.IO.Path]::GetFullPath($ReportLogPath).ToUpperInvariant()
    $sha256 = [System.Security.Cryptography.SHA256]::Create()

    try {
        $pathBytes = [System.Text.Encoding]::UTF8.GetBytes($normalizedPath)
        $hashBytes = $sha256.ComputeHash($pathBytes)
        $hashText = -join ($hashBytes | ForEach-Object { $_.ToString('X2') })
        return ('ADServerLocalGroupReport_{0}' -f $hashText)
    }
    finally {
        $sha256.Dispose()
    }
}

function Write-ReportLogFileLine {
    param(
        [Parameter(Mandatory)][string]$ReportLogPath,
        [Parameter(Mandatory)][string]$LogMessage,
        [ValidateRange(100, 60000)][int]$MutexTimeoutMs = 5000
    )

    $mutexName = Get-ReportLogMutexName -ReportLogPath $ReportLogPath
    if ([string]::IsNullOrWhiteSpace($mutexName)) {
        return $false
    }

    $mutex = $null
    $lockTaken = $false

    try {
        $mutex = [System.Threading.Mutex]::new($false, $mutexName)

        try {
            $lockTaken = $mutex.WaitOne($MutexTimeoutMs)
        }
        catch [System.Threading.AbandonedMutexException] {
            $lockTaken = $true
        }

        if (-not $lockTaken) {
            Write-Verbose ("Не удалось получить mutex для файла лога '{0}' за {1} мс." -f $ReportLogPath, $MutexTimeoutMs)
            return $false
        }

        [System.IO.File]::AppendAllText($ReportLogPath, $LogMessage + [System.Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
        return $true
    }
    catch {
        Write-Verbose ("Не удалось записать строку в лог-файл '{0}': {1}" -f $ReportLogPath, $_.Exception.Message)
        return $false
    }
    finally {
        if ($null -ne $mutex) {
            if ($lockTaken) {
                [void]$mutex.ReleaseMutex()
            }

            $mutex.Dispose()
        }
    }
}

function Write-ReportLog {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO',

        [switch]$MirrorToWarningStream,
        [switch]$MirrorToErrorStream,

        [psobject]$RuntimeContext
    )

    $effectiveRuntimeContext = Resolve-ReportRuntimeContext -RuntimeContext $RuntimeContext
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $color = switch ($Level) {
        'INFO' { 'Cyan' }
        'WARN' { 'Yellow' }
        'ERROR' { 'Red' }
    }

    $logMessage = "[$timestamp] [$Level] $Message"

    if (-not [string]::IsNullOrWhiteSpace($effectiveRuntimeContext.ReportLogPath)) {
        [void](Write-ReportLogFileLine -ReportLogPath $effectiveRuntimeContext.ReportLogPath -LogMessage $logMessage)
    }

    switch ($Level) {
        'WARN' {
            if ($MirrorToWarningStream) {
                Write-Warning $logMessage
                return
            }
        }
        'ERROR' {
            if ($MirrorToErrorStream) {
                Write-Error -Message $logMessage -ErrorAction Continue
                return
            }
        }
    }

    if (-not $effectiveRuntimeContext.IsInteractiveRun) {
        Write-Information -MessageData $logMessage -Tags @('ReportLog', $Level) -InformationAction Continue
        return
    }

    Write-ConsoleLine -Message $logMessage -ForegroundColor $color -RuntimeContext $effectiveRuntimeContext
}

function Initialize-ReportLog {
    param(
        [Parameter(Mandatory)][string]$DirectoryPath,
        [psobject]$RuntimeContext
    )

    $effectiveRuntimeContext = Resolve-ReportRuntimeContext -RuntimeContext $RuntimeContext
    New-DirectoryIfMissing -Path $DirectoryPath
    $reportLogPath = Join-Path -Path $DirectoryPath -ChildPath ("execution_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    Set-Content -Path $reportLogPath -Value ("[{0}] [INFO] Log initialized." -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -Encoding UTF8

    return (Get-ReportRuntimeContext -ReportLogPath $reportLogPath -IsInteractiveRun $effectiveRuntimeContext.IsInteractiveRun -ModulePath $effectiveRuntimeContext.ModulePath)
}

function New-DirectoryIfMissing {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path) -and $PSCmdlet.ShouldProcess($Path, 'Create directory')) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Get-PlaceholderObject {
    param([Parameter(Mandatory)][string[]]$PropertyOrder)

    $placeholder = [ordered]@{}
    foreach ($propertyName in $PropertyOrder) {
        $placeholder[$propertyName] = $null
    }

    return [PSCustomObject]$placeholder
}

function Export-ReportCsv {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Data,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$PropertyOrder
    )

    $parentPath = Split-Path -Path $Path -Parent
    New-DirectoryIfMissing -Path $parentPath

    if ((Get-SafeCount -InputObject $Data) -gt 0) {
        $Data |
            Select-Object -Property $PropertyOrder |
            Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
        return
    }

    $header = (Get-PlaceholderObject -PropertyOrder $PropertyOrder) |
        Select-Object -Property $PropertyOrder |
        ConvertTo-Csv -NoTypeInformation |
        Select-Object -First 1

    Set-Content -Path $Path -Value $header -Encoding UTF8
}
