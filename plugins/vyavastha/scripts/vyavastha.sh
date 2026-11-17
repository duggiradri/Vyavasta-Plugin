#!/bin/sh
# Vyavastha for Claude Code and Codex: the hooks the coding tool runs, and the sign-in, sign-out, status and ask
# commands.
#
# Written for POSIX sh with git, curl and awk only. Claude Code runs a hook's command through sh on macOS and
# Linux and through Git Bash on Windows; this plugin needs git, and on Windows git comes as Git for Windows,
# which brings Git Bash, curl and awk with it. No Python, Node or jq is assumed.
#
# What it sends: the request's words to the check, the repository's GitHub remote (without any credentials in
# it), the branch, Claude Code's session id, and for each changed file its path, git's status and line counts.
# A message that asks about the team is sent on as a question to the developer's own assistant in Vyavastha, which
# keeps it in a chat of theirs, as its web app does. Never the conversation transcript, what a file holds, or
# environment variables. Every failure is quiet and lets Claude go on: our server being down never stops the
# developer's work.

umask 077
LC_ALL=C
export LC_ALL

VERSION="0.3.0"
DEFAULT_SERVER="https://vyavasta.com"
PHRASE="Plan it anyway"
# Which coding tool runs this script: its hooks file says so (Codex's sets VYAVASTHA_TOOL=codex). The tool's own name,
# what its model is called, and how its developer gives this plugin a command.
case "${VYAVASTHA_TOOL:-}" in
  codex)
    CLIENT="codex"; TOOL="Codex"; AGENT="Codex"; VERB="Send"; VERB_LOWER="send"
    CMD_SIGN_IN="“vyavastha sign in”"; CMD_SIGN_OUT="“vyavastha sign out”"; CMD_STATUS="“vyavastha status”" ;;
  *)
    CLIENT="claude-code"; TOOL="Claude Code"; AGENT="Claude"; VERB="Run"; VERB_LOWER="run"
    CMD_SIGN_IN="/vyavastha:sign-in"; CMD_SIGN_OUT="/vyavastha:sign-out"; CMD_STATUS="/vyavastha:status" ;;
esac
# This script, by its full path: what the tool's model is told to run to ask Vyavastha a question.
SELF="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")"
case "$CLIENT" in codex) ASK_WITH="VYAVASTHA_TOOL=codex sh \"$SELF\" ask" ;; *) ASK_WITH="sh \"$SELF\" ask" ;; esac
HOME_DIR="${VYAVASTHA_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/vyavastha}"
CREDENTIALS="$HOME_DIR/credentials"
PENDING="$HOME_DIR/pairing"
SESSIONS="$HOME_DIR/sessions"
# How long a check may take (a real model reads the record), a report, and anything else.
CHECK_SECONDS=75
# How long one call for the answer to a question may take, and how many more calls wait on for an answer that is
# not ready: the assistant may read the record and look things up, and no call stays open for long.
ASK_SECONDS=55
ASK_AGAIN=5
REPORT_SECONDS=8
QUICK_SECONDS=8
# A report after an edit waits this long after the last one; once the server can't be reached, nothing is tried
# again for this long.
REPORT_EVERY=10
OFFLINE_FOR=60
EMPTY_TREE="4b825dc642cb6eb9a060e54bf8d69288fbee4904"

TMP=$(mktemp -d 2>/dev/null || mktemp -d -t vyavastha 2>/dev/null)
[ -n "$TMP" ] && [ -d "$TMP" ] || exit 0
trap 'rm -rf "$TMP"' EXIT
trap 'exit 0' INT TERM HUP

# -- JSON, with awk ---------------------------------------------------------------------------------------

# The raw value of a top-level key of the JSON object in a file: a string with its quotes and escapes as they
# are, a number, true/false/null, or a whole object or array. Nothing when the key isn't there.
json_get() {
  awk -v want="$2" '
    function strend(p,   q, ch) {
      q = p + 1
      while (q <= n) { ch = substr(s, q, 1); if (ch == "\\") q += 2; else if (ch == "\"") return q; else q++ }
      return n
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
    }' "$1" 2>/dev/null
}

