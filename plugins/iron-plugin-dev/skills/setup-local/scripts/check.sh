#!/usr/bin/env bash
# setup-local/check: report how every plugin under plugins/ is wired up —
# whether .claude/skills/ links it, and whether Claude Code has it installed and
# at which scope. Read-only; changes nothing.
set -euo pipefail
shopt -s nullglob

# The lib sits at the plugin root, shared with the deploy-plugin skill.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/scripts/lib/common.sh"

root="$(find_root)" || die "no plugin repo at $(pwd -P) or any parent — run verify-repo.sh"
[ -d "$root/plugins" ] || die "no plugins/ directory at $root — run verify-repo.sh"
plugins="$root/plugins"
skills="$root/.claude/skills"

installs="$(shadowing_installs "$root")"
if [ -z "$installs" ]; then
  note "install scopes unavailable — the claude CLI is not on PATH"
fi

echo "Repo: $root"
echo

total=0; linked=0; shadowed=0; stale=0
for dir in "$plugins"/*/; do
  [ -f "${dir}.claude-plugin/plugin.json" ] || continue
  name="$(basename "$dir")"
  total=$((total + 1))

  link="$skills/$name"
  if is_link "$link"; then
    link_state="linked"; linked=$((linked + 1))
  elif [ -e "$link" ]; then
    link_state="blocked"   # a real directory sits on the name
  else
    link_state="missing"
  fi

  # The name matched a directory under plugins/, so any install at all is a
  # cached snapshot of the very folder being edited here. Scope decides where it
  # was declared, not whether it shadows — a project-scope install serves the
  # same frozen copy a user-scope one does.
  where="$(printf '%s\n' "$installs" | awk -F'\t' -v n="$name" \
             '$1 == n { printf "%s (%s) ", $3, $2 }')"
  where="${where% }"
  if [ -n "$where" ]; then
    where="$where — SHADOWS the link"
    shadowed=$((shadowed + 1))
  else
    where="none"
  fi

  printf '  %-24s link: %-8s install: %s\n' "$name" "$link_state" "$where"
done

# Links whose plugin is gone. They keep serving a folder that no longer backs a
# plugin, so they are worth naming even though nothing here removes them.
for entry in "$skills"/*; do
  name="$(basename "$entry")"
  [ -f "$plugins/$name/.claude-plugin/plugin.json" ] && continue
  if is_link "$entry"; then
    printf '  %-24s link: stale    install: —\n' "$name"
    stale=$((stale + 1))
  fi
done

echo
if [ "$total" = 1 ]; then noun="plugin"; else noun="plugins"; fi
echo "Summary: $total $noun, $linked linked, $shadowed shadowed by an install, $stale stale."
