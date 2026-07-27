#!/usr/bin/env bash
# deploy-plugin/release-status: report what each plugin would release and what
# each marketplace's users currently get. Read-only; changes nothing.
#
#   release-status.sh                 every marketplace target
#   release-status.sh iron-plugins    only the named ones
#
# The version and the tag are shared; only the ref differs per marketplace. That
# is what lets one marketplace hold a stable release while another carries a
# pre-release of the same plugin — and it makes each ref a separate switch.
set -euo pipefail
shopt -s nullglob

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/scripts/lib/common.sh"

root="$(find_root)" || die "no plugin repo at $(pwd -P) or any parent"
[ -d "$root/plugins" ] || die "no plugins/ directory at $root"

targets="$(marketplace_targets "$root")"
[ -n "$targets" ] || die "no marketplace — add .claude-plugin/marketplace.json to this repo, or list one by URL in .claude/iron-plugin-dev.md"

# Limit to the marketplaces named on the command line, when any were.
if [ "$#" -gt 0 ]; then
  targets="$(printf '%s\n' "$targets" | awk -F'\037' -v w="$(printf '%s\n' "$@")" '
    BEGIN { n = split(w, a, "\n"); for (i = 1; i <= n; i++) keep[a[i]] = 1 }
    keep[$1]')"
  [ -n "$targets" ] || die "no marketplace target matched: $*"
fi

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
printf '  %-17s %s\n' "marketplaces" "$(printf '%s\n' "$targets" | cut -d"$(printf '\037')" -f1 | tr '\n' ' ')"

for dir in "$root"/plugins/*/; do
  name="$(basename "$dir")"
  manifest="${dir}.claude-plugin/plugin.json"
  [ -f "$manifest" ] || continue

  version="$(json_field "$manifest" version)"
  [ -n "$version" ] || version="(none)"
  tag="$name--v$version"

  echo
  echo "$name"
  printf '  %-22s %s\n' "plugin.json version" "$version"

  if [ "$git_ok" = 1 ]; then
    if git -C "$root" rev-parse -q --verify "refs/tags/$tag" >/dev/null 2>&1; then
      printf '  %-22s %s (exists)\n' "release tag" "$tag"
    else
      printf '  %-22s %s (not created yet)\n' "release tag" "$tag"
    fi
  fi

  # One line per marketplace. The ref each names decides what its own users
  # receive, independently of every other marketplace listing this plugin.
  while IFS="$(printf '\037')" read -r mkt manifest url; do
    [ -n "${mkt:-}" ] || continue

    # A remote marketplace is read from a clone this plugin keeps itself, so a
    # URL is all the configuration a release needs.
    if [ -z "${manifest:-}" ]; then
      checkout="$(marketplace_checkout "$url")" || {
        printf '  %-22s %s\n' "$mkt" "$url — could not clone, ref unknown"
        continue
      }
      manifest="$checkout/.claude-plugin/marketplace.json"
    fi

    if [ ! -f "$manifest" ]; then
      printf '  %-22s %s\n' "$mkt" "no marketplace.json in $mkt"
      continue
    fi

    row="$(entry_ref "$manifest" "$name")"
    if [ -z "$row" ]; then
      printf '  %-22s %s\n' "$mkt" "does not list this plugin"
      continue
    fi

    kind="$(printf '%s' "$row" | cut -f1)"
    ref="$(printf '%s' "$row" | cut -f2)"
    entry_version="$(printf '%s' "$row" | cut -f3)"

    case "$kind" in
      git-subdir)
        if [ -z "$ref" ]; then
          printf '  %-22s %s\n' "$mkt" "UNPINNED (tracks default branch)"
        elif [ "$ref" = "$tag" ]; then
          printf '  %-22s %s\n' "$mkt" "$ref — users get $version, ref matches"
        else
          printf '  %-22s %s\n' "$mkt" "$ref — STALE, plugin.json is $version"
        fi
        ;;
      github|url)
        printf '  %-22s %s\n' "$mkt" "$kind · installs the REPO ROOT, not plugins/$name"
        printf '  %-22s %s\n' "" "needs git-subdir — adding a path here is silently dropped"
        ;;
      npm)  printf '  %-22s %s\n' "$mkt" "npm · released through the registry, not this repo" ;;
      path) printf '  %-22s %s\n' "$mkt" "path · local, cannot ship to anyone" ;;
      *)    printf '  %-22s %s\n' "$mkt" "$kind" ;;
    esac

    if [ -n "$entry_version" ] && [ "$entry_version" != "$version" ]; then
      printf '  %-22s %s\n' "" "entry version $entry_version disagrees — tagging refuses until it matches"
    fi
  done <<< "$targets"
done
