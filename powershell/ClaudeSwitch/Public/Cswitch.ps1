$script:Version = (Import-PowerShellDataFile (Join-Path $PSScriptRoot '..\ClaudeSwitch.psd1')).ModuleVersion

function Invoke-ClaudeShim {
  <#
  .SYNOPSIS
  What plain 'claude' runs once 'cswitch setup' has added it to your profile.
  .DESCRIPTION
  Asks which account to use, then runs Claude Code as it with your arguments
  unchanged. Goes straight to claude when there is nothing to choose, when
  nobody is there to answer (scripts, pipes), or for --version, --help,
  update, install and doctor. CSWITCH_PROFILE=<name> always uses that profile.
  #>
  if ($env:CSWITCH_PROFILE) {
    Invoke-ClaudeProfile $env:CSWITCH_PROFILE @args
    return
  }
  $ask = Test-Interactive
  if ($args.Count -gt 0 -and $args[0] -in '-v', '--version', '-h', '--help', 'update', 'install', 'doctor') { $ask = $false }
  if ($ask -and @(Get-ProfileNames).Count -gt 1) {
    $name = Select-ClaudeProfile
    if ($name) { Invoke-ClaudeProfile $name @args } else { $global:LASTEXITCODE = 130 }
    return
  }
  & (Get-ClaudeExe) @args
}

function Get-CsHelp {
  @"
cswitch $script:Version (PowerShell) - keep several Claude Code logins and launch any of them

Usage:
  cswitch add <name> [--isolated]      Create a profile
  cswitch list                         List profiles and who is logged in
  cswitch usage [--json]               Show each login's session and weekly limits
  cswitch best [claude args...]        Launch the login with the most room left
  cswitch                              Pick a profile from a menu and launch it
  cswitch pick [claude args...]        Same, passing arguments on to claude
  cswitch <name> [claude args...]      Launch Claude Code as a profile
  cswitch run <name> [claude args...]  Same as above
  cswitch env <name>                   Print the line that points this shell at a profile
  cswitch remove <name> [-y]           Delete a profile (shared settings and history are kept)
  cswitch setup [--vscode] [--terminal] [--undo]
                                       Make plain 'claude' ask which account to use
  cswitch pin <name> [folder]          Pin a login to a VS Code workspace
  cswitch unpin [folder]               Remove the pin
  cswitch vscode <name>                Make the Claude Code VS Code extension use a login
  cswitch doctor [--fix]               Check profiles, links and logins
  cswitch --version | --help

The same commands work as cmdlets with objects:
  Get-ClaudeUsage | Where-Object WeeklyPct -lt 50
  Get-ClaudeProfile, New-ClaudeProfile, Invoke-ClaudeProfile, Set-ClaudeWorkspace, Test-ClaudeSwitch

Email addresses are shown masked (ja***e@g***.com); CSWITCH_SHOW_EMAIL=1 shows them whole.
"default" is your existing ~\.claude setup and is never modified.
"@
}

# Splits "--flag" style switches out of cswitch's arguments.
function Split-CsArgs([object[]]$Arguments, [string[]]$Flags) {
  $found = @{}; $rest = @()
  foreach ($a in $Arguments) {
    if ($Flags -contains "$a") { $found["$a"] = $true } else { $rest += , $a }
  }
  @{ Flags = $found; Rest = $rest }
}

function Format-Meter($Pct, $Epoch, $Palette, [bool]$Fancy) {
  if ($null -eq $Pct) { return '   -'.PadRight(24) }
  $full = if ($Fancy) { [string][char]0x2588 } else { '#' }
  $empty = if ($Fancy) { [string][char]0x2591 } else { '.' }
  $n = [Math]::Min(10, [Math]::Floor(($Pct + 5) / 10))
  $bar = ($full * $n) + ($empty * (10 - $n))
  '{0}{1,4}%{2} {3}{4}{2} {5}{6,-7}{2}' -f $Palette.Bold, $Pct, $Palette.Reset, (Get-LevelColor $Pct $Palette), $bar, $Palette.Dim, (Format-Until $Epoch)
}

