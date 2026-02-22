#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
echo ""; echo "${BOLD}Exercise 2 — NFS with Ganesha${RESET}"; echo ""

# 2.1 NFS Ganesha is running
nfs_status=$(ssh_nfs "systemctl is-active nfs-ganesha 2>/dev/null" || echo "unknown")
assert_contains "NFS Ganesha is active" "$nfs_status" "active"

# 2.2 NFS exports are available
exports=$(ssh_nfs "showmount -e localhost 2>/dev/null" || echo "")
assert_contains "Shared export exists" "$exports" "shared"
assert_contains "Readonly export exists" "$exports" "readonly"

# 2.3 NFS shared directory has content
shared_files=$(ssh_nfs "ls /srv/nfs/shared/ 2>/dev/null" || echo "")
assert_contains "Shared dir has README.txt" "$shared_files" "README.txt"

# 2.4 NFS readonly directory has content
readonly_files=$(ssh_nfs "ls /srv/nfs/readonly/ 2>/dev/null" || echo "")
assert_contains "Readonly dir has README.txt" "$readonly_files" "README.txt"
assert_contains "Readonly dir has sample-data.txt" "$readonly_files" "sample-data.txt"

# 2.5 Client can reach NFS server
nfs_ping=$(ssh_client "ping -c1 -W2 192.168.100.2 2>/dev/null" || echo "")
assert_contains "Client can reach NFS server" "$nfs_ping" "1 received"

# 2.6 Client has NFS tools
showmount_tool=$(ssh_client "which showmount 2>/dev/null" || echo "")
assert_contains "showmount installed on client" "$showmount_tool" "showmount"

# 2.7 Client can see exports
client_exports=$(ssh_client "showmount -e nfs-server 2>/dev/null" || echo "")
assert_contains "Client sees NFS exports" "$client_exports" "shared"

# 2.8 Mount and read NFS shared
ssh_client "sudo mount -t nfs4 nfs-server:/shared /mnt/nfs-shared 2>/dev/null" || true
nfs_content=$(ssh_client "cat /mnt/nfs-shared/README.txt 2>/dev/null" || echo "")
assert_contains "NFS shared mount readable" "$nfs_content" "NFS|Welcome"

# 2.9 Write to NFS shared
ssh_client "sudo -u alice bash -c 'echo test-nfs-write > /mnt/nfs-shared/test-write.txt' 2>/dev/null" || true
nfs_write_check=$(ssh_nfs "cat /srv/nfs/shared/test-write.txt 2>/dev/null" || echo "")
assert_contains "NFS write works" "$nfs_write_check" "test-nfs-write"

# 2.10 Mount readonly and verify read-only
ssh_client "sudo mount -t nfs4 nfs-server:/readonly /mnt/nfs-readonly 2>/dev/null" || true
ro_content=$(ssh_client "cat /mnt/nfs-readonly/README.txt 2>/dev/null" || echo "")
assert_contains "NFS readonly mount readable" "$ro_content" "read-only|NFS"

# Clean up
ssh_nfs "sudo rm -f /srv/nfs/shared/test-write.txt" 2>/dev/null
ssh_client "sudo umount /mnt/nfs-shared 2>/dev/null; sudo umount /mnt/nfs-readonly 2>/dev/null" || true

report_results "Exercise 2"
