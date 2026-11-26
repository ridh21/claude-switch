$script:BlockStart = '# >>> claude-switch >>>'
$script:BlockEnd = '# <<< claude-switch <<<'
$script:VSCodeProfilesKey = 'terminal.integrated.profiles.windows'

function Get-ShellExe { if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' } }

function Get-WindowsTerminalFragment {
  Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\claude-switch\profiles.json'
}

# A GUID that stays the same for a name, so Windows Terminal keeps tab settings across rewrites.
function Get-StableGuid([string]$Name) {
  $md5 = [Security.Cryptography.MD5]::Create()
  try { '{' + ([guid]::new($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes("claude-switch:$Name")))).ToString() + '}' }
  finally { $md5.Dispose() }
}

function Get-ImportLine {
  # By name when installed where PowerShell finds modules, else by path.
  $here = (Get-Module ClaudeSwitch | Select-Object -First 1).ModuleBase
  $onPath = $env:PSModulePath -split ';' | Where-Object { $_ -and $here -and $here.StartsWith($_.TrimEnd('\') + '\', 'OrdinalIgnoreCase') }
  if ($onPath) { 'Import-Module ClaudeSwitch -ErrorAction SilentlyContinue' }
  else { "Import-Module '$((Join-Path $here 'ClaudeSwitch.psd1') -replace "'", "''")' -ErrorAction SilentlyContinue" }
}

function Write-WindowsTerminalFragment {
  $shell = Get-ShellExe
  $profiles = foreach ($n in Get-ProfileNames) {
    [ordered]@{
      guid        = Get-StableGuid $n
      name        = "Claude ($n)"
      commandline = "$shell -NoLogo -NoExit -Command cswitch $n"
      tabColor    = '#D97757'
      tabTitle    = "Claude ($n)"
      suppressApplicationTitle = $true
    }
  }
  $file = Get-WindowsTerminalFragment
  New-Item -ItemType Directory -Force -Path (Split-Path $file) | Out-Null
  $json = [ordered]@{ profiles = @($profiles) } | ConvertTo-Json -Depth 5
  [IO.File]::WriteAllText($file, $json, (New-Object Text.UTF8Encoding($false)))
}

# Our VS Code terminal profiles are "Claude (<name>)" entries that run cswitch.
function Get-OwnVSCodeProfileNames([string]$Text) {
  $current = Get-JsoncMember $Text $script:VSCodeProfilesKey
  if ($current -isnot [Management.Automation.PSCustomObject]) { return @() }
  @($current.PSObject.Properties | Where-Object {
      $_.Name -like 'Claude (*)' -and $_.Value -and ((@($_.Value.args) -join ' ') -match 'cswitch ')
    } | ForEach-Object Name)
}

function Sync-VSCodeTerminalProfiles([string]$SettingsPath, [switch]$Remove) {
  $shell = Get-ShellExe
  Update-JsoncFile $SettingsPath {
    param($text)
    $wanted = if ($Remove) { @() } else { @(Get-ProfileNames | ForEach-Object { "Claude ($_)" }) }
    foreach ($old in Get-OwnVSCodeProfileNames $text) {
      if ($wanted -notcontains $old) { $text = Remove-JsoncEntry $text $script:VSCodeProfilesKey $old }
    }
    if (-not $Remove) {
      foreach ($n in Get-ProfileNames) {
        $text = Set-JsoncEntry $text $script:VSCodeProfilesKey "Claude ($n)" ([ordered]@{
            path = $shell; args = @('-NoLogo', '-NoExit', '-Command', "cswitch $n"); icon = 'sparkle'
          })
      }
    }
    $text
  } "  `"$($script:VSCodeProfilesKey)`": { `"Claude (work)`": { `"path`": `"$shell`", `"args`": [ `"-NoExit`", `"-Command`", `"cswitch work`" ] } }"
}

# After a profile is added or removed, refresh the integrations that list profiles.
function Sync-ShellIntegrations {
  try {
    if ($env:LOCALAPPDATA -and (Test-Path -LiteralPath (Get-WindowsTerminalFragment))) { Write-WindowsTerminalFragment }
    $vs = Get-VSCodeUserSettingsPath
    if ($env:APPDATA -and (Test-Path -LiteralPath $vs) -and @(Get-OwnVSCodeProfileNames ([IO.File]::ReadAllText($vs))).Count) {
      Sync-VSCodeTerminalProfiles $vs
    }
  } catch {
    Write-Warning "cswitch: could not refresh the terminal profiles: $($_.Exception.Message)"
  }
}

function Install-ClaudeSwitchShell {
  <#
  .SYNOPSIS
  Make plain 'claude' ask which account to use (cswitch setup).
  .DESCRIPTION
  Adds a marked block to your PowerShell profile that imports ClaudeSwitch and
  defines a 'claude' function. -WindowsTerminal adds a Windows Terminal tab
  per login (a fragment, so your Terminal settings.json is not touched).
  -VSCode adds a VS Code terminal profile per login. Running it again is
  safe; Uninstall-ClaudeSwitchShell (cswitch setup --undo) takes it all out.
  #>
  [CmdletBinding()]
  param(
    [string]$ProfilePath = $PROFILE.CurrentUserAllHosts,
    [switch]$WindowsTerminal,
    [switch]$VSCode,
    [string]$VSCodeSettingsPath = (Get-VSCodeUserSettingsPath)
  )
  $text = if (Test-Path -LiteralPath $ProfilePath) { [IO.File]::ReadAllText($ProfilePath) } else { '' }
  $nl = if ($text -and -not $text.Contains("`r`n")) { "`n" } else { "`r`n" }
  $text = Remove-ProfileBlock $text
  if ($text -and -not $text.EndsWith("`n")) { $text += $nl }
  $block = @(
    $script:BlockStart
    (Get-ImportLine)
    'if (Get-Command Invoke-ClaudeShim -ErrorAction SilentlyContinue) { function claude { Invoke-ClaudeShim @args } }'
    $script:BlockEnd
  ) -join $nl
  New-Item -ItemType Directory -Force -Path (Split-Path $ProfilePath) | Out-Null
  [IO.File]::WriteAllText($ProfilePath, "$text$block$nl", (New-Object Text.UTF8Encoding($false)))
  Write-Host "Added the claude menu to $ProfilePath. Open a new PowerShell window, or run: . `$PROFILE.CurrentUserAllHosts"
  if ($WindowsTerminal) {
    Write-WindowsTerminalFragment
    Write-Host 'Added a Windows Terminal profile for every login (open the new-tab menu).'
  }
  if ($VSCode) {
    Sync-VSCodeTerminalProfiles $VSCodeSettingsPath
    Write-Host 'Added a VS Code terminal profile for every login (the + menu in the terminal panel).'
  }
}

function Remove-ProfileBlock([string]$Text) {
  $pattern = '(?m)^' + [regex]::Escape($script:BlockStart) + '[\s\S]*?' + [regex]::Escape($script:BlockEnd) + '(\r?\n)?'
  [regex]::Replace($Text, $pattern, '')
}

function Uninstall-ClaudeSwitchShell {
  <#
  .SYNOPSIS
  Take out everything cswitch setup added (cswitch setup --undo).
  #>
  [CmdletBinding()]
  param(
    [string]$ProfilePath = $PROFILE.CurrentUserAllHosts,
    [string]$VSCodeSettingsPath = (Get-VSCodeUserSettingsPath)
  )
  if (Test-Path -LiteralPath $ProfilePath) {
    $text = [IO.File]::ReadAllText($ProfilePath)
    $new = Remove-ProfileBlock $text
    if ($new -cne $text) {
      if ($new) { [IO.File]::WriteAllText($ProfilePath, $new, (New-Object Text.UTF8Encoding($false))) }
      else { Remove-Item -LiteralPath $ProfilePath }
      Write-Host "Removed the claude menu from $ProfilePath."
    }
  }
  $fragment = Get-WindowsTerminalFragment
  if (Test-Path -LiteralPath $fragment) {
    Remove-Item -LiteralPath (Split-Path $fragment) -Recurse -Force
    Write-Host 'Removed the Windows Terminal profiles.'
  }
  if (Test-Path -LiteralPath $VSCodeSettingsPath) {
    if (@(Get-OwnVSCodeProfileNames ([IO.File]::ReadAllText($VSCodeSettingsPath))).Count) {
      Sync-VSCodeTerminalProfiles $VSCodeSettingsPath -Remove
      Write-Host 'Removed the VS Code terminal profiles.'
    }
  }
}
