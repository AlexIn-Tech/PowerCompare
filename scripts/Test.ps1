[CmdletBinding()]
param(
    [string]$Path = (Join-Path $PSScriptRoot '../tests'),
    [switch]$Coverage,
    [string]$ResultsPath = (Join-Path $PSScriptRoot '../TestResults/pester.xml')
)
$ErrorActionPreference = 'Stop'
try {
    Import-Module Pester -RequiredVersion 5.7.1 -ErrorAction Stop
    $config = New-PesterConfiguration
    $config.Run.Path = $Path
    $config.Run.PassThru = $true
    $config.Output.Verbosity = 'Detailed'
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputPath = $ResultsPath
    $config.TestResult.OutputFormat = 'NUnitXml'
    $config.CodeCoverage.Enabled = $Coverage.IsPresent
    $config.CodeCoverage.Path = @(Join-Path $PSScriptRoot '../src/PowerCompare.Core/*.ps1')
    $config.CodeCoverage.OutputPath = Join-Path (Split-Path $ResultsPath) 'coverage.xml'
    $result = Invoke-Pester -Configuration $config
    if ($result.FailedCount -gt 0 -or $result.FailedContainersCount -gt 0 -or $result.TotalCount -eq 0) { exit 1 }
    exit 0
} catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
