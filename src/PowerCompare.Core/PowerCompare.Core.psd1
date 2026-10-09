@{
    RootModule = 'PowerCompare.Core.psm1'
    ModuleVersion = '0.2.0'
    GUID = 'a27a6f45-01da-4db7-92b1-f9cfe0b71af6'
    Author = 'PowerCompare contributors'
    Description = 'PowerShell comparison and file operation engine.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Get-PCResourceCapabilities', 'Get-PCResourceEntries', 'Open-PCResourceRead', 'Compare-PCFolder', 'Get-PCTextDocument', 'Compare-PCText', 'Compare-PCTextFile', 'New-PCCopyPlan', 'Invoke-PCCopyPlan', 'New-PCSession', 'Save-PCSession', 'Import-PCSession', 'Export-PCComparisonReport')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
