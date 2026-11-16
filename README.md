# claude-session-tools

Two [Claude Code](https://claude.com/claude-code) skills for managing sessions.

| Skill | What it does |
|---|---|
| `new-session` | Starts a background Claude Code session (`claude --bg --remote-control`) in a folder you allow, and returns its Remote Control link. Handy when you're driving one session from your phone and want to open more on the same machine. |
| `session-discovery` | Lists past sessions for a folder (and subfolders), tells you which folder `claude --resume` must run from, and **probes** sessions: asks them a question through an ephemeral, tool-less fork that never modifies the original. |

## Install

```
/plugin marketplace add Kino1994/claude-session-tools
/plugin install session-tools@claude-session-tools
```

Then just ask, e.g. *"open a session in ~/git/my-repo"* or *"what sessions are there in ~/git and where did they leave off?"*.

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `SESSION_TOOLS_ALLOWED_ROOTS` | `$HOME` | Colon-separated folders `new-session` may start sessions under (symlinks are resolved). E.g. `~/git:~/work`. |
| `SESSION_TOOLS_MAX_DEPTH` | `1` | Levels of sessions-started-by-`new-session` allowed. `1` means a spawned session cannot spawn another. |

Set them in your shell profile, or in the `env` block of `~/.claude/settings.json`.

## Requirements

- Claude Code with `--bg` and Remote Control support, logged in with a claude.ai account.
- Linux or macOS with `bash` and `python3`.

## Security model

Read this before using `new-session` with `bypassPermissions`.

- **Your claude.ai account becomes the boundary.** A Remote Control session in bypass mode is a permission-free shell on your machine, driven by whoever holds your account. With `new-session`, that person can also open new, persistent sessions. Use 2FA and check `claude agents` now and then.
- **Folder trust is permanent.** `claude --bg` refuses untrusted folders, so `new-session` marks the target as trusted in `~/.claude.json`. Before doing so for a folder that isn't trusted yet, it stops for review if the folder ships `.claude/settings*.json`, `.claude/hooks`, `.mcp.json`, `.claude/agents|skills|commands` or `CLAUDE.md`. After that, later changes (e.g. `git pull`) load without review, as with any trusted folder. Be careful with freshly cloned repos.
- **No chains by default.** A spawned session gets `SESSION_TOOLS_DEPTH` and the script refuses to spawn from it. This stops a prompt-injected session from using the skill to fan out persistent sessions. It is a guardrail, not a sandbox: a session with shell access can still run `claude --bg` itself.
- **Permissions.** New sessions use your default permission mode; `--bypass` is only added when you ask for it.
- **Probes are tool-less.** Replaying an old transcript replays any hostile content it once read. Probes run with `--tools ""`, `--strict-mcp-config` and hooks disabled, so they can only reason over the transcript: no file reads, no network. Their output is still untrusted text.
- **Transcripts contain secrets.** `session-discovery` reads `~/.claude/projects/*/*.jsonl`, which holds everything past sessions saw (pasted keys, `env` output, file contents), and brings it into the current session. Each probe resends the whole conversation to the API.
- **Internal formats.** Both skills read files Claude Code does not document (`~/.claude.json`, `~/.claude/projects/*/*.jsonl`). An update could break them. `~/.claude.json` is written atomically, keeping its file mode, with a backup at `~/.claude.json.bak`.

## License

MIT
