# no-agent-marketing

A GitHub Action that fails a PR when its commits, title or description contain
AI-agent attribution or marketing, such as:

```
🤖 Generated with [Claude Code](https://claude.com/claude-code)
Co-Authored-By: Claude <noreply@anthropic.com>
```

## Usage

```yaml
# .github/workflows/no-agent-marketing.yml
name: no-agent-marketing
on:
  pull_request:
    types: [opened, edited, synchronize, reopened]
  push:
    branches: [main]

permissions:
  contents: read
  pull-requests: read

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: kexhq/no-agent-marketing@v1
```

No checkout is needed unless you use `rule-files`. On a PR, every commit in the
PR is checked through the GitHub API. On a push, the pushed commits are read from
the event payload.

## Built-in rules

Each file in [`rules/`](rules) is one rule set. All are enabled by default.

| Rule | Covers |
|---|---|
| `claude` | Claude / Claude Code |
| `copilot` | GitHub Copilot |
| `openai` | ChatGPT, Codex |
| `cursor` | Cursor |
| `gemini` | Gemini, Jules |
| `other-agents` | Devin, Aider, Windsurf, Cline, Amp, … |
| `generic` | vendor-neutral lines (`🤖 …`, "Generated with an AI assistant") |

## Inputs

| Input | Default | Description |
|---|---|---|
| `rules` | `all` | Built-in rule sets to enable, `all` or `none` |
| `exclude-rules` | `""` | Built-in rule sets to disable, e.g. `copilot` |
| `rule-files` | `""` | Your own rule files, one path per line (needs `actions/checkout`) |
| `extra-patterns` | `""` | Inline regexes, one per line (reported as rule `custom`) |
| `allow-patterns` | `""` | Lines matching these are never reported |
| `sources` | `commits, pr-title, pr-body` | What to scan |
| `fail` | `true` | `false` = warnings only |
| `failure-message` | built-in | Printed when the check fails |
| `token` | `github.token` | Token for listing PR commits |

Patterns are case-insensitive POSIX extended regexes (`grep -iE`).

## Outputs

| Output | Description |
|---|---|
| `found` | `"true"` / `"false"` |
| `count` | Number of matching lines |
| `matches` | JSON array of `{source, ref, line, rule, text}` |

## Examples

Allow Copilot co-authors but block everything else:

```yaml
- uses: kexhq/no-agent-marketing@v1
  with:
    exclude-rules: copilot
```

Add your own rules from the repo:

```yaml
- uses: actions/checkout@v5
- uses: kexhq/no-agent-marketing@v1
  with:
    rule-files: .github/agent-marketing-rules.txt
    extra-patterns: |
      Built with MyInternalBot
```

Commit messages only, warnings only:

```yaml
- uses: kexhq/no-agent-marketing@v1
  with:
    sources: commits
    fail: false
```

## Adding a new LLM / agent

1. Add `rules/<name>.txt` with one regex per line (`#` starts a comment).
2. Add `tests/examples/<name>.txt` with real attribution lines that must match.
3. If a pattern is broad, add lines to `tests/clean.txt` that must *not* match.
4. Run `tests/run.sh`.

The new rule is on by default and can be turned off with `exclude-rules: <name>`.
This repo runs its own action in CI, so its own commits and PRs follow the rule.

## Publishing

```sh
git init -b main && git add . && git commit -m "Initial version"
git remote add origin git@github.com:kexhq/no-agent-marketing.git
git push -u origin main
git tag v1.0.0 && git tag v1 && git push origin v1.0.0 v1
```

To move `v1` forward on later releases, run `git tag -f v1 && git push -f origin v1`.
If the repo is private, go to Settings → Actions → General → Access and allow
other repositories in the `kexhq` organization to use it.
