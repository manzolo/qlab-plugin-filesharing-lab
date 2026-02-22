#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
echo ""; echo "${BOLD}Exercise 4 — Cross-Protocol Comparison${RESET}"; echo ""

# 4.1 Client has /etc/hosts entries
hosts=$(ssh_client "cat /etc/hosts 2>/dev/null" || echo "")
assert_contains "ftp-server in /etc/hosts" "$hosts" "ftp-server"
assert_contains "nfs-server in /etc/hosts" "$hosts" "nfs-server"
assert_contains "smb-server in /etc/hosts" "$hosts" "smb-server"

# 4.2 Client can ping all servers
ftp_ping=$(ssh_client "ping -c1 -W2 ftp-server 2>/dev/null" || echo "")
assert_contains "Client can ping ftp-server" "$ftp_ping" "1 received"

nfs_ping=$(ssh_client "ping -c1 -W2 nfs-server 2>/dev/null" || echo "")
assert_contains "Client can ping nfs-server" "$nfs_ping" "1 received"

smb_ping=$(ssh_client "ping -c1 -W2 smb-server 2>/dev/null" || echo "")
assert_contains "Client can ping smb-server" "$smb_ping" "1 received"

# 4.3 Client has all required tools
for tool in ftp lftp showmount smbclient; do
    tool_path=$(ssh_client "which $tool 2>/dev/null" || echo "")
    assert_contains "$tool available on client" "$tool_path" "$tool"
done

# 4.4 UID mapping: alice UID matches between NFS server and client
alice_uid_nfs=$(ssh_nfs "id -u alice 2>/dev/null" || echo "0")
alice_uid_client=$(ssh_client "id -u alice 2>/dev/null" || echo "1")
if [[ "$alice_uid_nfs" == "$alice_uid_client" && "$alice_uid_nfs" == "2001" ]]; then
    log_ok "Alice UID matches (2001) for NFS mapping"
    PASS_COUNT=$((PASS_COUNT+1))
else
    log_fail "Alice UID mismatch: NFS=$alice_uid_nfs, client=$alice_uid_client"
    FAIL_COUNT=$((FAIL_COUNT+1))
fi

# 4.5 Mount points exist on client
for mp in /mnt/nfs-shared /mnt/nfs-readonly /mnt/smb-shared /mnt/smb-public; do
    mp_exists=$(ssh_client "test -d $mp && echo yes || echo no" 2>/dev/null)
    assert_contains "Mount point $mp exists" "$mp_exists" "yes"
done

report_results "Exercise 4"