# A JSON string's text (the quotes taken off, its escapes undone): for ids, paths, words compared here, and an
# answer printed as it was written.
json_text() {
  printf '%s' "$1" | awk '
    function hex(h,   v, k, c) {
      v = 0; h = tolower(h)
      for (k = 1; k <= length(h); k++) { c = index("0123456789abcdef", substr(h, k, 1)); if (c == 0) return 63; v = v * 16 + c - 1 }
      return v
    }
    function utf8(u) {
      if (u < 128) return sprintf("%c", u)
      if (u < 2048) return sprintf("%c%c", 192 + int(u / 64), 128 + u % 64)
      if (u < 65536) return sprintf("%c%c%c", 224 + int(u / 4096), 128 + int(u / 64) % 64, 128 + u % 64)
      return sprintf("%c%c%c%c", 240 + int(u / 262144), 128 + int(u / 4096) % 64, 128 + int(u / 64) % 64, 128 + u % 64)
    }
    BEGIN { RS = "\001" }
    NR == 1 {
      s = $0
      if (substr(s, 1, 1) == "\"") s = substr(s, 2, length(s) - 2)
      out = ""; i = 1; n = length(s)
      while (i <= n) {
        c = substr(s, i, 1)
        if (c == "\\") {
          d = substr(s, i + 1, 1)
          if (d == "n") out = out "\n"; else if (d == "t") out = out "\t"; else if (d == "r") out = out "\r"
          else if (d == "u") {
            # \uXXXX, and a pair of them for a character beyond the first 65536, as the bytes of UTF-8.
            u = hex(substr(s, i + 2, 4)); i += 4
            if (u >= 55296 && u <= 56319 && substr(s, i + 2, 2) == "\\u") {
              low = hex(substr(s, i + 4, 4))
              if (low >= 56320 && low <= 57343) { u = 65536 + (u - 55296) * 1024 + (low - 56320); i += 6 }
            }
            out = out utf8(u)
          } else out = out d
          i += 2
        } else { out = out c; i++ }
      }
      printf "%s", out
    }'
}

# Text as a JSON string, quotes and all.
json_quote() {
  printf '%s' "$1" | awk '
    BEGIN { RS = "\001"; done = 0 }
    NR == 1 {
      s = $0; out = ""; n = length(s)
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (c == "\\") out = out "\\\\"
        else if (c == "\"") out = out "\\\""
        else if (c == "\n") out = out "\\n"
        else if (c == "\t") out = out "\\t"
        else if (c == "\r") out = out "\\r"
        else if (c < " ") out = out " "
        else out = out c
      }
      printf "\"%s\"", out; done = 1
    }
    END { if (!done) printf "\"\"" }'
}

# -- where things are kept --------------------------------------------------------------------------------

# The server, as the developer set it: VYAVASTHA_SERVER, else what `use-server` saved, else ours. Plain http only
# for this computer itself: a token never crosses a network unencrypted.
server_url() {
  url="${VYAVASTHA_SERVER:-}"
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
  mkdir -p "$HOME_DIR" && chmod 700 "$HOME_DIR" 2>/dev/null
  {
    printf 'server=%s\n' "$1"
    printf 'token=%s\n' "$2"
    printf 'email=%s\n' "$3"
    printf 'workspace=%s\n' "$4"
  } > "$CREDENTIALS.new" && chmod 600 "$CREDENTIALS.new" 2>/dev/null
  mv -f "$CREDENTIALS.new" "$CREDENTIALS"
}

session_dir() {
  id=$(printf '%s' "$1" | tr -cd 'A-Za-z0-9_-' | cut -c1-80)
  [ -n "$id" ] || id="no-session"
  dir="$SESSIONS/$id"
  mkdir -p "$dir" 2>/dev/null && chmod 700 "$SESSIONS" 2>/dev/null
  printf '%s' "$dir"
}

now() { date +%s; }

# Whether the server was found out of reach a moment ago: nothing is tried again so soon, so Claude isn't slowed.
offline() {
  [ -f "$HOME_DIR/offline" ] || return 1
  since=$(cat "$HOME_DIR/offline" 2>/dev/null)
  [ -n "$since" ] && [ $(( $(now) - since )) -lt "$OFFLINE_FOR" ]
}

# -- the server -----------------------------------------------------------------------------------------------

