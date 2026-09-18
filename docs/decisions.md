# Architecture Decision Log

Short ADR entries — decision + one-line reason. Full stack choices live in
`CLAUDE.md`; this file is for decisions made *along the way*.

## ADR-000 — Go installed user-local, not system-wide

Installed Go 1.27.1 to `~/.local/go` instead of `/usr/local` because this
machine's `sudo` requires a password not available non-interactively.
No functional downside — PATH is set in `~/.bashrc` and `~/.profile`.
See `docs/environment-setup.md`.
