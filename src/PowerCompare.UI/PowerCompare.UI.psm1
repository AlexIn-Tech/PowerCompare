# WPF event closures run in dynamic modules. Export their command dependencies
# into the runspace session rather than leaving them in a launcher's local scope.
Import-Module (Join-Path $PSScriptRoot '../PowerCompare.Core/PowerCompare.Core.psd1') -Global -Force
foreach($file in 'Workers','Controller','TextEditor','TextMerge','TextView','Operations','Application') {
    . (Join-Path $PSScriptRoot "$file.ps1")
}
Export-ModuleMember -Function @(
    'Test-PCCurrentGeneration','Start-PCOperationWorker','Receive-PCWorkerMessages',
    'Stop-PCComparisonWorker','Close-PCComparisonWorker','Start-PCComparisonWorker',
    'New-PCWorkspaceState','Invoke-PCCompareRequest','Update-PCWorkspace','Close-PCWorkspace',
    'Test-PCTextEditorDirty','Get-PCEditorNewlineStyle','ConvertTo-PCEditorSaveText',
    'Find-PCTextMatch','Replace-PCTextMatches','New-PCTextEditorWindow','Show-PCTextEditor',
    'Show-PCTextMerge','Get-PCNextDifferenceIndex','Get-PCEligibleCopyPaths',
    'ConvertTo-PCTextDisplayRows','Show-PCTextComparison','New-PCFileOperationState',
    'Start-PCFileOperationRequest','Update-PCFileOperationState','Show-PCCopyPreview',
    'Select-PCFolder','New-PCMainWindow','Show-PCMainWindow'
)
