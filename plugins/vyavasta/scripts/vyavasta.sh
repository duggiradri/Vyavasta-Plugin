#!/bin/sh
# Vyavasta for Claude Code and Codex: the hooks the coding tool runs, and the commands a developer gives it.
#
# Written for POSIX sh with git, curl and awk only. Claude Code runs a hook's command through sh on macOS and
# Linux and through Git Bash on Windows; this plugin needs git, and on Windows git comes as Git for Windows,
# which brings Git Bash, curl and awk with it. No Python, Node or jq is assumed.
#
# The plugin is off in every project until the developer sends “vyavasta on” there; off, a hook sends nothing: only
# the plugin's own commands are answered, a message that asks how to use Vyavasta gives the tool's model the phrases
# to tell the developer, and the first session on a computer that isn't signed in starts signing in. While that
# sign-in waits for approval, each message asks the server once whether it was approved, sending only the sign-in's
# own reference, never the message.
#
# What it sends from a project that is on: the words of each message to the check, the repository's GitHub remote
# (without any credentials in it), the branch, the tool's session id, and for each changed file its path, git's
# status and line counts. With code sharing on (off until the developer turns it on), also the uncommitted changes
# themselves, never from files git ignores, files that look like keys, machine-written files or files that are
# not text. A message that asks about the team is sent on as a question to the developer's own assistant in
# Vyavasta. With summaries on (on until the developer turns them off), each message and the tool's last reply of
# the turn, as written, are kept in the session's own chat in Vyavasta, to be summed up for teammates; a reply can
# quote code or what a file holds. Never the conversation transcript, the tool's other steps, the commands it ran,
# the files it read, or environment variables. Every failure is quiet and lets the tool
# go on: our server being down never stops the developer's work, and no error of a command is ever printed.

umask 077
LC_ALL=C
export LC_ALL
# Every git command here only reads the developer's repository: none may refresh or rewrite their index, or take
# its lock while they or the tool run git themselves.
GIT_OPTIONAL_LOCKS=0
export GIT_OPTIONAL_LOCKS
# The plugin was called Vyavastha before it became Vyavasta. A setting in the environment given under its earlier name
# (VYAVASTHA_HOME, VYAVASTHA_SERVER, ...) is still taken wherever the new one (VYAVASTA_...) isn't set.
VYAVASTA_DEBUG="${VYAVASTA_DEBUG:-${VYAVASTHA_DEBUG:-}}"
VYAVASTA_TOOL="${VYAVASTA_TOOL:-${VYAVASTHA_TOOL:-}}"
VYAVASTA_HOME="${VYAVASTA_HOME:-${VYAVASTHA_HOME:-}}"
VYAVASTA_SERVER="${VYAVASTA_SERVER:-${VYAVASTHA_SERVER:-}}"
VYAVASTA_BROWSER="${VYAVASTA_BROWSER:-${VYAVASTHA_BROWSER:-}}"
VYAVASTA_SESSION="${VYAVASTA_SESSION:-${VYAVASTHA_SESSION:-}}"
# Nothing a command writes to its error output ever reaches the developer or the tool: each failure has its own
# plain sentence instead.
[ -n "${VYAVASTA_DEBUG:-}" ] || exec 2>/dev/null

VERSION="0.5.0"
DEFAULT_SERVER="https://vyavasta.com"
PHRASE="Plan it anyway"
# Which coding tool runs this script: its hooks file says so (Codex's sets VYAVASTA_TOOL=codex). The tool's own name,
# what its model is called, and how its developer gives this plugin a command.
case "${VYAVASTA_TOOL:-}" in
  codex)
    CLIENT="codex"; TOOL="Codex"; AGENT="Codex"; VERB="Send"; CMD_SIGN_OUT="“vyavasta sign out”" ;;
  *)
    CLIENT="claude-code"; TOOL="Claude Code"; AGENT="Claude"; VERB="Run"; CMD_SIGN_OUT="/vyavasta:sign-out" ;;
esac
# The way in, said the same way in every sentence about being signed out, in both tools: a message of its own, which
# the plugin answers itself (in Claude Code the slash command does the same).
WAY_IN="Send “vyavasta sign in” to connect."
WAY_IN_AGAIN="Send “vyavasta sign in” to connect again."
# This script, by its full path: what the tool's model is told to run to ask Vyavasta a question.
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
case "$CLIENT" in codex) ASK_WITH="VYAVASTA_TOOL=codex sh \"$SELF\" ask" ;; *) ASK_WITH="sh \"$SELF\" ask" ;; esac
# Where the sign-in and the settings are kept: VYAVASTA_HOME when it is set, else vyavasta in the config folder. A
# computer the plugin was used on before the rename has them in the config folder's vyavastha: that folder is used for
# as long as no vyavasta folder is there, so nobody is signed out by the rename.
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
if [ -n "$VYAVASTA_HOME" ]; then HOME_DIR="$VYAVASTA_HOME"
elif [ ! -d "$CONFIG_DIR/vyavasta" ] && [ -d "$CONFIG_DIR/vyavastha" ]; then HOME_DIR="$CONFIG_DIR/vyavastha"
else HOME_DIR="$CONFIG_DIR/vyavasta"; fi
CREDENTIALS="$HOME_DIR/credentials"
PENDING="$HOME_DIR/pairing"
SESSIONS="$HOME_DIR/sessions"
PROJECTS="$HOME_DIR/projects"
# How long a check may take (a real model reads the record), a report, and anything else.
CHECK_SECONDS=75
# How long one call for the answer to a question may take, and for how long in all calls go on waiting for an
# answer that is not ready: the assistant may read the record and look things up, and no call stays open for long.
ASK_SECONDS=55
ASK_AGAIN=5
WAIT_FOR=240
REPORT_SECONDS=8
QUICK_SECONDS=8
# A session's start may take 15 seconds in all, so each call it makes is shorter than that.
START_SECONDS=4
# How long a sign-in's code lasts, unless the server says it lasts less.
PAIR_LASTS=600
# Sending the turn's reply at its end never holds the tool up for longer than this.
TURN_SECONDS=4
# A report after an edit waits this long after the last one; once the server can't be reached, nothing is tried
# again for this long.
REPORT_EVERY=10
OFFLINE_FOR=60
# How much of the uncommitted changes is sent at most, unless the server says otherwise, and the longest line.
CHANGE_LINES=5000
CHANGE_BYTES=600000
LONGEST_LINE=2000
# How much of the tool's reply at the end of a turn is kept for the developer's summary, in characters.
REPLY_CHARACTERS=4000
EMPTY_TREE="4b825dc642cb6eb9a060e54bf8d69288fbee4904"
STARTED_AT=$(date +%s)

# The one check that runs after every edit in Claude Code: whether a conflict is waiting to be told. It costs a
# file test when there is none, so it is answered before anything else is set up.
if [ "${1:-}" = "hook" ] && [ "${2:-}" = "edit-check" ]; then
  set -- "$SESSIONS"/*/conflict-stop
  if [ ! -f "$1" ]; then cat >/dev/null; exit 0; fi
  id=$(head -c 65536 | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([A-Za-z0-9_-]*\)".*/\1/p' | sed -n '1p')
  id=$(printf '%s' "$id" | cut -c1-80)
  [ -n "$id" ] || id="no-session"
  if [ -f "$SESSIONS/$id/conflict-stop" ]; then
    cat "$SESSIONS/$id/conflict-stop"
    rm -f "$SESSIONS/$id/conflict-stop" "$SESSIONS/$id/conflict-say"
  fi
  exit 0
fi

TMP=$(mktemp -d 2>/dev/null || mktemp -d -t vyavasta 2>/dev/null)
if [ -z "$TMP" ] || [ ! -d "$TMP" ]; then
  # No folder for scratch files at all: a sandbox (Codex's keeps its model's commands to the workspace).
  TMP="$HOME_DIR/tmp.$$"
  mkdir -p "$TMP" || {
    if [ "${1:-}" = "ask" ] && [ "$CLIENT" = "codex" ]; then
      echo "Codex kept this command from reaching Vyavasta. The developer can ask the same thing by sending a message that starts with “Vyavasta,”."
    elif [ "${1:-}" != "hook" ]; then
      echo "This command couldn’t make a scratch folder, so it can’t run here. Send it as a message instead, such as “vyavasta check”."
    fi
    exit 0
  }
fi
trap 'rm -rf "$TMP"' EXIT
trap 'exit 0' INT TERM HUP

# -- JSON, with awk ---------------------------------------------------------------------------------------

# The raw value of a top-level key of the JSON object in a file: a string with its quotes and escapes as they
# are, a number, true/false/null, or a whole object or array. Nothing when the key isn't there.
json_get() {
  awk -v want="$2" '
    # Where the string that opens at p ends: the first quote after p that no backslash escapes. The quotes are
    # found once, by splitting the text at them, so a long string is passed over in one step.
    function strend(p,   lo, hi, mid) {
      lo = 1; hi = nq
      while (lo < hi) { mid = int((lo + hi) / 2); if (qpos[mid] <= p) lo = mid + 1; else hi = mid }
      while (lo < nq && (qpos[lo] <= p || qesc[lo])) lo++
      return (lo < nq) ? qpos[lo] : n
    }
    function valend(p,   ch, d, q) {
      ch = substr(s, p, 1)
      if (ch == "\"") return strend(p)
      if (ch == "{" || ch == "[") {
        d = 0; q = p
        while (q <= n) {
          ch = substr(s, q, 1)
          if (ch == "\"") { q = strend(q) + 1; continue }
          if (ch == "{" || ch == "[") d++
          else if (ch == "}" || ch == "]") { d--; if (d == 0) return q }
          q++
        }
        return n
      }
      q = p
      while (q <= n && substr(s, q, 1) !~ /[,}\] \t\r\n]/) q++
      return q - 1
    }
    BEGIN { RS = "\001" }
    NR == 1 {
      s = $0; n = length(s); i = 1; depth = 0; key = 0
      # qpos[k] is where the k-th quote is, and qesc[k] whether an odd run of backslashes escapes it.
      nq = split(s, part, /"/); at = 0
      for (k = 1; k < nq; k++) {
        at += length(part[k]) + 1; qpos[k] = at
        qesc[k] = match(part[k], /\\+$/) ? RLENGTH % 2 : 0
      }
      qpos[nq] = n + 1
      while (i <= n) {
        c = substr(s, i, 1)
        if (c == "\"") {
          j = strend(i)
          if (depth == 1 && key) {
            k = j + 1
            while (substr(s, k, 1) ~ /[ \t\r\n]/) k++
            if (substr(s, k, 1) == ":") {
              k++
              while (substr(s, k, 1) ~ /[ \t\r\n]/) k++
              e = valend(k)
              if (substr(s, i, j - i + 1) == "\"" want "\"") { printf "%s", substr(s, k, e - k + 1); exit }
              i = e + 1; key = 0; continue
            }
          }
          i = j + 1; continue
        }
        if (c == "{") { depth++; if (depth == 1) key = 1 }
        else if (c == "[") depth++
        else if (c == "}" || c == "]") depth--
        else if (c == "," && depth == 1) key = 1
        i++
      }
    }' "$1"
}

# A key of a JSON object given as text rather than in a file.
field() {
  printf '%s' "$1" > "$TMP/field"
  json_get "$TMP/field" "$2"
}

# Each element of a JSON array given as text, one to a line, as raw JSON.
json_rows() {
  printf '%s' "$1" | awk '
    BEGIN { RS = "\001" }
    NR == 1 {
      s = $0; n = length(s); i = 1
      while (i <= n && substr(s, i, 1) != "[") i++
      i++; depth = 0; start = 0
      while (i <= n) {
        c = substr(s, i, 1)
        if (c == "\"") {
          j = i + 1
          while (j <= n) { ch = substr(s, j, 1); if (ch == "\\") j += 2; else if (ch == "\"") break; else j++ }
          if (depth == 0) print substr(s, i, j - i + 1)
          i = j + 1; continue
        }
        if (c == "{" || c == "[") { if (depth == 0) start = i; depth++ }
        else if (c == "}" || c == "]") {
          if (depth == 0) break
          depth--
          if (depth == 0) { row = substr(s, start, i - start + 1); gsub(/[\r\n]/, " ", row); print row }
        }
        i++
      }
    }'
}

# A JSON string's text (the quotes taken off, its escapes undone): for ids, paths, words compared here, and an
# answer printed as it was written. The text is split at its backslashes once and each piece printed as it comes,
# so a long text with many escapes costs time in proportion to its length.
json_text() {
  printf '%s' "$1" | awk '
    function hex(h,   v, k, c) {
      v = 0; h = tolower(h)
      for (k = 1; k <= length(h); k++) { c = index("0123456789abcdef", substr(h, k, 1)); if (c == 0) return 63; v = v * 16 + c - 1 }
      return v
    }
    function utf8(u) {
      # Half of a pair that came alone is no character at all: the replacement character stands in for it.
      if (u >= 55296 && u <= 57343) u = 65533
      if (u < 128) return sprintf("%c", u)
      if (u < 2048) return sprintf("%c%c", 192 + int(u / 64), 128 + u % 64)
      if (u < 65536) return sprintf("%c%c%c", 224 + int(u / 4096), 128 + int(u / 64) % 64, 128 + u % 64)
      return sprintf("%c%c%c%c", 240 + int(u / 262144), 128 + int(u / 4096) % 64, 128 + int(u / 64) % 64, 128 + u % 64)
    }
    BEGIN { RS = "\001" }
    NR == 1 {
      s = $0
      if (substr(s, 1, 1) != "\"") { if (s != "null") printf "%s", s; exit }
      s = substr(s, 2, length(s) - 2)
      n = split(s, p, /\\/)
      printf "%s", p[1]
      i = 2
      while (i <= n) {
        piece = p[i]
        if (piece == "") {
          # An escaped backslash: the text after the second backslash is the next piece, as it is.
          printf "\\"
          if (i + 1 <= n) printf "%s", p[i + 1]
          i += 2
          continue
        }
        d = substr(piece, 1, 1); rest = substr(piece, 2)
        if (d == "n") printf "\n"; else if (d == "t") printf "\t"; else if (d == "r") printf "\r"
        else if (d == "b" || d == "f") printf " "
        else if (d == "u") {
          # \uXXXX, and a pair of them for a character beyond the first 65536, as the bytes of UTF-8.
          u = hex(substr(piece, 2, 4)); rest = substr(piece, 6)
          if (u >= 55296 && u <= 56319 && rest == "" && i < n && substr(p[i + 1], 1, 1) == "u") {
            low = hex(substr(p[i + 1], 2, 4))
            if (low >= 56320 && low <= 57343) { u = 65536 + (u - 55296) * 1024 + (low - 56320); i++; rest = substr(p[i], 6) }
          }
          printf "%s", utf8(u)
        } else printf "%s", d
        printf "%s", rest
        i++
      }
    }'
}

# The awk function that makes one line of text safe inside a JSON string: backslashes, quotes, tabs and carriage
# returns escaped, and other control characters made spaces. It works a line at a time, so text of any length
# costs time in proportion to its length.
AWK_ESCAPE='
  function esc(s,   n, p, i, o) {
    # (Each is split on with a pattern: some awks split a text on its line breaks too when given one character.)
    n = split(s, p, /\\/); o = p[1]; for (i = 2; i <= n; i++) o = o "\\\\" p[i]; s = o
    n = split(s, p, /"/); o = p[1]; for (i = 2; i <= n; i++) o = o "\\\"" p[i]; s = o
    n = split(s, p, /\t/); o = p[1]; for (i = 2; i <= n; i++) o = o "\\t" p[i]; s = o
    n = split(s, p, /\r/); o = p[1]; for (i = 2; i <= n; i++) o = o "\\r" p[i]; s = o
    n = split(s, p, /\n/); o = p[1]; for (i = 2; i <= n; i++) o = o "\\n" p[i]; s = o
    gsub(CONTROL, " ", s)
    return s
  }
  BEGIN { CONTROL = "[" sprintf("%c", 1) "-" sprintf("%c", 31) "]" }'

# Text as a JSON string, quotes and all.
json_quote() {
  printf '%s' "$1" | awk "$AWK_ESCAPE"'
    BEGIN { printf "\"" }
    { printf "%s%s", (NR > 1 ? "\\n" : ""), esc($0) }
    END { printf "\"" }'
}

# Text made safe for a web address's query.
url_quote() {
  printf '%s' "$1" | awk '
    BEGIN { RS = "\001"; for (i = 1; i < 256; i++) code[sprintf("%c", i)] = i }
    NR == 1 {
      for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)
        if (c ~ /[A-Za-z0-9._~-]/) printf "%s", c; else printf "%%%02X", code[c]
      }
    }'
}

# Whether version $1 is older than version $2 (numbers separated by dots).
older() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    n = split(a, x, "."); m = split(b, y, ".")
    for (i = 1; i <= (n > m ? n : m); i++) { if (x[i] + 0 < y[i] + 0) exit 0; if (x[i] + 0 > y[i] + 0) exit 1 }
    exit 1 }'
}

# -- where things are kept --------------------------------------------------------------------------------

# The server, as the developer set it: VYAVASTA_SERVER, else what `use-server` saved, else ours. Plain http only
# for this computer itself: a token never crosses a network unencrypted.
server_url() {
  url="${VYAVASTA_SERVER:-}"
  [ -z "$url" ] && [ -f "$HOME_DIR/server" ] && url=$(sed -n '1p' "$HOME_DIR/server")
  [ -z "$url" ] && url="$DEFAULT_SERVER"
  url=${url%/}
  case "$url" in
    https://*) ;;
    http://localhost|http://localhost:*|http://127.0.0.1|http://127.0.0.1:*) ;;
    *) return 1 ;;
  esac
  case "$url" in
    *[!A-Za-z0-9.:/_-]*) return 1 ;;
  esac
  printf '%s' "$url"
}

saved() { [ -f "$CREDENTIALS" ] && sed -n "s/^$1=//p" "$CREDENTIALS" | sed -n '1p'; }

# The token, only when it was given by the server now set: one server's token is never sent to another.
token_for() {
  [ -f "$CREDENTIALS" ] || return 0
  [ "$(saved server)" = "$1" ] && saved token
}

keep_credentials() {
  mkdir -p "$HOME_DIR" && chmod 700 "$HOME_DIR"
  {
    printf 'server=%s\n' "$1"
    printf 'token=%s\n' "$2"
    printf 'email=%s\n' "$3"
    printf 'workspace=%s\n' "$4"
  } > "$CREDENTIALS.new" && chmod 600 "$CREDENTIALS.new"
  mv -f "$CREDENTIALS.new" "$CREDENTIALS"
  forget_told
}

