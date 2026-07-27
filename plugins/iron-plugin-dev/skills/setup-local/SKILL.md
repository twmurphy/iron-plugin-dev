---
name: setup-local
description: Set up a repo's local plugins so Claude Code loads the live folders during development. Use when scaffolding or auditing a plugin repo, after adding, renaming, or removing a plugin, when a local plugin's skills are missing from the session, or when edits to a plugin are not taking effect.
---

# Local plugin development

Claude Code can load a plugin from either of two places, and they are not equal.

An **install** is a snapshot copied into the plugin cache, frozen at the version it resolved. It keeps serving that copy however much you edit `plugins/`.

A **link** in `.claude/skills/` is a live view of the plugin folder. The scan finds every `skills/*/SKILL.md` inside, and edits land immediately because there is no copy to keep current.

Development wants the live view, so the snapshot goes first: an installed copy of a plugin that also lives in this repo shadows the link. Scope decides where the install was declared, not whether it shadows — a project-scope install of a plugin in this repo serves the same frozen copy a user-scope one does.

Neither one loads anything until the repo itself is a plugin repo, which is where this starts.

## Step 1: Confirm the scaffold

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/setup-local/scripts/verify-repo.sh"
```

Read-only. It checks the two halves of a plugin repo — `.claude-plugin/marketplace.json` and `plugins/` — and the join between them: every directory under `plugins/` carries a `plugin.json` whose name matches, and every one of those names appears in `marketplace.json`. `claude plugin validate` reads each manifest alone and never compares them, so a plugin missing from the marketplace passes validation while installing nothing.

For anything it reports, read [references/scaffold.md](references/scaffold.md) for the layout that fixes it, and offer the change. Common findings:

- **A plugin not listed in `marketplace.json`** — add an entry naming it, with `"source": "./plugins/<name>"`.
- **No `plugins/` directory, components at the repo root** — the repo is shaped like a single plugin. Move it down to `plugins/<name>/` and give the root a marketplace manifest; the repo and the plugin are two levels, and a one-plugin repo still keeps both.
- **A name disagreeing across `plugin.json`, the directory, and `marketplace.json`** — settle on one string for all three.

Done when the script prints `Scaffold OK`.

## Step 2: Check the current setup

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/setup-local/scripts/check.sh"
```

Read-only. Run it from anywhere inside the repo — it walks up for `plugins/`.

Done when you can state, for every plugin it lists, both the link state and the install scope.

If each one reads `link: linked` with `install: none`, the setup is already correct: confirm that to the user, naming the plugins, and stop here.

## Step 3: Clear any install that shadows the repo

For each plugin the check marked `SHADOWS the link`, tell the user which version the cache is serving, and offer the uninstall at the scope it reports:

```bash
claude plugin uninstall <name>@<marketplace> --scope <scope>
```

Uninstalling here does not cost them the plugin elsewhere. An install belongs to the scope it was made in, so the released version stays available in every *other* repo — only this one, where the source lives, drops back to the live link.

That split is the point: elsewhere you want the frozen release, here you want the folder you are editing.

Done when no plugin in `plugins/` has an install, or the user has chosen to keep one and accepts that edits will not take effect until it is gone.

## Step 4: Link the plugins into `.claude/skills/`

For each plugin reading `missing` or `stale`, offer:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/setup-local/scripts/link.sh"
```

Tell the user what it lands: one entry per plugin in `.claude/skills/` pointing at its folder — a junction on Windows, which needs no elevation, and a symlink everywhere else. Links whose plugin is gone are removed, so the set stays 1:1. Real directories are left alone, so any skill hand-written in `.claude/skills/` survives, and a real directory sitting on a plugin's name is reported rather than replaced.

A plugin linked becomes available after a restart.

Done when every plugin in `plugins/` reads `linked`.

---

Keep `.claude/skills/` gitignored apart from real skills authored there: the links are per-machine, disposable, and safe to regenerate any time.
