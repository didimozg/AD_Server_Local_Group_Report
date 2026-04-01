Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:DefaultRuntimeContext = $null
$script:ModuleFilePath = $PSCommandPath
$script:ModuleRoot = Split-Path -Path $PSCommandPath -Parent
$script:DefaultWellKnownAuthorities = @(
    'NT AUTHORITY',
    'BUILTIN',
    'NT SERVICE',
    'IIS APPPOOL',
    'APPLICATION PACKAGE AUTHORITY',
    'Window Manager',
    'Font Driver Host'
)

$moduleScriptFiles = @(
    'Private\Runtime.ps1',
    'Private\Contracts.ps1',
    'Private\Configuration.ps1',
    'Private\ActiveDirectory.ps1',
    'Private\ScanConnectivity.ps1',
    'Private\ScanMembership.ps1',
    'Private\Reporting.ps1',
    'Public\Commands.ps1'
)

foreach ($relativePath in $moduleScriptFiles) {
    $scriptPath = Join-Path -Path $script:ModuleRoot -ChildPath $relativePath
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw ("Не найден файл модуля: {0}" -f $scriptPath)
    }

    . $scriptPath
}

$script:DefaultRuntimeContext = Get-ReportRuntimeContext -ReportLogPath $null -IsInteractiveRun $true -ModulePath $script:ModuleFilePath

Export-ModuleMember -Function @(
    'Set-ReportRuntimeContext',
    'Invoke-ServerScan',
    'Invoke-ServerScanBatch',
    'Start-ServerLocalGroupReport'
)