# What each project last told the server about code sharing belongs to one connection: the server forgets it when
# the connection ends, so a new one is told again with the next message.
forget_told() { rm -f "$PROJECTS"/*/sharing-told; }

# Whether a JSON list of repository names (as /me gives it) holds the repository $2, in any letter case, as GitHub
# itself matches names.
lists_repository() {
  case "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" in
    *"\"$(printf '%s' "$2" | tr 'A-Z' 'a-z')\""*) return 0 ;;
  esac
  return 1
}

session_dir() {
  id=$(printf '%s' "$1" | tr -cd 'A-Za-z0-9_-' | cut -c1-80)
  [ -n "$id" ] || id="no-session"
  dir="$SESSIONS/$id"
  mkdir -p "$dir" && chmod 700 "$SESSIONS"
  printf '%s' "$dir"
}

# Whether the settings folder can be written: a sandbox may forbid it.
writable() {
  mkdir -p "$HOME_DIR" && true > "$HOME_DIR/.written" && rm -f "$HOME_DIR/.written"
}

now() { date +%s; }

# Whether the server was found out of reach a moment ago: nothing is tried again so soon, so the tool isn't slowed.
offline() {
  [ -f "$HOME_DIR/offline" ] || return 1
  since=$(cat "$HOME_DIR/offline")
  [ -n "$since" ] && [ $(( $(now) - since )) -lt "$OFFLINE_FOR" ]
}

# -- projects, on and off -----------------------------------------------------------------------------------

# Sets PROJECT (the git top-level folder of a folder, or the folder itself outside git) and PDIR, where this
# computer keeps the project's choices: `on` (there when the plugin is on here), `sharing` (on or off; not there
# when never chosen), `summaries` (on or off; not there when never chosen, which is on), `session` (the session a
# message was last sent in).
project_of() {
  PROJECT=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)
  [ -n "$PROJECT" ] || PROJECT="$1"
  PDIR="$PROJECTS/$(printf '%s' "$PROJECT" | cksum | awk '{ print $1 }')"
}

project_on() { [ -f "$PDIR/on" ]; }

project_keep() {
  mkdir -p "$PDIR" && chmod 700 "$PROJECTS" && printf '%s\n' "$PROJECT" > "$PDIR/path"
}

sharing() {
  [ -f "$PDIR/sharing" ] && [ "$(cat "$PDIR/sharing")" = "on" ] && { echo on; return; }
  echo off
}

# Summaries are on unless the developer turned them off: a project turned on before this setting existed has them
# on as well.
summaries() {
  [ -f "$PDIR/summaries" ] && [ "$(cat "$PDIR/summaries")" = "off" ] && { echo off; return; }
  echo on
}

# Whether the developer has been told what summaries do in this project (`summaries-told`, beside the setting): the
# answers to “vyavasta on” and “vyavasta summaries on” tell it, and a project turned on before this setting
# existed is told once, on the first line a session or message gets, before anything of it is kept.
summaries_told() { [ -f "$PDIR/summaries-told" ]; }
mark_summaries_told() { project_keep && true > "$PDIR/summaries-told"; }

# Whether summaries keep what this project sends now: the project on, summaries on, and the developer told so.
summaries_keep() { project_on && [ "$(summaries)" = "on" ] && summaries_told; }

# The words of a message made plain for comparing with a phrase: lower case, spacing made single spaces, and a
# closing mark (. ! ?) taken off.
plain_words() {
  printf '%s' "$1" | tr 'A-Z' 'a-z' | tr '\t\r\n' '   ' | sed -e 's/  */ /g' -e 's/^ //' -e 's/[ .!?]*$//'
}

# The phrases that answer the plugin's own questions, never kept for the developer's summary (the README lists the
# same): “Plan it anyway”, “continue”, “continue anyway”, “go on” and “stop”. $1 is the message's plain words.
never_kept() {
  case "$1" in "plan it anyway"|continue|"continue anyway"|"go on"|stop) return 0 ;; esac
  return 1
}

folder_name() { basename "$1"; }

# The repository a GitHub remote names, as owner/name.
repository_name() {
  printf '%s' "$1" | sed -E -e 's#^.*github\.com[:/]+##' -e 's#\.git/?$##' -e 's#/$##'
}

# -- the server -----------------------------------------------------------------------------------------------

# api METHOD PATH BODYFILE SECONDS: the answer's body in $TMP/answer and its status in STATUS ("000" when the
# server couldn't be reached). SLOW is set when the server took too long. The token travels in curl's
# configuration on stdin, never on its command line.
api() {
  STATUS=000
  SLOW=""
  true > "$TMP/answer"
  if [ -n "${TOKEN:-}" ]; then auth="header = \"Authorization: Bearer $TOKEN\""; else auth=""; fi
  # (Connecting never takes longer than the whole call may.)
  connect=5
  [ "$4" -lt "$connect" ] && connect=$4
  if [ -n "$3" ]; then
    STATUS=$(printf '%s\n' "$auth" | curl -sS -K - -X "$1" --max-time "$4" --connect-timeout "$connect" \
      -H "Content-Type: application/json" -H "User-Agent: vyavasta-$CLIENT/$VERSION" \
      --data-binary "@$3" -o "$TMP/answer" -w '%{http_code}' "$SERVER/api/v1/plugin$2")
  else
    STATUS=$(printf '%s\n' "$auth" | curl -sS -K - -X "$1" --max-time "$4" --connect-timeout "$connect" \
      -H "User-Agent: vyavasta-$CLIENT/$VERSION" \
      -o "$TMP/answer" -w '%{http_code}' "$SERVER/api/v1/plugin$2")
  fi
  code=$?
  [ -n "$STATUS" ] || STATUS=000
  if [ "$code" = "28" ]; then SLOW=1; STATUS=000; elif [ "$code" != "0" ]; then STATUS=000; fi
  case "$STATUS" in
    000) [ -n "$SLOW" ] || { mkdir -p "$HOME_DIR" && now > "$HOME_DIR/offline"; } ;;
    5*) mkdir -p "$HOME_DIR" && now > "$HOME_DIR/offline" ;;
    *) rm -f "$HOME_DIR/offline" ;;
  esac
  if [ "$STATUS" = "401" ] && [ -n "${TOKEN:-}" ]; then
    # The connection ended (disconnected in Settings, or run out): this computer is signed out.
    rm -f "$CREDENTIALS"
    forget_told
    TOKEN=""
  fi
}

answer() { json_get "$TMP/answer" "$1"; }

# The server's own sentence for a refusal (``{"detail": {"message": …}}``), if it gave one.
refusal() {
  json_get "$TMP/answer" detail > "$TMP/detail"
  said=$(json_text "$(json_get "$TMP/detail" message)")
  [ -n "$said" ] || said=$(json_text "$(answer notice)")
  printf '%s' "$said"
}

# Waits for an answer that was not ready, as long as one hook may: each call names the answer the one before was
# waiting for. $1 is the path, $2 the body file to send again with "waiting" in it.
wait_on() {
  tries=0
  while [ "$STATUS" = "200" ] && [ "$(json_text "$(answer status)")" = "pending" ] && [ "$tries" -lt "$ASK_AGAIN" ] \
      && [ $(( $(now) - STARTED_AT )) -lt "$WAIT_FOR" ]; do
    waiting=$(answer waiting)
    case "$waiting" in \"*\") ;; *) break ;; esac
    if [ -n "$2" ]; then
      sed -e 's/^{//' "$2" > "$TMP/rest"
      printf '{"waiting":%s,' "$waiting" > "$TMP/waiting"
      cat "$TMP/rest" >> "$TMP/waiting"
    else
      printf '{"waiting":%s,"tool":"%s"}' "$waiting" "$CLIENT" > "$TMP/waiting"
    fi
    api POST "$1" "$TMP/waiting" "$ASK_SECONDS"
    tries=$((tries + 1))
  done
}

# ask_vyavasta BODYFILE: puts a question to the developer's own assistant and waits for its answer, over as many
# calls as it takes. Leaves the last answer in $TMP/answer.
ask_vyavasta() {
  api POST /ask "$1" "$ASK_SECONDS"
  wait_on /ask ""
}

# A call made with no token: starting a pairing, and taking the token it gives.
api_unsigned() {
  held_token=$TOKEN
  TOKEN=""
  api "$@"
  TOKEN=$held_token
}

# A sign-in still waiting for approval: its code and page are kept with it (in PENDING), and while it waits it is
# never started again and its page never opened again; every sentence about it repeats the code and the address. It
# waits as long as the server said its code lasts (10 minutes unless it said otherwise). Sets PAIR_CODE and PAIR_PAGE
# when one waits; a code that ran out is never shown.
pending_waiting() {
  PAIR_CODE=""; PAIR_PAGE=""
  [ -f "$PENDING" ] || return 1
  [ "$(sed -n 's/^server=//p' "$PENDING")" = "$SERVER" ] || return 1
  pair_until=$(sed -n 's/^until=//p' "$PENDING")
  case "$pair_until" in
    ''|*[!0-9]*) pair_until=$(( $(sed -n 's/^started=//p' "$PENDING" | tr -cd '0-9') + 0 + PAIR_LASTS )) ;;
  esac
  [ "$(now)" -lt "$pair_until" ] || return 1
  PAIR_CODE=$(sed -n 's/^code=//p' "$PENDING")
  PAIR_PAGE=$(sed -n 's/^page=//p' "$PENDING")
  [ -n "$PAIR_CODE" ] && [ -n "$PAIR_PAGE" ]
}

# A pairing started by sign-in and approved in the browser since: the token is taken now. Quiet either way. A pairing
# is claimed for a minute after its code ran out, as one approved at its last moment may still be.
finish_pairing() {
  [ -f "$PENDING" ] || return 0
  pending_server=$(sed -n 's/^server=//p' "$PENDING")
  device=$(sed -n 's/^device=//p' "$PENDING")
  started=$(sed -n 's/^started=//p' "$PENDING")
  if [ "$pending_server" != "$SERVER" ] || [ -z "$device" ] || [ $(( $(now) - ${started:-0} )) -gt $((PAIR_LASTS + 60)) ]; then
    rm -f "$PENDING"
    return 0
  fi
  printf '{"device_code":%s}' "$(json_quote "$device")" > "$TMP/claim"
  api_unsigned POST /token "$TMP/claim" "$QUICK_SECONDS"
  case "$STATUS" in
    200)
      keep_credentials "$SERVER" "$(json_text "$(answer token)")" "$(json_text "$(answer email)")" \
        "$(json_text "$(answer workspace)")"
      rm -f "$PENDING"
      TOKEN=$(token_for "$SERVER")
      CONNECTED="Connected as $(saved email) in $(saved workspace)."
      ;;
    404|410) rm -f "$PENDING" ;;
  esac
  return 0
}

# Starts connecting this computer: a pairing the developer approves in the browser, whose page is opened. A sign-in
# still waiting is used as it is, and its page is not opened again (PAIR_AGAIN is then set). Sets PAIR_CODE and
# PAIR_PAGE, or fails with PAIR_FAILED set to the reason.
start_pairing() {
  PAIR_FAILED=""; PAIR_AGAIN=""
  if pending_waiting; then PAIR_AGAIN=1; return 0; fi
  machine=$(hostname | cut -d. -f1)
  [ -n "$machine" ] || machine=$(uname -n)
  printf '{"machine":%s,"tool":"%s"}' "$(json_quote "$machine")" "$CLIENT" > "$TMP/pair"
  api_unsigned POST /pair "$TMP/pair" "$QUICK_SECONDS"
  if [ "$STATUS" != "201" ]; then
    PAIR_FAILED=$(refusal)
    [ -n "$PAIR_FAILED" ] || PAIR_FAILED="Vyavasta’s server can’t be reached"
    return 1
  fi
  device=$(json_text "$(answer device_code)")
  PAIR_CODE=$(json_text "$(answer user_code)")
  PAIR_PAGE=$(json_text "$(answer verification_url)")
  lasts=$(answer expires_in)
  case "$lasts" in ''|*[!0-9]*) lasts=$PAIR_LASTS ;; esac
  [ "$lasts" -le "$PAIR_LASTS" ] || lasts=$PAIR_LASTS
  if [ -z "$device" ] || [ -z "$PAIR_CODE" ] || [ -z "$PAIR_PAGE" ]; then
    PAIR_FAILED="Vyavasta’s server gave no code"
    return 1
  fi
  started=$(now)
  pair_until=$((started + lasts))
  mkdir -p "$HOME_DIR" && chmod 700 "$HOME_DIR"
  printf 'server=%s\ndevice=%s\nstarted=%s\nuntil=%s\ncode=%s\npage=%s\n' "$SERVER" "$device" "$started" \
    "$((started + lasts))" "$PAIR_CODE" "$PAIR_PAGE" > "$PENDING"
  chmod 600 "$PENDING"
  open_page "$PAIR_PAGE"
  return 0
}

# Why sign-in couldn't start, as a sentence: the server's own words when it refused, else that it can't be reached.
pair_failed_said() {
  said="${PAIR_FAILED:-Vyavasta’s server can’t be reached}"
  printf '%s.' "${said%.}"
}

# What finishes connecting once the developer approves: their next message, in any project (in a project that is
# off, it only asks the server whether the sign-in was approved). A project that is off then still needs turning on.
finish_said() {
  if project_on; then printf '%s' "Once you approve, your next message finishes connecting."
  else printf '%s' "Once you approve, your next message finishes connecting. Then send “vyavasta on” in each project you want it in."; fi
}

# How long the code of the sign-in just started or still waiting goes on working, as a sentence: from what the server
# said when it started, as PENDING keeps it (pair_until), in whole minutes rounded up.
code_lasts_said() {
  left=$(( ${pair_until:-0} - $(now) ))
  [ "$left" -gt 0 ] || return 0
  minutes=$(( (left + 59) / 60 ))
  if [ -n "${PAIR_AGAIN:-}" ]; then
    if [ "$minutes" = "1" ]; then printf '%s' "The code works for 1 more minute."
    else printf '%s' "The code works for $minutes more minutes."; fi
  else printf '%s' "The code works for $(plural "$minutes" minute minutes)."; fi
}

# A sign-in that waits, in a project that is off, finished by the developer's next message: one quick call asks the
# server whether it was approved, made only while its code still works and the server wasn't just found out of reach.
# Nothing of the message is read or sent. Sets FINISHED_LINE to the one line saying so once it was approved, else
# leaves it empty; quiet either way.
finish_waiting_sign_in() {
  FINISHED_LINE=""
  pending_waiting || return 0
  offline && return 0
  QUICK_SECONDS=2
  finish_pairing
  [ -n "$CONNECTED" ] || return 0
  FINISHED_LINE="Vyavasta: $(printf '%s' "$CONNECTED" | sed 's/^Connected/connected/') It is off in this project: sending “vyavasta on” here switches it on, and “vyavasta help” shows everything."
}

# Where to enter the code of the sign-in that was just started or still waits, as the middle of a sentence: “enter the
# code … on the page that just opened in your browser (…)”, or for one already waiting, its page's address.
code_said() {
  if [ -n "${PAIR_AGAIN:-}" ]; then printf 'enter the code %s on the sign-in page (%s)' "$PAIR_CODE" "$PAIR_PAGE"
  else printf 'enter the code %s on the page that just opened in your browser (%s)' "$PAIR_CODE" "$PAIR_PAGE"; fi
}

# Opens a page in the developer's browser, or with the command VYAVASTA_BROWSER names when it is set. Only a web
# address is ever opened, as the server's own address may be (https, or plain http on this computer): an answer
# that names anything else, such as a program or a file on this computer, is not opened.
open_page() {
  case "$1" in
    https://*|http://localhost|http://localhost[:/]*|http://127.0.0.1|http://127.0.0.1[:/]*) ;;
    *) return 0 ;;
  esac
  case "$1" in *[!A-Za-z0-9._~:/?#@=+%,'&'-]*) return 0 ;; esac
  if [ -n "${VYAVASTA_BROWSER:-}" ]; then $VYAVASTA_BROWSER "$1" >/dev/null 2>&1; return 0; fi
  case "$(uname -s)" in
    Darwin) open "$1" >/dev/null 2>&1 & ;;
    MINGW*|MSYS*|CYGWIN*) start "" "$1" >/dev/null 2>&1 & ;;
    *) command -v xdg-open >/dev/null 2>&1 && xdg-open "$1" >/dev/null 2>&1 & ;;
  esac
}

# -- the repository it is in ------------------------------------------------------------------------------------

# Sets ROOT, REMOTE (the GitHub remote, without any user name or token in it) and BRANCH for a folder; fails when
# the folder isn't in a git repository.
repository() {
  ROOT=$(git -C "$1" rev-parse --show-toplevel) || return 1
  [ -n "$ROOT" ] || return 1
  REMOTE=$(git -C "$ROOT" remote get-url origin)
  if [ -z "$REMOTE" ]; then
    first=$(git -C "$ROOT" remote | sed -n '1p')
    [ -n "$first" ] && REMOTE=$(git -C "$ROOT" remote get-url "$first")
  fi
  REMOTE=$(printf '%s' "$REMOTE" | sed -E 's#^([A-Za-z+]+://)[^@/]*@#\1#')
  BRANCH=$(git -C "$ROOT" symbolic-ref --short -q HEAD)
  return 0
}

# -- what changed in the working tree ---------------------------------------------------------------------------

# Claude Code keeps one person's own settings for a project in .claude/settings.local.json: not the team's work, and
# never listed or sent.
OWN_SETTINGS=':(top,exclude).claude/settings.local.json'
# A new file larger than this is never read, not even to count its lines: it is left out as past the limit.
BIG_FILE=1000000
# At most this many new files are looked at; any more are left out as past the limit.
NEW_FILES=2000
# git's own options for every listing and diff here, the same each time so its lists agree: rename detection, and
# nothing an outside program or filter does. (Each also treats a file over BIG_FILE as one that isn't text, so it is
# never compared line by line.)
DIFF_OPTIONS="-M --no-ext-diff --no-textconv"

