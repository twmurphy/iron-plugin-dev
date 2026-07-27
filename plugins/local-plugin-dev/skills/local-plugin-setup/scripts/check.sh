#!/usr/bin/env bash
# local-plugin-setup/check: report how every plugin under plugins/ is wired up —
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

# `claude plugin list --json` is the authority on what is installed and at which
# scope. node does the parsing because jq is not a given, while node ships with
# Claude Code itself. Emits one "name<TAB>id<TAB>scope" line per install.
claude_installs() {
  command -v claude >/dev/null 2>&1 || return 0
  command -v node   >/dev/null 2>&1 || return 0
  claude plugin list --json 2>/dev/null | node -e '
    let raw = "";
    process.stdin.on("data", chunk => raw += chunk);
    process.stdin.on("end", () => {
      let list;
      try { list = JSON.parse(raw); } catch { return; }
      if (!Array.isArray(list)) return;
      for (const p of list) {
        if (p && typeof p.id === "string") {
          console.log([p.id.split("@")[0], p.id, p.scope || "unknown"].join("\t"));
        }
      }
    });
  ' 2>/dev/null
}

installs="$(claude_installs)"
if [ -z "$installs" ]; then
  note "install scopes unavailable — the claude CLI is not on PATH"
fi

echo "Repo: $root"
echo

total=0; linked=0; user_scope=0; stale=0
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

  where="$(printf '%s\n' "$installs" | awk -F'\t' -v n="$name" \
             '$1 == n { printf "%s (%s) ", $3, $2 }')"
  where="${where% }"
  [ -n "$where" ] || where="none"
  case "$where" in *user\ \(*) user_scope=$((user_scope + 1)) ;; esac

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
echo "Summary: $total $noun, $linked linked, $user_scope at user scope, $stale stale."
