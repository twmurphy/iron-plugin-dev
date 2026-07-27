#!/usr/bin/env bash
# setup-local/link: give every plugin under plugins/ one entry in
# .claude/skills/ pointing at its folder, and drop entries whose plugin is gone.
#
# Windows gets a junction (no elevation needed); everything else gets a symlink.
# Anything in .claude/skills/ that is a real directory — hand-made project
# skills among them — is left alone, so the set of links tracks plugins/ exactly
# and nothing else is at risk.
set -euo pipefail
shopt -s nullglob

# The lib sits at the plugin root, shared with the deploy-plugin skill.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/scripts/lib/common.sh"

root="$(find_root)" || die "no plugin repo at $(pwd -P) or any parent — run verify-repo.sh"
[ -d "$root/plugins" ] || die "no plugins/ directory at $root — run verify-repo.sh"
plugins="$root/plugins"
skills="$root/.claude/skills"

mkdir -p "$skills"

echo "Linking plugins into $skills"

# A stale link of either type is rebuilt rather than inspected, which is cheaper
# than comparing targets and always lands correct. A real directory sitting on a
# plugin's name is reported, never replaced.
linked=0
for dir in "$plugins"/*/; do
  [ -f "${dir}.claude-plugin/plugin.json" ] || continue
  name="$(basename "$dir")"
  link="$skills/$name"
  if is_link "$link"; then
    remove_link "$link"
  elif [ -e "$link" ]; then
    note "skip $name — a real directory sits at .claude/skills/$name, leaving it"
    continue
  fi
  make_link "$plugins/$name" "$link"
  note "linked $name -> plugins/$name"
  linked=$((linked + 1))
done

# Prune to 1:1. Remove any link whose plugin is gone; keep live plugins and
# leave every real directory — the whole reason unrelated skills survive here.
pruned=0
for entry in "$skills"/*; do
  name="$(basename "$entry")"
  [ -f "$plugins/$name/.claude-plugin/plugin.json" ] && continue
  if is_link "$entry"; then
    remove_link "$entry"
    note "removed stale $name (no plugin by that name)"
    pruned=$((pruned + 1))
  fi
done

# An installed copy of a plugin that also lives here is a frozen snapshot in the
# plugin cache, and it wins over the link just made — so linking without
# removing it changes nothing the user can see. Uninstall, and say so loudly:
# this is the one step that takes something away, and the same plugin may be
# wanted as a normal install in other projects.
removed=0
installs="$(shadowing_installs "$root")"
if [ -n "$installs" ]; then
  while IFS="$(printf '\t')" read -r pname pid pscope pproject; do
    [ -n "${pname:-}" ] || continue
    [ -f "$plugins/$pname/.claude-plugin/plugin.json" ] || continue
    if claude plugin uninstall "$pid" --scope "$pscope" -y >/dev/null 2>&1; then
      echo
      echo "  UNINSTALLED $pid (was $pscope scope)"
      echo "    It shadowed the link: an install is a frozen copy, so edits here"
      echo "    would not have taken effect while it was present."
      echo "    This affects THIS repo only. To use the released plugin in another"
      echo "    project, install it there:"
      echo "      claude plugin install $pid --scope project"
      removed=$((removed + 1))
    else
      echo
      echo "  COULD NOT UNINSTALL $pid ($pscope scope) — it will shadow the link."
      echo "    Remove it by hand:  claude plugin uninstall $pid --scope $pscope"
    fi
  done <<< "$installs"
fi

echo
echo "Done: $linked linked, $pruned pruned, $removed uninstalled."
[ "$removed" = 0 ] || echo "Restart Claude Code to pick up the linked copies."
