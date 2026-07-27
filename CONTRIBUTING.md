# Contributing

Thanks for taking an interest. This repo is a Claude Code plugin marketplace:
the repo is the marketplace, and each directory under `plugins/` is a plugin.
[scaffold.md](plugins/iron-plugin-dev/skills/setup-local/references/scaffold.md)
describes the layout in full.

## Getting set up

Clone the repo, then link each plugin into `.claude/skills/` so Claude Code
loads the live folders instead of a cached copy:

```bash
bash plugins/iron-plugin-dev/skills/setup-local/scripts/link.sh
```

Skills become available after restarting Claude Code.

Avoid installing a plugin from this repo while working on it. An install is a
frozen snapshot in the plugin cache, so your edits will appear to do nothing.
The `setup-local` skill checks for exactly that:

```bash
bash plugins/iron-plugin-dev/skills/setup-local/scripts/check.sh
```

## Before opening a pull request

Confirm the scaffold and both manifests still hold:

```bash
bash plugins/iron-plugin-dev/skills/setup-local/scripts/verify-repo.sh
```

```bash
claude plugin validate . --strict
```

`claude plugin validate` reads each manifest alone; `verify-repo.sh` checks the
join between them, which is where a new plugin usually goes wrong — a directory
under `plugins/` that no `marketplace.json` entry names installs nothing while
passing validation.

Shell scripts should pass `bash -n`, and `.gitattributes` keeps them checked out
with LF endings so the shebang survives on Windows.

## Conventions

- **Naming** — kebab-case for directories and files. Skills read verb-first
  (`setup-local`, `deploy-plugin`).
- **Paths** — reference anything inside a plugin through `${CLAUDE_PLUGIN_ROOT}`
  so it resolves wherever the plugin is installed.
- **Shared code** — helpers used by more than one skill live in the plugin's
  `scripts/lib/`, sourced relative to the plugin root.
- **Scripts that report** are read-only; anything that changes state is a
  separate script the skill offers rather than runs.

## Releasing

Releases are deliberate: a version, a git tag, and the `ref` in
`marketplace.json` all have to agree, and moving the `ref` is what publishes.
The `deploy-plugin` skill walks the whole sequence, and
[release-sources.md](plugins/iron-plugin-dev/skills/deploy-plugin/references/release-sources.md)
explains what users actually receive.

## License

By contributing you agree that your contributions are licensed under the
[MIT License](LICENSE) covering this project.
