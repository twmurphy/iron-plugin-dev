---
name: deploy-plugin
description: Release a plugin from a marketplace repo under control, so users receive a fixed version deliberately. Use when the user wants to release or version a plugin, or when a change that shipped has not reached its users.
---

# Deploy a plugin

One version number, one origin, three places:

```
plugin.json       "name": "my-plugin"   "version": "1.2.0"
                                 |
                                 |  concatenated by `claude plugin tag`
                                 v
git tag           my-plugin--v1.2.0
                                 |
                                 |  copied by hand — the release switch
                                 v
marketplace.json  "ref": "my-plugin--v1.2.0"
```

`plugin.json` holds the value: it is what installs, and what the tag name is
built from. The tag is a label frozen to one commit — nothing ever reads a
version back out of it, since an installer checks out the tag and reads
`plugin.json` inside. They agree only because the tag points at the commit where
`plugin.json` already said `1.2.0`.

The `ref` is a pointer naming that label, and it is the **switch**: users read
`marketplace.json` from your **branch** to learn which tag to use, then the
plugin's files from that **tag**. A tag does not move, so an install resolves the
same commit today or in six months, and later pushes reach nobody until the
switch is thrown.

Every way this goes wrong is **silent** — the manifest validates, the tag is
created, the push succeeds, and users still receive the old version or the wrong
directory. So each step below checks rather than assumes, and since a release is
outward-facing and hard to walk back, proposes and waits before running anything.

## Step 1: Choose the plugins and the marketplaces

Determine plugins available to be deployed. The user names a set > the session's work > git history. 

Ask when the reading is genuinely open, list what you would otherwise deploy.
A plugin released by accident is a version users cannot un-receive.

A plugin can be listed by more than one marketplace, each naming its own ref.
**Fan out to all of them by default** — same version, same tag, every ref moved
together. Narrow only when the user names a marketplace, which is how a
pre-release reaches a private channel while the public one stays put.

Done when the user has confirmed both lists.

## Step 2: Read the current state

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/deploy-plugin/scripts/release-status.sh"
```

Read-only. It prints, per plugin, the version and the tag, then one line per
marketplace showing the ref that marketplace names and what its users get. Pass
marketplace names to narrow it: `release-status.sh iron-plugins`.

Marketplaces come from `.claude/iron-plugin-dev.local.md` when it exists, and
otherwise from this repo's own `marketplace.json` — see
[references/release-sources.md](references/release-sources.md) for the settings
format.

Resolve anything it flags before going on:

- **`NOT A GIT REPO`** — releases travel through git. Offer `git init`, a first
  commit, and a remote.
- **`remote NONE`** — there is nowhere to push. Ask for the URL and offer
  `git remote add origin <url>`.
- **`marketplace entry MISSING`** — the plugin cannot install at all. This is
  scaffold work; the `setup-local` skill's `verify-repo.sh` covers it.
- **`entry version DISAGREES`** — the entry carries an optional `version` that
  no longer matches `plugin.json`, and tagging refuses until it does. Offer both
  fixes: update it, or remove it so `plugin.json` is the only place a version
  lives. Recommend removing.

Done when you can state, for each plugin being deployed, its `plugin.json`
version, whether its source is pinned, and what users currently resolve.

## Step 3: Confirm the source can pin a release

A plugin here lives at `plugins/<name>/`, a subdirectory, and exactly one source
type reaches a subdirectory. Recommend `git-subdir` with a `ref`:

```json
"source": {
  "source": "git-subdir",
  "url": "owner/repo",
  "path": "plugins/<name>",
  "ref": "<name>--v<version>"
}
```

`url` takes GitHub `owner/repo` shorthand, a full `https://` URL, or `git@`.

Both ways this fails are silent — `claude plugin validate` passes either one:

- a `github` or `url` source installs the repo root, and adding `path` to fix it
  changes nothing
- without a `ref`, the source follows the default branch, so every push is an
  immediate release with nothing to roll back to

[references/release-sources.md](references/release-sources.md) has every source
type, what each pins, and why the `path` field disappears.

Each marketplace carries its own entry, so check every one being deployed to —
one can be pinned correctly while another is unpinned or points at a repo root.

Done when every plugin being deployed has a `git-subdir` source with a `ref` in
each targeted marketplace, or the user has accepted that one of them ships on
every push.

## Step 4: Choose the version

Read what changed since the tag the `ref` currently names:

```bash
git diff --stat <current-ref>..HEAD -- plugins/<name>
```

```bash
git log --oneline <current-ref>..HEAD -- plugins/<name>
```

Then use **AskUserQuestion** to confirm the bump, offering major, minor, and
patch with the computed number in each label. Recommend one and say what in the
diff decides it:

- **major** — an installed user's existing usage breaks: a command or skill
  removed or renamed, a hook's contract changed, required settings added.
- **minor** — new capability that leaves existing usage working: a skill or
  command added, new optional behaviour.
- **patch** — corrections behind unchanged behaviour: wording, a fixed script,
  documentation.

Name the evidence rather than the rule — "the `refresh` command is gone, so
anyone invoking it breaks: major" beats "breaking changes are major".

Done when the user has picked a version for each plugin.

## Step 5: Cut the release

The order matters: the tag has to exist before the `ref` can name it.

1. **Bump** `version` in each plugin's `plugin.json` to the agreed number.
2. **Commit.** Tagging refuses on a dirty tree affecting the release, so the tag
   lands on the version intended.
3. **Tag**, checking it first:

   ```bash
   claude plugin tag ./plugins/<name> --dry-run
   ```

   ```bash
   claude plugin tag ./plugins/<name> --push
   ```

4. **Throw every switch** — move the `ref` to the new tag in each targeted
   marketplace, for each plugin deployed. Nothing does this for you and nothing
   warns that it is undone, which is the silent failure the whole skill guards
   against. Fanning out multiplies it: one manifest updated and another
   forgotten leaves half your users on the old version, and both look fine.
5. **Commit and push each marketplace's branch.** Publishing happens here, once
   per repo — marketplaces in separate repos each need their own commit and
   push, and a release is only live where that has happened.
6. **Verify** by re-running `release-status.sh` across every target — each
   should read `users get: <new version>, ref matches`.

Then tell the user what an installed user runs to receive it:

```bash
claude plugin marketplace update <marketplace-name>
```

```bash
claude plugin update <plugin>@<marketplace>
```

The new version applies after a restart.

Done when `release-status.sh` reports the new version on every plugin deployed,
and the branch and tags are pushed.
