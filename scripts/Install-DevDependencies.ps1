[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
# Development only: never called by the application launcher.
Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -Force -SkipPublisherCheck
Install-Module PSScriptAnalyzer -RequiredVersion 1.24.0 -Scope CurrentUser -Force
