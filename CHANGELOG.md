# Changelog

## 0.1.0

Initial release.

- `new-session`: starts background Claude Code sessions with Remote Control (`claude --bg --remote-control`) and returns their link.
  - Grants folder trust only under `SESSION_TOOLS_ALLOWED_ROOTS` (default `$HOME`, symlinks resolved), after a review of project-supplied Claude config (settings, hooks, MCP, agents, skills, commands, `CLAUDE.md`) for folders not trusted yet.
  - Writes `~/.claude.json` atomically, keeping its file mode, with a backup.
  - Blocks session chains via `SESSION_TOOLS_DEPTH` / `SESSION_TOOLS_MAX_DEPTH` (default `1`).
  - Uses the user's default permission mode; `--bypass` only on request.
- `session-discovery`: lists past sessions per folder (optionally with subfolders) with the folder `claude --resume` must run from, and probes sessions through an ephemeral fork with no tools, no MCP servers and hooks disabled.
