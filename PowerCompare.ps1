#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$LeftPath,
    [string]$RightPath,
    [ValidateSet('Content', 'Metadata')][string]$Mode = 'Content',
    [switch]$NoGui
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'src/PowerCompare.Core/PowerCompare.Core.psd1') -Force
if ($NoGui) {
    if ([string]::IsNullOrWhiteSpace($LeftPath) -or [string]::IsNullOrWhiteSpace($RightPath)) { throw '-NoGui requires -LeftPath and -RightPath.' }
    $rows = @(Compare-PCFolder -LeftPath $LeftPath -RightPath $RightPath -Mode $Mode)
    ConvertTo-Json -InputObject $rows -Depth 6
    return
}
if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'The WPF interface requires Windows. Use -NoGui for command-line comparison.' }
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    $engine = (Get-Process -Id $PID).Path
    $launchArgs = @('-NoProfile', '-STA', '-File', $PSCommandPath, '-Mode', $Mode)
    if ($LeftPath) { $launchArgs += @('-LeftPath', $LeftPath) }
    if ($RightPath) { $launchArgs += @('-RightPath', $RightPath) }
    & $engine @launchArgs
    exit $LASTEXITCODE
}
. (Join-Path $PSScriptRoot 'src/PowerCompare.UI/Workers.ps1')
. (Join-Path $PSScriptRoot 'src/PowerCompare.UI/Controller.ps1')
. (Join-Path $PSScriptRoot 'src/PowerCompare.UI/TextEditor.ps1')
. (Join-Path $PSScriptRoot 'src/PowerCompare.UI/TextMerge.ps1')
. (Join-Path $PSScriptRoot 'src/PowerCompare.UI/TextView.ps1')
. (Join-Path $PSScriptRoot 'src/PowerCompare.UI/Operations.ps1')
. (Join-Path $PSScriptRoot 'src/PowerCompare.UI/Application.ps1')
Show-PCMainWindow -LeftPath $LeftPath -RightPath $RightPath -Mode $Mode
