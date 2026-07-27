# Sources, refs, and what users actually receive

## The five source types

`marketplace.json` accepts exactly these. A plain `"git"` looks right and is not
among them.

| `source`     | Required      | Pins with        | Installs |
| ------------ | ------------- | ---------------- | -------- |
| `"./path"`   | —             | — (local only)   | a directory on your disk |
| `npm`        | `package`     | `version` range  | the package |
| `url`        | `url`         | `ref` / `sha`    | the repo root |
| `github`     | `repo`        | `ref` / `sha`    | the repo root |
| `git-subdir` | `url`, `path` | `ref` / `sha`    | one subdirectory |

`url` is a git repository URL — `https://` or `git@` — not an archive.
`git-subdir` takes GitHub `owner/repo` shorthand in its `url` as well.

## Reaching a plugin inside a monorepo

Only `git-subdir` carries a `path`, and it is the only type that installs
anything other than a repo root. It clones sparsely (`--filter=tree:0`), so a
large repo costs one subdirectory of bandwidth.

A repo laid out as `plugins/<name>/` therefore requires `git-subdir` for every
plugin in it. `github` and `url` can only serve a repo whose root *is* the
plugin.

Adding `path` to a `github` or `url` source is the natural-looking fix and does
nothing. The manifest schema discards fields a source type does not define, so
the entry validates, the field disappears, and users install the repo root. A
clean `claude plugin validate` is not evidence that a field is honoured.

## Why an unpinned source rules out controlled release

Without `ref` or `sha`, a git-backed source tracks the repo's default branch —
the schema says so outright: *"Defaults to repository default branch."* Every
push to that branch is a release, reaching everyone on their next marketplace
update, including the commit you meant to finish tomorrow. There is no version
to bump and nothing to roll back to.

With `ref` naming a tag, users stay on that tag until you move the ref. The push
and the release come apart, which is the whole point: you decide when.

`sha` pins harder still, to a full 40-character commit, and gives up the
readable version in the name.

## What `claude plugin tag` checks

```bash
claude plugin tag ./plugins/<name> --dry-run
```

- names the tag `{name}--v{version}`, taking both from that plugin's `plugin.json`
- refuses when the working tree has uncommitted changes affecting the release,
  so the tag lands on the version you meant
- refuses when the marketplace entry carries a `version` that disagrees with
  `plugin.json`, reporting that `plugin.json` wins at install time
- prints the exact `git tag` and `git push` commands it runs
- pushes the tag with `--push`, to `--remote` (default `origin`)

## Publishing through more than one marketplace

Nothing stops several marketplaces from listing the same plugin, and each names
its own `ref`. That is what separates channels: a private marketplace can carry
a pre-release while a public one stays on the last stable tag, from one repo and
one set of tags.

A repo publishes through two kinds of marketplace:

- **its own** `.claude-plugin/marketplace.json`, if it has one — no
  configuration, it is simply there
- **remote** ones living in other repos, listed by URL in
  `.claude/<plugin>.md`, which is **committed**, because where a repo publishes
  is a fact about the project and belongs in git:

```markdown
---
marketplaces:
  - name: iron-plugins
    url: https://github.com/twmurphy/iron-plugins.git
---
```

A URL is the whole configuration. Reading a remote marketplace's ref, or moving
it, works from a clone this plugin makes and keeps under
`~/.iron-plugin-dev/marketplaces/`. Nothing records a filesystem path, so there
is no per-machine state to set up, lose, or leave out of git — a fresh clone of
the repo can release from it immediately.

This also removes the assumption that a plugin repo carries a marketplace at
all: name one living in another repo and the plugin repo needs no manifest of
its own.

Scaffold checks never fetch. `verify-repo.sh` reports a remote marketplace as
*"remote, not checked here"* and verifies the join only for a marketplace in the
repo; reading remote refs is `release-status.sh`'s job.

**One plugin name loads once.** Claude Code deduplicates by plugin *name*, not
by `plugin@marketplace`, so installing the same plugin from two marketplaces
leaves one reported as `Not loaded — same plugin name … shadowed`. Several
marketplaces are several ways to *distribute* a plugin, not a way to run two
copies. During a migration between marketplaces, consumers should move from one
to the other rather than add the second alongside the first.

## Optional `version` on a marketplace entry

An entry may carry `version` alongside `name` and `source`. It is optional and
buys only a readable listing, since the installed version comes from
`plugin.json` regardless. Keeping it means keeping it in sync. Removing it is a
legitimate fix.

The marketplace itself has no release version. A top-level `version` validates,
but nothing consumes it: users track a branch, so the manifest at its head is
always what they get.
