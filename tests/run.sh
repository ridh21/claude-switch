#!/usr/bin/env bash
# Tests for cswitch. Runs against a throwaway HOME with stub claude, curl and
# security commands, so no real login or network is touched.
# Usage: tests/run.sh

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CSWITCH="$ROOT/bin/cswitch"
PASS=0 FAIL=0

setup() {
  T="$(mktemp -d "${TMPDIR:-/tmp}/cswitch-test.XXXXXX")"
  export HOME="$T/home" CSWITCH_HOME="$T/home/.claude-profiles" CSWITCH_BASE="$T/home/.claude"
  export FAKE="$T/fake" PATH="$T/bin:/usr/bin:/bin"
  unset CLAUDE_CONFIG_DIR CSWITCH_PROFILE CSWITCH_USAGE_TTL NO_COLOR
  export TERM=dumb LC_ALL=C
  mkdir -p "$HOME/.claude/projects" "$T/bin" "$FAKE"

  # claude: log the profile and arguments it ran with.
  cat > "$T/bin/claude" <<'EOF'
#!/bin/bash
printf '%s|%s\n' "${CLAUDE_CONFIG_DIR:-default}" "$*" >> "$FAKE/claude.log"
EOF
  # curl: answer from $FAKE/usage-<token>, counting each call.
  cat > "$T/bin/curl" <<'EOF'
#!/bin/bash
token="$(sed -n 's/.*Bearer \([^"]*\)".*/\1/p')"
echo "$token" >> "$FAKE/curl.log"
if [ -f "$FAKE/usage-$token" ]; then cat "$FAKE/usage-$token"; printf '\n200'; else printf '\n401'; fi
EOF
  # security: the credentials stored under a service name.
  cat > "$T/bin/security" <<'EOF'
#!/bin/bash
while [ $# -gt 0 ]; do [ "$1" = "-s" ] && svc="$2"; shift; done
[ -f "$FAKE/cred-$svc" ] && cat "$FAKE/cred-$svc" || exit 44
EOF
  chmod +x "$T/bin/"*
}

teardown() { rm -rf "$T"; }

# account <name> <token> <session%> <weekly%>
account() {
  local svc="Claude Code-credentials"
  [ "$1" = "default" ] || { "$CSWITCH" add "$1" >/dev/null 2>&1; svc="$svc-$(printf '%s' "$CSWITCH_HOME/$1" | shasum -a 256 | cut -c1-8)"; }
  printf '{"claudeAiOauth":{"accessToken":"%s","refreshToken":"r","expiresAt":9999999999999}}' "$2" > "$FAKE/cred-$svc"
  printf '{"five_hour":{"utilization":%s,"resets_at":"2099-01-01T00:00:00Z"},"seven_day":{"utilization":%s,"resets_at":"2099-01-05T00:00:00Z"}}' \
    "$3" "$4" > "$FAKE/usage-$2"
}

curl_calls() { [ -f "$FAKE/curl.log" ] && wc -l < "$FAKE/curl.log" | tr -d ' ' || echo 0; }

check() {
  local what="$1" got="$2" want="$3"
  case "$got" in
    *"$want"*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); printf 'FAIL: %s\n  wanted: %s\n  got:    %s\n' "$what" "$want" "$got" ;;
  esac
}

check_not() {
  local what="$1" got="$2" unwanted="$3"
  case "$got" in
    *"$unwanted"*) FAIL=$((FAIL + 1)); printf 'FAIL: %s\n  did not want: %s\n  got: %s\n' "$what" "$unwanted" "$got" ;;
    *) PASS=$((PASS + 1)) ;;
  esac
}

# Run under a pseudo-terminal so cswitch sees an interactive session.
# The input is typed after a moment, once cswitch is waiting for it.
in_tty() {
  local input="$1"
  shift
  if [ "$(uname -s)" = "Darwin" ]; then
    { sleep 1; printf '%s' "$input"; } | script -q /dev/null "$@"
  else
    { sleep 1; printf '%s' "$input"; } | script -qec "$(printf '%q ' "$@")" /dev/null
  fi
}

test_usage_picks_most_room() {
  setup
  account default t-default 90 40
  account work t-work 20 70
  account spare t-spare 30 10
  local out
  out="$("$CSWITCH" usage)"
  check "usage suggests the login furthest from either limit" "$out" "Most room: spare (30% session, 10% weekly)"
  out="$("$CSWITCH" usage --json)"
  check "json keeps ISO reset times" "$out" '"resets_at":"2099-01-01T00:00:00Z"'
  teardown
}

