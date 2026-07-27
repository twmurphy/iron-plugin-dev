# How a plugin repo is laid out

Two nested things share the word "plugin", and most scaffold mistakes come from
collapsing them:

- A **marketplace** is the repo. It carries `.claude-plugin/marketplace.json`
  and a `plugins/` directory. It is what you add with `claude plugin marketplace add`.
- A **plugin** is one directory under `plugins/`. It carries its own
  `.claude-plugin/plugin.json` and its components. It is what you install.

A repo holding a single plugin still keeps both levels. Flattening the plugin up
to the repo root leaves nothing for the marketplace to list.

## The layout

```
my-plugins/                          # the marketplace repo
├── .claude-plugin/
│   └── marketplace.json             # lists every plugin in plugins/
└── plugins/
    ├── first-plugin/                # a plugin
    │   ├── .claude-plugin/
    │   │   └── plugin.json          # this plugin's manifest
    │   ├── commands/                # optional components, at plugin root
    │   ├── agents/
    │   ├── skills/
    │   │   └── some-skill/
    │   │       ├── SKILL.md         # required name, exact case
    │   │       ├── references/      # progressive disclosure
    │   │       └── scripts/
    │   ├── hooks/
    │   │   └── hooks.json
    │   └── .mcp.json
    └── second-plugin/
        ├── .claude-plugin/
        │   └── plugin.json
        └── skills/
```

Component directories sit at the **plugin root**, beside `.claude-plugin/` and
never inside it. A `skills/` directory inside `.claude-plugin/` is invisible to
discovery.

## marketplace.json

```json
{
  "name": "my-plugins",
  "owner": { "name": "Your Name" },
  "metadata": { "description": "What this collection is for." },
  "plugins": [
    {
      "name": "first-plugin",
      "source": "./plugins/first-plugin",
      "description": "What this plugin does."
    }
  ]
}
```

Every plugin needs an entry. A directory under `plugins/` that no entry names is
invisible to the marketplace, so it never installs — the most common way a repo
looks finished but installs nothing.

`name` must match both the directory name and the `name` in that plugin's
`plugin.json`. Three places, one string.

`source` is a repo-relative path during development. A published plugin points at
a git repo instead:

```json
"source": {
  "source": "git-subdir",
  "url": "https://github.com/you/my-plugins.git",
  "path": "plugins/first-plugin",
  "ref": "first-plugin--v0.3.3"
}
```

`path` is where the plugin sits inside that repo, and `ref` is any git ref —
tag, branch, or commit — that installs check out before reading `path`.

Make it a tag. A branch such as `main` moves under everyone who installed from
it, so an unrelated commit reaches users as a silent update; a tag freezes what
they get until you publish a new one.

The `{name}--v{version}` shape matters when one repo holds several plugins, each
released on its own cadence: a bare `v0.3.3` cannot say which plugin it
released. Create the tag with:

```bash
claude plugin tag ./plugins/first-plugin --push
```

It builds the tag from the `name` and `version` in `plugin.json`, and refuses
unless those agree with the enclosing marketplace entry — so the ref you write
above and the plugin it resolves to cannot drift apart. Add `--dry-run` to see
the tag without creating it.

## plugin.json

Only `name` is required; the rest earns its place in listings and updates.

```json
{
  "name": "first-plugin",
  "description": "What this plugin does.",
  "version": "0.1.0",
  "author": { "name": "Your Name" },
  "keywords": ["testing", "automation"]
}
```

Leave component paths out. Discovery scans `commands/`, `agents/`, `skills/`,
and `hooks/` on its own, and a custom path in the manifest supplements those
defaults rather than replacing them.

## Naming

Kebab-case throughout: repo, plugin directories, skill directories, command and
agent files. A command file `review-pr.md` becomes `/review-pr`. Each skill is a
directory holding `SKILL.md` — that exact name, that exact case; `readme.md` or
`skill.md` is skipped silently.

## Paths inside a plugin

Reference anything shipped in the plugin through `${CLAUDE_PLUGIN_ROOT}`, which
resolves to the plugin directory wherever it ends up installed:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/some-skill/scripts/run.sh"
```

Absolute paths and paths relative to the working directory both break as soon as
the plugin is installed somewhere other than where it was written.

## Checking the manifests

```bash
claude plugin validate .
```

```bash
claude plugin validate ./plugins/first-plugin
```

The first validates the marketplace manifest, the second one plugin's manifest.
Neither cross-checks the two, so a plugin missing from `marketplace.json` passes
both — that gap is what Step 1 of this skill covers.
