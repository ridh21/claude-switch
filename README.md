<h1 align="center">
  <img src="assets/banner.svg" alt="claude-switch" width="412">
</h1>

`cswitch` keeps several Claude Code logins on one machine. Each one is a profile that you log in to once, then launch by name.

It is a single bash script with no dependencies beyond `curl` (used only by `cswitch usage`). It works with the bash 3.2 that ships with macOS, and on Linux.

## Install

Homebrew:

```bash
brew tap ridh21/claude-switch https://github.com/ridh21/claude-switch
brew trust ridh21/claude-switch
brew install claude-switch
```

Recent Homebrew versions refuse to load formulae from a third-party tap until you trust it. If your `brew` has no `trust` command, skip that line.

Without Homebrew:

```bash
curl -fsSL https://raw.githubusercontent.com/ridh21/claude-switch/main/install.sh | bash
```

You also need [Claude Code](https://claude.com/claude-code) itself.

## Usage

```bash
cswitch add work          # create a profile
cswitch work              # launch Claude Code; log in once with that account
cswitch list              # show profiles and the account each is logged in as
cswitch usage             # session and weekly limits for every account

cswitch work --continue   # any claude arguments are passed through
cswitch default           # your original login
cswitch remove work
```

`default` is your existing `~/.claude` setup. `cswitch` never modifies it.

## See which account has room left

```bash
cswitch usage
```

```
  PROFILE  ACCOUNT                SESSION (5h)    resets    WEEKLY (7d)     resets
* default  me@example.com           84% ████████░░ 1h 02m     56% ██████░░░░ 2d 15h
  work     me@company.com           12% █░░░░░░░░░ 3h 40m     20% ██░░░░░░░░ 4d 2h
  client   not logged in: run cswitch client

  Most room: work (12% session, 20% weekly)  ->  cswitch work
```

It shows each login's 5-hour session limit and 7-day weekly limit, the same numbers as `/usage` inside Claude Code, and suggests the one with the most room. All profiles are checked at once. `cswitch usage --json` prints the same data for scripts.

To do this, `cswitch` reads each profile's Claude Code login token (from the macOS Keychain, or `.credentials.json` on Linux) and sends it to `api.anthropic.com` only. The token is never printed, stored or put on a command line. It never refreshes or changes a login: if a token has expired, launch that profile once and Claude Code refreshes it.

The usage endpoint is the one Claude Code itself uses and is not a documented public API, so it may change.

"Most room" is the login furthest from either limit, so one at 0% session but 85% weekly ranks below one at 10% and 29%.

To launch that login directly:

```bash
cswitch best                 # interactive session on the login with the most room
cswitch best -p "summarize"  # or a one-off prompt
```

Readings are remembered for two minutes (`CSWITCH_USAGE_TTL`, in seconds) in `~/.claude-profiles/.cache/`, so the menu and `best` rarely wait on the network. `cswitch usage` always asks afresh.

## Carry on when a login runs out

When a session ends and that login has reached its 5-hour or weekly limit, `cswitch` offers to continue the same conversation with the login that has the most room:

```
  work hit its 5-hour limit (resets in 2h 14m).
  Continue this conversation on default (12% session, 30% weekly)? [Y/n]
```

Enter runs `claude --continue` as that login, in the same folder. Only logins that share conversation history are offered, so `--isolated` profiles are skipped. The new session starts with only `--continue`; arguments from the first session are not carried over.

This applies to interactive sessions only. `-p`, `--help`, and subcommands such as `mcp` and `update` run as before. `CSWITCH_HANDOFF=0` turns it off.

It is meant for people who hold more than one account of their own, such as a work seat and a personal plan. See [Intended use](#intended-use).

## Status line

Claude Code can show a line under the prompt from a command you choose. `cswitch statusline` shows which login you are on and how much of its limits is used:

```
work · 5h 42% 1h 10m · 7d 18%
```

Close to a limit (80%), it also names the login to switch to: `work · 5h 86% … · next: default 12%`.

Add it to `~/.claude/settings.json`. Profiles share that file, so this covers all of them:

```json
{
  "statusLine": { "type": "command", "command": "cswitch statusline" }
}
```

If you already have a status line script, `cswitch statusline --account` prints just the login name and the hint, to add to your own line. Pass it the same input Claude Code gave your script:

```bash
input=$(cat)
account=$(printf '%s' "$input" | cswitch statusline --account 2>/dev/null)
```

The status line never uses the network. It reads the limits Claude Code passes to it and remembers them, which keeps the menu and the limit check at the end of a session up to date for free.

## Pick an account every time

Run `cswitch` with no arguments to choose from a menu:

```
  Which Claude account?

  ❯ 1  default  me@example.com  5h  84%  7d  56%  last used
    2  work     me@company.com  5h  12%  7d  20%  most room
    3  client   not logged in   not logged in

  ↑/↓ move  ·  enter select  ·  1-9 pick  ·  q cancel
```

Move with the arrow keys or `j`/`k`, press Enter to launch, or press a number to launch that row directly. The menu starts on the profile you used last, so Enter repeats it, unless that login has reached a limit and another has room. Each row shows the login's session and weekly use. Above the menu sits a banner with the Claude Code pet in Claude orange; it shrinks to just the pet in narrow windows and is left out in short ones. `CSWITCH_BANNER=0` turns it off. `q`, Esc and Ctrl-C cancel without starting Claude Code.

To get the menu whenever you type `claude`, add this to `~/.zshrc` or `~/.bashrc`:

```bash
eval "$(cswitch init)"
```

After that, `claude`, `claude --continue`, `claude mcp list` and so on ask which account to use, then run with your arguments unchanged. The menu is skipped when:

- only the `default` profile exists
- input or output is not a terminal, such as in a script or a pipe
- the command does not depend on the account: `--version`, `--help`, `update`, `install`, `doctor`
- `CSWITCH_PROFILE` is set, as in `CSWITCH_PROFILE=work claude`, which uses that profile directly

`command claude` runs Claude Code without the menu. `cswitch pick [claude args...]` shows the menu without the shell function.

To point another tool or a whole shell at a profile:

```bash
eval "$(cswitch env work)"
```

## How it works

Claude Code reads its config directory from `CLAUDE_CONFIG_DIR`. Each profile is its own directory under `~/.claude-profiles/`, so each keeps its own login. `cswitch <name>` sets the variable and starts `claude`.

A new profile symlinks these from `~/.claude`, when they exist, so it behaves like your main setup:

| Shared | What it holds |
|---|---|
| `settings.json`, `keybindings.json` | Settings, permissions, hooks |
| `CLAUDE.md` | Your global instructions |
| `skills`, `commands`, `agents`, `plugins` | Extensions |
| `projects` | Conversation history and per-project memory |

Because `projects` is shared, `cswitch work --continue` picks up the last conversation in the current folder even if it was started under another profile.

Use `cswitch add <name> --isolated` for a profile that shares nothing.

Not shared: the login, and anything stored in `.claude.json`, which includes MCP servers added at user scope. Add those again inside the profile.

Removing a profile deletes only its own directory. Shared files stay in `~/.claude`. Run `/logout` inside the profile first if you also want its saved login removed.

## Intended use

This is for people who hold separate accounts for separate purposes, such as a work seat and a personal plan. Check Anthropic's terms before using additional accounts to get past a usage limit.

cswitch is not made by or affiliated with Anthropic. Claude and Claude Code are trademarks of Anthropic.

## License

MIT
