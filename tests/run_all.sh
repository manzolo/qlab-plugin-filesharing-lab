#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BOLD='\033[1m'; RESET='\033[0m'
printf "\n${BOLD}══════════════════════════════════════════${RESET}\n"
printf "${BOLD}  filesharing-lab — Automated Test Suite${RESET}\n"
printf "${BOLD}══════════════════════════════════════════${RESET}\n"

TOTAL_PASS=0; TOTAL_FAIL=0; SKIP="${SKIP:-}"

for t in "$DIR"/test_*.sh; do
    name="$(basename "$t" .sh)"
    if [[ -n "$SKIP" ]] && echo "$SKIP" | grep -q "$name"; then
        printf "\n${BOLD}  [SKIP] %s${RESET}\n" "$name"
        continue
    fi
    if bash "$t"; then
        TOTAL_PASS=$((TOTAL_PASS+1))
    else
        TOTAL_FAIL=$((TOTAL_FAIL+1))
    fi
done

echo ""
echo "=========================================="
if [[ "$TOTAL_FAIL" -eq 0 ]]; then
    printf "  \033[0;32m\033[1mAll %d exercise(s) passed!\033[0m\n" "$TOTAL_PASS"
else
    printf "  \033[0;31m\033[1m%d passed, %d failed\033[0m\n" "$TOTAL_PASS" "$TOTAL_FAIL"
fi
echo "=========================================="
exit "$TOTAL_FAIL"
