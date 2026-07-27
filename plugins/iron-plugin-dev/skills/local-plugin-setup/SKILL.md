---
name: local-plugin-setup
description: Set up a repo's local plugins so Claude Code loads the live folders during development. Use when scaffolding or auditing a plugin repo, after adding, renaming, or removing a plugin, when a local plugin's skills are missing from the session, or when edits to a plugin are not taking effect.
---

# Local plugin development

Claude Code can load a plugin from either of two places, and they are not equal.

A **user-scope install** is a snapshot copied into the plugin cache. It takes precedence over everything else, and it keeps serving that copy however much you edit `plugins/`.

A **link** in `.claude/skills/` is a live view of the plugin folder. The scan finds every `skills/*/SKILL.md` inside, and edits land immediately because there is no copy to keep current.

Development wants the live view, so the snapshot goes first: while a plugin is installed at user scope, it shadows the link.

Neither one loads anything until the repo itself is a plugin repo, which is where this starts.

## Step 1: Confirm the scaffold

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/local-plugin-setup/scripts/verify-repo.sh"
```

Read-only. It checks the two halves of a plugin repo — `.claude-plugin/marketplace.json` and `plugins/` — and the join between them: every directory under `plugins/` carries a `plugin.json` whose name matches, and every one of those names appears in `marketplace.json`. `claude plugin validate` reads each manifest alone and never compares them, so a plugin missing from the marketplace passes validation while installing nothing.

For anything it reports, read [references/scaffold.md](references/scaffold.md) for the layout that fixes it, and offer the change. Common findings:

- **A plugin not listed in `marketplace.json`** — add an entry naming it, with `"source": "./plugins/<name>"`.
- **No `plugins/` directory, components at the repo root** — the repo is shaped like a single plugin. Move it down to `plugins/<name>/` and give the root a marketplace manifest; the repo and the plugin are two levels, and a one-plugin repo still keeps both.
- **A name disagreeing across `plugin.json`, the directory, and `marketplace.json`** — settle on one string for all three.

Done when the script prints `Scaffold OK`.

## Step 2: Check the current setup

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/local-plugin-setup/scripts/check.sh"
```

Read-only. Run it from anywhere inside the repo — it walks up for `plugins/`.

Done when you can state, for every plugin it lists, both the link state and the install scope.

If each one reads `link: linked` with `install: none` or `install: project`, the setup is already correct: confirm that to the user, naming the plugins, and stop here.

## Step 3: Clear any user-scope install

For each plugin the check reported at `user` scope, tell the user it shadows the live link, and offer:

```bash
claude plugin uninstall <name>@<marketplace> --scope user
```

Uninstalling here does not cost them the plugin elsewhere. A project-scope install belongs to the project it was made in, so installing the released version in another repo leaves this one on its live link — both run, each from the copy that repo wants:

```bash
claude plugin install <name>@<marketplace> --scope project
```

Done when no plugin in `plugins/` is installed at user scope, or the user has chosen to keep one that way.

## Step 4: Link the plugins into `.claude/skills/`

For each plugin reading `missing` or `stale`, offer:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/local-plugin-setup/scripts/link.sh"
```

Tell the user what it lands: one entry per plugin in `.claude/skills/` pointing at its folder — a junction on Windows, which needs no elevation, and a symlink everywhere else. Links whose plugin is gone are removed, so the set stays 1:1. Real directories are left alone, so any skill hand-written in `.claude/skills/` survives, and a real directory sitting on a plugin's name is reported rather than replaced.

A plugin linked becomes available after a restart.

Done when every plugin in `plugins/` reads `linked`.

---

Keep `.claude/skills/` gitignored apart from real skills authored there: the links are per-machine, disposable, and safe to regenerate any time.
