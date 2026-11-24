<h1 align="center">
  <img src="assets/banner.svg" alt="claude-switch" width="412">
</h1>

<p align="center">
  <strong>All your Claude Code logins on one machine. Switch with one keystroke, see who has room left, and keep working when a limit hits.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/license-MIT-D97757" alt="MIT license">
  <img src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux-D97757" alt="macOS and Linux">
  <img src="https://img.shields.io/badge/bash-3.2%2B-D97757" alt="bash 3.2 or later">
</p>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="#quick-start">Quick start</a> ·
  <a href="#features">Features</a> ·
  <a href="#commands">Commands</a> ·
  <a href="#configuration">Configuration</a> ·
  <a href="#troubleshooting">Troubleshooting</a>
</p>

---

Claude Code keeps one login per config directory. If you have a work seat and a personal plan, switching means logging out and back in, and you can't see which account still has room until you're already in a session.

`cswitch` gives each login its own profile, which you log in to once. After that:

```
  ▐▛███▜▌   ▄▀▀▀  ▄▀▀▀▀ █   █ ▀█▀ ▀▀█▀▀ ▄▀▀▀  █   █
 ▝▜█████▛▘  █      ▀▀▀▄ █ █ █  █    █   █     █▀▀▀█
   ▘▘ ▝▝     ▀▀▀  ▀▀▀▀   ▀ ▀  ▀▀▀   ▀    ▀▀▀  ▀   ▀

  Which Claude account?

  ❯ 1  default  ja***e@g***.com  5h  84%  7d  56%  last used
    2  work     ja***h@a***.com  5h  12%  7d  20%  most room
    3  client   not logged in    not logged in

  ↑/↓ move  ·  enter select  ·  1-9 pick  ·  q cancel
```

It's a single bash script. The only dependency is `curl`, used to check usage limits. It runs on the bash 3.2 that ships with macOS, and on Linux. Your existing `~/.claude` setup is never modified.

## Features

- **One profile per login.** Log in once per account, then launch any of them by name.
- **Account menu.** Type `claude` and choose an account. Each row shows that login's 5-hour and weekly usage.
- **Usage at a glance.** `cswitch usage` shows every login's limits side by side and names the one with the most room.
- **`cswitch best`.** Launches the login with the most room, for interactive sessions or one-off prompts.
- **Handoff.** When a login runs out mid-conversation, you can carry on with another login.
- **Status line.** Shows which login you're on and how close it is to its limits, inside Claude Code.
- **Private by default.** Email addresses are always shown masked, so a shared screen or a screenshot doesn't leak them.
- **Shared setup.** Settings, skills, plugins and conversation history are shared across profiles, so every login behaves the same.

## Install

**Homebrew**

```bash
brew tap ridh21/claude-switch https://github.com/ridh21/claude-switch
brew trust ridh21/claude-switch
brew install claude-switch
```

Recent Homebrew versions refuse to load formulae from a third-party tap until you trust it. If your `brew` has no `trust` command, skip that line.

**Without Homebrew**

```bash
curl -fsSL https://raw.githubusercontent.com/ridh21/claude-switch/main/install.sh | bash
```