# api METHOD PATH BODYFILE SECONDS: the answer's body in $TMP/answer and its status in STATUS ("000" when the
# server couldn't be reached). The token travels in curl's configuration on stdin, never on its command line.
api() {
  STATUS=000
  : > "$TMP/answer"
  if [ -n "${TOKEN:-}" ]; then auth="header = \"Authorization: Bearer $TOKEN\""; else auth=""; fi
  if [ -n "$3" ]; then
    STATUS=$(printf '%s\n' "$auth" | curl -sS -K - -X "$1" --max-time "$4" --connect-timeout 5 \
      -H "Content-Type: application/json" -H "User-Agent: vyavastha-$CLIENT/$VERSION" \
      --data-binary "@$3" -o "$TMP/answer" -w '%{http_code}' "$SERVER/api/v1/plugin$2" 2>/dev/null) || STATUS=000
  else
    STATUS=$(printf '%s\n' "$auth" | curl -sS -K - -X "$1" --max-time "$4" --connect-timeout 5 \
      -H "User-Agent: vyavastha-$CLIENT/$VERSION" \
      -o "$TMP/answer" -w '%{http_code}' "$SERVER/api/v1/plugin$2" 2>/dev/null) || STATUS=000
  fi
  case "$STATUS" in
    000|5*) mkdir -p "$HOME_DIR" && now > "$HOME_DIR/offline" ;;
    *) rm -f "$HOME_DIR/offline" ;;
  esac
  if [ "$STATUS" = "401" ] && [ -n "${TOKEN:-}" ]; then
    # The connection ended (disconnected in Settings, or run out): this computer is signed out.
    rm -f "$CREDENTIALS"
    TOKEN=""
  fi
}

answer() { json_get "$TMP/answer" "$1"; }

# ask_vyavastha BODYFILE: puts a question to the developer's own assistant and waits for its answer, over as many
# calls as it takes (each names the answer the one before was waiting for). Leaves the last answer in $TMP/answer.
ask_vyavastha() {
  api POST /ask "$1" "$ASK_SECONDS"
  tries=0
  while [ "$STATUS" = "200" ] && [ "$(json_text "$(answer status)")" = "pending" ] && [ "$tries" -lt "$ASK_AGAIN" ]; do
    waiting=$(answer waiting)
    case "$waiting" in \"*\") ;; *) break ;; esac
    printf '{"waiting":%s,"tool":"%s"}' "$waiting" "$CLIENT" > "$TMP/waiting"
    api POST /ask "$TMP/waiting" "$ASK_SECONDS"
    tries=$((tries + 1))
  done
}

# A call made with no token: starting a pairing, and taking the token it gives.
api_unsigned() {
  held_token=$TOKEN
  TOKEN=""
  api "$@"
  TOKEN=$held_token
}

# A pairing started by sign-in and approved in the browser since: the token is taken now. Quiet either way.
finish_pairing() {
  [ -f "$PENDING" ] || return 0
  pending_server=$(sed -n 's/^server=//p' "$PENDING")
  device=$(sed -n 's/^device=//p' "$PENDING")
  started=$(sed -n 's/^started=//p' "$PENDING")
  if [ "$pending_server" != "$SERVER" ] || [ -z "$device" ] || [ $(( $(now) - ${started:-0} )) -gt 660 ]; then
    rm -f "$PENDING"
    return 0
  fi
  json_quote "$device" > "$TMP/device"
  printf '{"device_code":%s}' "$(cat "$TMP/device")" > "$TMP/claim"
  api_unsigned POST /token "$TMP/claim" "$QUICK_SECONDS"
  case "$STATUS" in
    200)
      keep_credentials "$SERVER" "$(json_text "$(answer token)")" "$(json_text "$(answer email)")" \
        "$(json_text "$(answer workspace)")"
      rm -f "$PENDING"
      TOKEN=$(token_for "$SERVER")
      CONNECTED="Vyavastha: connected as $(saved email) in $(saved workspace)."
      ;;
    404|410) rm -f "$PENDING" ;;
  esac
  return 0
}

# -- the repository it is in ------------------------------------------------------------------------------------

# Sets ROOT, REMOTE (the GitHub remote, without any user name or token in it) and BRANCH for a folder; fails when
# the folder isn't in a git repository.
repository() {
  ROOT=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 1
  [ -n "$ROOT" ] || return 1
  REMOTE=$(git -C "$ROOT" remote get-url origin 2>/dev/null)
  if [ -z "$REMOTE" ]; then
    first=$(git -C "$ROOT" remote 2>/dev/null | sed -n '1p')
    [ -n "$first" ] && REMOTE=$(git -C "$ROOT" remote get-url "$first" 2>/dev/null)
  fi
  REMOTE=$(printf '%s' "$REMOTE" | sed -E 's#^([A-Za-z+]+://)[^@/]*@#\1#')
  BRANCH=$(git -C "$ROOT" symbolic-ref --short -q HEAD 2>/dev/null)
  return 0
}

