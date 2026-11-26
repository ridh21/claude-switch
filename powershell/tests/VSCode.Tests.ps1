BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
  Import-Module (Join-Path $PSScriptRoot '..\ClaudeSwitch\ClaudeSwitch.psd1') -Force

  # A settings.json the way people really have them: comments, trailing commas.
  $script:Commented = @'
{
    // Editor
    "editor.fontSize": 14, // big enough
    /* Terminal */
    "terminal.integrated.env.windows": {
        "FOO": "bar", // keep me
    },
    "files.exclude": { "**/.git": true },
}
'@ -replace "`r`n", "`n"

  function Read-Settings($Path) { (Get-Content $Path -Raw) }
  function Read-SettingsJson($Path) {
    # Strip what JSON does not allow, then parse, to check the result is valid JSONC.
    $text = Get-Content $Path -Raw
    $text = [regex]::Replace($text, '"(?:[^"\\]|\\.)*"|//[^\n]*|/\*[\s\S]*?\*/', { param($m) if ($m.Value[0] -eq '"') { $m.Value } else { '' } })
    $text = [regex]::Replace($text, ',(\s*[}\]])', '$1')
    $text | ConvertFrom-Json
  }
}

Describe 'Set-ClaudeWorkspace (cswitch pin)' {
  BeforeEach {
    $t = New-TestEnvironment
    New-ClaudeProfile work | Out-Null
    New-ClaudeProfile client | Out-Null
    $ws = Join-Path $t.Root 'api'
    New-Item -ItemType Directory $ws | Out-Null
    $settings = Join-Path $ws '.vscode\settings.json'
  }
  AfterEach { Remove-TestEnvironment $t }

  It 'makes new VS Code terminals in the folder use the login, on every OS' {
    Set-ClaudeWorkspace -Profile work -Path $ws

    $s = Read-SettingsJson $settings
    $s.'terminal.integrated.env.windows'.CSWITCH_PROFILE | Should -Be 'work'
    $s.'terminal.integrated.env.osx'.CSWITCH_PROFILE | Should -Be 'work'
    $s.'terminal.integrated.env.linux'.CSWITCH_PROFILE | Should -Be 'work'
  }

  It 'keeps comments, trailing commas and other settings' {
    New-Item -ItemType Directory (Split-Path $settings) | Out-Null
    [IO.File]::WriteAllText($settings, $script:Commented)

    Set-ClaudeWorkspace -Profile work -Path $ws

    $text = Read-Settings $settings
    $text | Should -Match '// Editor'
    $text | Should -Match '"editor.fontSize": 14, // big enough'
    $text | Should -Match '/\* Terminal \*/'
    $s = Read-SettingsJson $settings
    $s.'terminal.integrated.env.windows'.FOO | Should -Be 'bar'
    $s.'terminal.integrated.env.windows'.CSWITCH_PROFILE | Should -Be 'work'
    $s.'files.exclude'.'**/.git' | Should -BeTrue
  }

  It 'moves the pin to another login' {
    Set-ClaudeWorkspace -Profile work -Path $ws
    Set-ClaudeWorkspace -Profile client -Path $ws
    (Read-SettingsJson $settings).'terminal.integrated.env.linux'.CSWITCH_PROFILE | Should -Be 'client'
  }

  It 'refuses an unknown profile and leaves the file alone' {
    { Set-ClaudeWorkspace -Profile nope -Path $ws } | Should -Throw '*no such profile*'
    $settings | Should -Not -Exist
  }

  It 'never overwrites a settings file it cannot read, and says what to add instead' {
    New-Item -ItemType Directory (Split-Path $settings) | Out-Null
    [IO.File]::WriteAllText($settings, '{ "a": 1 "b": 2 }')

    { Set-ClaudeWorkspace -Profile work -Path $ws } | Should -Throw '*"CSWITCH_PROFILE": "work"*'
    Read-Settings $settings | Should -Be '{ "a": 1 "b": 2 }'
  }

  It 'is reversed by Clear-ClaudeWorkspace, keeping everything else' {
    New-Item -ItemType Directory (Split-Path $settings) | Out-Null
    [IO.File]::WriteAllText($settings, $script:Commented)
    Set-ClaudeWorkspace -Profile work -Path $ws

    Clear-ClaudeWorkspace -Path $ws

    $text = Read-Settings $settings
    $text | Should -Match '// keep me'
    $s = Read-SettingsJson $settings
    $s.'terminal.integrated.env.windows'.FOO | Should -Be 'bar'
    $s.'terminal.integrated.env.windows'.PSObject.Properties.Name | Should -Not -Contain 'CSWITCH_PROFILE'
    $s.PSObject.Properties.Name | Should -Not -Contain 'terminal.integrated.env.osx'
    $s.PSObject.Properties.Name | Should -Not -Contain 'terminal.integrated.env.linux'
  }

  It 'leaves a file it created as an empty object after unpin' {
    Set-ClaudeWorkspace -Profile work -Path $ws
    Clear-ClaudeWorkspace -Path $ws
    @((Read-SettingsJson $settings).PSObject.Properties).Count | Should -Be 0
  }

  It 'is what cswitch pin and unpin do, defaulting to the current folder' {
    Push-Location $ws
    try {
      cswitch pin client 6>$null
      (Read-SettingsJson $settings).'terminal.integrated.env.windows'.CSWITCH_PROFILE | Should -Be 'client'
      cswitch unpin 6>$null
      (Read-SettingsJson $settings).PSObject.Properties.Name | Should -Not -Contain 'terminal.integrated.env.windows'
    } finally { Pop-Location }
  }
}

Describe 'Set-ClaudeExtensionProfile (cswitch vscode)' {
  BeforeEach {
    $t = New-TestEnvironment
    New-ClaudeProfile work | Out-Null
    $user = Join-Path $t.Root 'Code\User\settings.json'
  }
  AfterEach { Remove-TestEnvironment $t }

  It "points the Claude Code extension's sessions at the login" {
    Set-ClaudeExtensionProfile -Profile work -SettingsPath $user

    $vars = @((Read-SettingsJson $user).'claudeCode.environmentVariables')
    $vars.Count | Should -Be 1
    $vars[0].name | Should -Be 'CLAUDE_CONFIG_DIR'
    $vars[0].value | Should -Be (Join-Path $t.Profiles 'work')
  }

  It "keeps the extension's other environment variables, and default removes only ours" {
    New-Item -ItemType Directory (Split-Path $user) -Force | Out-Null
    [IO.File]::WriteAllText($user, "{`n    // mine`n    `"claudeCode.environmentVariables`": [ { `"name`": `"HTTPS_PROXY`", `"value`": `"http://proxy:8080`" } ]`n}`n")

    Set-ClaudeExtensionProfile -Profile work -SettingsPath $user
    @((Read-SettingsJson $user).'claudeCode.environmentVariables').name | Should -Be @('HTTPS_PROXY', 'CLAUDE_CONFIG_DIR')

    Set-ClaudeExtensionProfile -Profile default -SettingsPath $user
    @((Read-SettingsJson $user).'claudeCode.environmentVariables').name | Should -Be @('HTTPS_PROXY')
    Read-Settings $user | Should -Match '// mine'
  }
}
