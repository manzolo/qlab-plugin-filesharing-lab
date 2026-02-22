#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
echo ""; echo "${BOLD}Exercise 3 — Samba${RESET}"; echo ""

# 3.1 Samba (smbd) is running
smb_status=$(ssh_samba "systemctl is-active smbd 2>/dev/null" || echo "unknown")
assert_contains "smbd is active" "$smb_status" "active"

# 3.2 Port 445 listening
ports=$(ssh_samba "ss -tlnp 2>/dev/null")
assert_contains "Port 445 (SMB) listening" "$ports" ":445"

# 3.3 Samba users registered
samba_users=$(ssh_samba "sudo pdbedit -L 2>/dev/null" || echo "")
assert_contains "alice is a Samba user" "$samba_users" "alice"
assert_contains "bob is a Samba user" "$samba_users" "bob"

# 3.4 Samba shares configured
smb_conf=$(ssh_samba "cat /etc/samba/smb.conf 2>/dev/null" || echo "")
assert_contains "Shared share configured" "$smb_conf" "\\[shared\\]"
assert_contains "Public share configured" "$smb_conf" "\\[public\\]"

# 3.5 Share directories have content
shared_files=$(ssh_samba "ls /srv/samba/shared/ 2>/dev/null" || echo "")
assert_contains "Samba shared dir has content" "$shared_files" "README.txt"

public_files=$(ssh_samba "ls /srv/samba/public/ 2>/dev/null" || echo "")
assert_contains "Samba public dir has content" "$public_files" "README.txt"

# 3.6 Client can reach Samba server
smb_ping=$(ssh_client "ping -c1 -W2 192.168.100.3 2>/dev/null" || echo "")
assert_contains "Client can reach Samba server" "$smb_ping" "1 received"

# 3.7 Client has smbclient
smb_tool=$(ssh_client "which smbclient 2>/dev/null" || echo "")
assert_contains "smbclient installed on client" "$smb_tool" "smbclient"

# 3.8 Client can list Samba shares
shares_list=$(ssh_client "smbclient -L smb-server -U alice%labpass -g 2>/dev/null" || echo "")
assert_contains "Client sees shared share" "$shares_list" "shared"
assert_contains "Client sees public share" "$shares_list" "public"

# 3.9 Public share accessible as guest
public_content=$(ssh_client "smbclient //smb-server/public -N -c 'get README.txt /tmp/smb-public-test.txt' 2>/dev/null; cat /tmp/smb-public-test.txt 2>/dev/null" || echo "")
assert_contains "Public share readable via guest" "$public_content" "Samba|public|read-only"

# 3.10 Authenticated share accessible
auth_content=$(ssh_client "smbclient //smb-server/shared -U alice%labpass -c 'get README.txt /tmp/smb-shared-test.txt' 2>/dev/null; cat /tmp/smb-shared-test.txt 2>/dev/null" || echo "")
assert_contains "Shared share readable via auth" "$auth_content" "Samba|shared|Welcome"

# Clean up
ssh_client "rm -f /tmp/smb-public-test.txt /tmp/smb-shared-test.txt" 2>/dev/null

report_results "Exercise 3"
