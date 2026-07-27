#!/usr/bin/env bash
# deploy-plugin/release-status: report what each plugin would release and what
# users currently get. Read-only; changes nothing.
#
# Three things carry a version and they move independently:
#   plugin.json version   what installs, and what `claude plugin tag` names the tag after
#   the git tag           the commit that version lives at
#   marketplace ref       the tag users actually resolve
# A release lands only when all three agree, so this prints them side by side.
set -euo pipefail
shopt -s nullglob

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/scripts/lib/common.sh"

root="$(find_root)" || die "no plugin repo at $(pwd -P) or any parent"
[ -d "$root/plugins" ] || die "no plugins/ directory at $root"
market="$root/.claude-plugin/marketplace.json"
[ -f "$market" ] || die "no .claude-plugin/marketplace.json at $root"

echo "Repo: $root"

# --- Can this repo publish at all? -------------------------------------------
git_ok=0
if git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
  git_ok=1
  remotes="$(git -C "$root" remote 2>/dev/null | tr '\n' ' ')"
  if [ -n "${remotes// /}" ]; then
    for r in $remotes; do
      printf '  remote %-10s %s\n' "$r" "$(git -C "$root" remote get-url "$r" 2>/dev/null)"
    done
  else
    printf '  %-17s %s\n' "remote" "NONE — nothing to publish to"
  fi
  branch="$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  if [ -n "$(git -C "$root" status --porcelain 2>/dev/null)" ]; then
    dirty="dirty — commit before tagging"
  else
    dirty="clean"
  fi
  printf '  %-17s %s (%s)\n' "branch" "$branch" "$dirty"
else
  printf '  %-17s %s\n' "git" "NOT A GIT REPO — releases need one"
fi

# Marketplace entries as "name<TAB>kind<TAB>ref<TAB>entryVersion".
entries() {
  node -e '
    let raw = "";
    process.stdin.on("data", chunk => raw += chunk);
    process.stdin.on("end", () => {
      let j;
      try { j = JSON.parse(raw); } catch { return; }
      for (const p of (j && j.plugins) || []) {
        if (!p || typeof p.name !== "string") continue;
        const s = p.source;
        const kind = typeof s === "string" ? "path" : (s && s.source) || "none";
        const ref  = (s && typeof s === "object" && s.ref) || "";
        console.log([p.name, kind, ref, p.version || ""].join("\t"));
      }
    });
  ' < "$market" 2>/dev/null
}
listing="$(entries)"

for dir in "$root"/plugins/*/; do
  name="$(basename "$dir")"
  manifest="${dir}.claude-plugin/plugin.json"
  [ -f "$manifest" ] || continue

  version="$(json_field "$manifest" version)"
  [ -n "$version" ] || version="(none)"

  row="$(printf '%s\n' "$listing" | awk -F'\t' -v n="$name" '$1 == n')"
  kind="$(printf '%s' "$row" | cut -f2)"
  ref="$(printf '%s' "$row" | cut -f3)"
  entry_version="$(printf '%s' "$row" | cut -f4)"

  echo
  echo "$name"
  printf '  %-22s %s\n' "plugin.json version" "$version"

  if [ -z "$row" ]; then
    printf '  %-22s %s\n' "marketplace entry" "MISSING — users cannot install it"
    continue
  fi

  # Two independent requirements: the type has to reach plugins/<name>, and a ref
  # has to pin it. git-subdir is the only type carrying a path, so it is the only
  # one that installs anything but a repo root; without a ref, any git source
  # follows its default branch and every push reaches users immediately.
  reaches=0
  case "$kind" in
    git-subdir)
      reaches=1
      if [ -n "$ref" ]; then
        printf '  %-22s %s\n' "source" "git-subdir · pinned to $ref"
      else
        printf '  %-22s %s\n' "source" "git-subdir · UNPINNED (tracks default branch)"
      fi
      ;;
    github|url)
      printf '  %-22s %s\n' "source" "$kind · installs the REPO ROOT, not plugins/$name"
      printf '  %-22s %s\n' "" "needs git-subdir — adding a path here is silently dropped"
      ;;
    npm)  printf '  %-22s %s\n' "source" "npm · released through the registry, not this repo" ;;
    path) printf '  %-22s %s\n' "source" "path · local, cannot ship to anyone" ;;
    *)    printf '  %-22s %s\n' "source" "$kind" ;;
  esac

  [ -z "$entry_version" ] || printf '  %-22s %s\n' "entry version" "$entry_version"
  if [ -n "$entry_version" ] && [ "$entry_version" != "$version" ]; then
    printf '  %-22s %s\n' "" "DISAGREES with plugin.json — tagging refuses until it matches or is removed"
  fi

  # What `claude plugin tag` would name, and whether users would reach it.
  tag="$name--v$version"
  if [ "$git_ok" = 1 ]; then
    if git -C "$root" rev-parse -q --verify "refs/tags/$tag" >/dev/null 2>&1; then
      tag_state="exists"
    else
      tag_state="not created yet"
    fi
    printf '  %-22s %s (%s)\n' "release tag" "$tag" "$tag_state"
  fi

  # A matching ref only means the right version when the source type can reach
  # this plugin at all; saying "users get 1.2.0" off a repo-root source would be
  # the exact wrong reassurance.
  if [ -n "$ref" ] && [ "$reaches" = 1 ]; then
    if [ "$ref" = "$tag" ]; then
      printf '  %-22s %s\n' "users get" "$version — ref matches"
    else
      printf '  %-22s %s\n' "users get" "$ref — STALE, plugin.json is $version"
    fi
  elif [ -n "$ref" ]; then
    printf '  %-22s %s\n' "users get" "the repo root at $ref — not this plugin"
  fi
done
