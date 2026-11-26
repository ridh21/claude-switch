# VS Code integration, through settings files only (no extension to install):
#   Set-ClaudeWorkspace / Clear-ClaudeWorkspace  pin a login to a workspace
#     folder: its integrated terminals get CSWITCH_PROFILE, so 'claude' (and
#     bin/cswitch's shell function on macOS and Linux) starts as that login.
#   Set-ClaudeExtensionProfile  the login the Claude Code extension uses. Its
#     claudeCode.environmentVariables setting is machine-scoped, which VS Code
#     only reads from user settings, so it can't differ per workspace.
#   Install-ClaudeSwitchShell -VSCode  one terminal profile per login.

$script:TerminalEnvKeys = @('terminal.integrated.env.windows', 'terminal.integrated.env.osx', 'terminal.integrated.env.linux')

function Get-VSCodeUserSettingsPath {
  Join-Path $env:APPDATA 'Code\User\settings.json'
}

function Set-ClaudeWorkspace {
  <#
  .SYNOPSIS
  Pin a login to a VS Code workspace folder (cswitch pin).
  .DESCRIPTION
  Writes CSWITCH_PROFILE into the folder's .vscode\settings.json for the
  integrated terminal on Windows, macOS and Linux. Every new terminal in that
  folder then starts 'claude' as the pinned login, without the menu. Comments
  and other settings in the file are kept.
  .EXAMPLE
  Set-ClaudeWorkspace -Profile work -Path C:\code\api
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, Position = 0)][string]$Profile,
    [Parameter(Position = 1)][string]$Path = (Get-Location).ProviderPath
  )
  Assert-ProfileExists $Profile
  $file = Join-Path $Path '.vscode\settings.json'
  $snippet = ($script:TerminalEnvKeys | ForEach-Object { "  `"$_`": { `"CSWITCH_PROFILE`": `"$Profile`" }" }) -join ",`n"
  Update-JsoncFile $file {
    param($text)
    foreach ($key in $script:TerminalEnvKeys) { $text = Set-JsoncEntry $text $key 'CSWITCH_PROFILE' $Profile }
    $text
  } $snippet
  Write-Host "Pinned $Profile to $Path. New VS Code terminals there start claude as $Profile (open a new terminal to pick it up)."
}

function Clear-ClaudeWorkspace {
  <#
  .SYNOPSIS
  Remove a workspace's login pin (cswitch unpin). Other settings are kept.
  #>
  [CmdletBinding()]
  param([Parameter(Position = 0)][string]$Path = (Get-Location).ProviderPath)
  $file = Join-Path $Path '.vscode\settings.json'
  if (-not (Test-Path -LiteralPath $file)) { Write-Host "No login is pinned to $Path."; return }
  Update-JsoncFile $file {
    param($text)
    foreach ($key in $script:TerminalEnvKeys) { $text = Remove-JsoncEntry $text $key 'CSWITCH_PROFILE' }
    $text
  } "Remove CSWITCH_PROFILE from the terminal.integrated.env.* settings."
  Write-Host "Unpinned $Path."
}

function Set-ClaudeExtensionProfile {
  <#
  .SYNOPSIS
  Choose the login the Claude Code VS Code extension uses (cswitch vscode).
  .DESCRIPTION
  Sets CLAUDE_CONFIG_DIR in the extension's claudeCode.environmentVariables
  user setting, keeping any other variables there. 'default' removes it, so
  the extension uses your ~\.claude login again. Reload VS Code afterwards.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, Position = 0)][string]$Profile,
    [string]$SettingsPath = (Get-VSCodeUserSettingsPath)
  )
  Assert-ProfileExists $Profile
  $key = 'claudeCode.environmentVariables'
  $dir = Get-ProfileDir $Profile
  $snippet = "  `"$key`": [ { `"name`": `"CLAUDE_CONFIG_DIR`", `"value`": $(ConvertTo-JsonText $dir) } ]"
  Update-JsoncFile $SettingsPath {
    param($text)
    $current = Get-JsoncMember $text $key
    $vars = @(foreach ($v in @($current)) {
        if ($v -and $v.name -ne 'CLAUDE_CONFIG_DIR') { [ordered]@{ name = [string]$v.name; value = [string]$v.value } }
      })
    if ($Profile -ne 'default') { $vars += , ([ordered]@{ name = 'CLAUDE_CONFIG_DIR'; value = $dir }) }
    if ($vars.Count -eq 0) { Remove-JsoncMember $text $key } else { Set-JsoncMember $text $key $vars }
  } $snippet
  Write-Host "The Claude Code extension will use $Profile. Run 'Developer: Reload Window' in VS Code to apply it."
}
