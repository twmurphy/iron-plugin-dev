#!/usr/bin/env bash
# setup-local/verify-repo: confirm the repo is a plugin repo in good order — a
# plugins/ directory, at least one marketplace naming what is in it, and every
# plugin joined to a marketplace. Read-only; changes nothing.
#
# `claude plugin validate` checks each manifest in isolation and never compares
# them, so a plugin no marketplace lists passes validation and installs nothing.
# That join is what this checks, across every configured marketplace.
set -euo pipefail
shopt -s nullglob

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

# --- plugins/ ----------------------------------------------------------------
if [ -d "$root/plugins" ]; then
  pass "plugins/" "ok"
else
  fail "plugins/" "missing"
fi

# --- The marketplaces this repo publishes through ----------------------------
# Usually just the one at the repo root. A settings file can name others, which
# is how a plugin reaches a private channel and a public one at the same time.
targets="$(marketplace_targets "$root")"
remote_only=0
if [ -z "$targets" ]; then
  fail ".claude-plugin/marketplace.json" "missing, and no marketplaces configured"
else
  while IFS="$(printf '')" read -r mkt manifest url; do
    [ -n "${mkt:-}" ] || continue
    if [ -n "${manifest:-}" ]; then
      if [ -z "$(json_name "$manifest")" ]; then
        fail "marketplace $mkt" "unreadable or missing a name field"
      else
        pass "marketplace $mkt" "in this repo"
      fi
    else
      # Remote. Checking the join would mean cloning, which a scaffold check has
      # no business doing — deploy-plugin reads remote refs, this does not.
      pass "marketplace $mkt" "$url — remote, not checked here"
      remote_only=1
    fi
  done <<< "$targets"
fi

# Plugin names each in-repo marketplace lists, as "marketplace<TAB>plugin".
listed() {
  while IFS="$(printf '')" read -r mkt manifest url; do
    [ -n "${mkt:-}" ] && [ -n "${manifest:-}" ] && [ -f "$manifest" ] || continue
    node -e '
      let raw = "";
      process.stdin.on("data", chunk => raw += chunk);
      process.stdin.on("end", () => {
        let j;
        try { j = JSON.parse(raw); } catch { return; }
        for (const p of (j && j.plugins) || []) {
          if (p && typeof p.name === "string") console.log(process.argv[1] + "	" + p.name);
        }
      });
    ' "$mkt" < "$manifest" 2>/dev/null
  done <<< "$targets"
}
entries="$(listed)"

echo

# --- Every plugin directory, joined to at least one marketplace ---------------
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

  in="$(printf '%s\n' "$entries" | awk -F'\t' -v n="$name" '$2 == n { printf "%s ", $1 }')"
  if [ -n "$in" ]; then
    pass "$name" "plugin.json ok · listed in ${in% }"
  elif [ "$remote_only" = 1 ]; then
    pass "$name" "plugin.json ok · join not checked, marketplaces are remote"
  else
    fail "$name" "plugin.json ok · NOT LISTED in any marketplace"
  fi
done

if [ -d "$root/plugins" ] && [ "$found" = 0 ]; then
  fail "plugins/" "holds no plugin directories"
fi

# --- Entries in this repo's own manifest pointing at nothing -------------------
# Only the repo's own marketplace is checked this way. A shared marketplace
# legitimately lists plugins living in other repos, so a name with no directory
# here says nothing about it.
own="$root/.claude-plugin/marketplace.json"
if [ -f "$own" ]; then
  own_name="$(json_name "$own")"
  while IFS="$(printf '\t')" read -r mkt plugin; do
    [ -n "${plugin:-}" ] && [ "$mkt" = "$own_name" ] || continue
    [ -d "$root/plugins/$plugin" ] && continue
    fail "$plugin" "listed in this repo's marketplace · no plugins/$plugin directory"
  done <<< "$entries"
fi

echo
if [ "$problems" = 0 ]; then
  echo "Scaffold OK."
else
  echo "$problems problem(s). See references/scaffold.md for the layout."
  exit 1
fi
