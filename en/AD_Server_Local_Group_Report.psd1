@{
    RootModule        = 'AD_Server_Local_Group_Report.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '7f7903e1-2eb8-4887-b2f5-c26bfd508f71'
    Author            = 'didimozg'
    CompanyName       = 'didimozg'
    Copyright         = '(c) 2026 didimozg'
    Description       = 'English edition of the Windows Server local-group membership reporting tool for Active Directory and file-based server inventories.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport = @(
        'Set-ReportRuntimeContext',
        'Invoke-ServerScan',
        'Invoke-ServerScanBatch',
        'Start-ServerLocalGroupReport'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('PowerShell', 'ActiveDirectory', 'WindowsServer', 'Reporting', 'CIM')
            LicenseUri = 'https://opensource.org/licenses/MIT'
            ProjectUri = 'https://github.com/didimozg/AD_Server_Local_Group_Report'
            ReleaseNotes = 'Initial public standalone release of the bilingual AD Server local group reporting project.'
        }
    }
}
