# Runs the ClaudeSwitch tests. Needs Pester 5 or later:
#   Install-Module Pester -Scope CurrentUser -SkipPublisherCheck
# Usage: powershell -NoProfile -File powershell\tests\run.ps1 [-Path <test file>]
param([string]$Path = $PSScriptRoot, [string]$Output = 'Detailed')

Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop
$config = New-PesterConfiguration
$config.Run.Path = @($Path -split ',')
$config.Run.Exit = $true
$config.Output.Verbosity = $Output
Invoke-Pester -Configuration $config