# The text table bin/cswitch prints for 'cswitch usage'.
function Format-UsageTable($Readings) {
  $interactive = Test-Interactive
  $c = if ($interactive) { Get-Palette } else { @{ Reset = ''; Bold = ''; Dim = ''; Red = ''; Yellow = ''; Green = ''; Accent = '' } }
  $fancy = $interactive -and ([Console]::OutputEncoding.CodePage -eq 65001)
  $active = Get-ActiveProfileName
  $width = [Math]::Max(7, ($Readings | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum)
  '  {0}{1}  {2}  {3}  {4}{5}' -f $c.Dim, 'PROFILE'.PadRight($width), 'ACCOUNT'.PadRight(30), 'SESSION (5h)    resets'.PadRight(24), 'WEEKLY (7d)     resets', $c.Reset
  foreach ($r in $Readings) {
    $email = Hide-Email (Get-ProfileEmail $r.Name); if (-not $email) { $email = '(not logged in)' }
    $mark = if ($r.Name -eq $active) { '*' } else { ' ' }
    $x = $r.Reading
    $tail = switch ($x.Status) {
      'ok' { "$(Format-Meter $x.SessionPct $x.SessionAt $c $fancy)  $(Format-Meter $x.WeeklyPct $x.WeeklyAt $c $fancy)" }
      'logged-out' { "$($c.Dim)not logged in: run cswitch $($r.Name)$($c.Reset)" }
      'expired' { "$($c.Yellow)login expired: run cswitch $($r.Name) once to refresh it$($c.Reset)" }
      'rate-limited' { "$($c.Yellow)asked too often; try again in a minute$($c.Reset)" }
      default { "$($c.Red)could not reach the usage service$($c.Reset)" }
    }
    "$mark $($r.Name.PadRight($width))  $($email.PadRight(30))  $tail"
  }
  $best = Find-BestProfile $Readings
  if ($best) {
    $w = if ($null -eq $best.Reading.WeeklyPct) { 0 } else { $best.Reading.WeeklyPct }
    ''
    "  Most room: $($c.Bold)$($best.Name)$($c.Reset) ($($best.Reading.SessionPct)% session, $w% weekly)  ->  cswitch $($best.Name)"
  }
}

function cswitch {
  <#
  .SYNOPSIS
  Keep several Claude Code logins on one machine and launch any of them.
  .DESCRIPTION
  The same commands as cswitch on macOS and Linux. Run 'cswitch --help' for the list.
  #>
  $cmd = if ($args.Count -gt 0) { "$($args[0])" } else { '' }
  $rest = @(if ($args.Count -gt 1) { $args[1..($args.Count - 1)] })
  switch -CaseSensitive ($cmd) {
    'add' {
      $s = Split-CsArgs $rest @('--isolated')
      if ($s.Rest.Count -ne 1) { Stop-Cs 'usage: cswitch add <name> [--isolated]' }
      New-ClaudeProfile $s.Rest[0] -Isolated:([bool]$s.Flags['--isolated']) | Out-Null
      return
    }
    { $_ -in 'list', 'ls' } {
      foreach ($p in Get-ClaudeProfile) {
        $mark = if ($p.Active) { '*' } else { ' ' }
        $acct = if ($p.Account) { $p.Account } else { '(not logged in)' }
        '{0} {1} {2}' -f $mark, $p.Name.PadRight(16), $acct
      }
      return
    }
    'usage' {
      $s = Split-CsArgs $rest @('--json')
      if ($s.Rest.Count) { Stop-Cs 'usage: cswitch usage [--json]' }
      if ($s.Flags['--json']) { Get-ClaudeUsage -Json; return }
      Format-UsageTable @(Get-UsageReadings @(Get-ProfileNames) 0 15)
      return
    }
    'best' {
      $readings = @(Get-UsageReadings @(Get-ProfileNames) (Get-UsageTtl) 15)
      $best = Find-BestProfile $readings
      if (-not $best) { Stop-Cs "no login has room left right now (see 'cswitch usage')" }
      $w = if ($null -eq $best.Reading.WeeklyPct) { 0 } else { $best.Reading.WeeklyPct }
      Write-Host "Using $($best.Name) ($($best.Reading.SessionPct)% session, $w% weekly)."
      Invoke-ClaudeProfile $best.Name @rest
      return
    }
    'run' {
      if (-not $rest.Count) { Stop-Cs 'usage: cswitch run <name> [claude args...]' }
      Invoke-ClaudeProfile @rest
      return
    }
    'pick' {
      if (@(Get-ProfileNames).Count -eq 1) { & (Get-ClaudeExe) @rest; return }
      $name = Select-ClaudeProfile
      if ($name) { Invoke-ClaudeProfile $name @rest } else { $global:LASTEXITCODE = 130 }
      return
    }
    'env' {
      if ($rest.Count -ne 1) { Stop-Cs 'usage: cswitch env <name>' }
      Assert-ProfileExists $rest[0]
      if ($rest[0] -eq 'default') { 'Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction Ignore' }
      else { "`$env:CLAUDE_CONFIG_DIR = '$((Get-ProfileDir $rest[0]) -replace "'", "''")'" }
      return
    }
    { $_ -in 'remove', 'rm' } {
      $s = Split-CsArgs $rest @('-y', '--yes')
      if ($s.Rest.Count -ne 1) { Stop-Cs 'usage: cswitch remove <name> [-y]' }
      Remove-ClaudeProfile $s.Rest[0] -Force:([bool]($s.Flags['-y'] -or $s.Flags['--yes']))
      return
    }
    'setup' {
      $s = Split-CsArgs $rest @('--vscode', '--terminal', '--undo')
      if ($s.Flags['--undo']) { Uninstall-ClaudeSwitchShell; return }
      Install-ClaudeSwitchShell -VSCode:([bool]$s.Flags['--vscode']) -WindowsTerminal:([bool]$s.Flags['--terminal'])
      return
    }
    'pin' {
      if ($rest.Count -lt 1 -or $rest.Count -gt 2) { Stop-Cs 'usage: cswitch pin <name> [folder]' }
      $path = if ($rest.Count -eq 2) { $rest[1] } else { (Get-Location).ProviderPath }
      Set-ClaudeWorkspace -Profile $rest[0] -Path $path
      return
    }
    'unpin' {
      $path = if ($rest.Count -ge 1) { $rest[0] } else { (Get-Location).ProviderPath }
      Clear-ClaudeWorkspace -Path $path
      return
    }
    'vscode' {
      if ($rest.Count -ne 1) { Stop-Cs 'usage: cswitch vscode <name>' }
      Set-ClaudeExtensionProfile -Profile $rest[0]
      return
    }
    'doctor' {
      $s = Split-CsArgs $rest @('--fix')
      $c = if (Test-Interactive) { Get-Palette } else { @{ Reset = ''; Red = ''; Yellow = ''; Green = ''; Dim = '' } }
      foreach ($check in Test-ClaudeSwitch -Fix:([bool]$s.Flags['--fix'])) {
        $color = switch ($check.Status) { 'ok' { $c.Green } 'warn' { $c.Yellow } 'fail' { $c.Red } default { $c.Dim } }
        '  {0}{1,-5}{2} {3,-18} {4}' -f $color, $check.Status, $c.Reset, $check.Check, $check.Detail
      }
      return
    }
    { $_ -in '-v', '--version', 'version' } { "cswitch $script:Version (PowerShell)"; return }
    { $_ -in '-h', '--help', 'help' } { Get-CsHelp; return }
    '' {
      if ((Test-Interactive) -and @(Get-ProfileNames).Count -gt 1) {
        $name = Select-ClaudeProfile
        if ($name) { Invoke-ClaudeProfile $name } else { $global:LASTEXITCODE = 130 }
      } else { Get-CsHelp }
      return
    }
    default {
      if (Test-ProfileExists $cmd) { Invoke-ClaudeProfile $cmd @rest; return }
      Stop-Cs "unknown command or profile: $cmd (try 'cswitch --help')"
    }
  }
}
