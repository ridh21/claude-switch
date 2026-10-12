# claude-switch

`cswitch` keeps several Claude Code logins on one machine. Each one is a profile that you log in to once, then launch by name.

It is a single bash script with no dependencies. It works with the bash 3.2 that ships with macOS, and on Linux.

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

cswitch work --continue   # any claude arguments are passed through
cswitch default           # your original login
cswitch remove work
```

`default` is your existing `~/.claude` setup. `cswitch` never modifies it.

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

## License

MIT