# git's own list of what changed in the working tree and the index since the last commit, as a JSON array of
# paths, statuses and line counts. A new file's lines are counted here; nothing of any file is sent.
OWN_SETTINGS=':(top,exclude).claude/settings.local.json'
changed_files() {
  base=HEAD
  git -C "$ROOT" rev-parse -q --verify HEAD >/dev/null 2>&1 || base=$EMPTY_TREE
  # Claude Code keeps one person's own settings for a project in .claude/settings.local.json: not the team's work.
  git -C "$ROOT" status --porcelain=v1 -z --untracked-files=all -- . "$OWN_SETTINGS" 2>/dev/null | tr '\000' '\001' > "$TMP/status"
  git -C "$ROOT" diff --numstat -z "$base" -- . "$OWN_SETTINGS" 2>/dev/null | tr '\000' '\001' > "$TMP/numstat"
  (cd "$ROOT" && awk '
    function quote(s,   out, i, c, n) {
      out = ""; n = length(s)
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (c == "\\") out = out "\\\\"; else if (c == "\"") out = out "\\\""
        else if (c < " ") out = out " "; else out = out c
      }
      return "\"" out "\""
    }
    function lines(path,   count, line) {
      count = 0; RS = "\n"
      while (count < 100000 && (getline line < path) > 0) count++
      close(path); RS = "\001"
      return count
    }
    BEGIN { RS = "\001"; renamed_from = 0; skip = 0; shown = 0; counted = 0 }
    FILENAME == ARGV[1] {
      # numstat: "added<TAB>removed<TAB>path", or for a rename "added<TAB>removed<TAB>" then the old and new path.
      if (renamed_from == 2) { renamed_from = 1; next }
      if (renamed_from == 1) { adds[$0] = pending_add; dels[$0] = pending_del; renamed_from = 0; next }
      split($0, part, "\t")
      a = (part[1] == "-") ? 0 : part[1] + 0; d = (part[2] == "-") ? 0 : part[2] + 0
      if (part[3] == "") { pending_add = a; pending_del = d; renamed_from = 2; next }
      path = substr($0, length(part[1]) + length(part[2]) + 3)
      adds[path] = a; dels[path] = d
      next
    }
    {
      if (skip) { skip = 0; next }
      if (length($0) < 4) next
      x = substr($0, 1, 1); y = substr($0, 2, 1); path = substr($0, 4)
      if (x == "R" || x == "C") skip = 1
      if (x == "?" && y == "?") status = "added"
      else if (x == "A" || y == "A") status = "added"
      else if (x == "D" || y == "D") status = "deleted"
      else if (x == "R" || x == "C") status = "renamed"
      else status = "changed"
      if (shown >= 300) next
      a = (path in adds) ? adds[path] : 0; d = (path in dels) ? dels[path] : 0
      if (x == "?" && counted < 200) { a = lines(path); counted++ }
      printf "%s{\"path\":%s,\"status\":\"%s\",\"additions\":%d,\"deletions\":%d}", (shown ? "," : ""), quote(path), status, a, d
      shown++
    }' "$TMP/numstat" "$TMP/status") > "$TMP/files"
  printf '[%s]' "$(cat "$TMP/files")"
}

# Where the session's work stands, as git shows it: files changed and not committed; committed and not pushed;
# pushed; or none of it kept (the tree as it was when the session began).
work_state() {
  if [ -s "$TMP/files" ]; then printf 'changing'; return; fi
  head=$(git -C "$ROOT" rev-parse -q --verify HEAD 2>/dev/null)
  start=$(cat "$1/start" 2>/dev/null)
  if git -C "$ROOT" rev-parse -q --verify '@{u}' >/dev/null 2>&1; then
    ahead=$(git -C "$ROOT" rev-list --count '@{u}..HEAD' 2>/dev/null)
    if [ "${ahead:-0}" -gt 0 ]; then printf 'committed'
    elif [ -n "$start" ] && [ "$head" != "$start" ]; then printf 'pushed'
    else printf 'abandoned'; fi
  elif [ -n "$start" ] && [ "$head" != "$start" ]; then printf 'committed'
  else printf 'abandoned'; fi
}

# -- what Claude Code is told ---------------------------------------------------------------------------------

# A note for the developer (Claude isn't shown it).
say() { printf '{"systemMessage":%s}\n' "$(json_quote "$1")"; }

# A note shown once in a session, under a name.
say_once() {
  [ -f "$1/said-$2" ] && return 0
  : > "$1/said-$2"
  say "$3"
}

# -- the hooks -----------------------------------------------------------------------------------------------------

