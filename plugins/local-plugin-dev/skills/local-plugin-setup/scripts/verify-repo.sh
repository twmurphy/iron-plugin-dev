#!/usr/bin/env bash
# local-plugin-setup/verify-repo: confirm the repo is a plugin repo in good order —
# a marketplace manifest, a plugins/ directory, and every plugin joined to the
# manifest in both directions. Read-only; changes nothing.
#
# `claude plugin validate` checks each manifest in isolation and never compares
# them, so a plugin missing from marketplace.json passes validation and installs
# nothing. That join is what this checks.
set -euo pipefail
shopt -s nullglob

# The lib sits at the plugin root, shared with the deploy-plugin skill.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/scripts/lib/common.sh"

problems=0
fail() { printf '  %-32s %s\n' "$1" "$2"; problems=$((problems + 1)); }
pass() { printf '  %-32s %s\n' "$1" "$2"; }

root="$(find_root)" || {
  echo "No plugin repo found at $(pwd -P) or any parent."
  echo "Neither .claude-plugin/marketplace.json nor plugins/ exists above here."
  echo "See references/scaffold.md for the layout."
  exit 1
}

echo "Repo: $root"
echo

# --- The two halves of the scaffold ------------------------------------------
market="$root/.claude-plugin/marketplace.json"
market_name=""
if [ -f "$market" ]; then
  market_name="$(json_name "$market")"
  if [ -n "$market_name" ]; then
    pass ".claude-plugin/marketplace.json" "ok — marketplace \"$market_name\""
  else
    fail ".claude-plugin/marketplace.json" "unreadable or missing a name field"
  fi
else
  fail ".claude-plugin/marketplace.json" "missing"
fi

if [ -d "$root/plugins" ]; then
  pass "plugins/" "ok"
else
  fail "plugins/" "missing"
fi

# Plugin names listed in the manifest, one per line.
listed() {
  [ -n "$market_name" ] || return 0
  node -e '
    let raw = "";
    process.stdin.on("data", chunk => raw += chunk);
    process.stdin.on("end", () => {
      let j;
      try { j = JSON.parse(raw); } catch { return; }
      for (const p of (j && j.plugins) || []) {
        if (p && typeof p.name === "string") console.log(p.name);
      }
    });
  ' < "$market" 2>/dev/null
}
entries="$(listed)"

echo

# --- Every plugin directory, joined to the manifest ---------------------------
found=0
for dir in "$root"/plugins/*/; do
  name="$(basename "$dir")"
  found=$((found + 1))
  manifest="${dir}.claude-plugin/plugin.json"

  if [ ! -f "$manifest" ]; then
    fail "$name" "no .claude-plugin/plugin.json — not a plugin"
    continue
  fi

  declared="$(json_name "$manifest")"
  if [ -z "$declared" ]; then
    fail "$name" "plugin.json unreadable or missing a name field"
    continue
  fi
  if [ "$declared" != "$name" ]; then
    fail "$name" "plugin.json says \"$declared\" — must match the directory name"
    continue
  fi

  if printf '%s\n' "$entries" | grep -qx "$name"; then
    pass "$name" "plugin.json ok · listed in marketplace"
  else
    fail "$name" "plugin.json ok · NOT LISTED in marketplace.json"
  fi
done

# Only worth saying when plugins/ is there to be empty; a missing plugins/ is
# already counted above and the same problem twice reads as two.
if [ -d "$root/plugins" ] && [ "$found" = 0 ]; then
  fail "plugins/" "holds no plugin directories"
fi

# --- Manifest entries pointing at nothing ------------------------------------
while read -r name; do
  [ -n "${name:-}" ] || continue
  [ -d "$root/plugins/$name" ] && continue
  fail "$name" "listed in marketplace.json · no plugins/$name directory"
done <<< "$entries"

echo
if [ "$problems" = 0 ]; then
  echo "Scaffold OK."
else
  echo "$problems problem(s). See references/scaffold.md for the layout."
  exit 1
fi
