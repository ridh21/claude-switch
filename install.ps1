# Installer for the ClaudeSwitch PowerShell module, for people who don't use
# the PowerShell Gallery (Install-Module ClaudeSwitch).
#
#   irm https://raw.githubusercontent.com/ridh21/claude-switch/main/install.ps1 | iex
#
# Installs for both Windows PowerShell 5.1 and PowerShell 7 (current user, no
# admin), then run 'cswitch setup' to make plain 'claude' ask which account to use.
[CmdletBinding()]
param(
  # Where to get the module from: the repo on GitHub, or a local folder.
  [string]$Source = 'https://raw.githubusercontent.com/ridh21/claude-switch/main/powershell/ClaudeSwitch',
  # Install into this modules folder only, instead of both editions' user folders.
  [string]$ModulesPath,
  # Run 'cswitch setup' afterwards.
  [switch]$Setup
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$files = @(
  'ClaudeSwitch.psd1', 'ClaudeSwitch.psm1', 'ClaudeSwitch.Format.ps1xml',
  'Private/Console.ps1', 'Private/Core.ps1', 'Private/Jsonc.ps1', 'Private/Links.ps1', 'Private/Usage.ps1',
  'Public/Cswitch.ps1', 'Public/Doctor.ps1', 'Public/Launch.ps1', 'Public/Menu.ps1',
  'Public/Profiles.ps1', 'Public/Setup.ps1', 'Public/Usage.ps1', 'Public/VSCode.ps1'
)

$isUrl = $Source -match '^https?://'
$staging = Join-Path ([IO.Path]::GetTempPath()) ('claude-switch-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
try {
  foreach ($f in $files) {
    $dest = Join-Path $staging $f
    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
    if ($isUrl) { Invoke-WebRequest -UseBasicParsing -Uri "$($Source.TrimEnd('/'))/$f" -OutFile $dest }
    else { Copy-Item -LiteralPath (Join-Path $Source $f) -Destination $dest }
  }
  # Downloaded files carry the Mark of the Web, which RemoteSigned refuses to load.
  Get-ChildItem $staging -Recurse -File | Unblock-File

  $version = (Import-PowerShellDataFile (Join-Path $staging 'ClaudeSwitch.psd1')).ModuleVersion
  $targets = if ($ModulesPath) { @($ModulesPath) } else {
    $docs = [Environment]::GetFolderPath('MyDocuments')
    @((Join-Path $docs 'WindowsPowerShell\Modules'), (Join-Path $docs 'PowerShell\Modules'))
  }
  foreach ($t in $targets) {
    $dir = Join-Path $t "ClaudeSwitch\$version"
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Copy-Item -Path (Join-Path $staging '*') -Destination $dir -Recurse -Force
    Write-Host "Installed ClaudeSwitch $version to $dir"
  }
} finally {
  Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
}

if ($Setup) {
  Import-Module ClaudeSwitch -Force
  cswitch setup
} else {
  Write-Host ''
  Write-Host 'Next: make plain "claude" ask which account to use:'
  Write-Host '  Import-Module ClaudeSwitch; cswitch setup'
  Write-Host 'Add --vscode and --terminal for VS Code and Windows Terminal profiles.'
}
