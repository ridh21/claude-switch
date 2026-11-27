# The on-disk contract (v1)

claude-switch has two front ends: `bin/cswitch` (bash, for macOS, Linux and
Git Bash) and the `ClaudeSwitch` PowerShell module (Windows). Neither calls
the other. They work together only through the files below, so a profile made
by one works with the other, and the status line that `bin/cswitch` runs inside
Claude Code keeps the PowerShell menu's limits fresh.

Change anything here only with a new contract version, and update both front
ends and both test suites (`tests/run.sh`, `powershell/tests`) together.

## Locations

| What | Where | Override |
|---|---|---|
| Profiles | `~/.claude-profiles` (`%USERPROFILE%\.claude-profiles`) | `CSWITCH_HOME` |
| The `default` profile and the source of shared files | `~/.claude` | `CSWITCH_BASE` |
| `default`'s account file | `.claude.json` next to `CSWITCH_BASE` (that is, in the home folder) | |

## Profiles

- A profile is a folder `CSWITCH_HOME/<name>/`, used as Claude Code's
  `CLAUDE_CONFIG_DIR`. `default` has no folder there: it runs with
  `CLAUDE_CONFIG_DIR` unset.
- Names match `^[A-Za-z0-9_][A-Za-z0-9._-]*$`, do not end with `.`, and are not
  Windows device names (`CON`, `PRN`, `AUX`, `NUL`, `COM0`-`COM9`,
  `LPT0`-`LPT9`, in any case, with or without an extension). Folders whose names
  start with `.` are not profiles.
- Reserved names: `default add list ls usage best run env remove rm pick init
  statusline update _claude help version setup doctor pin unpin vscode`.

## Shared items

A profile that is not isolated links these from `CSWITCH_BASE`, when they exist
there: `settings.json CLAUDE.md keybindings.json skills commands agents plugins
projects`.

| OS | Folders | Files |
|---|---|---|
| macOS, Linux | symbolic link | symbolic link |
| Windows | directory junction | symbolic link (needs Developer Mode), else hard link |

A shared item is never copied. A copy silently drifts apart and breaks the
handoff, which needs both logins' `projects` to resolve to the same folder.

An isolated profile (`add --isolated`) shares nothing and contains an empty
file `.cswitch-isolated`.

## `.last`

`CSWITCH_HOME/.last`: the name of the profile launched last, on the first line.

## Usage cache

`CSWITCH_HOME/.cache/usage-<name>`: one line, UTF-8 without a BOM, LF ending,
written atomically (write a temporary file, then rename it):

```
<written at, Unix seconds>|<status>|<session %>|<session resets, Unix seconds>|<weekly %>|<weekly resets, Unix seconds>
```

- `status` is `ok`, `logged-out`, `expired`, `rate-limited` or `error`.
- Percentages are whole numbers. Any field after `status` may be empty.
- A reading counts as fresh for `CSWITCH_USAGE_TTL` seconds (default 120).

## Credentials

Read only, never written, printed or stored:

- macOS: the Keychain item `Claude Code-credentials`, plus
  `-<first 8 hex of sha256(CLAUDE_CONFIG_DIR)>` for profiles other than `default`.
- Linux and Windows: `<config dir>/.credentials.json`.

The `claudeAiOauth.accessToken` is sent only to
`https://api.anthropic.com/api/oauth/usage` (`CSWITCH_USAGE_URL`), with the
header `anthropic-beta: oauth-2025-04-20`.

## `usage --json`

An array, one object per profile, `default` first:

```json
[{"name":"work","email":"ja***e@a***.co","status":"ok","active":false,"last_used":true,
  "session":{"percent":12,"resets_at":"2026-11-26T14:00:00Z"},
  "weekly":{"percent":20,"resets_at":"2026-11-29T09:00:00Z"}}]
```

`email` is masked unless `CSWITCH_SHOW_EMAIL=1`. Missing values are `null`.
Reset times are UTC, to the second.

## VS Code pin

`cswitch pin <name>` writes `"CSWITCH_PROFILE": "<name>"` into the
`terminal.integrated.env.windows`, `.osx` and `.linux` settings of the
workspace's `.vscode/settings.json`. Both front ends launch that profile
without the menu when `CSWITCH_PROFILE` is set.
