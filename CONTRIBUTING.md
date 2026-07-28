# Contributing

Thanks for taking an interest. This repo holds plugins; each directory under
`plugins/` is one. It publishes through the
[iron-plugins](https://github.com/twmurphy/iron-plugins) marketplace, which
lives in its own repo and pins each plugin to a released tag.
[scaffold.md](plugins/iron-plugin-dev/skills/setup-local/references/scaffold.md)
describes the layout in full.

## Getting set up

The plugin provides the tooling you use to work on it, so install it first:

```bash
claude plugin marketplace add twmurphy/iron-plugins
```

```bash
claude plugin install iron-plugin-dev@iron-plugins --scope project
```

Restart Claude Code, then run:

```
/iron-plugin-dev:setup-local
```

That checks the scaffold and swaps the install you just made for a live view of
your working copy — a junction on Windows, a symlink elsewhere — so your edits
take effect instead of being served from a frozen cache copy. Restart once more
and you are editing what Claude Code loads.

The install is a bootstrap, not the end state. `setup-local` will tell you it
shadows the repo and offer to remove it; let it.

If your edits ever seem to do nothing, run `/iron-plugin-dev:setup-local` again
— a shadowing install is the usual cause.

## Before opening a pull request

```
/iron-plugin-dev:setup-local
```

Its first step confirms the scaffold: that `.claude-plugin/marketplace.json` and
`plugins/` both exist, and that they agree in both directions. A directory under
`plugins/` that no marketplace entry names installs nothing while passing
validation, which is where a new plugin usually goes wrong.

Then check the manifests themselves:

```bash
claude plugin validate . --strict
```

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

## License

By contributing you agree that your contributions are licensed under the
[MIT License](LICENSE) covering this project.