hook_session_start() {
  input="$TMP/input"
  dir=$(session_dir "$(json_text "$(json_get "$input" session_id)")")
  folder=$(json_text "$(json_get "$input" cwd)")
  [ -n "$folder" ] || folder="${CLAUDE_PROJECT_DIR:-$PWD}"
  # Where the tree stood when the session began, to tell later whether anything of it was kept.
  if repository "$folder"; then
    [ -f "$dir/start" ] || git -C "$ROOT" rev-parse -q --verify HEAD > "$dir/start" 2>/dev/null
  fi
  # Sessions over a week old are forgotten.
  find "$SESSIONS" -mindepth 1 -maxdepth 1 -type d -mtime +7 -exec rm -rf {} + 2>/dev/null
  finish_pairing
  if [ -z "$TOKEN" ]; then
    if [ -f "$PENDING" ]; then
      say "Vyavastha: waiting for you to approve the connection in your browser. ${VERB} ${CMD_STATUS} once you have."
    else
      say "Vyavastha: not signed in, so requests aren’t checked against your team’s record. ${VERB} ${CMD_SIGN_IN} to connect."
    fi
    return
  fi
  api GET /me "" "$QUICK_SECONDS"
  case "$STATUS" in
    200)
      json_get "$TMP/answer" workspace > "$TMP/workspace"
      # The developer is told they are connected; the tool's model is told what Vyavastha is here for, and how
      # to ask it what the plugin did not already ask for them.
      printf '{"systemMessage":%s,"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' \
        "$(json_quote "${CONNECTED:-Vyavastha: signed in as $(json_text "$(answer email)") in $(json_text "$(json_get "$TMP/workspace" name)").} Requests are checked against your team’s record before ${AGENT} changes code, and questions about your team are answered from it.")" \
        "$(json_quote "Vyavastha is connected for this developer. It keeps their team’s record: what teammates said, decided and promised, and what each of them is working on, read from the sources the team connected. When the developer’s message asks about the team, Vyavastha answers it before the message reaches you, and you are given the answer to pass on. For anything else you need to know about the team (what a teammate is doing, what was decided, who said what, whether someone else is changing the same code), ask Vyavastha before any other source such as email or chat tools, by running this command with the question in plain words: $ASK_WITH \"<the question>\" . Changes to the code are yours to make on this computer; each request for one is checked against the record before it reaches you.")"
      ;;
    401) say "Vyavastha: this computer’s connection has ended. ${VERB} ${CMD_SIGN_IN} to connect again." ;;
    *) say "Vyavastha: the server can’t be reached right now, so requests aren’t being checked. ${AGENT} works as usual." ;;
  esac
}

