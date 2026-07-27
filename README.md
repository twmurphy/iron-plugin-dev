# iron-plugin-dev

A Claude Code marketplace of plugins for building and releasing Claude Code
plugins.

## What's in it

| Plugin | Skill | What it does |
| ------ | ----- | ------------ |
| `iron-plugin-dev` | `setup-local` | Verifies a plugin repo's scaffold, clears installs that shadow it, and links each plugin into `.claude/skills/` as a live view |
| | `deploy-plugin` | Cuts a controlled release: version, tag, and marketplace ref moved together so users receive a fixed version deliberately |

Both are model-invoked, so Claude reaches for them on its own — or call them by
name with `/iron-plugin-dev:setup-local` and `/iron-plugin-dev:deploy-plugin`.

## Install

```bash
claude plugin marketplace add twmurphy/iron-plugin-dev
```

```bash
claude plugin install iron-plugin-dev@iron-plugin-dev --scope project
```

Plugins become available after restarting Claude Code.

Project scope keeps the install with the project it was made in. A user-scope
install follows the machine instead and applies everywhere, which is rarely what
you want for a plugin you may also work on.

## The problem it solves

Claude Code loads a plugin from a **cached snapshot**, frozen at the version it
resolved. That is what you want for a released plugin and exactly what you do
not want for one you are editing, because your changes appear to do nothing.

`setup-local` replaces the snapshot with a **live view** — a junction on
Windows, a symlink elsewhere — pointing at the folder you are working in, and
reports any install still shadowing it.

`deploy-plugin` handles the other end. A release is one version number in three
places: `plugin.json` holds the value, the git tag is a label built from it, and
the `ref` in `marketplace.json` names that tag. Users read `marketplace.json`
from your branch and the plugin's files from the tag, so a tag never moves and
later pushes reach nobody until you edit the `ref`. Nothing throws that switch
for you, and nothing warns when it is undone.

## Layout

```
iron-plugin-dev/                          # the marketplace repo
├── .claude-plugin/
│   └── marketplace.json                  # lists every plugin in plugins/
└── plugins/
    └── iron-plugin-dev/                  # a plugin
        ├── .claude-plugin/
        │   └── plugin.json
        ├── scripts/lib/common.sh         # shared: repo discovery, JSON, links
        └── skills/
            ├── setup-local/
            │   ├── SKILL.md
            │   ├── references/scaffold.md
            │   └── scripts/
            │       ├── verify-repo.sh    # read-only: scaffold + manifest join
            │       ├── check.sh          # read-only: link state + installs
            │       └── link.sh           # junctions/symlinks, prunes stale
            └── deploy-plugin/
                ├── SKILL.md
                ├── references/release-sources.md
                └── scripts/
                    └── release-status.sh # read-only: version vs tag vs ref
```

The repo and the plugin are two levels, and a one-plugin repo still keeps both —
see [scaffold.md](plugins/iron-plugin-dev/skills/setup-local/references/scaffold.md).

## Working on this repo

See [CONTRIBUTING.md](CONTRIBUTING.md). In short, link rather than install:

```bash
bash plugins/iron-plugin-dev/skills/setup-local/scripts/link.sh
```

## License

[MIT](LICENSE)
