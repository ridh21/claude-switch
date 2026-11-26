BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
  $script:ModulePath = Join-Path $PSScriptRoot '..\ClaudeSwitch\ClaudeSwitch.psd1'
  Import-Module $script:ModulePath -Force
}

Describe 'Install-ClaudeSwitchShell (cswitch setup)' {
  BeforeEach {
    $t = New-TestEnvironment
    $psProfile = Join-Path $t.Root 'Documents\PowerShell\profile.ps1'
    $vscode = Join-Path $t.Root 'Code\User\settings.json'
    $fragment = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\claude-switch\profiles.json'
  }
  AfterEach { Remove-TestEnvironment $t }

  It 'makes plain "claude" in a new PowerShell ask which account to use' {
    Install-ClaudeSwitchShell -ProfilePath $psProfile 6>$null

    $type = powershell -NoProfile -Command ". '$psProfile'; (Get-Command claude).CommandType; (Get-Command claude).Definition.Trim()"
    $type[0] | Should -Be 'Function'
    $type[1] | Should -Be 'Invoke-ClaudeShim @args'
  }

  It 'adds its block once, however often it runs, after what is already there' {
    New-Item -ItemType Directory (Split-Path $psProfile) | Out-Null
    [IO.File]::WriteAllText($psProfile, "Set-Alias ll Get-ChildItem`r`n")

    Install-ClaudeSwitchShell -ProfilePath $psProfile 6>$null
    Install-ClaudeSwitchShell -ProfilePath $psProfile 6>$null

    $text = Get-Content $psProfile -Raw
    $text | Should -BeLike "Set-Alias ll Get-ChildItem`r`n*"
    ([regex]::Matches($text, '# >>> claude-switch >>>')).Count | Should -Be 1
  }

  It 'is undone by Uninstall-ClaudeSwitchShell, leaving the profile byte for byte as it was' {
    New-Item -ItemType Directory (Split-Path $psProfile) | Out-Null
    $before = "Set-Alias ll Get-ChildItem`r`n# my stuff`r`n"
    [IO.File]::WriteAllText($psProfile, $before)
    Install-ClaudeSwitchShell -ProfilePath $psProfile -WindowsTerminal -VSCode -VSCodeSettingsPath $vscode 6>$null

    Uninstall-ClaudeSwitchShell -ProfilePath $psProfile -VSCodeSettingsPath $vscode 6>$null

    [IO.File]::ReadAllText($psProfile) | Should -BeExactly $before
    $fragment | Should -Not -Exist
    (Get-Content $vscode -Raw) | Should -Not -Match 'Claude \('
  }

  It 'adds a Windows Terminal tab for every login with -WindowsTerminal' {
    New-ClaudeProfile work | Out-Null

    Install-ClaudeSwitchShell -ProfilePath $psProfile -WindowsTerminal 6>$null

    $wt = Get-Content $fragment -Raw | ConvertFrom-Json
    $wt.profiles.name | Should -Be @('Claude (default)', 'Claude (work)')
    $wt.profiles[1].commandline | Should -Match '-NoExit -Command cswitch work$'
    $wt.profiles[1].guid | Should -Match '^\{[0-9a-f-]{36}\}$'
  }

  It 'adds a VS Code terminal profile for every login with -VSCode, keeping other settings' {
    New-ClaudeProfile work | Out-Null
    New-Item -ItemType Directory (Split-Path $vscode) -Force | Out-Null
    [IO.File]::WriteAllText($vscode, "{`n    // mine`n    `"editor.fontSize`": 14`n}`n")

    Install-ClaudeSwitchShell -ProfilePath $psProfile -VSCode -VSCodeSettingsPath $vscode 6>$null

    $text = Get-Content $vscode -Raw
    $text | Should -Match '// mine'
    $text | Should -Match '"Claude \(work\)": \{ "path": "[^"]+", "args": \[ "-NoLogo", "-NoExit", "-Command", "cswitch work" \]'
    $text | Should -Match '"Claude \(default\)"'
  }

  It 'drops the VS Code terminal profile of a removed login when run again' {
    New-ClaudeProfile work | Out-Null
    Install-ClaudeSwitchShell -ProfilePath $psProfile -VSCode -VSCodeSettingsPath $vscode 6>$null
    Remove-ClaudeProfile work -Force 6>$null

    Install-ClaudeSwitchShell -ProfilePath $psProfile -VSCode -VSCodeSettingsPath $vscode 6>$null

    Get-Content $vscode -Raw | Should -Not -Match 'Claude \(work\)'
  }

  It 'completes profile names and commands with Tab' {
    New-ClaudeProfile work | Out-Null
    (TabExpansion2 -inputScript 'cswitch wo' -cursorColumn 10).CompletionMatches.CompletionText | Should -Contain 'work'
    (TabExpansion2 -inputScript 'cswitch us' -cursorColumn 10).CompletionMatches.CompletionText | Should -Contain 'usage'
    (TabExpansion2 -inputScript 'cswitch pin w' -cursorColumn 13).CompletionMatches.CompletionText | Should -Contain 'work'
  }
}
