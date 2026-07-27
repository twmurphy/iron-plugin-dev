# iron-plugin-dev

A marketplace of utilities for developing Claude Code plugins.

## Structure

```
plugin-utils/                            # the marketplace repo (name: iron-plugin-dev)
├── .claude-plugin/
│   └── marketplace.json                 # lists every plugin in plugins/
└── plugins/
    └── local-plugin-dev/                    # a plugin
        ├── .claude-plugin/
        │   └── plugin.json
        ├── scripts/lib/common.sh            # shared: repo discovery, JSON, links
        └── skills/
            ├── local-plugin-setup/
            │   ├── SKILL.md
            │   ├── references/scaffold.md   # how a plugin repo is laid out
            │   └── scripts/
            │       ├── verify-repo.sh       # read-only: scaffold + manifest join
            │       ├── check.sh             # read-only: link state + install scope
            │       └── link.sh              # junctions/symlinks, prunes stale
            └── deploy-plugin/
                ├── SKILL.md
                ├── references/
                │   └── release-sources.md   # sources, refs, what users receive
                └── scripts/
                    └── release-status.sh    # read-only: version vs tag vs ref
```

The repo and the plugin are two levels, and a one-plugin repo still keeps both —
see [scaffold.md](plugins/local-plugin-dev/skills/local-plugin-setup/references/scaffold.md).

## Plugins

| Name               | Skills                            | Purpose                                                    |
| ------------------ | --------------------------------- | ---------------------------------------------------------- |
| `local-plugin-dev` | `local-plugin-setup`, `deploy-plugin` | Verify a plugin repo's scaffold, clear user-scope installs that shadow it, link each plugin into `.claude/skills/` as a live view — then release under control when it is ready |

## Install locally

```bash
claude plugin marketplace add "S:/Vibe Coding/plugin-utils"
```

```bash
claude plugin install local-plugin-dev@iron-plugin-dev --scope project
```

Project scope, not user scope: a user-scope install is a cached snapshot that
takes precedence over the live folder and keeps serving that copy however much
you edit. Plugins become available after a restart.

## Validate

```bash
claude plugin validate .
```

```bash
bash plugins/local-plugin-dev/skills/local-plugin-setup/scripts/verify-repo.sh
```

`claude plugin validate` reads each manifest in isolation; `verify-repo.sh`
checks the join between them.
