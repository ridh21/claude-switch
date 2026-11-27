# ClaudeSwitch - keep several Claude Code logins on one Windows machine.
# The PowerShell counterpart of bin/cswitch. Both read and write the same
# files under ~/.claude-profiles (see docs/CONTRACT.md), so a profile made by
# either one works with the other.

# Version 1 only: the usage service and settings files may leave out fields,
# and reading a missing field must give $null rather than stop the command.
Set-StrictMode -Version 1.0

foreach ($folder in 'Private', 'Public') {
  Get-ChildItem -Path (Join-Path $PSScriptRoot $folder) -Filter '*.ps1' -ErrorAction Ignore |
    Sort-Object Name | ForEach-Object { . $_.FullName }
}

# Tab completion. cswitch takes its arguments as they are (so -p, -c and the
# rest reach claude), which leaves the native-style completer as the way in.
$script:CsCommands = @('add', 'list', 'usage', 'best', 'run', 'pick', 'env', 'remove', 'setup', 'pin', 'unpin', 'vscode', 'doctor', 'help')
Register-ArgumentCompleter -Native -CommandName cswitch -ScriptBlock {
  param($wordToComplete, $commandAst, $cursorPosition)
  $words = @($commandAst.CommandElements | Select-Object -Skip 1 | ForEach-Object { $_.Extent.Text })
  if ($wordToComplete) { $words = @($words | Select-Object -SkipLast 1) }
  $choices = if ($words.Count -eq 0) { @($script:CsCommands) + @(Get-ProfileNames) }
  elseif ($words.Count -eq 1 -and $words[0] -in 'run', 'env', 'remove', 'rm', 'pin', 'vscode') { Get-ProfileNames }
  elseif ($words.Count -eq 1 -and $words[0] -eq 'usage') { '--json' }
  elseif ($words.Count -eq 1 -and $words[0] -eq 'setup') { '--vscode', '--terminal', '--undo' }
  elseif ($words.Count -eq 1 -and $words[0] -eq 'doctor') { '--fix' }
  else { @() }
  $choices | Where-Object { $_ -like "$wordToComplete*" } |
    ForEach-Object { [Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}
Register-ArgumentCompleter -CommandName Get-ClaudeUsage, Get-ClaudeProfile, Remove-ClaudeProfile, Set-ClaudeWorkspace, Set-ClaudeExtensionProfile -ParameterName Name -ScriptBlock {
  param($commandName, $parameterName, $wordToComplete)
  Get-ProfileNames | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object { [Management.Automation.CompletionResult]::new($_) }
}
Register-ArgumentCompleter -CommandName Set-ClaudeWorkspace, Set-ClaudeExtensionProfile -ParameterName Profile -ScriptBlock {
  param($commandName, $parameterName, $wordToComplete)
  Get-ProfileNames | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object { [Management.Automation.CompletionResult]::new($_) }
}

Export-ModuleMember -Function (Import-PowerShellDataFile (Join-Path $PSScriptRoot 'ClaudeSwitch.psd1')).FunctionsToExport
