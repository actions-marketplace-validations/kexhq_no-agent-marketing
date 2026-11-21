# Agent instructions

This repository enforces its own rule: **no AI-agent attribution or marketing**.

- Do not add `Co-Authored-By:` trailers for AI tools, `🤖 Generated with ...` lines,
  or links to agent products to commit messages, PR titles, or PR descriptions.
- CI runs this action against every PR and push to `main` and fails on any match.

## Adding a new LLM / agent

1. Add `rules/<name>.txt`: one case-insensitive extended regex per line (`#` comments allowed).
2. Add `tests/examples/<name>.txt`: real attribution lines that must match.
3. If a pattern is broad, add lines that must *not* match to `tests/clean.txt`.
4. Run `tests/run.sh`.

The rule is enabled by default (`rules: all`) and can be turned off by name with `exclude-rules`.
