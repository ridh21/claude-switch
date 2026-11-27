function New-Check([string]$Status, [string]$Check, [string]$Detail) {
  [pscustomobject]@{ PSTypeName = 'ClaudeSwitch.Check'; Status = $Status; Check = $Check; Detail = $Detail }
}

function Test-DeveloperMode {
  $v = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Name AllowDevelopmentWithoutDevLicense -ErrorAction Ignore
  $v -and $v.AllowDevelopmentWithoutDevLicense -eq 1
}

function Test-ClaudeSwitch {
  <#
  .SYNOPSIS
  Check Claude Code, every profile's shared links and logins (cswitch doctor).
  .DESCRIPTION
  Each check comes back as an object with Status ok, info, warn or fail.
  -Fix puts lost links back: a shared file that has become a copy passes any
  newer contents on to ~\.claude first, and a copied folder is kept as a
  backup after its new files are added to ~\.claude.
  #>
  [CmdletBinding()]
  param([switch]$Fix)

  $claude = Get-Command claude -CommandType Application -ErrorAction Ignore | Select-Object -First 1
  if ($claude) { New-Check ok 'claude' $claude.Source }
  else { New-Check fail 'claude' "not on your PATH; install Claude Code from https://claude.com/claude-code" }

  $policy = Get-ExecutionPolicy
  if ($policy -in 'Restricted', 'AllSigned') {
    New-Check warn 'execution policy' "$policy stops the module from loading; run: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned"
  } else { New-Check ok 'execution policy' "$policy" }

  if ($env:CSWITCH_FILE_LINKS -eq 'hardlink') { New-Check info 'file links' 'hard links (CSWITCH_FILE_LINKS=hardlink)' }
  elseif (Test-DeveloperMode) { New-Check ok 'file links' 'symbolic links (Developer Mode is on)' }
  else { New-Check info 'file links' 'hard links, repaired at launch if an editor breaks them; Developer Mode allows symbolic links' }

  $profileFile = $PROFILE.CurrentUserAllHosts
  if ($profileFile -and (Test-Path -LiteralPath $profileFile) -and ([IO.File]::ReadAllText($profileFile) -match [regex]::Escape($script:BlockStart))) {
    New-Check ok 'claude menu' "set up in $profileFile"
  } else { New-Check info 'claude menu' "plain 'claude' does not ask yet; run: cswitch setup" }

  foreach ($n in Get-ProfileNames) {
    $cred = Get-UsageCredential $n
    $email = Hide-Email (Get-ProfileEmail $n)
    if ($cred -is [string]) { New-Check ok "${n}: login" $(if ($email) { "logged in as $email" } else { 'logged in' }) }
    elseif ($cred.Status -eq 'expired') { New-Check warn "${n}: login" "expired; run cswitch $n once to refresh it" }
    else { New-Check warn "${n}: login" "not logged in; run cswitch $n" }

    if ($n -eq 'default') { continue }
    if (Test-IsolatedProfile $n) { New-Check ok "${n}: links" 'isolated, shares nothing'; continue }
    $states = @(Get-SharedItemStates $n)
    $linked = @($states | Where-Object State -in 'junction', 'symlink', 'hardlink')
    $broken = @($states | Where-Object State -in 'copy', 'missing')
    if ($linked.Count -eq 0 -and $states.Count -gt 0 -and -not $Fix) {
      New-Check warn "${n}: links" "shares nothing with ~\.claude. If it should, run: cswitch doctor --fix. If not, create an empty .cswitch-isolated file in it."
      continue
    }
    if ($broken.Count -eq 0) { New-Check ok "${n}: links" (($linked | ForEach-Object { "$($_.Item) ($($_.State))" }) -join ', '); continue }
    if ($Fix) {
      $done = foreach ($b in $broken) {
        try { Repair-SharedItem $b } catch { New-Check fail "${n}: links" "$($b.Item): $($_.Exception.Message)" }
      }
      New-Check ok "${n}: links" ('fixed: ' + (($done | Where-Object { $_ -is [string] }) -join '; '))
      $done | Where-Object { $_ -isnot [string] }
    } else {
      $what = ($broken | ForEach-Object { if ($_.State -eq 'copy') { "$($_.Item) is a copy, not a link" } else { "$($_.Item) is missing" } }) -join '; '
      New-Check fail "${n}: links" "$what. Run: cswitch doctor --fix"
    }
  }
}

# On every launch: put back file links an editor or Claude Code broke by
# saving over them. Folders are left to 'cswitch doctor --fix'.
function Repair-SharedLinks([string]$Name) {
  if ($Name -eq 'default' -or (Test-IsolatedProfile $Name)) { return }
  $states = @(Get-SharedItemStates $Name)
  if (-not ($states | Where-Object State -in 'junction', 'symlink', 'hardlink')) { return }
  foreach ($s in $states | Where-Object { -not $_.Folder -and $_.State -eq 'copy' }) {
    try { Write-Verbose (Repair-SharedItem $s) } catch { Write-Warning "cswitch: could not relink $($s.Item): $($_.Exception.Message)" }
  }
}