# Which paths look like keys or credentials, or are written by machines: by name only, in any letter case.
CLASSIFY='
  function why(path,   low, base, n, part, i) {
    low = tolower(path); n = split(low, part, /\//); base = part[n]
    if (base == ".env" || base ~ /^\.env\./ || base ~ /\.(pem|key|p12|pfx|jks|keystore|kdbx|secret|tfvars)$/ \
        || base ~ /^id_(rsa|ed25519)/ || base == "credentials" || base ~ /^credentials\./ || base ~ /^secrets\./ \
        || base == ".npmrc" || base == ".pypirc" || base == ".netrc" || base ~ /\.tfstate/ || base == "auth.json" \
        || base ~ /^service-account.*\.json$/) return "secret"
    if (base ~ /^(package-lock\.json|npm-shrinkwrap\.json|yarn\.lock|pnpm-lock\.yaml|bun\.lockb|cargo\.lock|poetry\.lock|uv\.lock|pipfile\.lock|gemfile\.lock|composer\.lock|go\.sum|flake\.lock)$/ \
        || base ~ /\.min\.(js|css)$/ || base ~ /\.map$/ || base ~ /\.pb\.go$/ || base ~ /_pb2\.py$/) return "generated"
    for (i = 1; i < n; i++)
      if (part[i] ~ /^(node_modules|dist|build|out|target|vendor|\.next|coverage|__pycache__)$/) return "generated"
    return ""
  }'

# Reads one record of git's `diff --raw --numstat -z` (or `--raw -z` alone) into arrays: for each changed file n,
# its old and new path, its old and new mode and git's status letter; and by new path its added and removed lines,
# and whether git found it isn't text. Every file is known by its own name from git, never by its place in a list.
SCAN_AWK='
  function scan_record(r,   p, a, d) {
    if (sstate == 1) { old[n] = r; new[n] = r; sstate = (st[n] == "R" || st[n] == "C") ? 2 : 0; return }
    if (sstate == 2) { new[n] = r; sstate = 0; return }
    if (sstate == 3) { sstate = 4; return }
    if (sstate == 4) { adds[r] = padd; dels[r] = pdel; bin[r] = pbin; sstate = 0; return }
    if (r ~ /^:[0-7]+ [0-7]+ [0-9a-f.]+ [0-9a-f.]+ [A-Z][0-9]*$/) {
      split(substr(r, 2), p, " "); n++; m1[n] = p[1]; m2[n] = p[2]; st[n] = substr(p[5], 1, 1); sstate = 1
      return
    }
    split(r, p, /\t/)
    a = (p[1] == "-") ? 0 : p[1] + 0; d = (p[2] == "-") ? 0 : p[2] + 0
    if (p[3] == "" && substr(r, length(r)) == "\t") { padd = a; pdel = d; pbin = (p[1] == "-"); sstate = 3; return }
    r = substr(r, length(p[1]) + length(p[2]) + 3); adds[r] = a; dels[r] = d; bin[r] = (p[1] == "-")
  }'

# A path as git writes it in the first line of a file's diff: as it is, or in quotes with C escapes when it holds a
# quote, a backslash or a control character (bytes past ASCII stay as they are, with core.quotePath off).
GIT_QUOTE='
  function gq(s,   i, c, o, q) {
    o = ""; q = 0
    for (i = 1; i <= length(s); i++) {
      c = substr(s, i, 1)
      if (c == "\"" || c == "\\") { o = o "\\" c; q = 1 }
      else if (c in CESC) { o = o CESC[c]; q = 1 }
      else if (c < " " || c == DEL) { o = o sprintf("\\%03o", ORD[c]); q = 1 }
      else o = o c
    }
    return q ? "\"" o "\"" : o
  }
  BEGIN {
    for (i = 1; i < 128; i++) ORD[sprintf("%c", i)] = i
    DEL = sprintf("%c", 127)
    CESC[sprintf("%c", 7)] = "\\a"; CESC[sprintf("%c", 8)] = "\\b"; CESC["\t"] = "\\t"; CESC["\n"] = "\\n"
    CESC[sprintf("%c", 11)] = "\\v"; CESC[sprintf("%c", 12)] = "\\f"; CESC["\r"] = "\\r"
  }'

# Text with every byte that is not valid UTF-8 dropped (a file name or file in another encoding), so what is sent
# is valid JSON text: $1 in, $2 out.
clean_utf8() {
  if command -v iconv >/dev/null 2>&1 && iconv -c -f UTF-8 -t UTF-8 < "$1" > "$2"; then :
  elif command -v iconv >/dev/null 2>&1 && [ -s "$2" ]; then :
  else tr -cd '\11\12\15\40-\176' < "$1" > "$2"; fi
}

# git with the scan's own copy of the index when it made one, else the developer's index, read only.
gitx() {
  if [ -n "$SCAN_INDEX" ]; then GIT_INDEX_FILE="$SCAN_INDEX" git -C "$ROOT" "$@"; else git -C "$ROOT" "$@"; fi
}

# Looks at the working tree once for the whole run, for both the list of changed files and the shared change.
# git reads a copy of the developer's index (their own is never written). With code sharing on, new files git does
# not ignore are added to that copy, only as names, so git lists and compares them as new files. A
# new file that looks like a key or credential, or is written by machines, is never added, so nothing of it is
# even read; nor is a new file over BIG_FILE, or one whose name holds a line break. Leaves git's listing against
# the last commit in $TMP/scan, the new files left out in $TMP/left-untracked ("why<TAB>path" records) and the
# others in $TMP/added.
scan_tree() {
  [ -n "${SCANNED:-}" ] && return 0
  SCANNED=1
  SCAN_INDEX=""
  HEAD_SHA=$(git -C "$ROOT" rev-parse -q --verify HEAD)
  true > "$TMP/add"; true > "$TMP/big"; true > "$TMP/left-untracked"; true > "$TMP/added"
  git -C "$ROOT" ls-files --others --exclude-standard -z -- . "$OWN_SETTINGS" | tr '\000' '\001' \
    | awk -v ADD="$TMP/add" -v LEFT="$TMP/left-untracked" -v MOST="$NEW_FILES" "$CLASSIFY"'
      BEGIN { RS = "\001"; added = 0 }
      $0 == "" { next }
      index($0, "\n") { printf "binary\t%s%c", $0, 1 > LEFT; next }
      { w = why($0)
        if (w == "" && added >= MOST) w = "limit"
        if (w == "") { print $0 > ADD; added++ } else printf "%s\t%s%c", w, $0, 1 > LEFT }'
  if [ -s "$TMP/add" ]; then
    # Their sizes, from the file system alone: every character escaped for xargs, so any name is passed as it is.
    (cd "$ROOT" && sed -e 's#^#./#' -e 's/./\\&/g' "$TMP/add" \
      | xargs sh -c 'exec find "$@" -prune -type f -size +'"$BIG_FILE"'c -print' sh) > "$TMP/big"
    awk -v LEFT="$TMP/left-untracked" '
      FILENAME == ARGV[1] { big[substr($0, 3)] = 1; next }
      ($0 in big) { printf "limit\t%s%c", $0, 1 >> LEFT; next }
      { print }' "$TMP/big" "$TMP/add" > "$TMP/added"
  fi
  # git reads a copy of the developer's index, never their own: comparing the working tree, it may rewrite an index
  # whose times look stale even when told to take no optional lock. (Its times kept, so git tells a file changed
  # within the same second as it would with its own.)
  gitdir=$(git -C "$ROOT" rev-parse --absolute-git-dir)
  rm -f "$TMP/index"
  if [ -f "$gitdir/index" ] && cp -p "$gitdir/index" "$TMP/index"; then SCAN_INDEX="$TMP/index"; fi
  if [ -s "$TMP/added" ] && [ "$(sharing)" = "on" ]; then
    tr '\n' '\000' < "$TMP/added" > "$TMP/added-nul"
    if GIT_INDEX_FILE="$TMP/index" GIT_LITERAL_PATHSPECS=1 git -C "$ROOT" add -N --pathspec-from-file="$TMP/added-nul" \
        --pathspec-file-nul >/dev/null; then
      SCAN_INDEX="$TMP/index"
    fi
  fi
  gitx -c core.bigFileThreshold="$BIG_FILE" diff --raw --numstat -z $DIFF_OPTIONS "${HEAD_SHA:-$EMPTY_TREE}" \
    -- . "$OWN_SETTINGS" | tr '\000' '\001' > "$TMP/scan"
}

# git's own list of what changed in the working tree and the index since the last commit, as a JSON array of
# paths, statuses and line counts, written to $TMP/files without its brackets. Nothing of any file is sent. A new
# file git didn't compare has its lines counted here (each is under BIG_FILE, and at most 200 are counted); one left
# out by name or size is listed with no counts. NFILES is how many there are.
changed_files() {
  scan_tree
  tr '\n' '\001' < "$TMP/added" > "$TMP/added-list"
  (cd "$ROOT" && awk -v COUNT="$TMP/files-count" "$AWK_ESCAPE$SCAN_AWK"'
    function lines(path,   count, line) {
      count = 0; RS = "\n"
      while ((getline line < path) > 0) count++
      close(path); RS = "\001"
      return count
    }
    function show(path, status, a, d) {
      if (path in seen) return
      seen[path] = 1
      if (shown >= 300) return
      printf "%s{\"path\":\"%s\",\"status\":\"%s\",\"additions\":%d,\"deletions\":%d}", (shown ? "," : ""), esc(path), status, a, d
      shown++
    }
    BEGIN { RS = "\001"; n = 0; sstate = 0; shown = 0; extra = 0 }
    FILENAME == ARGV[1] { scan_record($0); next }
    FILENAME == ARGV[2] { k = index($0, "\t"); if (k) more[++extra] = substr($0, k + 1); next }
    FILENAME == ARGV[3] { if ($0 != "") small[++smalls] = $0; next }
    END {
      for (e = 1; e <= n; e++) {
        s = st[e]
        status = (s == "A") ? "added" : (s == "D") ? "deleted" : (s == "R" || s == "C") ? "renamed" : "changed"
        show(new[e], status, adds[new[e]], dels[new[e]])
      }
      # New files git was not asked to compare: counted here, or listed by name only.
      for (e = 1; e <= smalls; e++) if (!(small[e] in seen)) show(small[e], "added", (counted++ < 200) ? lines(small[e]) : 0, 0)
      for (e = 1; e <= extra; e++) show(more[e], "added", 0, 0)
      printf "%d\n", shown > COUNT
    }' "$TMP/scan" "$TMP/left-untracked" "$TMP/added-list") > "$TMP/files-raw"
  clean_utf8 "$TMP/files-raw" "$TMP/files"
  NFILES=$(cat "$TMP/files-count")
  [ -n "$NFILES" ] || NFILES=0
}

# The uncommitted changes as one unified diff of the working tree against the GitHub copy, for code sharing:
# written as the `change` object to $TMP/change. The base is where this branch last matched GitHub: the
# merge-base with its upstream, else with origin's default branch, else the last commit, else nothing. Untracked
# files git does not ignore are new files.
#
# What is sent is chosen file by file from git's own listing, by each file's exact name: a file's part of the diff
# is kept only when its first line is the one git writes for a file listed as safe, so a file nothing can vouch for
# is left out, never sent. Left out: files that look like keys or credentials (by their old or new name), machine-
# written files, files git finds aren't text, symbolic links (whatever they point to), files that changed type,
# and any file that would take the whole past the limit. Long lines are cut, and bytes that are not UTF-8 dropped.
# Sets CH_FILES, CH_LINES, CH_COMPLETE and CH_SECRET, CH_GENERATED, CH_BINARY, CH_LIMIT (how many files were left
# out for each reason).
build_change() {
  limit_lines=$CHANGE_LINES; limit_bytes=$CHANGE_BYTES
  if [ -f "$HOME_DIR/limits" ]; then
    kept_lines=$(sed -n 's/^lines=//p' "$HOME_DIR/limits"); kept_bytes=$(sed -n 's/^bytes=//p' "$HOME_DIR/limits")
    case "$kept_lines" in ''|*[!0-9]*) ;; *) limit_lines=$kept_lines ;; esac
    case "$kept_bytes" in ''|*[!0-9]*) ;; *) limit_bytes=$kept_bytes ;; esac
  fi
  scan_tree
  ch_base=""
  upstream=$(git -C "$ROOT" rev-parse -q --verify '@{u}')
  [ -n "$upstream" ] && ch_base=$(git -C "$ROOT" merge-base HEAD "$upstream")
  if [ -z "$ch_base" ]; then
    for ref in origin/HEAD origin/main origin/master; do
      found=$(git -C "$ROOT" rev-parse -q --verify "$ref^{commit}") || continue
      ch_base=$(git -C "$ROOT" merge-base HEAD "$found") && [ -n "$ch_base" ] && break
    done
  fi
  [ -n "$ch_base" ] || ch_base=$HEAD_SHA
  [ -n "$ch_base" ] || ch_base=$EMPTY_TREE
  if [ "$ch_base" = "${HEAD_SHA:-$EMPTY_TREE}" ]; then cp "$TMP/scan" "$TMP/change-raw"
  else
    gitx -c core.bigFileThreshold="$BIG_FILE" diff --raw -z $DIFF_OPTIONS "$ch_base" -- . "$OWN_SETTINGS" \
      | tr '\000' '\001' > "$TMP/change-raw"
  fi
  gitx -c core.quotePath=false -c core.bigFileThreshold="$BIG_FILE" diff $DIFF_OPTIONS --no-color \
    --src-prefix=a/ --dst-prefix=b/ --submodule=short "$ch_base" -- . "$OWN_SETTINGS" > "$TMP/change-diff"
  true > "$TMP/change-kept"
  awk -v KEPT="$TMP/change-kept" -v META="$TMP/change-meta" -v LEFTJSON="$TMP/change-left-raw" -v LIMIT="$limit_lines" \
      -v BYTES="$limit_bytes" -v LONGEST="$LONGEST_LINE" -v DIFF="$TMP/change-diff" \
      "$CLASSIFY$AWK_ESCAPE$SCAN_AWK$GIT_QUOTE"'
    function flush(   i, size) {
      if (cur > 0 && reason[cur] == "") {
        if (binary) reason[cur] = "binary"
        else {
          size = 0
          for (i = 1; i <= held; i++) size += length(buf[i]) + 1
          if (lines + changed > LIMIT || bytes + size > BYTES) reason[cur] = "limit"
          else {
            for (i = 1; i <= held; i++) print buf[i] > KEPT
            lines += changed; bytes += size
            if (!(cur in sent)) { sent[cur] = 1; files++ }
          }
        }
      }
      held = 0; cur = 0; binary = 0; hunk = 0; changed = 0
    }
    function leave(w, p) {
      count[w]++
      if (listed < 300) { out = out (listed ? "," : "") "{\"path\":\"" esc(p) "\",\"why\":\"" w "\"}"; listed++ }
    }
    BEGIN { RS = "\001"; n = 0; sstate = 0; cur = 0; held = 0; lines = 0; bytes = 0; files = 0; listed = 0; out = "" }
    FILENAME == ARGV[1] { k = index($0, "\t"); if (k) leave(substr($0, 1, k - 1), substr($0, k + 1)); next }
    FILENAME == ARGV[2] { scan_record($0); next }
    END {
      for (e = 1; e <= n; e++) {
        r = why(new[e]); if (r == "") r = why(old[e])
        link[e] = (m1[e] == "120000" || m2[e] == "120000")
        # A symbolic link holds only where it points, which may be a key file anywhere; a file that changed
        # type is two things at once. Neither is sent.
        if (r == "" && (link[e] || st[e] == "T")) r = "binary"
        reason[e] = r
        first["diff --git " gq("a/" old[e]) " " gq("b/" new[e])] = e
      }
      # The diff itself, a line at a time: each file found by its own first line.
      RS = "\n"
      while ((getline line < DIFF) > 0) {
        if (substr(line, 1, 11) == "diff --git ") {
          flush()
          if (line in first) cur = first[line]
          else { cur = -1; unknown[++unknowns] = substr(line, 12) }
        }
        if (cur <= 0) continue
        # Where a link points, said as a reason when it is a key file.
        if (link[cur] && line ~ /^[-+]/ && line !~ /^(\+\+\+|---) / && why(substr(line, 2)) == "secret") reason[cur] = "secret"
        if (reason[cur] != "") continue
        if (substr(line, 1, 13) == "Binary files " || line == "GIT binary patch") binary = 1
        if (substr(line, 1, 2) == "@@") hunk = 1
        else if (hunk && (substr(line, 1, 1) == "+" || substr(line, 1, 1) == "-")) changed++
        if (length(line) > LONGEST) line = substr(line, 1, LONGEST)
        buf[++held] = line
      }
      flush()
      for (i = 1; i <= unknowns; i++) leave("binary", unknown[i])
      for (e = 1; e <= n; e++) if (reason[e] != "") leave(reason[e], new[e] != "" ? new[e] : old[e])
      printf "files=%d\nlines=%d\nsecret=%d\ngenerated=%d\nbinary=%d\nlimit=%d\n", files, lines, count["secret"], \
        count["generated"], count["binary"], count["limit"] > META
      printf "[%s]", out > LEFTJSON
    }' "$TMP/left-untracked" "$TMP/change-raw"
  clean_utf8 "$TMP/change-kept" "$TMP/change-clean"
  clean_utf8 "$TMP/change-left-raw" "$TMP/change-left"
  CH_FILES=$(sed -n 's/^files=//p' "$TMP/change-meta"); CH_LINES=$(sed -n 's/^lines=//p' "$TMP/change-meta")
  CH_SECRET=$(sed -n 's/^secret=//p' "$TMP/change-meta"); CH_GENERATED=$(sed -n 's/^generated=//p' "$TMP/change-meta")
  CH_BINARY=$(sed -n 's/^binary=//p' "$TMP/change-meta"); CH_LIMIT=$(sed -n 's/^limit=//p' "$TMP/change-meta")
  CH_COMPLETE=true
  [ "${CH_LIMIT:-0}" -gt 0 ] && CH_COMPLETE=false
  {
    printf '{"base":"%s","diff":' "$ch_base"
    awk "$AWK_ESCAPE"'
      BEGIN { printf "\"" }
      { printf "%s\\n", esc($0) }
      END { printf "\"" }' "$TMP/change-clean"
    printf ',"lines":%d,"files":%d,"complete":%s,"left_out":' "${CH_LINES:-0}" "${CH_FILES:-0}" "$CH_COMPLETE"
    cat "$TMP/change-left"
    printf '}'
  } > "$TMP/change"
}

# What was left out of the changes and why, as one plain clause ("" when nothing was).
left_out_said() {
  parts=""
  [ "${CH_SECRET:-0}" -gt 0 ] && parts="${parts:+$parts, }$(counted "$CH_SECRET" "1 file that looks like a key or password" "files that look like keys or passwords")"
  [ "${CH_GENERATED:-0}" -gt 0 ] && parts="${parts:+$parts, }$(counted "$CH_GENERATED" "1 machine-written file, such as a lock file or build output" "machine-written files, such as lock files or build output")"
  [ "${CH_BINARY:-0}" -gt 0 ] && parts="${parts:+$parts, }$(counted "$CH_BINARY" "1 file that isn’t text" "files that aren’t text")"
  [ "${CH_LIMIT:-0}" -gt 0 ] && parts="${parts:+$parts, }$(counted "$CH_LIMIT" "1 file past the limit of $(thousands "$limit_lines") lines" "files past the limit of $(thousands "$limit_lines") lines")"
  printf '%s' "$parts"
}

# "1 thing" said one way, more said with their number: counted N ONE MANY.
counted() { if [ "$1" = "1" ]; then printf '%s' "$2"; else printf '%s %s' "$1" "$3"; fi; }

plural() { if [ "$1" = "1" ]; then printf '1 %s' "$2"; else printf '%s %s' "$1" "$3"; fi; }
thousands() { awk -v n="$1" 'BEGIN { s = ""; while (length(n) > 3) { s = "," substr(n, length(n) - 2) s; n = substr(n, 1, length(n) - 3) } print n s }'; }

