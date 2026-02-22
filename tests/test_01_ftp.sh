#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
echo ""; echo "${BOLD}Exercise 1 — FTP with vsftpd${RESET}"; echo ""

# 1.1 vsftpd is running
ftp_status=$(ssh_ftp "systemctl is-active vsftpd 2>/dev/null" || echo "unknown")
assert_contains "vsftpd is active" "$ftp_status" "active"

# 1.2 Port 21 listening
ports=$(ssh_ftp "ss -tlnp 2>/dev/null")
assert_contains "Port 21 listening" "$ports" ":21"

# 1.3 FTP users exist
alice_id=$(ssh_ftp "id alice 2>/dev/null" || echo "")
assert_contains "User alice exists on FTP server" "$alice_id" "uid="

bob_id=$(ssh_ftp "id bob 2>/dev/null" || echo "")
assert_contains "User bob exists on FTP server" "$bob_id" "uid="

# 1.4 Anonymous FTP directory exists with content
anon_dir=$(ssh_ftp "ls /srv/ftp/shared/ 2>/dev/null" || echo "")
assert_contains "Anonymous FTP has README.txt" "$anon_dir" "README.txt"
assert_contains "Anonymous FTP has sample.txt" "$anon_dir" "sample.txt"

# 1.5 Client can reach FTP server
ftp_ping=$(ssh_client "ping -c1 -W2 192.168.100.1 2>/dev/null" || echo "")
assert_contains "Client can reach FTP server" "$ftp_ping" "1 received"

# 1.6 Client has FTP tools
ftp_tool=$(ssh_client "which ftp 2>/dev/null" || echo "")
assert_contains "ftp client installed" "$ftp_tool" "ftp"

lftp_tool=$(ssh_client "which lftp 2>/dev/null" || echo "")
assert_contains "lftp client installed" "$lftp_tool" "lftp"

# 1.7 Anonymous FTP download works
anon_dl=$(ssh_client "echo -e 'user anonymous\npass\nget README.txt /tmp/ftp-anon-test.txt\nbye' | timeout 10 ftp -n ftp-server 2>/dev/null; cat /tmp/ftp-anon-test.txt 2>/dev/null" || echo "")
assert_contains "Anonymous FTP download works" "$anon_dl" "filesharing-lab|Welcome"

# 1.8 Alice's upload directory exists
assert "Alice upload dir exists" ssh_ftp "sudo test -d /home/alice/upload"

# Clean up
ssh_client "rm -f /tmp/ftp-anon-test.txt" 2>/dev/null

report_results "Exercise 1"
