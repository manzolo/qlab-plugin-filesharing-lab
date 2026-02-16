#!/usr/bin/env bash
set -euo pipefail

echo ""
echo "  ╔═══════════════════════════════════════════════════════════╗"
echo "  ║             filesharing-lab — Installation                ║"
echo "  ╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "  This lab deploys 4 VMs to compare three file sharing protocols:"
echo ""
echo "    • FTP  — vsftpd with local users and anonymous access"
echo "    • NFS  — NFS server with read-write and read-only exports"
echo "    • Samba — Samba with authenticated and guest shares"
echo "    • Client — A shared client VM to test all three protocols"
echo ""
echo "  You will learn:"
echo "    - How to configure and use FTP, NFS and Samba"
echo "    - Differences in authentication, permissions and use cases"
echo "    - How to mount remote filesystems on a Linux client"
echo ""

# Create lab working directory
mkdir -p lab

echo "  Checking dependencies..."
echo ""

MISSING=0
for cmd in qemu-system-x86_64 qemu-img genisoimage curl; do
    if command -v "$cmd" &>/dev/null; then
        echo "    [OK] $cmd"
    else
        echo "    [!!] $cmd — not found"
        MISSING=1
    fi
done

echo ""

if [[ "$MISSING" -eq 1 ]]; then
    echo "  Some dependencies are missing. Install them with:"
    echo ""
    echo "    sudo apt install qemu-system-x86 qemu-utils genisoimage curl"
    echo ""
fi

echo "  [filesharing-lab] Installation complete."
echo "  Run with: qlab run filesharing-lab"
echo ""