# Where the session's work stands, as git shows it: files changed and not committed; committed and not pushed;
# pushed; or none of it kept (the tree as it was when the session began).
work_state() {
  if [ -s "$TMP/files" ]; then printf 'changing'; return; fi
  head=$(git -C "$ROOT" rev-parse -q --verify HEAD)
  start=$(cat "$1/start")
  if git -C "$ROOT" rev-parse -q --verify '@{u}' >/dev/null 2>&1; then
    ahead=$(git -C "$ROOT" rev-list --count '@{u}..HEAD')
    if [ "${ahead:-0}" -gt 0 ]; then printf 'committed'
    elif [ -n "$start" ] && [ "$head" != "$start" ]; then printf 'pushed'
    else printf 'abandoned'; fi
  elif [ -n "$start" ] && [ "$head" != "$start" ]; then printf 'committed'
  else printf 'abandoned'; fi
}

# -- what the tool is told -------------------------------------------------------------------------------------

# A note for the developer (the model isn't shown it).
say() { printf '{"systemMessage":%s}\n' "$(json_quote "$1")"; }

# The one line every message in a project that is on gets: what was sent, what was not and why, whether the message
# was kept for the developer's summary ($4, when it is said), and what came of it.
line() {
  said="Vyavasta · sent: $1."
  [ -n "$2" ] && said="$said Not sent: $2."
  [ -n "${4:-}" ] && said="$said $4"
  printf '%s · %s' "$said" "$3"
}

# The same line when nothing at all was sent: why, in a few words, and what came of it.
nothing_line() { printf 'Vyavasta · nothing sent (%s) · %s' "$1" "$2"; }

# A conflict found in the real change, kept for the session from an answer that carries one: told by the check
# after an edit, or when the tool stops, until the developer chooses to continue or stop. Fails when the answer
# carries none, or one already kept or decided.
keep_conflict() {
  conflict=$(answer conflict)
  case "$conflict" in \{*) ;; *) return 1 ;; esac
  conflict_id=$(json_text "$(field "$conflict" id)")
  [ -n "$conflict_id" ] || return 1
  [ -f "$1/conflicts-closed" ] && grep -qxF "$conflict_id" "$1/conflicts-closed" && return 1
  [ -f "$1/conflict-id" ] && [ "$(cat "$1/conflict-id")" = "$conflict_id" ] && return 1
  printf '%s' "$conflict" > "$1/conflict"
  printf '%s' "$conflict_id" > "$1/conflict-id"
  told="$(json_text "$(field "$conflict" notice)")

Send “continue” to go on, or “stop” to leave the change where it is."
  printf '{"continue":false,"stopReason":%s}\n' "$(json_quote "$told")" > "$1/conflict-stop"
  printf '{"systemMessage":%s}\n' "$(json_quote "$told")" > "$1/conflict-say"
  return 0
}

close_conflict() {
  cat "$1/conflict-id" >> "$1/conflicts-closed"
  echo >> "$1/conflicts-closed"
  rm -f "$1/conflict" "$1/conflict-id" "$1/conflict-stop" "$1/conflict-say" "$1/conflict-prompt"
}

# Tells the server what the developer chose about the session's conflict.
decide_conflict() {
  printf '{"session":%s,"remote":%s,"id":%s,"decision":"%s"}' "$(json_quote "$(basename "$1")")" \
    "$(json_quote "$REMOTE")" "$(json_quote "$(cat "$1/conflict-id")")" "$2" > "$TMP/decided"
  api POST /conflict "$TMP/decided" "$QUICK_SECONDS"
}

# -- the hooks -----------------------------------------------------------------------------------------------------

# The input's folder: the tool's cwd, else the project folder it says.
input_folder() {
  folder=$(json_text "$(json_get "$TMP/input" cwd)")
  [ -n "$folder" ] || folder="${CLAUDE_PROJECT_DIR:-$PWD}"
  printf '%s' "$folder"
}

hook_session_start() {
  PAIR_FAILED=""
  # The tool gives this hook 15 seconds in all: each call is short, and none is made while the server was just found
  # out of reach.
  QUICK_SECONDS=$START_SECONDS
  dir=$(session_dir "$(json_text "$(json_get "$TMP/input" session_id)")")
  folder=$(input_folder)
  project_of "$folder"
  if ! project_on; then
    welcome "$dir"
    return
  fi
  mkdir -p "$HOME_DIR" && true > "$HOME_DIR/welcomed"
  basename "$dir" > "$PDIR/session"
  # A new session has no message of its own waiting for its reply.
  rm -f "$dir/turn-waiting"
  summaries_note
  # Where the tree stood when the session began, to tell later whether anything of it was kept.
  if repository "$folder"; then
    [ -f "$dir/start" ] || git -C "$ROOT" rev-parse -q --verify HEAD > "$dir/start"
  else ROOT=""; REMOTE=""; fi
  # Sessions over a week old are forgotten.
  find "$SESSIONS" -mindepth 1 -maxdepth 1 -type d -mtime +7 -exec rm -rf {} +
  offline || finish_pairing
  if [ -z "$TOKEN" ]; then
    # Signed out in a project that is on: sign-in starts by itself, once, here (the session's first message then
    # doesn't start it again); one still waiting is told again, with its code.
    if pending_waiting; then
      PAIR_AGAIN=1
      say "Vyavasta: not signed in yet, so nothing is checked. To connect, $(code_said). Once you approve, your next message finishes connecting.$SUMMARIES_NOTE"
    elif ! offline && start_pairing; then
      true > "$dir/said-sign-in"
      say "Vyavasta: not signed in yet, so nothing is checked. To connect, $(code_said). Once you approve, your next message finishes connecting.$SUMMARIES_NOTE"
    else
      say "Vyavasta: not signed in, and sign-in couldn’t start: $(pair_failed_said) $WAY_IN ${AGENT} works as usual.$SUMMARIES_NOTE"
    fi
    return
  fi
  api GET /me "" "$QUICK_SECONDS"
  case "$STATUS" in
    200)
      remember_me
      if [ -n "$CONNECTED" ]; then who="connected as $(saved email) in $(saved workspace)."
      else who="signed in as $(json_text "$(answer email)") in $(json_text "$(json_get "$TMP/workspace" name)")."; fi
      greeting="Vyavasta: $who $(reach_said "$(answer repositories)")"
      if [ -n "$SHARING_ENDED" ]; then
        greeting="$greeting Code sharing was turned off for this repository in Vyavasta’s web app, so your uncommitted changes are no longer sent. Send “vyavasta share code on” to turn it on again."
      fi
      greeting="$greeting$SUMMARIES_NOTE"
      # What teammates asked of the developer while they were away, each told once.
      api GET "/inbox?told=1" "" "$QUICK_SECONDS"
      if [ "$STATUS" = "200" ]; then
        items=$(answer items)
        if [ -n "$items" ] && [ "$items" != "[]" ]; then
          greeting="$greeting

While you were away:
$(render_inbox "$items")"
        fi
      fi
      sandboxed=""
      [ "$CLIENT" = "codex" ] && sandboxed=" Codex runs that command in a closed-off space that may keep it from reaching Vyavasta; when it says so, tell the developer they can ask the same thing by sending a message that starts with “Vyavasta,”."
      # The developer is told they are connected; the tool's model is told what Vyavasta is here for, and how
      # to ask it what the plugin did not already ask for them.
      printf '{"systemMessage":%s,"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' \
        "$(json_quote "$greeting")" \
        "$(json_quote "Vyavasta is connected for this developer. It keeps their team’s record: what teammates said, decided and promised, and what each of them is working on, read from the sources the team connected. When the developer’s message asks about the team, Vyavasta answers it before the message reaches you, and you are given the answer to pass on. For anything else you need to know about the team (what a teammate is doing, what was decided, who said what, whether someone else is changing the same code), ask Vyavasta before any other source such as email or chat tools, by running this command with the question in plain words: $ASK_WITH \"<the question>\" .$sandboxed Changes to the code are yours to make on this computer; each request for one is checked against the record before it reaches you. Messages that start with “vyavasta” are the developer’s commands to the plugin, which answers them itself.")"
      ;;
    401) say "Vyavasta: this computer’s connection has ended. $WAY_IN_AGAIN$SUMMARIES_NOTE" ;;
    *) say "Vyavasta: the server can’t be reached right now, so requests aren’t being checked. ${AGENT} works as usual.$SUMMARIES_NOTE" ;;
  esac
}

# A session in a project that is off. The first one on this computer welcomes the developer in one message, and
# when nobody is signed in it starts signing in there and then (the Connect page opens and the message gives its
# code); the project stays off and nothing else is sent. Later sessions say nothing, unless a sign-in is waiting: it
# is finished when it was approved, and told again with its code when it still waits. $1 is the session folder.
welcome() {
  if [ ! -f "$HOME_DIR/welcomed" ]; then
    mkdir -p "$HOME_DIR" && true > "$HOME_DIR/welcomed" || return 0
    offline || finish_pairing
    if [ -n "$TOKEN" ]; then
      say "Vyavasta is installed and off in this project. Send “vyavasta on” to use it here, and “vyavasta help” to see everything it does."
    elif pending_waiting; then
      PAIR_AGAIN=1
      say "Vyavasta is installed. To connect this computer, $(code_said). $(finish_said) “vyavasta help” shows everything."
    elif ! offline && start_pairing; then
      true > "$1/said-sign-in"
      say "Vyavasta is installed. To connect this computer, $(code_said). $(finish_said) “vyavasta help” shows everything."
    else
      say "Vyavasta is installed, but sign-in couldn’t start: $(pair_failed_said) $WAY_IN Then send “vyavasta on” in each project you want it in. “vyavasta help” shows everything."
    fi
    return 0
  fi
  [ -f "$PENDING" ] && [ -z "$TOKEN" ] || return 0
  offline || finish_pairing
  if [ -n "$TOKEN" ]; then
    say "Vyavasta: $(printf '%s' "$CONNECTED" | sed 's/^Connected/connected/') It is off in this project: send “vyavasta on” to use it here, and “vyavasta help” to see everything it does."
  elif pending_waiting; then
    PAIR_AGAIN=1
    say "Vyavasta: a sign-in is waiting. To connect this computer, $(code_said). $(finish_said)"
  fi
}

# What summaries do, said once in a project that has them on and was never told (turned on before this setting
# existed): SUMMARIES_NOTE is the sentence, with a space before it, or empty; the project is then marked told.
summaries_note() {
  SUMMARIES_NOTE=""
  [ "$(summaries)" = "on" ] && ! summaries_told || return 0
  SUMMARIES_NOTE=" Summaries are on in this project: from your next message, your messages here and ${TOOL}’s replies, as written, are kept in a chat of your own in Vyavasta and summed up for teammates, until you send “vyavasta summaries off”."
  mark_summaries_told
}

# What a session in this folder does, for the line a session starts with. $1 is /me's list of repositories.
reach_said() {
  if [ -z "${ROOT:-}" ]; then
    echo "This folder isn’t a git repository, so requests here aren’t checked; questions about your team are still answered."
  elif [ -z "${REMOTE:-}" ]; then
    echo "This repository has no copy on GitHub, so requests here aren’t checked; questions about your team are still answered."
  elif [ -n "$1" ] && ! lists_repository "$1" "$(repository_name "$REMOTE")"; then
    echo "Vyavasta doesn’t read $(repository_name "$REMOTE") for you, so requests here aren’t checked; questions about your team are still answered."
  else
    echo "Requests are checked against your team’s record before ${AGENT} changes code, and questions about your team are answered from it."
  fi
}

# What /me said that is kept: the limits on shared changes, and whether code sharing was turned off in the web app
# for this project's repository (SHARING_ENDED). Leaves the workspace in $TMP/workspace.
remember_me() {
  json_get "$TMP/answer" workspace > "$TMP/workspace"
  json_get "$TMP/answer" limits > "$TMP/limits"
  me_lines=$(json_get "$TMP/limits" change_lines); me_bytes=$(json_get "$TMP/limits" change_bytes)
  if [ -n "$me_lines" ] || [ -n "$me_bytes" ]; then
    mkdir -p "$HOME_DIR" && printf 'lines=%s\nbytes=%s\n' "$me_lines" "$me_bytes" > "$HOME_DIR/limits"
  fi
  SHARING_ENDED=""
  me_sharing=$(answer sharing)
  case "$me_sharing" in \[*) ;; *) return 0 ;; esac
  if [ -n "${REMOTE:-}" ] && [ "$(sharing)" = "on" ] && [ "$(cat "$PDIR/sharing-told")" = "on" ]; then
    if ! lists_repository "$me_sharing" "$(repository_name "$REMOTE")"; then
      echo off > "$PDIR/sharing"; echo off > "$PDIR/sharing-told"; SHARING_ENDED=1
    fi
  fi
}

# What teammates sent the developer, each under its header, numbered as the server numbers them; the numbers are
# kept so “vyavasta reply 2: …” knows which item it answers.
render_inbox() {
  true > "$TMP/listing"
  json_rows "$1" > "$TMP/rows"
  has_task=""; has_message=""
  while IFS= read -r row; do
    n=$(field "$row" n)
    message_id=$(json_text "$(field "$row" message_id)")
    kind=$(json_text "$(field "$row" kind)")
    from=$(json_text "$(field "$(field "$row" from)" name)")
    at=$(json_text "$(field "$row" at_said)")
    text=$(json_text "$(field "$row" text)")
    answered=$(json_text "$(field "$row" answer)")
    state=$(json_text "$(field "$(field "$row" task)" state)")
    case "$kind" in
      task) what="assigned you a task"; has_task=1 ;;
      reply) what="replied"; has_message=1 ;;
      *) what="asked your agent"; has_message=1 ;;
    esac
    printf '── From %s · %s · %s ──\n' "$from" "$at" "$what"
    printf '%s. %s\n' "$n" "$text"
    [ -n "$answered" ] && printf 'Your agent answered: %s\n' "$answered"
    [ "$kind" = "task" ] && [ -n "$state" ] && [ "$state" != "open" ] && printf 'This task is %s.\n' "$state"
    printf '\n'
    printf '%s\t%s\t%s\t%s\n' "$n" "$message_id" "$kind" "$from" >> "$TMP/listing"
  done < "$TMP/rows"
  mkdir -p "$HOME_DIR" && cp "$TMP/listing" "$HOME_DIR/inbox"
  if [ -n "$has_task" ] && [ -n "$has_message" ]; then
    echo "Answer with “vyavasta reply <number>: <your words>”; for a task, “vyavasta start <number>”, “vyavasta done <number>” or “vyavasta decline <number>”."
  elif [ -n "$has_task" ]; then
    echo "For a task, send “vyavasta start <number>” to begin it, “vyavasta done <number>” or “vyavasta decline <number>”."
  else
    echo "Answer with “vyavasta reply <number>: <your words>”."
  fi
}

