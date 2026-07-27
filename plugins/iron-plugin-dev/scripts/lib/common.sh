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

# The marketplaces a release fans out to, as "name<TAB>manifest-path<TAB>repo"
# lines. Either of the last two may be empty.
#
# One plugin can be listed by several marketplaces — a private one for testing
# and a public one for release, say — and each names its own ref, so each is a
# separate switch to throw. Two files describe them, split by what is durable:
#
#   .claude/iron-plugin-dev.md         committed — which marketplaces publish
#                                      this repo, by `repo:` (owner/name)
#   .claude/iron-plugin-dev.local.md   gitignored — where your clones of them
#                                      live, by `path:`
#
#   ---
#   marketplaces:
#     - name: iron-plugins
#       repo: twmurphy/iron-plugins
#       path: S:/Vibe Coding/iron-plugins
#   ---
#
# The split matters because a repo that publishes through a marketplace it does
# not contain still needs to say so — a fresh clone with no local paths should
# report "not checked locally", never "no marketplace". Entries merge by name,
# so the committed file can name a marketplace the local one only locates.
#
# `path` is the repo holding .claude-plugin/marketplace.json; "." is this repo.
# With neither file, this repo's own manifest is the only target — the
# single-marketplace case, needing no configuration.
_parse_targets() {  # _parse_targets FILE ROOT
  awk -v root="$2" '
    function trim(s) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      gsub(/^["'"'"']|["'"'"']$/, "", s)
      return s
    }
    function emit() {
      if (name == "") return
      p = (path == ".") ? root : path
      # Unit separator, not tab: a field here is often empty, and tab is an IFS
      # whitespace character, so bash read would collapse the run and shift
      # every later field left.
      print name "\037" (p == "" ? "" : p "/.claude-plugin/marketplace.json") "\037" repo
      name = ""; path = ""; repo = ""
    }
    /^---[[:space:]]*$/ { fm = !fm; next }
    !fm { next }
    /^marketplaces:[[:space:]]*$/ { inlist = 1; next }
    inlist && /^[[:space:]]*-[[:space:]]*name:/ {
      emit(); sub(/^[[:space:]]*-[[:space:]]*name:/, ""); name = trim($0); next
    }
    inlist && /^[[:space:]]+path:/ { sub(/^[[:space:]]*path:/, ""); path = trim($0); next }
    inlist && /^[[:space:]]+repo:/ { sub(/^[[:space:]]*repo:/, ""); repo = trim($0); next }
    inlist && /^[^[:space:]#]/ { emit(); inlist = 0 }
    END { emit() }
  ' "$1"
}

marketplace_targets() {  # marketplace_targets ROOT
  local root="$1" rows=""
  local shared="$root/.claude/iron-plugin-dev.md"
  local local_file="$root/.claude/iron-plugin-dev.local.md"

  # $'\n' rather than "$(printf '\n')" — command substitution strips trailing
  # newlines, which would run the two files' rows together.
  [ -f "$shared" ]     && rows+="$(_parse_targets "$shared" "$root")"$'\n'
  [ -f "$local_file" ] && rows+="$(_parse_targets "$local_file" "$root")"$'\n'

  if [ -z "${rows//[[:space:]]/}" ]; then
    local own="$root/.claude-plugin/marketplace.json"
    [ -f "$own" ] || return 0
    printf '%s\037%s\037\n' "$(json_name "$own")" "$own"
    return 0
  fi

  # Merge by name, first-seen order. A later file fills in fields the earlier
  # one left blank, which is how the local file supplies paths for marketplaces
  # the committed file names.
  printf '%s\n' "$rows" | awk -F'\037' '
    $1 == "" { next }
    {
      if (!($1 in seen)) { seen[$1] = 1; order[++n] = $1 }
      if ($2 != "") path[$1] = $2
      if ($3 != "") repo[$1] = $3
    }
    END { for (i = 1; i <= n; i++) { k = order[i]; print k "\037" path[k] "\037" repo[k] } }
  '
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
