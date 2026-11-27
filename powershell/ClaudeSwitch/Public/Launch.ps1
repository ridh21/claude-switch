function Get-ClaudeExe {
  $cmd = Get-Command claude -CommandType Application -ErrorAction Ignore | Select-Object -First 1
  if (-not $cmd) { Stop-Cs "'claude' is not on your PATH; install Claude Code first (https://claude.com/claude-code)" }
  $cmd.Source
}

function Invoke-ClaudeProfile {
  <#
  .SYNOPSIS
  Run Claude Code as a profile. Any further arguments go to claude unchanged.
  .DESCRIPTION
  CLAUDE_CONFIG_DIR is set for this launch only and restored afterwards, so
  the shell is left as it was. When the session ends on a login that has hit
  its 5-hour or weekly limit, offers to continue the same conversation on the
  login with the most room (CSWITCH_HANDOFF=0 turns that off).
  .EXAMPLE
  Invoke-ClaudeProfile work --continue
  .NOTES
  Deliberately a simple function without declared parameters: every argument
  after the profile name, including ones like -p or -Verbose, goes to claude.
  #>
  $Name = if ($args.Count -gt 0) { "$($args[0])" } else { '' }
  $ClaudeArgs = @(if ($args.Count -gt 1) { $args[1..($args.Count - 1)] | ForEach-Object { "$_" } })
  Assert-ProfileExists $Name
  if ($ClaudeArgs.Count -gt 0 -and $ClaudeArgs[0] -eq '--') { $ClaudeArgs = @($ClaudeArgs | Select-Object -Skip 1) }
  Start-ClaudeAs $Name $ClaudeArgs
  $rc = $script:ClaudeExitCode
  if (Test-HandoffWanted $ClaudeArgs) { Invoke-Handoff $Name }
  $global:LASTEXITCODE = $rc
}

# Run claude as a profile. Its output flows on down the pipeline; its exit
# code is left in $script:ClaudeExitCode. The environment is put back afterwards.
function Start-ClaudeAs([string]$Name, [string[]]$ClaudeArgs) {
  $exe = Get-ClaudeExe
  if ($Name -ne 'default') { Repair-SharedLinks $Name }
  $old = $env:CLAUDE_CONFIG_DIR
  try {
    # The default profile runs with the variable unset: pointing it at
    # ~\.claude explicitly makes Claude Code look for its login elsewhere.
    if ($Name -eq 'default') { Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction Ignore }
    else { $env:CLAUDE_CONFIG_DIR = Get-ProfileDir $Name }
    Set-LastProfileName $Name
    & $exe @ClaudeArgs
    $script:ClaudeExitCode = $LASTEXITCODE
  } finally {
    if ($null -eq $old) { Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction Ignore } else { $env:CLAUDE_CONFIG_DIR = $old }
  }
}

# Only an interactive session can run out mid-conversation and be carried on.
function Test-HandoffWanted([string[]]$ClaudeArgs) {
  if ($env:CSWITCH_HANDOFF -eq '0' -or -not (Test-Interactive)) { return $false }
  if ($ClaudeArgs.Count -gt 0 -and $ClaudeArgs[0] -in
    'update', 'install', 'doctor', 'mcp', 'config', 'plugin', 'auth', 'setup-token', 'migrate-installer') { return $false }
  foreach ($a in $ClaudeArgs) { if ($a -in '-p', '--print', '-v', '--version', '-h', '--help') { return $false } }
  $true
}

# If the login just used has hit a limit, offer to carry the conversation on
# with the login that has the most room and shares conversation history.
function Invoke-Handoff([string]$Name) {
  $r = @(Get-UsageReadings @($Name) (Get-UsageTtl) 5)[0].Reading
  if ($r.Status -ne 'ok' -or -not (Test-OverLimit $r)) { return }
  if ($null -ne $r.SessionPct -and $r.SessionPct -ge 100) { $kind = '5-hour'; $at = $r.SessionAt } else { $kind = 'weekly'; $at = $r.WeeklyAt }
  $c = Get-Palette
  $all = @(Get-UsageReadings (Get-ProfileNames) (Get-UsageTtl) 3)
  $best = Find-BestProfile $all $Name $Name
  $head = "`n  $($c.Bold)$Name$($c.Reset) hit its $kind limit (resets in $(Format-Until $at))."
  if (-not $best) {
    Write-Term "$head No other login with shared history has room.`n"
    return
  }
  $w = if ($null -eq $best.Reading.WeeklyPct) { 0 } else { $best.Reading.WeeklyPct }
  Write-Term ("$head`n  Continue this conversation on $($c.Accent)$($c.Bold)$($best.Name)$($c.Reset) " +
    "($($best.Reading.SessionPct)% session, $w% weekly)? [Y/n] ")
  $reply = & $script:Term.ReadLine
  if ($null -ne $reply -and $reply.Trim() -in '', 'y', 'yes') { Start-ClaudeAs $best.Name @('--continue') }
}
