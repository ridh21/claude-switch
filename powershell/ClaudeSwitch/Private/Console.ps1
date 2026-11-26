# The console, behind one small seam so the menu and the handoff prompt can be
# driven by tests: everything that reads keys or asks a question goes through
# $script:Term. Nothing else in the module touches [Console] directly.

$script:Term = @{
  # Someone is there to answer: input and output are both a console.
  IsInteractive = {
    try { -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected -and [Environment]::UserInteractive }
    catch { $false }
  }
  # One keypress as: up, down, enter, cancel, or the character typed.
  ReadKey       = {
    $k = [Console]::ReadKey($true)
    switch ($k.Key) {
      'UpArrow' { 'up' } 'DownArrow' { 'down' } 'Enter' { 'enter' } 'Escape' { 'cancel' }
      default { if ($k.Modifiers -band [ConsoleModifiers]::Control -and $k.Key -eq 'C') { 'cancel' } else { [string]$k.KeyChar } }
    }
  }
  ReadLine      = { [Console]::ReadLine() }
  # The Windows PowerShell 5.1 console starts on an OEM code page, which turns
  # the banner and arrows into '?'. UTF-8 while the menu is up, then put back.
  Begin         = {
    $script:SavedEncoding = $null
    try {
      if ([Console]::OutputEncoding.CodePage -ne 65001) {
        $script:SavedEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
      }
    } catch { }
  }
  End           = {
    if ($script:SavedEncoding) { try { [Console]::OutputEncoding = $script:SavedEncoding } catch { } }
  }
  Write         = { param([string]$Text) [Console]::Write($Text) }
  Size          = { try { @([Console]::WindowHeight, [Console]::WindowWidth) } catch { @(0, 0) } }
}

function Write-Term([string]$Text) { & $script:Term.Write $Text }

function Test-Interactive { [bool](& $script:Term.IsInteractive) }

# Colours as VT sequences; empty when NO_COLOR is set or the console can't show them.
function Get-Palette {
  $on = -not $env:NO_COLOR
  if ($on) { try { $on = [bool]$Host.UI.SupportsVirtualTerminal -or [bool]$env:WT_SESSION -or $env:TERM_PROGRAM -eq 'vscode' } catch { $on = $false } }
  $e = [char]27
  if (-not $on) { return @{ Reset = ''; Bold = ''; Dim = ''; Red = ''; Yellow = ''; Green = ''; Accent = '' } }
  $accent = if ($env:COLORTERM -in 'truecolor', '24bit' -or $env:WT_SESSION -or $env:TERM_PROGRAM -eq 'vscode') { "$e[38;2;217;119;87m" } else { "$e[38;5;173m" }
  @{ Reset = "$e[0m"; Bold = "$e[1m"; Dim = "$e[2m"; Red = "$e[31m"; Yellow = "$e[33m"; Green = "$e[32m"; Accent = $accent }
}
