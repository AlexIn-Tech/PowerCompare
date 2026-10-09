[CmdletBinding()]
param(
    [string]$Path,
    [string]$ResultsDirectory
)
$ErrorActionPreference = 'Stop'
if (-not $Path) { $Path = Join-Path $PSScriptRoot '../tests' }
if (-not $ResultsDirectory) { $ResultsDirectory = Join-Path $PSScriptRoot ("../TestResults/PowerShell-" + $PSVersionTable.PSVersion.Major) }
$localModules = Join-Path $PSScriptRoot '../TestResults/modules'
if (Test-Path -LiteralPath $localModules) {
    $env:PSModulePath = $localModules + [IO.Path]::PathSeparator + $env:PSModulePath
}
$failed = $false
try {
    [void][IO.Directory]::CreateDirectory($ResultsDirectory)
    # Test.ps1 exits with its result, so run it in a child of this same runtime.
    $engine = (Get-Process -Id $PID).Path
    & $engine -NoProfile -File (Join-Path $PSScriptRoot 'Test.ps1') -Path $Path -Coverage -ResultsPath (Join-Path $ResultsDirectory 'pester.xml')
    if ($LASTEXITCODE -ne 0) { $failed = $true }

    Import-Module PSScriptAnalyzer -RequiredVersion 1.24.0 -ErrorAction Stop
    $issues = @(Invoke-ScriptAnalyzer -Path (Join-Path $PSScriptRoot '../src') -Recurse -Severity Error)
    $issues | Export-Clixml -LiteralPath (Join-Path $ResultsDirectory 'analysis.xml')
    if ($issues.Count) {
        $issues | Format-Table -AutoSize
        $failed = $true
    }
} catch {
    Write-Error $_ -ErrorAction Continue
    $failed = $true
}
if ($failed) { exit 1 }
exit 0
