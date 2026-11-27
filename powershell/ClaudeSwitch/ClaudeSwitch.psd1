@{
  RootModule           = 'ClaudeSwitch.psm1'
  ModuleVersion        = '0.5.0'
  GUID                 = '7d3f4c1e-2b8a-4d6e-9f10-6a5c2e9b8d41'
  Author               = 'ridh21'
  Copyright            = '(c) ridh21. MIT License.'
  Description          = 'Keep several Claude Code logins on one Windows machine. Pick one from a menu when you type claude, see every login''s usage limits as objects, carry a conversation on when a limit hits, and pin a login to a VS Code workspace.'
  PowerShellVersion    = '5.1'
  CompatiblePSEditions = @('Desktop', 'Core')
  FunctionsToExport    = @(
    'New-ClaudeProfile', 'Get-ClaudeProfile', 'Remove-ClaudeProfile',
    'Get-ClaudeUsage', 'Invoke-ClaudeProfile', 'Select-ClaudeProfile', 'Invoke-ClaudeShim',
    'Set-ClaudeWorkspace', 'Clear-ClaudeWorkspace', 'Set-ClaudeExtensionProfile',
    'Install-ClaudeSwitchShell', 'Uninstall-ClaudeSwitchShell', 'Test-ClaudeSwitch', 'cswitch'
  )
  CmdletsToExport      = @()
  VariablesToExport    = @()
  AliasesToExport      = @()
  FormatsToProcess     = @('ClaudeSwitch.Format.ps1xml')
  PrivateData          = @{
    PSData = @{
      Tags         = @('Claude', 'ClaudeCode', 'Anthropic', 'AI', 'Windows', 'VSCode', 'Profiles')
      LicenseUri   = 'https://github.com/ridh21/claude-switch/blob/main/LICENSE'
      ProjectUri   = 'https://github.com/ridh21/claude-switch'
      ReleaseNotes = 'First PowerShell release: profiles, menu, usage, handoff, VS Code workspace pinning, setup and doctor.'
    }
  }
}
