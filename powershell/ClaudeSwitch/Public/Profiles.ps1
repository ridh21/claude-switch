function New-ClaudeProfile {
  <#
  .SYNOPSIS
  Create a profile: a Claude Code config folder for one more login.
  .DESCRIPTION
  The profile shares settings, CLAUDE.md, keybindings, skills, commands,
  agents, plugins and conversation history with ~\.claude, so every login
  behaves the same. Use -Isolated for a profile that shares nothing.
  .EXAMPLE
  New-ClaudeProfile work; cswitch work   # then log in once
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, Position = 0)][string]$Name,
    [switch]$Isolated
  )
  if (-not (Test-ProfileName $Name)) {
    Stop-Cs "'$Name' can't be a profile name: use letters, digits, '.', '_' and '-' (not CON, NUL, COM1 and other Windows device names)"
  }
  if ($script:ReservedNames -contains $Name) { Stop-Cs "'$Name' is a reserved name" }
  $dir = Get-ProfileDir $Name
  if (Test-Path -LiteralPath $dir) { Stop-Cs "profile '$Name' already exists" }
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  if ($Isolated) {
    # Tells cswitch doctor and bin/cswitch that sharing nothing is intended.
    Write-CsFile (Join-Path $dir '.cswitch-isolated') ''
  } else {
    try {
      foreach ($item in $script:SharedItems) {
        $target = Join-Path (Get-CsBase) $item
        if (Test-Path -LiteralPath $target) {
          $kind = New-SharedLink $target (Join-Path $dir $item)
          Write-Verbose "shared $item ($kind)"
        }
      }
    } catch {
      # Undo the half-made profile so a retry works; ~\.claude is never touched.
      Remove-ProfileDir $dir
      throw
    }
  }
  Sync-ShellIntegrations
  Write-Host "Created profile '$Name'. Run 'cswitch $Name' and log in once with that account."
  Get-ClaudeProfile -Name $Name
}

function Get-ClaudeProfile {
  <#
  .SYNOPSIS
  List profiles and the account each one is logged in as.
  #>
  [CmdletBinding()]
  param([Parameter(Position = 0)][string[]]$Name)
  $active = Get-ActiveProfileName
  $last = Get-LastProfileName
  foreach ($n in Get-ProfileNames) {
    if ($Name -and $Name -notcontains $n) { continue }
    $dir = Get-ProfileDir $n
    [pscustomobject]@{
      PSTypeName = 'ClaudeSwitch.Profile'
      Name       = $n
      Account    = Hide-Email (Get-ProfileEmail $n)
      Active     = ($n -eq $active)
      LastUsed   = ($n -eq $last)
      Isolated   = Test-IsolatedProfile $n
      Path       = $dir
    }
  }
}

function Remove-ClaudeProfile {
  <#
  .SYNOPSIS
  Delete a profile. Shared settings and conversation history stay in ~\.claude.
  .DESCRIPTION
  Run /logout inside the profile first if you also want its saved login gone.
  #>
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
  param([Parameter(Mandatory, Position = 0)][string]$Name, [switch]$Force)
  if ($Name -eq 'default') { Stop-Cs 'the default profile is your ~\.claude setup and cannot be removed' }
  Assert-ProfileExists $Name
  if ($Force) { $ConfirmPreference = 'None' }
  if (-not $PSCmdlet.ShouldProcess($Name, 'Delete profile (shared settings and history are kept)')) { return }
  $dir = Get-ProfileDir $Name
  Remove-ProfileDir $dir
  Remove-Item -LiteralPath (Join-Path (Get-CsHome) ".cache\usage-$Name") -ErrorAction Ignore
  Sync-ShellIntegrations
  Write-Host "Removed profile '$Name'."
}
