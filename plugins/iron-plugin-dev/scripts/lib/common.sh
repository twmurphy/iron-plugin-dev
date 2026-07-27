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

# The marketplaces this repo publishes through, as "name<US>manifest<US>url"
# lines, where <US> is the unit separator and exactly one of manifest/url is set.
#
# Two kinds of target:
#   local   the repo's own .claude-plugin/marketplace.json — needs no config
#   remote  a marketplace living in another repo, named by URL in
#           .claude/iron-plugin-dev.md, which is committed so the list of
#           destinations travels with the repo
#
#   ---
#   marketplaces:
#     - name: iron-plugins
#       url: https://github.com/twmurphy/iron-plugins.git
#   ---
#
# Nothing here records a filesystem path. A URL is enough: reading or moving a
# remote marketplace's ref works from a clone this plugin makes itself, so there
# is no per-machine state to configure, lose, or leave out of git.
marketplace_targets() {  # marketplace_targets ROOT
  local root="$1"
  local own="$root/.claude-plugin/marketplace.json"
  local cfg="$root/.claude/iron-plugin-dev.md"

  [ -f "$own" ] && printf '%s\037%s\037\n' "$(json_name "$own")" "$own"
  [ -f "$cfg" ] || return 0

  awk '
    function trim(s) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      gsub(/^["'"'"']|["'"'"']$/, "", s)
      return s
    }
    function emit() {
      if (name != "" && url != "") print name "\037" "\037" url
      name = ""; url = ""
    }
    /^---[[:space:]]*$/ { fm = !fm; next }
    !fm { next }
    /^marketplaces:[[:space:]]*$/ { inlist = 1; next }
    inlist && /^[[:space:]]*-[[:space:]]*name:/ {
      emit(); sub(/^[[:space:]]*-[[:space:]]*name:/, ""); name = trim($0); next
    }
    inlist && /^[[:space:]]+url:/ { sub(/^[[:space:]]*url:/, ""); url = trim($0); next }
    inlist && /^[^[:space:]#]/ { emit(); inlist = 0 }
    END { emit() }
  ' "$cfg"
}

# A working copy of a remote marketplace, cloned once and refreshed after.
# Echoes the checkout path. Reading a ref and moving one both need the repo on
# disk, and keeping the clone out of the user's tree means no stray directories
# and nothing to configure.
marketplace_checkout() {  # marketplace_checkout URL
  local url="$1"
  local slug cache
  slug="$(printf '%s' "$url" | tr -c 'A-Za-z0-9._-' '_')"
  cache="${HOME}/.iron-plugin-dev/marketplaces/$slug"

  if [ -d "$cache/.git" ]; then
    git -C "$cache" fetch --quiet --depth 1 origin HEAD 2>/dev/null || return 1
    git -C "$cache" reset --quiet --hard FETCH_HEAD 2>/dev/null || return 1
  else
    mkdir -p "$(dirname "$cache")"
    git clone --quiet --depth 1 "$url" "$cache" 2>/dev/null || return 1
  fi
  echo "$cache"
}

# One comparable spelling for a path: forward slashes, lowercased, no trailing
# slash. Claude Code reports Windows paths ("S:\dir"); the shell has POSIX ones
# ("/s/dir"). cygpath bridges them so the two can be compared at all.
norm_path() {
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then
    p="$(cygpath -w "$p" 2>/dev/null || printf '%s' "$p")"
  fi
  printf '%s' "$p" | tr 'A-Z\\' 'a-z/' | sed 's|/*$||'
}

# Plugins Claude Code has installed, as "name<TAB>id<TAB>scope<TAB>project".
# `claude plugin list --json` is the authority; node parses because jq is not a
# given while node ships with Claude Code itself.
#
# `claude plugin list` returns project-scope installs for every project, not
# just this one, so the project field decides which are ours — see
# shadowing_installs.
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
          console.log([p.id.split("@")[0], p.id, p.scope || "unknown", p.projectPath || ""].join("\t"));
        }
      }
    });
  ' 2>/dev/null
}

# Installs that actually shadow this repo, same fields as claude_installs.
#
# An install shadows only when its copy would load here: a user-scope install
# applies everywhere, while a project- or local-scope one belongs to the project
# it was made in and is no business of ours when that project is elsewhere.
shadowing_installs() {  # shadowing_installs ROOT
  local root_n
  root_n="$(norm_path "$1")"
  claude_installs | while IFS="$(printf '\t')" read -r name id scope project; do
    [ -n "${name:-}" ] || continue
    case "${scope:-}" in
      user) ;;
      *) [ -n "${project:-}" ] && [ "$(norm_path "$project")" = "$root_n" ] || continue ;;
    esac
    printf '%s\t%s\t%s\t%s\n' "$name" "$id" "$scope" "$project"
  done
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
