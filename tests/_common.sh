#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'
PASS_COUNT=0; FAIL_COUNT=0
log_ok()   { printf "${GREEN}  [PASS]${RESET} %s\n" "$*"; }
log_fail() { printf "${RED}  [FAIL]${RESET} %s\n" "$*"; }
log_info() { printf "${YELLOW}  [INFO]${RESET} %s\n" "$*"; }
assert() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then log_ok "$d"; PASS_COUNT=$((PASS_COUNT+1)); else log_fail "$d"; FAIL_COUNT=$((FAIL_COUNT+1)); fi; }
assert_fail() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then log_fail "$d"; FAIL_COUNT=$((FAIL_COUNT+1)); else log_ok "$d"; PASS_COUNT=$((PASS_COUNT+1)); fi; }
assert_contains() { local d="$1" o="$2" p="$3"; if echo "$o"|grep -qE "$p"; then log_ok "$d"; PASS_COUNT=$((PASS_COUNT+1)); else log_fail "$d (expected: $p)"; FAIL_COUNT=$((FAIL_COUNT+1)); fi; }
assert_not_contains() { local d="$1" o="$2" p="$3"; if echo "$o"|grep -qE "$p"; then log_fail "$d (unexpected: $p)"; FAIL_COUNT=$((FAIL_COUNT+1)); else log_ok "$d"; PASS_COUNT=$((PASS_COUNT+1)); fi; }

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; PLUGIN_DIR="$(cd "$TESTS_DIR/.." && pwd)"
_find_workspace() { local d="$PLUGIN_DIR"; if [[ -d "$d/../../.qlab" ]]; then echo "$(cd "$d/../.." && pwd)"; return; fi; while [[ "$d" != "/" ]]; do if [[ -d "$d/.qlab" ]]; then echo "$d"; return; fi; d="$(dirname "$d")"; done; echo ""; }

WORKSPACE_DIR="$(_find_workspace)"
if [[ -z "$WORKSPACE_DIR" ]]; then echo "ERROR: Cannot find qlab workspace."; exit 1; fi
STATE_DIR="$WORKSPACE_DIR/.qlab/state"; SSH_KEY="$WORKSPACE_DIR/.qlab/ssh/qlab_id_rsa"
_get_port() { local f="$STATE_DIR/${1}.port"; if [[ -f "$f" ]]; then cat "$f"; else echo ""; fi; }

FTP_PORT="$(_get_port filesharing-lab-ftp)"
NFS_PORT="$(_get_port filesharing-lab-nfs)"
SAMBA_PORT="$(_get_port filesharing-lab-samba)"
CLIENT_PORT="$(_get_port filesharing-lab-client)"
if [[ -z "$FTP_PORT" || -z "$NFS_PORT" || -z "$SAMBA_PORT" || -z "$CLIENT_PORT" ]]; then
    echo "ERROR: Cannot find VM ports. Are filesharing-lab VMs running?"
    exit 1
fi

_ssh_base_opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
ssh_ftp()    { ssh "${_ssh_base_opts[@]}" -i "$SSH_KEY" -p "$FTP_PORT"    labuser@localhost "$@"; }
ssh_nfs()    { ssh "${_ssh_base_opts[@]}" -i "$SSH_KEY" -p "$NFS_PORT"    labuser@localhost "$@"; }
ssh_samba()  { ssh "${_ssh_base_opts[@]}" -i "$SSH_KEY" -p "$SAMBA_PORT"  labuser@localhost "$@"; }
ssh_client() { ssh "${_ssh_base_opts[@]}" -i "$SSH_KEY" -p "$CLIENT_PORT" labuser@localhost "$@"; }

report_results() { local t="${1:-Test}"; echo ""; if [[ "$FAIL_COUNT" -eq 0 ]]; then printf "${GREEN}${BOLD}  %s: All %d checks passed${RESET}\n" "$t" "$PASS_COUNT"; else printf "${RED}${BOLD}  %s: %d passed, %d failed${RESET}\n" "$t" "$PASS_COUNT" "$FAIL_COUNT"; fi; return "$FAIL_COUNT"; }