You also need [Claude Code](https://claude.com/claude-code) itself.

## Quick start

```bash
cswitch add work      # 1. create a profile
cswitch work          # 2. launch it and log in once with that account
cswitch usage         # 3. see every login's limits
```

To get the menu whenever you type `claude`, add this to `~/.zshrc` or `~/.bashrc`:

```bash
eval "$(cswitch init)"
```

`default` is your existing `~/.claude` login, so it works from the start.

## Features in detail

### Account menu

Run `cswitch`, or `claude` once you've set up `cswitch init`, to choose a login:

- Move with the arrow keys or `j`/`k`. Press Enter to launch, or a number to launch that row directly.
- `q`, Esc and Ctrl-C cancel without starting Claude Code.
- The menu starts on the login you used last, so Enter repeats it. If that login has reached a limit and another has room, it starts on the one with room.
- Above the menu is a banner with the Claude Code pet in Claude orange. In narrow windows it shrinks to just the pet, and in short windows it's left out. `CSWITCH_BANNER=0` turns it off.

With `cswitch init`, `claude`, `claude --continue`, `claude mcp list` and so on ask which account to use, then run with your arguments unchanged. The menu is skipped when:

- only the `default` profile exists
- input or output is not a terminal, such as in a script or a pipe
- the command doesn't depend on the account: `--version`, `--help`, `update`, `install`, `doctor`
- `CSWITCH_PROFILE` is set, as in `CSWITCH_PROFILE=work claude`, which uses that profile directly

`command claude` runs Claude Code without the menu. `cswitch pick [claude args...]` shows the menu without the shell function.

### Usage limits

```bash
cswitch usage
```

```
  PROFILE  ACCOUNT                SESSION (5h)    resets    WEEKLY (7d)     resets
* default  ja***e@g***.com          84% ████████░░ 1h 02m     56% ██████░░░░ 2d 15h
  work     ja***h@a***.com          12% █░░░░░░░░░ 3h 40m     20% ██░░░░░░░░ 4d 2h
  client   not logged in: run cswitch client

  Most room: work (12% session, 20% weekly)  ->  cswitch work
```

These are the same numbers `/usage` shows inside Claude Code. All profiles are checked at once. `cswitch usage --json` prints the same data for scripts.

"Most room" means the login furthest from either limit. A login at 0% session but 85% weekly is nearly out, so it ranks below one at 10% and 29%.

### Launch the login with the most room

```bash
cswitch best                 # interactive session
cswitch best -p "summarize"  # or a one-off prompt
```

### Keep going when a login runs out

When you end a session on a login that has reached its 5-hour or weekly limit, `cswitch` offers to continue the same conversation on the login with the most room:

```
  work hit its 5-hour limit (resets in 2h 14m).
  Continue this conversation on default (12% session, 30% weekly)? [Y/n]
```

Press Enter to run `claude --continue` as that login, in the same folder.

- Only logins that share conversation history are offered, so `--isolated` profiles are skipped.
- The new session starts with only `--continue`. Arguments from the first session aren't carried over.
- It applies to interactive sessions only. `-p`, `--help`, and subcommands such as `mcp` and `update` run as usual.
- `CSWITCH_HANDOFF=0` turns it off.

This is for people with more than one account of their own. See [Intended use](#intended-use).

### Status line

Claude Code can show a line under the prompt, produced by a command you choose. `cswitch statusline` shows your login and its limits:

```
work · 5h 42% 1h 10m · 7d 18%
```

From 80% of a limit, it also names the login to switch to: `work · 5h 86% … · next: default 12%`.

Add it to `~/.claude/settings.json`. Profiles share that file, so this covers all of them:

```json
{
  "statusLine": { "type": "command", "command": "cswitch statusline" }
}
```

Already have a status line script? `cswitch statusline --account` prints just the login name and the hint. Pass it the same input Claude Code gave your script:

```bash
input=$(cat)
account=$(printf '%s' "$input" | cswitch statusline --account 2>/dev/null)
```

The status line never uses the network. It reads the limits Claude Code passes to it and saves them, which keeps the menu and the end-of-session check up to date at no cost.

### Updates

Once a day, `cswitch` checks in the background whether a new version is out. If one is, the menu and `cswitch usage` show a line under their output:

```
  cswitch 0.5.0 is out (you have 0.4.2)  ·  brew upgrade claude-switch
```

For a Homebrew install, the line suggests `brew upgrade claude-switch`. Otherwise it suggests `cswitch update`, which does the upgrade for you. `cswitch update --check` checks right away without installing anything.

The check never slows anything down. The menu shows what the last check found, and a new check runs in the background with a short timeout. Scripts, pipes, `-p` and the status line never check. `CSWITCH_UPDATE_CHECK=0` turns it off.

## Commands

| Command | What it does |
|---|---|
| `cswitch` | Choose a login from the menu and launch it |
| `cswitch <name> [claude args...]` | Launch Claude Code as a profile (`run <name>` does the same) |
| `cswitch pick [claude args...]` | Show the menu, passing the arguments on to `claude` |
| `cswitch best [claude args...]` | Launch the login with the most room left |
| `cswitch add <name> [--isolated]` | Create a profile |
| `cswitch list` | List profiles and the account each one is logged in as |
| `cswitch usage [--json]` | Show every login's session and weekly limits |
| `cswitch statusline [--account]` | Print the status line for Claude Code |
| `cswitch env <name>` | Print the `export` line that points a shell at a profile |
| `cswitch init` | Print the shell function that makes `claude` show the menu |
| `cswitch remove <name> [-y]` | Delete a profile |
| `cswitch update [--check]` | Upgrade cswitch, or only check for a new version |
| `cswitch --version`, `--help` | Version and help |

Any arguments after a profile name go to `claude` unchanged, as in `cswitch work --continue`.

To point another tool or a whole shell at a profile:

```bash
eval "$(cswitch env work)"
```

## Configuration

| Variable | Default | Effect |
|---|---|---|
| `CSWITCH_HOME` | `~/.claude-profiles` | Where profiles live |
| `CSWITCH_BASE` | `~/.claude` | The `default` profile, and the source of shared files |
| `CSWITCH_PROFILE` | unset | With `cswitch init`, always use this profile and skip the menu |
| `CSWITCH_HANDOFF` | `1` | `0` turns off the offer to continue on another login |
| `CSWITCH_BANNER` | `1` | `0` hides the banner above the menu |
| `CSWITCH_USAGE_TTL` | `120` | Seconds a saved usage reading counts as fresh |
| `CSWITCH_UPDATE_CHECK` | `1` | `0` turns off the daily check for a new version |
| `CSWITCH_SHOW_EMAIL` | `0` | `1` shows email addresses in full instead of masked |
| `NO_COLOR` | unset | Set it to any value to turn off colour |

## How it works

Claude Code reads its config directory from `CLAUDE_CONFIG_DIR`. Each profile is its own directory under `~/.claude-profiles/`, so each one keeps its own login. `cswitch <name>` sets the variable and starts `claude`.

A new profile symlinks these from `~/.claude`, when they exist, so it behaves like your main setup:

| Shared | What it holds |
|---|---|
| `settings.json`, `keybindings.json` | Settings, permissions, hooks |
| `CLAUDE.md` | Your global instructions |
| `skills`, `commands`, `agents`, `plugins` | Extensions |
| `projects` | Conversation history and per-project memory |

Because `projects` is shared, `cswitch work --continue` picks up the last conversation in the current folder, even if it was started under another profile. That's also what makes the handoff work.

Use `cswitch add <name> --isolated` for a profile that shares nothing.

Not shared: the login, and anything stored in `.claude.json`, which includes MCP servers added at user scope. Add those again inside the profile.

Usage readings are saved in `~/.claude-profiles/.cache/` for two minutes, so the menu and `best` rarely have to wait for the network. `cswitch usage` always fetches fresh readings.

## Privacy and security

- Email addresses are shown masked everywhere: in the menu, `list`, `usage` and `usage --json`. `jane.doe@gmail.com` appears as `ja***e@g***.com`. Set `CSWITCH_SHOW_EMAIL=1` to see them in full.
- To check limits, `cswitch` reads each profile's Claude Code login token from the macOS Keychain, or from `.credentials.json` on Linux. It sends the token only to `api.anthropic.com`.
- The token is never printed or stored, and it's passed to `curl` on stdin, so it never appears in the process list.
- `cswitch` never refreshes or changes a login. If a token has expired, launch that profile once and Claude Code refreshes it.
- The daily update check downloads one public file, this repo's Homebrew formula, from `raw.githubusercontent.com`. It sends no account data.
- The usage service is the one Claude Code itself uses. It isn't a documented public API, so it may change.

## Troubleshooting

**"login expired"** — Run `cswitch <name>` once. Claude Code refreshes the login when it starts.

**"asked too often; try again in a minute"** — The usage service is rate-limiting you. The menu, `best` and the status line use saved readings, so this mostly comes from running `cswitch usage` many times in a row.

**An MCP server is missing in a profile** — Servers added at user scope live in `.claude.json`, which isn't shared. Add them again inside that profile.

**The menu doesn't appear** — It only shows in an interactive terminal, and only when you have more than one profile. Scripts and pipes go straight to Claude Code.

**Remove a profile completely** — Run `/logout` inside the profile first to delete its saved login, then `cswitch remove <name>`. Removing a profile deletes only its own directory. Shared files stay in `~/.claude`.

## Development

The tests run against a throwaway home directory, with fake `claude`, `curl` and `security` commands, so they never touch a real login or the network. They need `expect`, which ships with macOS (`apt install expect` on Debian and Ubuntu):

```bash
tests/run.sh
```

To release a version:

1. Bump `CSWITCH_VERSION` in `bin/cswitch`, commit, and push `main`.
2. Tag that commit (`git tag v0.5.0 && git push origin v0.5.0`).
3. Point `Formula/claude-switch.rb` at the new tag's tarball and its `sha256`, then push `main` again.

Step 3 is what users see: the update check reads the version from the formula on `main`.

## Intended use

This is for people who hold separate accounts for separate purposes, such as a work seat and a personal plan. Check Anthropic's terms before using additional accounts to get past a usage limit.

cswitch is not made by or affiliated with Anthropic. Claude and Claude Code are trademarks of Anthropic.

## License

MIT
