# Shared by every skill script in this plugin — sourced, never run directly.
#
# Holds the things those scripts need and none should restate: where the
# repo is, and how to make/inspect/remove a link on this platform.

die()  { echo "iron-plugin-dev: $*" >&2; exit 1; }
note() { echo "  $*"; }

# Locate the repo by walking up from the working directory. These scripts ship
# inside an installed plugin, so their own path sits in the plugin cache and
# says nothing about where the repo being developed lives.
#
# Either half of the scaffold anchors the search — the marketplace manifest or
# the plugins/ directory. Finding one half of a broken repo beats finding
# nothing, because naming the missing half is verify-repo.sh's whole job.
# Returns 1 when neither appears anywhere above the working directory.
find_root() {
  local dir
  dir="$(pwd -P)"
  while [ "$dir" != "/" ] && [ "$dir" != "." ]; do
    if [ -f "$dir/.claude-plugin/marketplace.json" ] || [ -d "$dir/plugins" ]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

# Reads one top-level string field of a JSON manifest, empty when absent or the
# file will not parse. node does the parsing because jq is not a given, while
# node ships with Claude Code itself.
json_field() {  # json_field FILE FIELD
  node -e '
    let raw = "";
    process.stdin.on("data", chunk => raw += chunk);
    process.stdin.on("end", () => {
      try {
        const j = JSON.parse(raw);
        const v = j && j[process.argv[1]];
        if (typeof v === "string") console.log(v);
      } catch {}
    });
  ' "$2" < "$1" 2>/dev/null
}

json_name() { json_field "$1" name; }

# The marketplaces a release fans out to, as "name<TAB>manifest-path" lines.
#
# One plugin can be listed by several marketplaces — a private one for testing
# and a public one for release, say — and each names its own ref, so each is a
# separate switch to throw. Targets come from .claude/iron-plugin-dev.local.md:
#
#   ---
#   marketplaces:
#     - name: iron-plugin-dev
#       path: .
#     - name: iron-plugins
#       path: S:/Vibe Coding/skills
#   ---
#
# `path` is the repo holding .claude-plugin/marketplace.json; "." is this repo.
# With no settings file the repo's own manifest is the only target, which is the
# single-marketplace case and needs no configuration.
marketplace_targets() {  # marketplace_targets ROOT
  local root="$1" settings="$1/.claude/iron-plugin-dev.local.md"

  if [ ! -f "$settings" ]; then
    local own="$root/.claude-plugin/marketplace.json"
    [ -f "$own" ] || return 0
    printf '%s\t%s\n' "$(json_name "$own")" "$own"
    return 0
  fi

  awk -v root="$root" '
    function trim(s) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      gsub(/^["'"'"']|["'"'"']$/, "", s)
      return s
    }
    function emit() {
      if (name == "") return
      p = (path == "" || path == ".") ? root : path
      print name "\t" p "/.claude-plugin/marketplace.json"
      name = ""; path = ""
    }
    /^---[[:space:]]*$/ { fm = !fm; next }
    !fm { next }
    /^marketplaces:[[:space:]]*$/ { inlist = 1; next }
    inlist && /^[[:space:]]*-[[:space:]]*name:/ {
      emit(); sub(/^[[:space:]]*-[[:space:]]*name:/, ""); name = trim($0); next
    }
    inlist && /^[[:space:]]+path:/ { sub(/^[[:space:]]*path:/, ""); path = trim($0); next }
    inlist && /^[^[:space:]#]/ { emit(); inlist = 0 }
    END { emit() }
  ' "$settings"
}

# The name a marketplace entry gives a plugin's ref, empty when unlisted.
entry_ref() {  # entry_ref MANIFEST PLUGIN
  node -e '
    let raw = "";
    process.stdin.on("data", chunk => raw += chunk);
    process.stdin.on("end", () => {
      let j;
      try { j = JSON.parse(raw); } catch { return; }
      for (const p of (j && j.plugins) || []) {
        if (p && p.name === process.argv[1]) {
          const s = p.source;
          const kind = typeof s === "string" ? "path" : (s && s.source) || "none";
          console.log([kind, (s && typeof s === "object" && s.ref) || "", p.version || ""].join("\t"));
          return;
        }
      }
    });
  ' "$2" < "$1" 2>/dev/null
}

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) windows=1 ;;
  *)                    windows=0 ;;
esac

# On Windows the link primitives go through native tools: cmd for mklink/rmdir
# and PowerShell to read a reparse point, because a junction is invisible to
# bash's own -L test. cygpath hands them backslashed absolute paths.
win() { cygpath -w "$1"; }

is_link() {
  if [ "$windows" = 1 ]; then
    [ "$(powershell.exe -NoProfile -NonInteractive -Command \
          "\$i = Get-Item -LiteralPath '$(win "$1")' -Force -ErrorAction SilentlyContinue; if (\$i -and \$i.LinkType) { 'yes' }" \
          2>/dev/null | tr -d '\r')" = yes ]
  else
    [ -L "$1" ]
  fi
}

make_link() {  # make_link TARGET LINK
  if [ "$windows" = 1 ]; then
    cmd //c mklink //J "$(win "$2")" "$(win "$1")" >/dev/null \
      || die "could not create junction at $2"
  else
    ln -s "$1" "$2"
  fi
}

remove_link() {  # removes the link only; the plugin folder it points at is left alone
  if [ "$windows" = 1 ]; then
    cmd //c rmdir "$(win "$1")" >/dev/null 2>&1 || die "could not remove link $1"
  else
    rm -f "$1"
  fi
}