test_best_launches_with_room_and_uses_cache() {
  setup
  account default t-default 100 40
  account work t-work 30 30
  local out
  out="$("$CSWITCH" best -p hi 2>&1)"
  check "best says which login" "$out" "Using work"
  check "best launches that login" "$(cat "$FAKE/claude.log")" "$CSWITCH_HOME/work|-p hi"
  local before
  before="$(curl_calls)"
  "$CSWITCH" best -p again >/dev/null 2>&1
  check "a second best within the TTL reuses remembered limits" "$(curl_calls)" "$before"
  teardown
}

test_best_with_no_room_fails() {
  setup
  account default t-default 100 40
  local out rc=0
  out="$("$CSWITCH" best -p hi 2>&1)" || rc=$?
  check "best refuses when nobody has room" "$out" "no login has room left"
  check "best exits non-zero" "$rc" "1"
  teardown
}

test_statusline_remembers_limits_without_network() {
  setup
  account default t-default 10 10
  account work t-work 5 5
  local out
  out="$(printf '{"rate_limits":{"five_hour":{"used_percentage":42.4,"resets_at":4070908800},"seven_day":{"used_percentage":18,"resets_at":4071254400}}}' |
    CLAUDE_CONFIG_DIR="$CSWITCH_HOME/work" "$CSWITCH" statusline)"
  check "statusline names the login" "$out" "work"
  check "statusline shows session use" "$out" "5h 42%"
  check "statusline shows weekly use" "$out" "7d 18%"
  check "statusline never asks the network" "$(curl_calls)" "0"
  check "statusline remembers the reading" "$(cat "$CSWITCH_HOME/.cache/usage-work")" "|ok|42|4070908800|18|4071254400"
  teardown
}

test_statusline_names_next_login_near_limit() {
  setup
  account default t-default 10 10
  account work t-work 5 5
  "$CSWITCH" usage >/dev/null
  local out
  out="$(printf '{"rate_limits":{"five_hour":{"used_percentage":85,"resets_at":4070908800}}}' |
    CLAUDE_CONFIG_DIR="$CSWITCH_HOME/work" "$CSWITCH" statusline --account)"
  check "account mode names the next login near the limit" "$out" "work - next: default 10%"
  out="$(printf '{"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":4070908800}}}' |
    CLAUDE_CONFIG_DIR="$CSWITCH_HOME/work" "$CSWITCH" statusline --account)"
  check_not "no hint while there is room" "$out" "next:"
  teardown
}

test_handoff_continues_on_login_with_room() {
  setup
  account default t-default 10 10
  account work t-work 100 50
  in_tty "y
" "$CSWITCH" work >/dev/null 2>&1
  local log
  log="$(cat "$FAKE/claude.log")"
  check "the first session ran on work" "$log" "$CSWITCH_HOME/work|"
  check "the conversation carried on with default" "$log" "default|--continue"
  check "the last used login is now default" "$(cat "$CSWITCH_HOME/.last")" "default"
  teardown
}

test_handoff_declined_stays_put() {
  setup
  account default t-default 10 10
  account work t-work 100 50
  in_tty "n
" "$CSWITCH" work >/dev/null 2>&1
  check_not "declining starts nothing else" "$(cat "$FAKE/claude.log")" "--continue"
  teardown
}

test_no_handoff_with_room_left() {
  setup
  account default t-default 10 10
  account work t-work 40 50
  in_tty "" "$CSWITCH" work >/dev/null 2>&1
  check "claude ran once" "$(wc -l < "$FAKE/claude.log" | tr -d ' ')" "1"
  teardown
}

test_no_handoff_to_isolated_history() {
  setup
  account default t-default 100 10
  "$CSWITCH" add solo --isolated >/dev/null 2>&1
  account solo t-solo 5 5
  in_tty "y
" "$CSWITCH" default >/dev/null 2>&1
  check_not "an isolated login cannot continue the conversation" "$(cat "$FAKE/claude.log")" "--continue"
  teardown
}

test_print_mode_never_offers_handoff() {
  setup
  account default t-default 10 10
  account work t-work 100 50
  in_tty "y
" "$CSWITCH" work -p hi >/dev/null 2>&1
  check_not "-p is not interactive, so nothing is handed off" "$(cat "$FAKE/claude.log")" "--continue"
  check "and no limit check was made" "$(curl_calls)" "0"
  teardown
}

test_remove_forgets_limits() {
  setup
  account work t-work 10 10
  "$CSWITCH" usage >/dev/null
  "$CSWITCH" remove work -y >/dev/null 2>&1
  check "remove drops the remembered reading" "$(ls "$CSWITCH_HOME/.cache")" ""
  check_not "and the reading for work is gone" "$(ls "$CSWITCH_HOME/.cache")" "usage-work"
  teardown
}

for t in $(declare -F | awk '{print $3}' | grep '^test_'); do "$t"; done
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