# The words of a message read as one of the plugin's commands. Sets TYPED (the command) and TYPED_ARG (a name or
# number), and writes free text to $TMP/typed-text. A command is a message that is exactly the phrase, case and
# trailing punctuation ignored; ask, assign and reply carry words after a name or number.
#
# A message that is “vyavasta” and words that ask how to use the plugin itself is help: the words, after “vyavasta”
# with or without a comma, must be the whole of one of the shapes below (“help”, “how do I sign in”, “what can you
# do”, “what does it send”, “how does it work”), so a question about the team that starts with Vyavasta's name
# (“Vyavasta, what is Priya working on?”) and a longer request that only mentions it never are: those go on as they
# always have.
parse_typed() {
  TYPED=""; TYPED_ARG=""
  true > "$TMP/typed-text"
  printf '%s' "$1" | awk -v out="$TMP/typed-text" '
    function trim(s) { sub(/^[ \t\r\n]+/, "", s); sub(/[ \t\r\n]+$/, "", s); return s }
    # Whether the words after “vyavasta” ask for help with the plugin itself, as a whole.
    function helpish(a,   obj, verbs) {
      gsub(/’/, "", a); gsub(sprintf("%c", 39), "", a); gsub(/[,;:]+/, " ", a); gsub(/ +/, " ", a); sub(/^ /, "", a); sub(/ $/, "", a)
      sub(/^(hey|hi|hello|ok|okay|so) /, "", a); sub(/^please /, "", a); sub(/ please$/, "", a)
      if (a == "" || a ~ /^[?]+$/) return 1
      obj = "( (it|this|you|vyavasth?a|the plugin|this plugin|here|in this project|now|again|with (it|this|you|vyavasth?a)|to (it|this|vyavasth?a)|for (this project|me)))*"
      verbs = "(use|start using|get started|start|begin|set up|setup|install|sign in|signin|log in|login|connect|sign out|turn on|turn off|turn (it|you|vyavasth?a) (on|off)|switch on|switch off|switch (it|you|vyavasth?a) (on|off)|enable|disable|stop|see the commands|see what it sends)"
      if (a ~ ("^(help|help me|commands|the commands|usage|guide|instructions|getting started|get started|what now|options)" obj "$")) return 1
      if (a ~ ("^help( me)? (with )?(signing in|sign in|setting up|set up|getting started|get started|using|connecting|connect)" obj "$")) return 1
      if (a ~ ("^(how|where) (do|can|should|would) (i|we) " verbs obj "$")) return 1
      if (a ~ ("^how to " verbs obj "$")) return 1
      if (a ~ ("^how (does|do) (it|this|vyavasth?a|the plugin|you) work" obj "$")) return 1
      if (a ~ ("^what (can|do|does|will|would) (you|it|this|vyavasth?a|the plugin|i) (do|send|share|keep|see)" obj "$")) return 1
      if (a ~ /^what (is|are) (this|it|vyavasth?a|the plugin|this plugin|the commands|your commands|my options)$/) return 1
      if (a ~ /^what commands (are there|do you have|can i use)$/) return 1
      return 0
    }
    # How long the name of the plugin is at the start of s: 8 for "vyavasta", 9 for "vyavastha" (its spelling before
    # the rename, which is still taken), else 0.
    function named(s) { return (s ~ /^vyavastha/) ? 9 : ((s ~ /^vyavasta/) ? 8 : 0) }
    BEGIN { RS = "\001" }
    NR == 1 {
      s = trim($0); low = tolower(s)
      if (low ~ /^vyavasth?a[ \t]+(ask|assign|reply)[ \t]/) {
        sub(/^[^ \t]+[ \t]+/, "", s); verb = tolower(s); sub(/[ \t].*$/, "", verb)
        body = trim(substr(s, length(verb) + 1)); name = ""; text = ""
        k1 = index(body, ":"); k2 = index(body, ","); k = k1
        if (k == 0 || (k2 > 0 && k2 < k)) k = k2
        if (k > 0) {
          head = trim(substr(body, 1, k - 1))
          if (head != "" && head !~ /\n/ && split(head, words, /[ \t]+/) <= 3) { name = head; text = substr(body, k + 1) }
        }
        if (name == "" && match(body, /^[^ \t\r\n:,]+/)) { name = substr(body, 1, RLENGTH); text = substr(body, RLENGTH + 1) }
        text = trim(text)
        if (verb == "reply") { sub(/^#/, "", name); if (name !~ /^[0-9]+$/) name = "" }
        printf "%s\t%s\n", verb, (text == "" ? "" : name)
        printf "%s", text > out
        exit
      }
      gsub(/[ \t\r\n-]+/, " ", low); sub(/[ .!?]+$/, "", low)
      n = named(low); after = substr(low, n + 1, 1)
      if (n == 0 || (after != " " && after != "")) {
        if (n > 0 && (after == "," || after == ":") && substr(low, n + 2, 1) ~ /^ ?$/ && helpish(substr(low, n + 2))) printf "help\t\n"
        exit
      }
      rest = substr(low, n + 2)
      if (rest == "") rest = "help"
      if (rest ~ /^(start|done|decline) #?[0-9]+$/) { split(rest, p, " "); sub(/^#/, "", p[2]); printf "%s\t%s\n", p[1], p[2]; exit }
      known["on"] = "on"; known["off"] = "off"; known["status"] = "status"; known["check"] = "check"
      known["settings"] = "settings"; known["help"] = "help"; known["sign in"] = "sign_in"; known["signin"] = "sign_in"
      known["sign out"] = "sign_out"; known["signout"] = "sign_out"; known["share code on"] = "share_on"
      known["share code off"] = "share_off"; known["shared"] = "shared"; known["chat"] = "chat"
      known["summaries on"] = "summaries_on"; known["summaries off"] = "summaries_off"
      known["chat open"] = "chat_open"; known["open chat"] = "chat_open"; known["upload"] = "upload"
      known["inbox"] = "inbox"; known["ask"] = "ask"; known["assign"] = "assign"; known["reply"] = "reply"
      known["start"] = "start"; known["done"] = "done"; known["decline"] = "decline"
      if (rest in known) printf "%s\t\n", known[rest]
      else if (helpish(rest)) printf "help\t\n"
    }' > "$TMP/typed"
  TYPED=$(cut -f1 < "$TMP/typed")
  TYPED_ARG=$(cut -f2 < "$TMP/typed")
}

# A question about using the plugin is short: a message longer than this, as the hook's input writes it, is never
# taken for one.
GUIDE_LONGEST=2000

# Whether the message the tool sent might be one of the plugin's commands: its first words, read straight from the
# hook's input without decoding the rest, start with “vyavasta” (0); or the message itself is short and names
# Vyavasta, and may ask how to use it (2); or neither (1). Only the prompt's own value is looked at, never the rest of
# the input (such as the folder it was sent from), and of it at most GUIDE_LONGEST characters, so this costs a moment
# however long the message is.
maybe_typed() {
  awk -v longest="$GUIDE_LONGEST" 'BEGIN { RS = "\001"; found = 1 }
    NR == 1 {
      s = $0
      while ((k = index(s, "\"prompt\"")) > 0) {
        s = substr(s, k + 8)
        if (match(s, /^[ \t\r\n]*:[ \t\r\n]*"/)) {
          value = substr(s, RLENGTH + 1, longest + 1)
          head = substr(value, 1, 80)
          while (sub(/^([ \t]|\\[ntr])/, "", head)) {}
          lead = tolower(substr(head, 1, 9))
          if (lead == "vyavastha" || substr(lead, 1, 8) == "vyavasta") { found = 0; exit }
          # Where the value ends: the first quote no backslash escapes, within the bound; past it, it is too long.
          n = length(value); i = 1
          while (i <= n) {
            c = substr(value, i, 1)
            if (c == "\\") i += 2
            else if (c == "\"") break
            else i++
          }
          said = tolower(substr(value, 1, i - 1))
          if (i <= n && (index(said, "vyavasta") > 0 || index(said, "vyavastha") > 0)) found = 2
          exit
        }
      }
    }
    END { exit found }' "$TMP/input"
}

hook_prompt() {
  HERE=$(input_folder)
  project_of "$HERE"
  GUIDE=""
  if ! project_on; then
    # Off here, and not one of the plugin's commands: nothing is done, and the message is not even read, unless it
    # names Vyavasta and asks how to use it: then the tool's model is told how, and nothing is sent. A sign-in that
    # waits is finished by this message once it was approved (a file test when none waits).
    maybe_typed
    typed=$?
    [ "$typed" = "0" ] || {
      [ "$typed" = "2" ] && guide_wanted "$(json_text "$(json_get "$TMP/input" prompt)")" && GUIDE=$(guide_context)
      off_answer
      return
    }
  fi
  prompt=$(json_get "$TMP/input" prompt)
  [ -n "$prompt" ] || return
  dir=$(session_dir "$(json_text "$(json_get "$TMP/input" session_id)")")
  SESSION=$(basename "$dir")
  # A new message starts a new turn: whatever message of an earlier turn waited for its reply (a turn that never
  # came to its end) waits no longer, so a later reply is never filed under it.
  rm -f "$dir/turn-waiting"
  text=$(json_text "$prompt")
  TYPED=""; TYPED_ARG=""
  case "$(printf '%.80s' "$text" | tr 'A-Z' 'a-z' | tr -d ' \t\r\n')" in vyavasta*|vyavastha*) parse_typed "$text" ;; esac
  if [ -n "$TYPED" ]; then
    # The plugin's own commands, answered here whether or not it is on, and never sent to the model; `start`
    # alone lets the task it starts through.
    if project_on; then basename "$dir" > "$PDIR/session"; basename "$dir" > "$HOME_DIR/session"; fi
    if [ "$TYPED" = "start" ]; then
      START_LINE=""
      command_start "$TYPED_ARG" > "$TMP/said"
      reason=$(cat "$TMP/said")
      if [ -n "$START_TEXT" ]; then
        prompt=$(json_quote "$START_TEXT")
        if project_on; then
          handle_message "$prompt" "$dir"
        else
          printf '{"systemMessage":%s,"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' \
            "$(json_quote "Vyavasta · $START_LINE")" "$(json_quote "$START_CONTEXT")"
        fi
        return
      fi
    else
      reason=$(command_"$TYPED" "$TYPED_ARG")
    fi
    if [ "$CLIENT" = "codex" ]; then
      printf '{"decision":"block","reason":%s}\n' "$(json_quote "$reason")"
    else
      printf '{"decision":"block","reason":%s,"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","suppressOriginalPrompt":true}}\n' \
        "$(json_quote "$reason")"
    fi
    return
  fi
  # A message that asks how to use Vyavasta: the tool's model is told how, with whatever else it is given.
  guide_wanted "$text" && GUIDE=$(guide_context)
  # Off in this project: only that.
  if ! project_on; then
    off_answer
    return
  fi
  words=$(plain_words "$text")
  if [ "$words" = "$(plain_words "$PHRASE")" ] && [ -s "$dir/held" ]; then
    # The developer chose to go on with the request that was held: the model is shown it, with what stood in the way.
    printf '{"systemMessage":%s,"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' \
      "$(json_quote "Vyavasta: going ahead. ${AGENT} was shown your request, what stands in the way, and that you chose to go on.")" \
      "$(cat "$dir/held")"
    rm -f "$dir/held"
    return
  fi
  case "$words" in /*) return ;; esac
  # The session a question asked by the tool's model belongs to (``ask``): the one a message was last sent in.
  basename "$dir" > "$HOME_DIR/session"
  basename "$dir" > "$PDIR/session"
  CONFLICT_CONTEXT=""
  if [ -f "$dir/conflict-id" ]; then
    if repository "$HERE"; then :; else REMOTE=""; fi
    facts=$(json_text "$(field "$(cat "$dir/conflict")" context)")
    earlier=$(cat "$dir/conflict-prompt")
    [ -n "$earlier" ] && earlier="

Their request, sent before they were asked: $earlier"
    case "$words" in
      continue|"continue anyway"|go\ on)
        decide_conflict "$dir" continue
        close_conflict "$dir"
        printf '{"systemMessage":%s,"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' \
          "$(json_quote "Vyavasta · sent: your choice to continue. · ${AGENT} goes on, with what your team has said in mind.")" \
          "$(json_quote "$facts

The developer was told that something their team has said stands against the change being made, and chose to continue.$earlier")"
        return ;;
      stop)
        decide_conflict "$dir" stop
        close_conflict "$dir"
        printf '{"systemMessage":%s,"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' \
          "$(json_quote "Vyavasta · sent: your choice to stop. · ${AGENT} makes no more edits and tells you what was changed so far.")" \
          "$(json_quote "$facts

The developer was told that something their team has said stands against the change being made, and chose to stop. Make no more edits. Say what was changed so far in this session, and ask whether to undo it.")"
        return ;;
      *)
        decide_conflict "$dir" seen
        close_conflict "$dir"
        CONFLICT_CONTEXT="$facts" ;;
    esac
  fi
  rm -f "$dir/held"
  handle_message "$prompt" "$dir"
}

# What a message in a project that is off gets: the line saying a waiting sign-in was finished, once it was approved
# (a file test when none waits), and the guidance in GUIDE when the message asks how to use the plugin. The message
# itself goes through as it is.
off_answer() {
  FINISHED_LINE=""
  [ -f "$PENDING" ] && [ -z "$TOKEN" ] && finish_waiting_sign_in
  if [ -n "$GUIDE" ] && [ -n "$FINISHED_LINE" ]; then
    printf '{"systemMessage":%s,"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' \
      "$(json_quote "$FINISHED_LINE")" "$(json_quote "$GUIDE")"
  elif [ -n "$GUIDE" ]; then
    printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' "$(json_quote "$GUIDE")"
  elif [ -n "$FINISHED_LINE" ]; then
    say "$FINISHED_LINE"
  fi
}

# A message in a project that is on: checked, or asked as a question, with its one line. $1 is the message as a JSON
# string, $2 the session folder.
handle_message() {
  prompt=$1; dir=$2
  OUT_LINE=""; OUT_CONTEXT=""; OUT_REASON=""; attach_note=""
  prefix="${START_LINE:+$START_LINE }"
  # Whether this message is kept for the developer's summary is settled before they are told what summaries do: the
  # message whose line first tells them is never kept.
  keep=false
  keep_this && keep=true
  summaries_note
  finish_pairing
  if [ -z "$TOKEN" ]; then
    # Signed out: sign-in starts by itself on the first message of a session (unless the session's start began it),
    # and never again in it; one still waiting is told again with its code, and its page isn't opened again.
    if pending_waiting; then
      outcome="Enter the code $PAIR_CODE on the sign-in page ($PAIR_PAGE) to connect. Once you approve, your next message finishes connecting. ${AGENT} works as usual until then."
    elif [ ! -f "$dir/said-sign-in" ]; then
      true > "$dir/said-sign-in"
      if start_pairing; then
        outcome="The sign-in page is open in your browser: enter the code $PAIR_CODE there (or open $PAIR_PAGE). Once you approve, your next message finishes connecting."
      else
        outcome="Sign-in couldn’t start: $(pair_failed_said) $WAY_IN ${AGENT} works as usual."
      fi
    else
      outcome="$WAY_IN ${AGENT} works as usual."
    fi
    OUT_LINE=$(nothing_line "you aren’t signed in" "$prefix$outcome")
    OUT_CONTEXT="${START_CONTEXT:-}"
    emit; return
  fi
  # A folder that is no repository has nothing to check, and a question about the team can still be asked from it.
  if repository "$HERE"; then :; else ROOT=""; REMOTE=""; BRANCH=""; fi
  if offline; then
    OUT_LINE=$(nothing_line "Vyavasta’s server can’t be reached" "$prefix${AGENT} works as usual, and Vyavasta is tried again in a minute.")
    OUT_CONTEXT="${START_CONTEXT:-}"
    emit; return
  fi
  NFILES=0; shared=""; consent=""
  if [ -n "$ROOT" ] && [ -n "$REMOTE" ]; then
    changed_files
    if [ "$(sharing)" = "on" ]; then
      [ "$(cat "$PDIR/sharing-told")" = "on" ] || tell_sharing on
      build_change
      shared=1
    elif [ ! -f "$PDIR/sharing" ] && [ "$NFILES" -gt 0 ] && [ ! -f "$PDIR/asked" ]; then
      # Asked once: code sharing is off until the developer chooses.
      true > "$PDIR/asked"
      consent=" Send “vyavasta share code on” to also send your uncommitted changes for the check; teammates see only a summary, and key, ignored, machine-written and non-text files never go (asked once)."
    fi
  fi
  # A picture or file the tool marks in the message's text never reaches Vyavasta: this session's chat is opened to
  # drop it there (with code sharing on), or the developer is told once how to give it.
  case "$(json_text "$prompt")" in
    *"[Image #"*)
      if [ "$(sharing)" = "on" ]; then
        attach_note=1
      elif [ ! -f "$PDIR/asked-attach" ]; then
        true > "$PDIR/asked-attach"
        consent="$consent Your image stays in ${TOOL}. To give it to Vyavasta, send “vyavasta upload” and drop it on the page that opens."
      fi ;;
  esac
  {
    printf '{"request":%s,"remote":%s,"branch":%s,"session":%s,"tool":"%s","keep":%s' "$prompt" \
      "$(json_quote "$REMOTE")" "$(json_quote "$BRANCH")" "$(json_quote "$SESSION")" "$CLIENT" "$keep"
    if [ -n "$shared" ]; then printf ',"change":'; cat "$TMP/change"; fi
    printf '}'
  } > "$TMP/check"
  api POST /check "$TMP/check" "$CHECK_SECONDS"
  if [ -n "$shared" ] && [ "$STATUS" = "200" ]; then cksum < "$TMP/change" > "$dir/change-sum"; fi
  case "$STATUS" in
    200) ;;
    401)
      OUT_LINE=$(nothing_line "this computer’s connection to Vyavasta has ended" "$prefix$WAY_IN_AGAIN ${AGENT} works as usual.")
      OUT_CONTEXT="${START_CONTEXT:-}"; emit; return ;;
    429)
      OUT_LINE=$(line "your message" "" "${prefix}Vyavasta had too many requests just now, so it wasn’t checked. ${AGENT} works as usual.")
      OUT_CONTEXT="${START_CONTEXT:-}"; emit; return ;;
    000)
      if [ -n "$SLOW" ]; then
        OUT_LINE=$(line "your message" "" "${prefix}Vyavasta took too long to answer, so it wasn’t checked this time. ${AGENT} works as usual.")
      else
        OUT_LINE=$(nothing_line "Vyavasta’s server can’t be reached" "$prefix${AGENT} works as usual, and Vyavasta is tried again in a minute.")
      fi
      OUT_CONTEXT="${START_CONTEXT:-}"; emit; return ;;
    5*)
      OUT_LINE=$(nothing_line "Vyavasta’s server isn’t working right now" "$prefix${AGENT} works as usual, and Vyavasta is tried again in a minute.")
      OUT_CONTEXT="${START_CONTEXT:-}"; emit; return ;;
    *)
      OUT_LINE=$(line "your message" "" "${prefix}Vyavasta couldn’t check it just now. ${AGENT} works as usual.")
      OUT_CONTEXT="${START_CONTEXT:-}"; emit; return ;;
  esac
  cp "$TMP/answer" "$TMP/checked"
  # Whether the message's words were kept in this session's chat for the developer's summary: the tool's reply to
  # it is then sent when the turn ends, named by the kept message's id when the server gave one.
  if [ "$(answer kept)" = "true" ]; then
    json_text "$(answer kept_id)" | tr -cd 'A-Za-z0-9_.:-' | cut -c1-200 > "$dir/turn-waiting"
    kept_said="Kept in this session’s chat for your summary."
  elif [ "$(summaries)" = "off" ]; then kept_said="Not kept, because summaries are off."
  else kept_said="Not kept for your summary."; fi
  verdict=$(json_text "$(answer verdict)")
  notice=$(json_text "$(answer notice)")
  context=$(json_text "$(answer context)")
  was_shared=$(json_text "$(answer sharing)")
  new_conflict=""
  keep_conflict "$dir" && new_conflict=1
  # What was sent, and what was not.
  sent="your message"; not_sent=""
  [ -n "${START_LINE:-}" ] && sent="the task’s words"
  if [ -n "$shared" ]; then
    if [ "$was_shared" = "off" ] && [ "$verdict" != "not_connected" ]; then
      echo off > "$PDIR/sharing"; echo off > "$PDIR/sharing-told"
      not_sent="your code changes (code sharing was turned off for this repository in Vyavasta’s web app, so it is off here too; send “vyavasta share code on” to turn it on again)"
    elif [ "${CH_FILES:-0}" -gt 0 ]; then
      sent="$sent and your uncommitted changes ($(plural "$CH_FILES" file files), $(plural "$CH_LINES" line lines) of changes)"
    fi
    left=$(left_out_said)
    if [ -n "$left" ] && [ "$was_shared" != "off" ]; then
      not_sent="${not_sent:+$not_sent; }$left"
    fi
  fi
  # The names of changed files go with a work report, in a repository Vyavasta reads.
  if [ "$NFILES" -gt 0 ] && [ "$verdict" != "not_connected" ] && [ -n "$REMOTE" ]; then
    report_work "$dir" changing
    if [ "$REPORTED" = "1" ] && { [ -z "$shared" ] || [ "$was_shared" = "off" ]; }; then
      sent="$sent and $(plural "$NFILES" "changed file’s name" "changed files’ names")"
      [ -n "$shared" ] || not_sent="${not_sent:+$not_sent; }what the files hold (code sharing is off)"
    fi
    keep_conflict "$dir" && new_conflict=1
  fi
  cp "$TMP/checked" "$TMP/answer"
  if [ "$(answer ask)" = "true" ]; then
    # A question for the developer's own assistant in Vyavasta: asked there, in this session's chat, and the
    # answer is given to the tool's model to pass on. When no answer comes, the model has the message as it is.
    # A message put to the team is never also taken for a question about using the plugin.
    GUIDE=""
    printf '{"question":%s,"remote":%s,"branch":%s,"session":%s,"tool":"%s","keep":%s}' "$prompt" \
      "$(json_quote "$REMOTE")" "$(json_quote "$BRANCH")" "$(json_quote "$SESSION")" "$CLIENT" "$keep" > "$TMP/ask"
    ask_vyavasta "$TMP/ask"
    sent=$(printf '%s' "$sent" | sed 's/^your message/your question/')
    if [ "$STATUS" != "200" ]; then
      OUT_LINE=$(line "$sent" "$not_sent" "${prefix}Your question couldn’t be asked just now, so ${AGENT} answers by itself.$consent")
    else
      outcome=$(json_text "$(answer notice)")
      [ -n "$outcome" ] || outcome="Vyavasta had no answer to give."
      OUT_LINE=$(line "$sent" "$not_sent" "$prefix$outcome$consent")
      OUT_CONTEXT=$(json_text "$(answer context)")
    fi
  else
    case "$verdict" in
      not_a_change) outcome="It isn’t a request for a change or a question about your team, so nothing was checked." ;;
      not_connected)
        if [ -z "$ROOT" ]; then outcome="This folder isn’t a git repository, so nothing was checked. Questions about your team are still answered here."
        elif [ -z "$REMOTE" ]; then outcome="This folder has no copy on GitHub, so nothing was checked. Questions about your team are still answered here."
        else outcome="${notice:-Vyavasta doesn’t read this repository for you, so nothing was checked.}"; fi ;;
      *) outcome="${notice:-Checked against your team’s record.}" ;;
    esac
    if [ -n "$CONNECTED" ]; then outcome="$CONNECTED $outcome"; fi
    if [ "$(answer hold)" = "true" ]; then
      # Held, as the web app holds a plan: the model isn't sent the request, and the developer is told why and how
      # to go on. What going on tells the model is kept for this session until then.
      answer anyway > "$TMP/anyway"
      json_get "$TMP/anyway" context > "$dir/held"
      # The notice below says what stands, so the line only says which kind of hold it is.
      if [ "$verdict" = "held" ]; then held_said="On hold; see below."
      else held_said="On hold: what your team has said doesn’t settle this request; see below."; fi
      OUT_LINE=$(line "$sent" "$not_sent" "$prefix$held_said$consent" "$kept_said")
      OUT_REASON="$notice"
      emit; return
    fi
    OUT_LINE=$(line "$sent" "$not_sent" "$prefix$outcome$consent" "$kept_said")
    OUT_CONTEXT="$context"
  fi
  if [ -n "${attach_note:-}" ]; then
    chat_page "$dir"
    if [ -n "$CHAT_UPLOAD" ]; then
      if [ ! -f "$dir/opened-upload" ]; then
        true > "$dir/opened-upload"
        open_page "$CHAT_UPLOAD"
        OUT_LINE="$OUT_LINE Your image stays in ${TOOL}; this session’s chat is open in your browser so you can drop it there for Vyavasta."
      else
        OUT_LINE="$OUT_LINE Your image stays in ${TOOL}; to give it to Vyavasta, drop it in this session’s chat: $CHAT_UPLOAD"
      fi
    fi
  fi
  [ -n "$CONFLICT_CONTEXT" ] && OUT_CONTEXT="$CONFLICT_CONTEXT${OUT_CONTEXT:+

$OUT_CONTEXT}"
  [ -n "${START_CONTEXT:-}" ] && OUT_CONTEXT="$START_CONTEXT${OUT_CONTEXT:+

$OUT_CONTEXT}"
  if [ -n "$new_conflict" ]; then
    # Something the team said stands against the change already made: the message waits until the developer
    # chooses, and is kept to pass on if they continue.
    json_text "$prompt" > "$dir/conflict-prompt"
    rm -f "$dir/conflict-stop" "$dir/conflict-say"
    OUT_LINE=$(line "$sent" "$not_sent" "${prefix}Paused: something your team has said stands against the changes already made on your computer. Your message waits until you answer." "$kept_said")
    OUT_REASON="$(json_text "$(field "$(cat "$dir/conflict")" notice)")

Send “continue” to go on, or “stop” to leave the change where it is."
    OUT_CONTEXT=""
  fi
  emit
}

# Whether a message's words are to be kept in the session's chat for the developer's summary: with summaries on (and
# the developer told so), every message but those the plugin's own commands make (a started task's words) and the
# answers to the plugin's own questions (never_kept).
keep_this() {
  summaries_keep || return 1
  [ -z "${START_LINE:-}" ] || return 1
  never_kept "${words:-}" && return 1
  return 0
}

# Prints what a message's hook answers: a block with its reason, or the one line and what the model is given. The
# line carries what summaries do when it is the first to tell it.
emit() {
  [ -n "$OUT_LINE" ] && OUT_LINE="$OUT_LINE${SUMMARIES_NOTE:-}"
  [ -n "${GUIDE:-}" ] && OUT_CONTEXT="${OUT_CONTEXT:+$OUT_CONTEXT

}$GUIDE"
  if [ -n "$OUT_REASON" ]; then
    if [ -n "$OUT_LINE" ]; then
      printf '{"systemMessage":%s,"decision":"block","reason":%s}\n' "$(json_quote "$OUT_LINE")" "$(json_quote "$OUT_REASON")"
    else
      printf '{"decision":"block","reason":%s}\n' "$(json_quote "$OUT_REASON")"
    fi
  elif [ -n "$OUT_CONTEXT" ]; then
    printf '{"systemMessage":%s,"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' \
      "$(json_quote "$OUT_LINE")" "$(json_quote "$OUT_CONTEXT")"
  elif [ -n "$OUT_LINE" ]; then
    say "$OUT_LINE"
  fi
}

# Tells the server whether code sharing is on for this project's repository. Quiet; sets SHARING_NOTICE.
tell_sharing() {
  SHARING_NOTICE=""
  printf '{"remote":%s,"on":%s}' "$(json_quote "$REMOTE")" "$([ "$1" = on ] && echo true || echo false)" > "$TMP/sharing"
  api POST /sharing "$TMP/sharing" "$QUICK_SECONDS"
  if [ "$STATUS" = "200" ]; then
    echo "$1" > "$PDIR/sharing-told"
    SHARING_NOTICE=$(json_text "$(answer notice)")
    return 0
  fi
  rm -f "$PDIR/sharing-told"
  return 1
}

# Sends git's list of changed files (and, with code sharing on, the changes when they moved since they were last
# sent) as the session's work. Sets REPORTED to 1 when the server took it. $1 is the session folder.
report_work() {
  REPORTED=""
  [ -f "$TMP/files" ] || changed_files
  state=$(work_state "$1")
  # A session that has nothing open and nothing changed has nothing to tell.
  [ "$state" != "changing" ] && [ ! -f "$1/open" ] && return
  with_change=""
  if [ "$(sharing)" = "on" ]; then
    [ -f "$TMP/change" ] || build_change
    if [ "$(cksum < "$TMP/change")" != "$(cat "$1/change-sum")" ]; then with_change=1; fi
  fi
  {
    printf '{"remote":%s,"branch":%s,"session":%s,"state":"%s","files":[%s],"tool":"%s"' "$(json_quote "$REMOTE")" \
      "$(json_quote "$BRANCH")" "$(json_quote "$(basename "$1")")" "$state" "$(cat "$TMP/files")" "$CLIENT"
    if [ -n "$with_change" ]; then printf ',"change":'; cat "$TMP/change"; fi
    printf '}'
  } > "$TMP/report"
  api POST /work "$TMP/report" "$REPORT_SECONDS"
  now > "$1/reported"
  [ "$STATUS" = "200" ] || return
  REPORTED=1
  [ -n "$with_change" ] && cksum < "$TMP/change" > "$1/change-sum"
  if [ "$(answer recorded)" = "true" ]; then
    case "$(json_text "$(answer status)")" in
      pushed|abandoned) rm -f "$1/open" ;;
      *) true > "$1/open" ;;
    esac
  fi
  if [ "$(json_text "$(answer sharing)")" = "off" ] && [ "$(sharing)" = "on" ] && [ -n "$with_change" ]; then
    echo off > "$PDIR/sharing"; echo off > "$PDIR/sharing-told"
  fi
}

# After an edit (``edited``, at most every REPORT_EVERY seconds) and when the tool stops (``stopped``): git's list
# of changed files goes to the server, which keeps the session's work for teammates to see. When the tool stops
# after a message that was kept for the developer's summary, its last reply goes to the same chat. Nothing is
# printed, except when the tool stops while a conflict found in the change waits to be told.
hook_report() {
  dir=$(session_dir "$(json_text "$(json_get "$TMP/input" session_id)")")
  folder=$(input_folder)
  project_of "$folder"
  project_on || return
  if [ "$1" = "edited" ] && [ -f "$dir/reported" ]; then
    last=$(cat "$dir/reported")
    [ -n "$last" ] && [ $(( $(now) - last )) -lt "$REPORT_EVERY" ] && return
  fi
  STATUS=""
  if [ -n "$TOKEN" ] && repository "$folder" && ! offline; then
    changed_files
    report_work "$dir"
    [ "$REPORTED" = "1" ] && keep_conflict "$dir"
  fi
  # (A report just now that found the server out of reach, or too slow to answer, is not followed by a second
  # call: the end of a turn is never held up twice.)
  if [ "$1" = "stopped" ] && [ -f "$dir/turn-waiting" ]; then
    if [ "$(summaries)" = "off" ]; then rm -f "$dir/turn-waiting"
    elif [ -n "$TOKEN" ] && [ "$STATUS" != "000" ] && ! offline; then send_turn "$dir" "$folder"; fi
  fi
  if [ "$1" = "stopped" ] && [ -f "$dir/conflict-say" ]; then
    cat "$dir/conflict-say"
    rm -f "$dir/conflict-say" "$dir/conflict-stop"
  fi
}

# The tool's last reply of the turn, from the Stop hook's input, as a JSON string of at most REPLY_CHARACTERS
# characters ("" when there is none). Only the first part of the reply is ever decoded; bytes that aren't UTF-8 are
# dropped; the cut never falls inside a character; and the text is escaped a line at a time, never a character at a
# time.
reply_json() {
  json_get "$TMP/input" last_assistant_message > "$TMP/reply-raw"
  case "$(head -c 1 "$TMP/reply-raw")" in \") ;; *) printf '""'; return ;; esac
  # No character takes more than 12 bytes of JSON (two \u escapes), so this much holds every character kept. A
  # string cut short, here or by the hook's input being cut, is closed again.
  head -c $((REPLY_CHARACTERS * 12 + 12)) "$TMP/reply-raw" > "$TMP/reply-cut"
  awk 'BEGIN { RS = "\001"; closed = 0 }
    NR == 1 { n = length($0); if (n >= 2 && substr($0, n, 1) == "\"") closed = !(match(substr($0, 1, n - 1), /\\+$/) && RLENGTH % 2) }
    END { exit closed ? 0 : 1 }' "$TMP/reply-cut" || printf '"' >> "$TMP/reply-cut"
  json_text "$(cat "$TMP/reply-cut")" > "$TMP/reply-text"
  clean_utf8 "$TMP/reply-text" "$TMP/reply-clean"
  # (A last character after the text, so a line break that ends it is not lost: taken off again below.)
  printf 'x' >> "$TMP/reply-clean"
  awk -v MOST="$REPLY_CHARACTERS" "$AWK_ESCAPE"'
    # The characters of valid UTF-8 text: its bytes, less those that continue a character.
    function chars(s) { return length(s) - gsub(CONT, "", s) }
    function put(line,   c, lo, hi, mid) {
      if (full) return
      if (lines++) { if (used >= MOST) { full = 1; return }; printf "\\n"; used++ }
      c = chars(line)
      if (used + c > MOST) {
        # The longest start of the line that fits, found by halves: it ends where a character ends.
        lo = 0; hi = length(line)
        while (lo < hi) { mid = int((lo + hi + 1) / 2); if (chars(substr(line, 1, mid)) <= MOST - used) lo = mid; else hi = mid - 1 }
        line = substr(line, 1, lo); c = MOST - used; full = 1
      }
      printf "%s", esc(line); used += c
    }
    BEGIN { CONT = "[" sprintf("%c", 128) "-" sprintf("%c", 191) "]"; used = 0; full = 0; lines = 0; printf "\"" }
    NR > 1 { put(held) }
    { held = $0 }
    END { sub(/x$/, "", held); put(held); printf "\"" }' "$TMP/reply-clean"
}

# Sends the turn's reply to the session's chat, as the answer to the message kept this turn (named by its id when
# the server gave one). Quiet, and never longer than TURN_SECONDS. $1 is the session folder, $2 the folder the tool
# works in.
send_turn() {
  if repository "$2"; then :; else REMOTE=""; BRANCH=""; fi
  kept_id=$(cat "$1/turn-waiting")
  {
    printf '{"session":%s,"remote":%s,"branch":%s,"tool":"%s","keep":true' \
      "$(json_quote "$(basename "$1")")" "$(json_quote "$REMOTE")" "$(json_quote "$BRANCH")" "$CLIENT"
    [ -n "$kept_id" ] && printf ',"message_id":%s' "$(json_quote "$kept_id")"
    printf ',"reply":'
    reply_json
    printf '}'
  } > "$TMP/turn"
  api POST /turn "$TMP/turn" "$TURN_SECONDS"
  # Tried again at the next stop only when the server couldn't be reached.
  [ "$STATUS" = "000" ] || rm -f "$1/turn-waiting"
}

# -- the commands ------------------------------------------------------------------------------------------------

# The folder a command is about: the hook's cwd, else the tool's project folder, else here. Sets PROJECT and PDIR.
command_here() {
  HERE="${HERE:-${CLAUDE_PROJECT_DIR:-$PWD}}"
  project_of "$HERE"
}

# The session a command run outside a hook belongs to: the one a message was last sent in from this project.
command_session() {
  if [ -n "${SESSION:-}" ]; then printf '%s' "$SESSION"; return; fi
  if [ -n "${VYAVASTA_SESSION:-}" ]; then printf '%s' "$VYAVASTA_SESSION"; return; fi
  [ -f "$PDIR/session" ] && { cat "$PDIR/session"; return; }
  cat "$HOME_DIR/session"
}

# The line a command gives when it needs the server and can't have it: signed out, the connection ended, or the
# server out of reach. Fails (and says so) unless signed in.
need_token() {
  finish_pairing
  if [ -z "$TOKEN" ]; then
    if pending_waiting; then
      PAIR_AGAIN=1
      echo "You aren’t signed in to Vyavasta on this computer yet. To connect, $(code_said). Once you approve, send this again."
    else
      echo "You aren’t signed in to Vyavasta on this computer. $WAY_IN"
    fi
    return 1
  fi
}

not_reached() {
  case "$STATUS" in
    401) echo "This computer’s connection to Vyavasta has ended. $WAY_IN_AGAIN" ;;
    429) echo "Vyavasta had too many requests just now. Try again in a minute." ;;
    000)
      if [ -n "$SLOW" ]; then echo "Vyavasta took too long to answer. Try again in a moment."
      elif [ "$CLIENT" = "codex" ] && [ -z "${IN_HOOK:-}" ]; then echo "Vyavasta can’t be reached from here. Codex runs the commands its model starts in a closed-off space that can’t reach the internet: send it as a message instead, such as “vyavasta status”."
      else echo "Vyavasta’s server can’t be reached right now. Check your internet connection, or try again in a minute."; fi ;;
    5*) echo "Vyavasta’s server isn’t working right now. Try again in a minute." ;;
    *) said=$(refusal); echo "${said:-Vyavasta couldn’t do that just now. Try again in a minute.}" ;;
  esac
}

command_sign_in() {
  command_here
  finish_pairing
  if [ -n "$TOKEN" ]; then
    api GET /me "" "$QUICK_SECONDS"
    if [ "$STATUS" = "200" ]; then
      echo "${CONNECTED:-Already signed in to Vyavasta ($SERVER) as $(json_text "$(answer email)").} ${VERB} ${CMD_SIGN_OUT} first to switch accounts."
      return
    fi
  fi
  # A sign-in still waiting is told again, never started a second time.
  if ! start_pairing; then
    echo "Couldn’t start connecting to Vyavasta at $SERVER: ${PAIR_FAILED%.}."
    [ "$STATUS" = "000" ] && echo "Check the address and your connection. To use another server, set VYAVASTA_SERVER before starting ${TOOL}."
    return
  fi
  machine=$(hostname | cut -d. -f1)
  [ -n "$machine" ] || machine=$(uname -n)
  if [ -n "$PAIR_AGAIN" ]; then
    echo "A sign-in is already waiting for you. To connect ${TOOL} on $machine to Vyavasta, $(code_said)."
  else
    echo "To connect ${TOOL} on $machine to Vyavasta, $(code_said)."
  fi
  lasts_said=$(code_lasts_said)
  echo "${lasts_said:+$lasts_said }$(finish_said)"
}

command_sign_out() {
  rm -f "$PENDING"
  if [ -z "$TOKEN" ]; then
    rm -f "$CREDENTIALS"
    echo "Not signed in to Vyavasta on this computer."
    return
  fi
  api POST /signout "" "$QUICK_SECONDS"
  rm -f "$CREDENTIALS"
  forget_told
  echo "Signed out of Vyavasta on this computer. Requests are no longer checked, and nothing is sent from this computer."
}

command_on() {
  command_here
  already=""
  project_on && already=1
  if ! { project_keep && true > "$PDIR/on"; }; then
    echo "Vyavasta couldn’t save that it is on here, because its settings folder ($HOME_DIR) can’t be written. If ${TOOL} ran this as a command, send “vyavasta on” as a message instead."
    return
  fi
  mkdir -p "$HOME_DIR" && true > "$HOME_DIR/welcomed"
  if [ -n "${SESSION:-}" ]; then
    printf '%s\n' "$SESSION" > "$PDIR/session"
    if repository "$HERE"; then
      [ -f "$SESSIONS/$SESSION/start" ] || git -C "$ROOT" rev-parse -q --verify HEAD > "$SESSIONS/$SESSION/start"
    fi
  fi
  if [ -n "$already" ]; then echo "Vyavasta is already on for $(folder_name "$PROJECT") ($PROJECT)."
  else echo "Vyavasta is on for $(folder_name "$PROJECT") ($PROJECT)."; fi
  finish_pairing
  if repository "$HERE"; then :; else ROOT=""; REMOTE=""; fi
  if [ -z "$TOKEN" ]; then
    if start_pairing; then
      # The page is open already: the session's first message doesn't open it a second time.
      [ -n "${SESSION:-}" ] && mkdir -p "$SESSIONS/$SESSION" && true > "$SESSIONS/$SESSION/said-sign-in"
      lasts_said=$(code_lasts_said)
      echo "To sign in, $(code_said). ${lasts_said:+$lasts_said }Once you approve, your next message finishes connecting."
    else
      echo "You aren’t signed in, and sign-in couldn’t start: $(pair_failed_said) $WAY_IN"
    fi
    repo_said
  else
    api GET /me "" "$QUICK_SECONDS"
    if [ "$STATUS" = "200" ]; then
      remember_me
      echo "${CONNECTED:-Signed in as $(json_text "$(answer email)") in $(json_text "$(json_get "$TMP/workspace" name)").}"
      repo_said "$(answer repositories)"
    else
      not_reached
      repo_said
    fi
  fi
  if [ -n "$ROOT" ] && [ -n "$REMOTE" ]; then
    if [ "$(sharing)" = "on" ]; then
      echo "Code sharing is on: your uncommitted changes go with each message and after each edit. Send “vyavasta share code off” to stop."
    else
      echo "Code sharing is off: your changed files’ names are sent, not your uncommitted changes. Send “vyavasta share code on” to also send them."
    fi
  fi
  # This answer tells what summaries do, so no later line tells it again.
  summaries_said
  mark_summaries_told
  echo "Send “vyavasta help” for everything else, or “vyavasta off” to turn it off here."
}

# Whether Vyavasta reads this project's repository. $1, when given, is /me's list of repositories.
repo_said() {
  if [ -z "$ROOT" ]; then
    echo "This folder isn’t a git repository, so changes here aren’t checked. Questions about your team are answered here all the same."
  elif [ -z "$REMOTE" ]; then
    echo "This repository has no copy on GitHub, so changes here aren’t checked. Questions about your team are answered here all the same."
  elif [ -n "${1:-}" ]; then
    name=$(repository_name "$REMOTE")
    if lists_repository "$1" "$name"; then echo "Vyavasta reads $name for you: requests here are checked against your team’s record."
    else echo "Vyavasta doesn’t read $name for you, so changes here aren’t checked. Connect it with GitHub in Vyavasta’s Sources."; fi
  fi
}

# What summaries do in this project, and how to change that, in one line.
summaries_said() {
  if [ "$(summaries)" = "on" ]; then
    echo "Summaries are on: your messages here and ${TOOL}’s replies, as written, are kept in a chat of your own in Vyavasta and summed up for teammates under categories you control there. $(summaries_scope) Send “vyavasta summaries off” to stop."
  else
    echo "Summaries are off: $(summaries_off_said) Send “vyavasta summaries on” to turn them on."
  fi
}

# What is kept with summaries on, and what never is, in short sentences.
summaries_scope() {
  printf '%s' "A reply can quote code or what a file holds. Nothing else of the conversation is kept: not ${TOOL}’s other steps, the commands it ran or the files it read."
}

# What summaries off means, in short sentences.
summaries_off_said() {
  printf '%s' "nothing you write in this project, and none of ${TOOL}’s replies, is kept or summed up for teammates. A question about your team is still answered by Vyavasta’s assistant. It stays in your chat there, where you can delete it."
}

command_off() {
  command_here
  rm -f "$PDIR/on"
  echo "Vyavasta is off for $(folder_name "$PROJECT"): nothing is checked or sent from here. Send “vyavasta on” to turn it back on."
}

command_share_on() {
  command_here
  if ! repository "$HERE" || [ -z "$REMOTE" ]; then
    echo "This folder has no copy on GitHub, so there is no code to share with Vyavasta from here."
    return
  fi
  if ! { project_keep && echo on > "$PDIR/sharing"; }; then
    echo "Vyavasta couldn’t save the setting, because its settings folder ($HOME_DIR) can’t be written. Send “vyavasta share code on” as a message instead."
    return
  fi
  name=$(repository_name "$REMOTE")
  limit_lines=$CHANGE_LINES
  [ -f "$HOME_DIR/limits" ] && kept_lines=$(sed -n 's/^lines=//p' "$HOME_DIR/limits") && case "$kept_lines" in ''|*[!0-9]*) ;; *) limit_lines=$kept_lines ;; esac
  told=""; SHARING_NOTICE=""
  if [ -n "$TOKEN" ] && ! offline; then tell_sharing on && told=1; fi
  # The server's own account when it answered (what Vyavasta does with the changes, and whether it reads this
  # repository), else the plugin's. The list of what never leaves this computer is always the plugin's: it decides.
  if [ -n "$SHARING_NOTICE" ]; then echo "$SHARING_NOTICE"
  else
    echo "Code sharing is on for $name: your uncommitted changes (up to $(thousands "$limit_lines") lines) now go to Vyavasta with each message and after each edit, and Vyavasta’s check reads them."
    echo "Teammates who can already see this work see a short summary of what the change does, never the code. Vyavasta keeps only the latest changes of each session, for 7 days at most."
  fi
  echo "Never sent from this computer: files git ignores, key and password files (such as .env or .pem), machine-written files such as lock files and build output, and files that aren’t text."
  project_on || echo "Vyavasta is off in this project, so nothing is sent until you send “vyavasta on”."
  [ -z "$told" ] && [ -n "$TOKEN" ] && echo "Vyavasta couldn’t be told just now; it is told with your next message."
  echo "Send “vyavasta share code off” to stop it and delete what was kept."
}

command_share_off() {
  command_here
  project_keep && echo off > "$PDIR/sharing"
  SHARING_NOTICE=""
  if repository "$HERE" && [ -n "$REMOTE" ] && [ -n "$TOKEN" ] && ! offline; then tell_sharing off; fi
  if [ -n "$SHARING_NOTICE" ]; then echo "$SHARING_NOTICE"
  else echo "Code sharing is off: from now on your uncommitted changes aren’t sent, only your changed files’ names."; fi
  echo "Send “vyavasta share code on” to turn it on again."
}

command_summaries_on() {
  command_here
  if ! { project_keep && echo on > "$PDIR/summaries"; }; then
    echo "Vyavasta couldn’t save the setting, because its settings folder ($HOME_DIR) can’t be written. Send “vyavasta summaries on” as a message instead."
    return
  fi
  mark_summaries_told
  echo "Summaries are on for $(folder_name "$PROJECT"): your messages here and ${TOOL}’s replies, as written, are kept in this session’s chat in Vyavasta, which only you read, and summed up for teammates under categories you control there."
  summaries_scope; echo
  project_on || echo "Vyavasta is off in this project, so nothing is kept until you send “vyavasta on”."
  echo "Send “vyavasta summaries off” to stop."
}

command_summaries_off() {
  command_here
  if ! { project_keep && echo off > "$PDIR/summaries"; }; then
    echo "Vyavasta couldn’t save the setting, because its settings folder ($HOME_DIR) can’t be written. Send “vyavasta summaries off” as a message instead."
    return
  fi
  echo "Summaries are off for $(folder_name "$PROJECT"): from now on $(summaries_off_said) Chats kept before stay in Vyavasta, where you can delete them."
  echo "Send “vyavasta summaries on” to turn them on again."
}

command_status() {
  command_here
  echo "Vyavasta plugin $VERSION, server $SERVER."
  if project_on; then echo "Vyavasta is on in this project ($(folder_name "$PROJECT"))."
  else echo "Vyavasta is off in this project ($(folder_name "$PROJECT")). Send “vyavasta on” to use it here."; fi
  if project_on; then echo "Code sharing is $(sharing) for this project."; echo "Summaries are $(summaries) for this project."; fi
  finish_pairing
  [ -n "${CONNECTED:-}" ] && echo "$CONNECTED" | sed 's/^Connected/connected/'
  if [ -z "$TOKEN" ]; then
    if pending_waiting; then
      PAIR_AGAIN=1
      echo "Waiting for you to approve the connection: $(code_said). $(finish_said)"
    else
      echo "Not signed in. $WAY_IN"
    fi
    return
  fi
  api GET /me "" "$QUICK_SECONDS"
  case "$STATUS" in
    200)
      remember_me
      echo "Signed in as $(json_text "$(answer email)") in $(json_text "$(json_get "$TMP/workspace" name)"), on $(json_text "$(answer machine)")."
      repositories=$(answer repositories)
      if repository "$HERE" && [ -n "$REMOTE" ]; then
        name=$(repository_name "$REMOTE")
        if lists_repository "$repositories" "$name"; then
          echo "Vyavasta reads $name for you: requests here are checked, and teammates see which files you’re changing."
        else
          echo "Vyavasta doesn’t read $name for you, so nothing here is checked. Connect it with GitHub in Vyavasta’s Sources."
        fi
      fi
      ;;
    *) not_reached ;;
  esac
}

command_settings() {
  command_here
  echo "Vyavasta settings for $(folder_name "$PROJECT"):"
  if project_on; then echo "- This project: on. Send “vyavasta off” to turn it off."
  else echo "- This project: off. Send “vyavasta on” to turn it on."; fi
  if [ "$(sharing)" = "on" ]; then echo "- Code sharing: on. Send “vyavasta share code off” to turn it off."
  else echo "- Code sharing: off. Send “vyavasta share code on” to turn it on."; fi
  if [ "$(summaries)" = "on" ]; then echo "- Summaries: on. Send “vyavasta summaries off” to turn them off."
  else echo "- Summaries: off. Send “vyavasta summaries on” to turn them on."; fi
  if [ -n "$TOKEN" ]; then echo "- Signed in as: $(saved email) in $(saved workspace). Send “vyavasta sign out” to sign out."
  else echo "- Signed in as: nobody. $WAY_IN"; fi
  echo "- Server: $SERVER. To use another, run “sh $SELF use-server <address>” in a terminal, or set VYAVASTA_SERVER."
}

# Help: what Vyavasta does here in two lines, the three steps to start with the state of each, then every command,
# one line each. It is read as the reason of a blocked message in both tools, so it stays short. No call is made
# but the one that finishes a sign-in that waits.
command_help() {
  command_here
  finish_pairing
  if [ -n "$TOKEN" ]; then signed="You’re signed in as $(saved email) in $(saved workspace)."
  elif pending_waiting; then PAIR_AGAIN=1; signed="A sign-in is waiting: $(code_said)."
  else signed="You aren’t signed in yet."; fi
  if project_on; then here="It is on here."; else here="It is off here now."; fi
  cat <<EOF
Vyavasta connects ${TOOL} to your team’s record. Where it is on, it checks each request against what your team has said and decided before ${AGENT} changes code.
It also sums each session up for teammates under categories you control, answers your questions about the team, and lets you ask teammates’ agents.
Start here
1. Sign in: send “vyavasta sign in”. $signed
2. Turn it on in this project: send “vyavasta on”. $here
3. Then just work. Every message gets one line from Vyavasta saying what was sent, and what came of it.
Everything else, each sent as a message of its own:
Your setup
- “vyavasta status”: whether you’re signed in, and whether this project, code sharing and summaries are on.
- “vyavasta check”: tests sign-in, the connection, this project and the plugin’s version, and says how to fix each problem.
- “vyavasta off”: stop using Vyavasta in this project.
- “vyavasta sign out”: disconnect this computer.
See what is shared
- “vyavasta settings”: every setting and how to change it.
- “vyavasta share code on” / “vyavasta share code off”: start or stop code sharing, which sends your uncommitted changes with each message.
- “vyavasta summaries on” / “vyavasta summaries off”: start or stop summaries, which keep your messages and the replies in a chat of your own, summed up for teammates.
- “vyavasta shared”: everything sent from this session.
- “vyavasta chat” (or “vyavasta chat open”): this session’s chat in Vyavasta.
- “vyavasta upload”: opens that chat so you can drop in a file for your next question.
Teammates
- “vyavasta inbox”: what teammates asked of you.
- “vyavasta ask <name>: <question>”: ask a teammate’s agent. It answers only from what you can both already see, and they see what you asked.
- “vyavasta assign <name>: <task>”: give a teammate a task (owners and administrators).
- “vyavasta reply <number>: <your words>”, “vyavasta start <number>”, “vyavasta done <number>”, “vyavasta decline <number>”: answer an item of your inbox.
EOF
  [ "$CLIENT" = "claude-code" ] && echo "In Claude Code most of these are slash commands too, such as /vyavasta:on, /vyavasta:shared and /vyavasta:check; ask, assign, reply, start, done and decline are typed only."
}

# What the tool's model is told when the developer's message asks how to use the plugin itself (guide_wanted): what
# Vyavasta is, the phrases the developer sends, and that the
# model cannot send them itself. No call is made for it. Slash commands are named only to Claude Code's model.
guide_context() {
  case "$CLIENT" in
    codex) also="" ;;
    *) also=" In Claude Code most of these are also slash commands, such as /vyavasta:sign-in, /vyavasta:on and /vyavasta:help, which the developer can run instead." ;;
  esac
  printf '%s' "The developer’s message asks about the Vyavasta plugin. Vyavasta connects ${TOOL} to the developer’s team: in a project where it is on, it checks each request against what the team has said and decided before you change code, sums each session up for teammates under categories the developer controls, answers questions about the team, and lets the developer ask teammates’ agents. It is off in every project until the developer turns it on there. These phrases are the plugin’s own commands. The developer sends each one as a message of its own, and the plugin answers it itself before it reaches you, so you cannot run them: tell the developer which one to send. Sign in: “vyavasta sign in” (the sign-in page opens in their browser with a code to enter). Turn it on in this project: “vyavasta on”, and “vyavasta off” to stop. Everything it does: “vyavasta help”. Whether they are signed in and it is on: “vyavasta status”. Test the setup and say how to fix each problem: “vyavasta check”. Every setting: “vyavasta settings”. Summaries, which keep the developer’s messages and your replies in a chat of their own in Vyavasta and sum them up for teammates: “vyavasta summaries on” and “vyavasta summaries off”. Code sharing, which also sends their uncommitted changes for the check (teammates see only a short summary, never the code): “vyavasta share code on” and “vyavasta share code off”. What it sends from a project that is on: each message’s words, the repository and branch, changed files’ names, and with code sharing on the uncommitted changes; from a project that is off, nothing of their work. Every message in a project that is on gets one line saying what was sent.$also"
}

# Whether a message asks how to use the plugin itself: it is short (GUIDE_LONGEST), asks something (a question mark,
# a question word, or a first word such as “can”), and within one sentence ties Vyavasta's name directly to the
# plugin: “the Vyavasta plugin”, “Vyavasta’s commands”, “sign in to Vyavasta”, “set up / install / use / connect /
# turn on Vyavasta”, “turn Vyavasta off”, “how does Vyavasta work”, “what can Vyavasta do”, “what does Vyavasta
# send”. A message that only mentions the name near such words (“How do I connect to the database? Vyavasta said
# Priya knows.”) never is, and neither is one addressed to Vyavasta (it starts with the name): those that ask for help
# are the plugin's help command, and the rest are put to the team. $1 is the message's text.
guide_wanted() {
  [ "${#1}" -le "$GUIDE_LONGEST" ] || return 1
  printf '%s' "$1" | grep -qi -e vyavasta -e vyavastha || return 1
  printf '%s' "$1" | awk 'BEGIN { RS = "\001"; wanted = 0 }
    NR == 1 {
      s = tolower($0)
      if (index(s, "vyavasta") == 0 && index(s, "vyavastha") == 0) exit
      # Addressed to Vyavasta: never this.
      t = s; sub(/^[^a-z0-9]+/, "", t)
      if (t ~ /^vyavasth?a([^a-z0-9_-]|$)/) exit
      asked = index(s, "?") > 0
      # Words, with each break between sentences or clauses kept as a full stop of its own, so a phrase never runs
      # across one; a name joined to more letters by a hyphen or underscore (vyavasta_export) is another word.
      gsub(/[.?!;:,()]+/, " . ", s)
      gsub(/[^a-z0-9_.-]+/, " ", s); gsub(/ +/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); s = " " s " "
      if (s ~ / (how|what|where|why|which|when) /) asked = 1
      if (s ~ /^ (can|could|do|does|is|are|should|would|will) /) asked = 1
      if (!asked) exit
      name = "vyavasth?a"
      if (s ~ (" " name " (plugin|plugins|extension|hooks?|commands?|settings|setup|sign-in|sign in|summaries|code sharing|privacy)( s)? ")) wanted = 1
      if (s ~ (" " name " s (plugin|commands?|settings|setup|sign-in|summaries|code sharing|privacy) ")) wanted = 1
      if (s ~ (" (sign|log) (in|into|in to|out of) " name " ")) wanted = 1
      if (s ~ (" (sign-in|signin|login|log-in) (to|into) " name " ")) wanted = 1
      if (s ~ (" (use|using|start using|get started with|set up|setup|install|installing|reinstall|uninstall|update|upgrade|configure|connect|connecting|enable|disable|turn on|turn off|switch on|switch off|activate|deactivate) " name " ")) wanted = 1
      if (s ~ (" (turn|switch) " name " (on|off) ")) wanted = 1
      if (s ~ (" how (does|do|will|would|can) " name " work ")) wanted = 1
      if (s ~ (" what (can|could|does|do|will|would) " name " (do|send|sends|share|shares|keep|keeps|see|sees|collect|store|read) ")) wanted = 1
      if (s ~ (" what is " name " (\\. )?$")) wanted = 1
      if (s ~ (" is " name " (on|off|installed|connected|working|sending|sharing|keeping) ")) wanted = 1
    }
    END { exit wanted ? 0 : 1 }'
}

# This session's chat in Vyavasta: sets CHAT_URL and CHAT_UPLOAD (empty when it couldn't be had).
chat_page() {
  CHAT_URL=""; CHAT_UPLOAD=""
  printf '{"session":%s,"remote":%s,"branch":%s,"tool":"%s"}' "$(json_quote "$(command_session)")" \
    "$(json_quote "${REMOTE:-}")" "$(json_quote "${BRANCH:-}")" "$CLIENT" > "$TMP/chat"
  api POST /chat "$TMP/chat" "$QUICK_SECONDS"
  [ "$STATUS" = "200" ] || [ "$STATUS" = "201" ] || return 1
  CHAT_URL=$(json_text "$(answer url)")
  CHAT_UPLOAD=$(json_text "$(answer upload_url)")
  [ -n "$CHAT_UPLOAD" ] || CHAT_UPLOAD="$CHAT_URL?attach=1"
  [ -n "$CHAT_URL" ]
}

command_chat() {
  command_here
  need_token || return
  if repository "$HERE"; then :; else REMOTE=""; BRANCH=""; fi
  if ! chat_page; then not_reached; return; fi
  if [ "${1:-}" = "open" ]; then
    open_page "$CHAT_URL"
    echo "This session’s chat in Vyavasta is open in your browser: $CHAT_URL"
  else
    echo "This session’s chat in Vyavasta: $CHAT_URL"
    echo "Send “vyavasta chat open” to open it in your browser."
  fi
}

command_chat_open() { command_chat open; }

command_upload() {
  command_here
  need_token || return
  if repository "$HERE"; then :; else REMOTE=""; BRANCH=""; fi
  if ! chat_page; then not_reached; return; fi
  open_page "$CHAT_UPLOAD"
  echo "This session’s chat is open in your browser: drop the file there, and your next question in this session will carry it."
  echo "If the page didn’t open: $CHAT_UPLOAD"
}

command_shared() {
  command_here
  need_token || return
  if repository "$HERE"; then :; else REMOTE=""; fi
  session=$(command_session)
  api GET "/shared?session=$(url_quote "$session")&remote=$(url_quote "${REMOTE:-}")" "" "$QUICK_SECONDS"
  [ "$STATUS" = "200" ] || { not_reached; return; }
  json_rows "$(answer items)" > "$TMP/rows"
  true > "$TMP/listed"
  while IFS= read -r row; do
    printf '%s\t%s\t%s\n' "$(json_text "$(field "$row" at)")" "$(json_text "$(field "$row" at_said)")" \
      "$(json_text "$(field "$row" said)")" >> "$TMP/listed"
  done < "$TMP/rows"
  if [ -s "$TMP/listed" ]; then
    echo "Sent to Vyavasta from this session, oldest first:"
    sort "$TMP/listed" | awk -F '\t' '{ printf "- %s: %s\n", $2, $3 }'
  else
    echo "Nothing has been sent to Vyavasta from this session yet."
  fi
  kept=$(json_text "$(answer kept)")
  [ -n "$kept" ] && echo "$kept"
  chat=$(json_text "$(answer chat_url)")
  [ -n "$chat" ] && echo "This session’s chat: $chat"
}

command_check() {
  command_here
  IN_CHECK=1
  missing=""
  for tool in git curl awk; do command -v "$tool" >/dev/null 2>&1 || missing="${missing:+$missing, }$tool"; done
  if [ -z "$missing" ]; then echo "ok: git, curl and awk are installed."
  else echo "Problem: $missing is missing. Install it, and on Windows use Git for Windows, which brings all three."; fi
  if writable; then echo "ok: the settings folder ($HOME_DIR) can be written."
  elif [ "$CLIENT" = "codex" ]; then echo "Problem: Codex runs the commands its model starts in a closed-off space that can’t write the settings folder ($HOME_DIR) or reach the internet. Send “vyavasta check” as a message instead; messages aren’t closed off."
  else echo "Problem: the settings folder ($HOME_DIR) can’t be written. Make sure it belongs to you, or set VYAVASTA_HOME to a folder you can write."; fi
  echo "ok: the server address is $SERVER."
  api_unsigned GET /hello "" "$QUICK_SECONDS"
  latest=""; minimum=""
  case "$STATUS" in
    200) echo "ok: Vyavasta’s server answers."; latest=$(json_text "$(answer latest)"); minimum=$(json_text "$(answer minimum)") ;;
    404) echo "ok: Vyavasta’s server answers." ;;
    000)
      if [ -n "$SLOW" ]; then echo "Problem: Vyavasta’s server is very slow to answer. Try again in a minute."
      elif [ "$CLIENT" = "codex" ] && [ -z "${IN_HOOK:-}" ]; then echo "Problem: Vyavasta’s server can’t be reached from here. Codex runs the commands its model starts in a closed-off space that can’t reach the internet. Send “vyavasta check” as a message instead; messages aren’t closed off."
      else echo "Problem: Vyavasta’s server can’t be reached. Check your internet connection, and that $SERVER is the right address."; fi ;;
    *) echo "Problem: Vyavasta’s server isn’t working right now. Try again in a few minutes." ;;
  esac
  reached=""
  [ "$STATUS" = "200" ] || [ "$STATUS" = "404" ] && reached=1
  finish_pairing
  repositories=""
  if [ -z "$TOKEN" ]; then
    if pending_waiting; then PAIR_AGAIN=1; echo "Problem: not signed in yet. To connect, $(code_said). $(finish_said)"
    else echo "Problem: not signed in. $WAY_IN"; fi
  elif [ -n "$reached" ]; then
    api GET /me "" "$QUICK_SECONDS"
    case "$STATUS" in
      200) remember_me; repositories=$(answer repositories); echo "ok: signed in as $(json_text "$(answer email)") in $(json_text "$(json_get "$TMP/workspace" name)")." ;;
      401) echo "Problem: this computer’s connection has ended. $WAY_IN_AGAIN" ;;
      *) echo "Problem: whether you’re signed in couldn’t be checked just now. Try again in a minute." ;;
    esac
  else
    echo "Problem: signed in as $(saved email), but that couldn’t be checked while the server is out of reach."
  fi
  if ! repository "$HERE"; then
    echo "Problem: this folder isn’t a git repository, so changes here can’t be checked. Questions about your team still work."
  elif [ -z "$REMOTE" ]; then
    echo "Problem: this repository has no copy on GitHub (no remote), so changes here can’t be checked. Add one with “git remote add origin <address>”."
  else
    name=$(repository_name "$REMOTE")
    echo "ok: this folder is the repository $name on GitHub."
    if [ -n "$repositories" ]; then
      if lists_repository "$repositories" "$name"; then echo "ok: Vyavasta reads $name for you."
      else echo "Problem: Vyavasta doesn’t read $name for you. Connect it with GitHub in Vyavasta’s Sources."; fi
    fi
  fi
  if project_on; then echo "ok: Vyavasta is on in this project."
  else echo "Problem: Vyavasta is off in this project. Send “vyavasta on” to use it here."; fi
  if [ "$(sharing)" = "on" ]; then echo "ok: code sharing is on. Send “vyavasta share code off” to stop it."
  else echo "ok: code sharing is off, so your uncommitted changes aren’t sent, only changed files’ names. Send “vyavasta share code on” to also send your uncommitted changes."; fi
  if [ "$(summaries)" = "on" ]; then echo "ok: summaries are on, so your messages and ${TOOL}’s replies, as written, are kept in your own chat and summed up for teammates. Send “vyavasta summaries off” to stop."
  else echo "ok: summaries are off, so $(summaries_off_said) Send “vyavasta summaries on” to turn them on."; fi
  if [ -n "$minimum" ] && older "$VERSION" "$minimum"; then
    echo "Problem: this plugin ($VERSION) is older than the oldest version Vyavasta still works with ($minimum), so it must be updated. $(update_how)"
  elif [ -n "$latest" ] && older "$VERSION" "$latest"; then
    echo "Problem: this plugin is $VERSION and $latest is out. $(update_how)"
  elif [ -n "$latest" ]; then
    echo "ok: this plugin ($VERSION) is the latest."
  else
    echo "ok: this plugin is $VERSION."
  fi
}

update_how() {
  case "$CLIENT" in
    codex) echo "Update it from Codex’s plugin list (or run “codex plugin marketplace upgrade”), then restart Codex and trust its hooks again." ;;
    *) echo "Update it with “claude plugin marketplace update vyavasta” and “claude plugin update vyavasta@vyavasta” in a terminal, then run /reload-plugins." ;;
  esac
}

command_inbox() {
  need_token || return
  api GET /inbox "" "$QUICK_SECONDS"
  [ "$STATUS" = "200" ] || { not_reached; return; }
  items=$(answer items)
  if [ -z "$items" ] || [ "$items" = "[]" ]; then
    echo "Nothing new from your teammates."
    return
  fi
  render_inbox "$items"
}

# A message to a teammate's agent (`ask`), a task for a teammate (`assign`), or a reply to an item of the inbox.
# $1 is the kind (message or task), $2 who it is for, $3 the words, $4 the message it replies to.
tell() {
  command_here
  need_token || return
  if repository "$HERE"; then :; else REMOTE=""; BRANCH=""; fi
  {
    printf '{"to":%s,"text":%s,"kind":"%s"' "$(json_quote "$2")" "$(json_quote "$3")" "$1"
    [ -n "${4:-}" ] && printf ',"reply_to":%s' "$(json_quote "$4")"
    printf ',"session":%s,"remote":%s,"branch":%s,"tool":"%s"}' "$(json_quote "$(command_session)")" \
      "$(json_quote "$REMOTE")" "$(json_quote "$BRANCH")" "$CLIENT"
  } > "$TMP/tell"
  api POST /tell "$TMP/tell" "$ASK_SECONDS"
  wait_on /tell "$TMP/tell"
  [ "$STATUS" = "200" ] || [ "$STATUS" = "201" ] || { not_reached; return; }
  status=$(json_text "$(answer status)")
  to=$(json_text "$(field "$(answer to)" name)"); [ -n "$to" ] || to="$2"
  from=$(json_text "$(field "$(answer from)" name)"); [ -n "$from" ] || from=$(saved email)
  at=$(json_text "$(answer at_said)")
  notice=$(json_text "$(answer notice)")
  url=$(json_text "$(answer url)")
  case "$status" in
    unknown_person)
      people=$(json_rows "$(answer people)" | while IFS= read -r one; do json_text "$one"; echo; done | awk 'NF' \
        | awk '{ printf "%s%s", (NR > 1 ? ", " : ""), $0 }')
      echo "Vyavasta doesn’t know a teammate called “$2”.${people:+ Your teammates: $people.}"
      return ;;
    refused|unavailable)
      echo "${notice:-Vyavasta couldn’t send that just now.}"
      return ;;
  esac
  sent_text=$(json_text "$(answer text)"); [ -n "$sent_text" ] || sent_text="$3"
  if [ "$1" = "message" ] && [ -z "${4:-}" ]; then
    printf '── To %s’s agent · from %s · %s · through Vyavasta ──\n%s\n\n' "$to" "$from" "$at" "$sent_text"
    said=$(json_text "$(answer answer)")
    if [ "$status" = "answered" ] && [ -n "$said" ]; then
      printf '── From %s’s agent · %s · answered only from what you can both already see ──\n%s\n\n' "$to" \
        "$(json_text "$(answer answer_at_said)")" "$said"
    elif [ -z "$notice" ]; then
      # (The server's notice says the same when it gives one.)
      echo "$to’s agent is still answering. The answer will be in your conversation with $to in Vyavasta."
      echo
    fi
  else
    printf '── To %s · from %s · %s · through Vyavasta ──\n%s\n\n' "$to" "$from" "$at" "$sent_text"
  fi
  [ -n "$notice" ] && echo "$notice"
  # The link once: the server's notice may end with it already.
  if [ -n "$url" ]; then
    case "$notice" in *"$url"*) ;; *) echo "Your conversation with $to in Vyavasta: $url" ;; esac
  fi
}

command_ask_teammate() { tell message "$1" "$(cat "$TMP/typed-text")"; }
command_ask() {
  # Typed by the developer as “vyavasta ask <name>: …” (the hook passes a name and the words) or run by the tool's
  # model as `vyavasta.sh ask "<question>"` for the developer's own assistant.
  if [ -n "${TYPED:-}" ]; then
    if [ -z "$1" ]; then echo "Say who and what, such as “vyavasta ask Priya: are you changing the billing page?”"; return; fi
    tell message "$1" "$(cat "$TMP/typed-text")"
    return
  fi
  command_ask_assistant "$@"
}

command_assign() {
  if [ -z "$1" ]; then echo "Say who and what, such as “vyavasta assign Priya: update the export to the new format”."; return; fi
  tell task "$1" "$(cat "$TMP/typed-text")"
}

# The item numbered $1 in the last inbox listing: sets ITEM_ID, ITEM_KIND and ITEM_FROM, or fails and says so.
inbox_item() {
  ITEM_ID=""; ITEM_KIND=""; ITEM_FROM=""
  case "$1" in ''|*[!0-9]*) echo "Give the number of an item in your inbox, such as “vyavasta reply 1: thanks”."; return 1 ;; esac
  if [ -f "$HOME_DIR/inbox" ]; then
    ITEM_ID=$(awk -F '\t' -v n="$1" '$1 == n { print $2; exit }' "$HOME_DIR/inbox")
    ITEM_KIND=$(awk -F '\t' -v n="$1" '$1 == n { print $3; exit }' "$HOME_DIR/inbox")
    ITEM_FROM=$(awk -F '\t' -v n="$1" '$1 == n { print $4; exit }' "$HOME_DIR/inbox")
  fi
  if [ -z "$ITEM_ID" ]; then
    echo "There is no item $1 in your last inbox listing. Send “vyavasta inbox” to see it again."
    return 1
  fi
}

command_reply() {
  if [ -z "$1" ]; then echo "Say which item and what, such as “vyavasta reply 1: yes, I’m on it”."; return; fi
  inbox_item "$1" || return
  tell message "$ITEM_FROM" "$(cat "$TMP/typed-text")" "$ITEM_ID"
}

# Marks a task of the inbox accepted, done or declined. Sets TASK_TEXT and TASK_FROM.
set_task() {
  TASK_TEXT=""; TASK_FROM=""
  need_token || return 1
  inbox_item "$1" || return 1
  if [ "$ITEM_KIND" != "task" ]; then echo "Item $1 isn’t a task. Answer it with “vyavasta reply $1: <your words>”."; return 1; fi
  printf '{"message_id":%s,"state":"%s"}' "$(json_quote "$ITEM_ID")" "$2" > "$TMP/task"
  api POST /task "$TMP/task" "$QUICK_SECONDS"
  [ "$STATUS" = "200" ] || { not_reached; return 1; }
  TASK_TEXT=$(json_text "$(answer text)")
  TASK_FROM=$(json_text "$(field "$(answer from)" name)"); [ -n "$TASK_FROM" ] || TASK_FROM="$ITEM_FROM"
}

# Starting a task: it is marked accepted, and its text goes to the model as the developer's request (in a hook),
# through the usual check. START_TEXT is the task's text when it was started.
command_start() {
  START_TEXT=""; START_CONTEXT=""
  set_task "$1" accepted || return
  START_TEXT="$TASK_TEXT"
  START_LINE="Started the task $TASK_FROM assigned you; $TASK_FROM will see that you started it."
  START_CONTEXT="The developer accepted a task that $TASK_FROM assigned them through Vyavasta, and asks you to do it now. The task, in $TASK_FROM’s words: $TASK_TEXT"
  if [ -z "${IN_HOOK:-}" ]; then
    echo "$START_LINE"
    echo "The task: $TASK_TEXT"
  fi
}

command_done() {
  set_task "$1" done || return
  echo "Marked done. $TASK_FROM will see it."
}

command_decline() {
  set_task "$1" declined || return
  echo "Declined. $TASK_FROM will see that you won’t take it on."
}

# A question for the developer's own assistant in Vyavasta, asked by the tool's model or from a terminal: the
# answer as text, or why there is none.
command_ask_assistant() {
  if [ -z "$1" ]; then
    echo "Usage: vyavasta.sh ask \"<a question about your team, in plain words>\""
    return
  fi
  if [ "$CLIENT" = "codex" ] && ! writable; then
    echo "Codex kept this command from reaching Vyavasta. The developer can ask the same thing by sending a message that starts with “Vyavasta,”."
    return
  fi
  finish_pairing
  if [ -z "$TOKEN" ]; then
    echo "Not signed in to Vyavasta on this computer, so nothing can be asked. Tell the developer: $WAY_IN"
    return
  fi
  HERE="${HERE:-${CLAUDE_PROJECT_DIR:-$PWD}}"
  project_of "$HERE"
  if repository "$HERE"; then :; else REMOTE=""; BRANCH=""; fi
  session=$(command_session)
  # Summed up for teammates only as the project's summaries setting says; from a project that is off, never.
  keep=false
  summaries_keep && keep=true
  printf '{"question":%s,"remote":%s,"branch":%s,"session":%s,"tool":"%s","keep":%s}' "$(json_quote "$1")" \
    "$(json_quote "$REMOTE")" "$(json_quote "$BRANCH")" "$(json_quote "$session")" "$CLIENT" "$keep" > "$TMP/ask"
  ask_vyavasta "$TMP/ask"
  case "$STATUS" in
    200)
      said=$(json_text "$(answer answer)")
      if [ -n "$said" ]; then
        printf '%s\n\nFrom Vyavasta, the team’s record. The same chat there: %s\n' "$said" "$(json_text "$(answer url)")"
      else
        printf 'Vyavasta gave no answer: %s\n' "$(json_text "$(answer notice)")"
      fi
      ;;
    401) echo "This computer’s connection to Vyavasta has ended, so nothing was asked. Tell the developer: $WAY_IN_AGAIN" ;;
    429) echo "Too many requests to Vyavasta just now. Ask again in a minute." ;;
    000)
      if [ "$CLIENT" = "codex" ] && [ -z "$SLOW" ]; then
        echo "Codex kept this command from reaching Vyavasta. The developer can ask the same thing by sending a message that starts with “Vyavasta,”."
      else
        echo "Vyavasta can’t be reached right now, so nothing was asked."
      fi ;;
    *) echo "Vyavasta can’t be reached right now, so nothing was asked." ;;
  esac
}

command_use_server() {
  case "$1" in
    "") rm -f "$HOME_DIR/server"; echo "Using $DEFAULT_SERVER." ;;
    *)
      mkdir -p "$HOME_DIR" && printf '%s\n' "${1%/}" > "$HOME_DIR/server"
      if VYAVASTA_SERVER="" server_url >/dev/null; then echo "Using ${1%/}."
      else rm -f "$HOME_DIR/server"; echo "That address isn’t one this plugin uses: it must start with https:// (or http:// for this computer only)."; fi
      ;;
  esac
}

USAGE="Usage: vyavasta.sh on | off | status | check | settings | help | sign-in | sign-out | share-code on|off | summaries on|off | shared | chat [open] | upload | inbox | tell <name> <words> | assign <name> <words> | reply <number> <words> | start|done|decline <number> | ask \"<question>\" | use-server [address] | hook <event>"

# -- start here --------------------------------------------------------------------------------------------------

main() {
  if SERVER=$(server_url); then :; else
    case "$1" in
      hook) [ "${2:-}" = "session-start" ] && say "Vyavasta: the server address set in VYAVASTA_SERVER isn’t one this plugin uses, so nothing is checked." ;;
      use-server) command_use_server "${2:-}" ;;
      *) echo "The server address set for Vyavasta isn’t one this plugin uses: it must start with https:// (or http:// for this computer only)." ;;
    esac
    return
  fi
  TOKEN=$(token_for "$SERVER")
  case "$1" in
    hook)
      IN_HOOK=1
      cat > "$TMP/full"
      case "${2:-}" in
        prompt|session-start) mv "$TMP/full" "$TMP/input" ;;
        # The Stop hook's input carries the tool's last reply, which may be long: what is needed of it, and the
        # fields before it, come first.
        stopped) head -c 131072 "$TMP/full" > "$TMP/input" ;;
        # An edit's input carries what was written, which may be long: what is needed comes first.
        *) head -c 65536 "$TMP/full" > "$TMP/input" ;;
      esac
      case "${2:-}" in
        session-start) hook_session_start ;;
        prompt) hook_prompt ;;
        edited|stopped) hook_report "$2" ;;
      esac
      ;;
    on|off|status|check|settings|help|shared|upload|inbox) "command_$1" ;;
    sign-in) command_sign_in ;;
    sign-out) command_sign_out ;;
    share-code)
      case "${2:-}" in on) command_share_on ;; off) command_share_off ;; *) echo "$USAGE" ;; esac ;;
    summaries)
      case "${2:-}" in on) command_summaries_on ;; off) command_summaries_off ;; *) echo "$USAGE" ;; esac ;;
    chat) command_chat "${2:-}" ;;
    tell|assign)
      kind=message; [ "$1" = "assign" ] && kind=task
      who="${2:-}"
      shift 2 2>/dev/null || shift $#
      if [ -z "$who" ] || [ -z "$*" ]; then echo "$USAGE"; return; fi
      tell "$kind" "$who" "$*" ;;
    reply)
      number="${2:-}"
      shift 2 2>/dev/null || shift $#
      if [ -z "$number" ] || [ -z "$*" ]; then echo "$USAGE"; return; fi
      printf '%s' "$*" > "$TMP/typed-text"
      command_reply "$number" ;;
    start|done|decline) "command_$1" "${2:-}" ;;
    ask) shift; command_ask_assistant "$*" ;;
    use-server) command_use_server "${2:-}" ;;
    *) echo "$USAGE" ;;
  esac
}

main "$@"
exit 0