hook_prompt() {
  input="$TMP/input"
  prompt=$(json_get "$input" prompt)
  [ -n "$prompt" ] || return
  dir=$(session_dir "$(json_text "$(json_get "$input" session_id)")")
  words=$(json_text "$prompt" | tr 'A-Z' 'a-z' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:].!]*$//')
  if [ "$words" = "$(printf '%s' "$PHRASE" | tr 'A-Z' 'a-z')" ] && [ -s "$dir/held" ]; then
    # The developer chose to go on with the request that was held: Claude is shown it, with what stood in the way.
    printf '{"systemMessage":%s,"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' \
      "$(json_quote "Vyavastha: going ahead. ${AGENT} was shown your request, what stands in the way, and that you chose to go on.")" \
      "$(cat "$dir/held")"
    rm -f "$dir/held"
    return
  fi
  case "$words" in /*) return ;; esac
  # The plugin's own commands, sent as a plain message (how a tool without slash commands of ours is given them):
  # answered here, and never sent to the model.
  typed=""
  case "$(printf '%s' "$words" | tr -s ' -' '  ')" in
    "vyavastha sign in") typed=sign_in ;;
    "vyavastha sign out") typed=sign_out ;;
    "vyavastha status") typed=status ;;
  esac
  if [ -n "$typed" ]; then
    HERE=$(json_text "$(json_get "$input" cwd)")
    printf '{"decision":"block","reason":%s}\n' "$(json_quote "$(command_$typed)")"
    return
  fi
  rm -f "$dir/held"
  # The session a question asked by the tool's model belongs to (``ask``): the one a message was last sent in.
  basename "$dir" > "$HOME_DIR/session" 2>/dev/null
  finish_pairing
  if [ -z "$TOKEN" ]; then
    say_once "$dir" signed-out "Vyavastha: not signed in, so this request wasn’t checked against your team’s record. ${VERB} ${CMD_SIGN_IN} to connect."
    return
  fi
  folder=$(json_text "$(json_get "$input" cwd)")
  [ -n "$folder" ] || folder="${CLAUDE_PROJECT_DIR:-$PWD}"
  # A folder that is no repository has nothing to check, and a question about the team can still be asked from it.
  if repository "$folder"; then :; else ROOT=""; REMOTE=""; BRANCH=""; fi
  if offline; then
    say_once "$dir" offline "Vyavastha: the server can’t be reached right now, so requests aren’t being checked. ${AGENT} works as usual."
    return
  fi
  printf '{"request":%s,"remote":%s,"branch":%s,"session":%s,"tool":"%s"}' "$prompt" "$(json_quote "$REMOTE")" \
    "$(json_quote "$BRANCH")" "$(json_quote "$(basename "$dir")")" "$CLIENT" > "$TMP/check"
  api POST /check "$TMP/check" "$CHECK_SECONDS"
  case "$STATUS" in
    200) ;;
    401) say_once "$dir" ended "Vyavastha: this computer’s connection has ended, so this request wasn’t checked. ${VERB} ${CMD_SIGN_IN} to connect again."; return ;;
    429) say_once "$dir" busy "Vyavastha: too many requests just now, so this one wasn’t checked. ${AGENT} works as usual."; return ;;
    *) say_once "$dir" offline "Vyavastha: the server can’t be reached right now, so requests aren’t being checked. ${AGENT} works as usual."; return ;;
  esac
  if [ "$(answer ask)" = "true" ]; then
    # A question for the developer's own assistant in Vyavastha: asked there, in this session's chat, and the
    # answer is given to the tool's model to pass on. When no answer comes, the model has the message as it is.
    printf '{"question":%s,"remote":%s,"branch":%s,"session":%s,"tool":"%s"}' "$prompt" "$(json_quote "$REMOTE")" \
      "$(json_quote "$BRANCH")" "$(json_quote "$(basename "$dir")")" "$CLIENT" > "$TMP/ask"
    ask_vyavastha "$TMP/ask"
    if [ "$STATUS" != "200" ]; then
      say "Vyavastha: your question couldn’t be asked just now, so ${AGENT} answers by itself."
      return
    fi
  fi
  notice=$(answer notice)
  context=$(answer context)
  if [ -n "${CONNECTED:-}" ]; then
    # Connected just now, by this request: said first, in the same note.
    told=$(json_text "$notice")
    notice=$(json_quote "$CONNECTED${told:+ $told}")
  fi
  if [ "$(answer hold)" = "true" ]; then
    # Held, as the web app holds a plan: Claude isn't sent the request, and the developer is told why and how to
    # go on. What going on tells Claude is kept for this session until then.
    answer anyway > "$TMP/anyway"
    json_get "$TMP/anyway" context > "$dir/held"
    printf '{"decision":"block","reason":%s}\n' "${notice:-\"\"}"
    return
  fi
  verdict=$(json_text "$(answer verdict)")
  if [ "$verdict" = "not_connected" ]; then
    [ -f "$dir/said-not-connected" ] && return
    : > "$dir/said-not-connected"
  fi
  if [ -n "$context" ] && [ "$context" != '""' ]; then
    if [ -n "$notice" ] && [ "$notice" != '""' ]; then
      printf '{"systemMessage":%s,"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' \
        "$notice" "$context"
    else
      printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' "$context"
    fi
  elif [ -n "$notice" ] && [ "$notice" != '""' ]; then
    printf '{"systemMessage":%s}\n' "$notice"
  fi
}

# After an edit (``edited``, at most every REPORT_EVERY seconds) and when Claude stops (``stopped``): git's list of
# changed files goes to the server, which keeps the session's work for teammates to see. Nothing is printed.
hook_report() {
  input="$TMP/input"
  dir=$(session_dir "$(json_text "$(json_get "$input" session_id)")")
  [ -n "$TOKEN" ] || return
  folder=$(json_text "$(json_get "$input" cwd)")
  [ -n "$folder" ] || folder="${CLAUDE_PROJECT_DIR:-$PWD}"
  repository "$folder" || return
  offline && return
  if [ "$1" = "edited" ] && [ -f "$dir/reported" ]; then
    last=$(cat "$dir/reported" 2>/dev/null)
    [ -n "$last" ] && [ $(( $(now) - last )) -lt "$REPORT_EVERY" ] && return
  fi
  files=$(changed_files)
  state=$(work_state "$dir")
  # A session that has nothing open and nothing changed has nothing to tell.
  [ "$state" != "changing" ] && [ ! -f "$dir/open" ] && return
  printf '{"remote":%s,"branch":%s,"session":%s,"state":"%s","files":%s,"tool":"%s"}' "$(json_quote "$REMOTE")" \
    "$(json_quote "$BRANCH")" "$(json_quote "$(basename "$dir")")" "$state" "$files" "$CLIENT" > "$TMP/report"
  api POST /work "$TMP/report" "$REPORT_SECONDS"
  now > "$dir/reported"
  [ "$STATUS" = "200" ] || return
  if [ "$(answer recorded)" = "true" ]; then
    case "$(json_text "$(answer status)")" in
      pushed|abandoned) rm -f "$dir/open" ;;
      *) : > "$dir/open" ;;
    esac
  fi
}

# -- the commands ------------------------------------------------------------------------------------------------

open_page() {
  case "$(uname -s 2>/dev/null)" in
    Darwin) open "$1" >/dev/null 2>&1 & ;;
    MINGW*|MSYS*|CYGWIN*) start "" "$1" >/dev/null 2>&1 & ;;
    *) command -v xdg-open >/dev/null 2>&1 && xdg-open "$1" >/dev/null 2>&1 & ;;
  esac
}

command_sign_in() {
  if [ -n "$TOKEN" ]; then
    api GET /me "" "$QUICK_SECONDS"
    if [ "$STATUS" = "200" ]; then
      echo "Already signed in to Vyavastha ($SERVER) as $(json_text "$(answer email)"). ${VERB} ${CMD_SIGN_OUT} first to switch accounts."
      return
    fi
  fi
  machine=$(hostname 2>/dev/null | cut -d. -f1)
  [ -n "$machine" ] || machine=$(uname -n 2>/dev/null)
  printf '{"machine":%s,"tool":"%s"}' "$(json_quote "$machine")" "$CLIENT" > "$TMP/pair"
  api_unsigned POST /pair "$TMP/pair" "$QUICK_SECONDS"
  if [ "$STATUS" != "201" ]; then
    message=$(json_get "$TMP/answer" detail > "$TMP/detail"; json_text "$(json_get "$TMP/detail" message)")
    echo "Couldn’t start connecting to Vyavastha at $SERVER${message:+: $message}"
    [ "$STATUS" = "000" ] && echo "Check the address and your connection. To use another server, set VYAVASTHA_SERVER before starting ${TOOL}."
    return
  fi
  device=$(json_text "$(answer device_code)")
  code=$(json_text "$(answer user_code)")
  page=$(json_text "$(answer verification_url)")
  mkdir -p "$HOME_DIR" && chmod 700 "$HOME_DIR" 2>/dev/null
  printf 'server=%s\ndevice=%s\nstarted=%s\n' "$SERVER" "$device" "$(now)" > "$PENDING"
  chmod 600 "$PENDING" 2>/dev/null
  open_page "$page"
  echo "To connect ${TOOL} on $machine to Vyavastha, open $page and enter the code $code."
  echo "The code works for 10 minutes. Once you approve, ${TOOL} finishes connecting by itself on your next request, or ${VERB_LOWER} ${CMD_STATUS}."
}

command_sign_out() {
  rm -f "$PENDING"
  if [ -z "$TOKEN" ]; then
    rm -f "$CREDENTIALS"
    echo "Not signed in to Vyavastha on this computer."
    return
  fi
  api POST /signout "" "$QUICK_SECONDS"
  rm -f "$CREDENTIALS"
  echo "Signed out of Vyavastha on this computer. Requests are no longer checked, and your edits are no longer shared."
}

command_status() {
  echo "Vyavastha plugin $VERSION, server $SERVER."
  finish_pairing
  [ -n "${CONNECTED:-}" ] && echo "${CONNECTED#Vyavastha: }"
  if [ -z "$TOKEN" ]; then
    if [ -f "$PENDING" ]; then
      echo "Waiting for you to approve the connection in your browser. ${VERB} ${CMD_STATUS} again once you have."
    else
      echo "Not signed in. ${VERB} ${CMD_SIGN_IN} to connect."
    fi
    return
  fi
  api GET /me "" "$QUICK_SECONDS"
  case "$STATUS" in
    200)
      json_get "$TMP/answer" workspace > "$TMP/workspace"
      echo "Signed in as $(json_text "$(answer email)") in $(json_text "$(json_get "$TMP/workspace" name)"), on $(json_text "$(answer machine)")."
      repositories=$(answer repositories)
      if repository "${HERE:-${CLAUDE_PROJECT_DIR:-$PWD}}"; then
        name=$(printf '%s' "$REMOTE" | sed -E -e 's#^.*github\.com[:/]##' -e 's#\.git/?$##' -e 's#/$##')
        case "$repositories" in
          *"\"$name\""*) echo "This repository, $name, is connected: requests here are checked and your edits are shared." ;;
          *) echo "This folder’s repository isn’t one Vyavastha reads for you, so nothing here is checked or shared." ;;
        esac
      fi
      ;;
    401) echo "This computer’s connection has ended. ${VERB} ${CMD_SIGN_IN} to connect again." ;;
    *) echo "The server can’t be reached right now. Requests aren’t checked until it can be." ;;
  esac
}

# A question for the developer's own assistant in Vyavastha, asked by the tool's model or from a terminal: the
# answer as text, or why there is none.
command_ask() {
  if [ -z "$1" ]; then
    echo "Usage: vyavastha.sh ask \"<a question about your team, in plain words>\""
    return
  fi
  finish_pairing
  if [ -z "$TOKEN" ]; then
    echo "Not signed in to Vyavastha on this computer, so nothing can be asked. The developer signs in with ${CMD_SIGN_IN}."
    return
  fi
  if repository "${HERE:-${CLAUDE_PROJECT_DIR:-$PWD}}"; then :; else REMOTE=""; BRANCH=""; fi
  session="${VYAVASTHA_SESSION:-$(cat "$HOME_DIR/session" 2>/dev/null)}"
  printf '{"question":%s,"remote":%s,"branch":%s,"session":%s,"tool":"%s"}' "$(json_quote "$1")" \
    "$(json_quote "$REMOTE")" "$(json_quote "$BRANCH")" "$(json_quote "$session")" "$CLIENT" > "$TMP/ask"
  ask_vyavastha "$TMP/ask"
  case "$STATUS" in
    200)
      said=$(json_text "$(answer answer)")
      if [ -n "$said" ]; then
        printf '%s\n\nFrom Vyavastha, the team’s record. The same chat there: %s\n' "$said" "$(json_text "$(answer url)")"
      else
        printf 'Vyavastha gave no answer: %s\n' "$(json_text "$(answer notice)")"
      fi
      ;;
    401) echo "This computer’s connection to Vyavastha has ended, so nothing was asked. The developer signs in again with ${CMD_SIGN_IN}." ;;
    429) echo "Too many requests to Vyavastha just now. Ask again in a minute." ;;
    *) echo "Vyavastha can’t be reached right now, so nothing was asked." ;;
  esac
}

command_use_server() {
  case "$1" in
    "") rm -f "$HOME_DIR/server"; echo "Using $DEFAULT_SERVER." ;;
    *)
      mkdir -p "$HOME_DIR" && printf '%s\n' "${1%/}" > "$HOME_DIR/server"
      if VYAVASTHA_SERVER="" server_url >/dev/null; then echo "Using ${1%/}."
      else rm -f "$HOME_DIR/server"; echo "That address isn’t one this plugin uses: it must start with https:// (or http:// for this computer only)."; fi
      ;;
  esac
}

# -- start here --------------------------------------------------------------------------------------------------

main() {
  if SERVER=$(server_url); then :; else
    case "$1" in
      hook) [ "${2:-}" = "session-start" ] && say "Vyavastha: the server address set in VYAVASTHA_SERVER isn’t one this plugin uses, so nothing is checked." ;;
      use-server) command_use_server "${2:-}" ;;
      *) echo "The server address set for Vyavastha isn’t one this plugin uses: it must start with https:// (or http:// for this computer only)." ;;
    esac
    return
  fi
  TOKEN=$(token_for "$SERVER")
  case "$1" in
    hook)
      cat > "$TMP/input" 2>/dev/null
      case "${2:-}" in
        session-start) hook_session_start ;;
        prompt) hook_prompt ;;
        edited|stopped) hook_report "$2" ;;
      esac
      ;;
    sign-in) command_sign_in ;;
    sign-out) command_sign_out ;;
    status) command_status ;;
    ask) shift; command_ask "$*" ;;
    use-server) command_use_server "${2:-}" ;;
    *) echo "Usage: vyavastha.sh sign-in | sign-out | status | ask \"<question>\" | use-server [address] | hook <event>" ;;
  esac
}

main "$@"
exit 0
