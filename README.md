# filesharing-lab

A multi-VM lab that deploys three file sharing servers (FTP, NFS, Samba) and a shared client to compare protocols, authentication models, and use cases.

## Architecture

```
   Internal LAN (192.168.100.0/24)
  ┌───────────────────────────────────────────────────┐
  │                                                   │
  │  ┌──────────────────┐  ┌──────────────────┐       │
  │  │ ftp-server       │  │ nfs-server       │       │
  │  │ 192.168.100.1    │  │ 192.168.100.2    │       │
  │  │ vsftpd (FTP:21)  │  │ NFS:2049         │       │
  │  └────────┬─────────┘  └────────┬─────────┘       │
  │           │                     │                 │
  │  ┌────────┴─────────┐   ┌───────┴──────────┐      │
  │  │ smb-server       │   │ client           │      │
  │  │ 192.168.100.3    │   │ 192.168.100.10   │      │
  │  │ Samba (SMB:445)  │   │ ftp/nfs/smb      │      │
  │  └──────────────────┘   └──────────────────┘      │
  └───────────────────────────────────────────────────┘
```

## VMs

| VM | IP | Role |
|----|-----|------|
| filesharing-lab-ftp | 192.168.100.1 | vsftpd — local users + anonymous access |
| filesharing-lab-nfs | 192.168.100.2 | NFS server — rw and ro exports |
| filesharing-lab-samba | 192.168.100.3 | Samba — authenticated and guest shares |
| filesharing-lab-client | 192.168.100.10 | Client with ftp, nfs-common, smbclient, cifs-utils |

## Services

**FTP Server (vsftpd):**
- Anonymous read-only access on `/srv/ftp/shared`
- Authenticated access with chroot per user
- Passive mode on ports 30000-30100

**NFS Server:**
- `/srv/nfs/shared` — read-write, no_root_squash
- `/srv/nfs/readonly` — read-only
- UID mapping via fixed UIDs (alice=2001, bob=2002)

**Samba Server:**
- `[shared]` — read-write, authenticated (alice, bob)
- `[public]` — read-only, guest access allowed

## Credentials

| User | Password | Notes |
|------|----------|-------|
| labuser | labpass | SSH access, sudo on all VMs |
| alice | labpass | Lab user (UID 2001 on NFS server + client) |
| bob | labpass | Lab user (UID 2002 on NFS server + client) |

## Usage

```bash
# Install the plugin
qlab install ./qlab-plugin-filesharing-lab

# Start the lab (4 VMs)
qlab run filesharing-lab

# Connect to VMs
qlab shell filesharing-lab-client
qlab shell filesharing-lab-ftp
qlab shell filesharing-lab-nfs
qlab shell filesharing-lab-samba

# View VM logs
qlab log filesharing-lab-client

# Stop all VMs
qlab stop filesharing-lab
```

## Quick Test

After boot (~90 seconds), connect to the client and test all three protocols:

```bash
qlab shell filesharing-lab-client

# Wait for cloud-init
cloud-init status --wait

# FTP
ftp ftp-server

# NFS
showmount -e nfs-server
sudo mount -t nfs nfs-server:/srv/nfs/shared /mnt/nfs-shared

# Samba
smbclient -L smb-server -U alice
```

## Exercises

See [GUIDE.md](GUIDE.md) for detailed step-by-step exercises:

1. **FTP** — anonymous and authenticated access, chroot, uploads
2. **NFS** — mount exports, test permissions, UID mapping
3. **Samba** — smbclient, CIFS mounts, guest vs authenticated
4. **Cross-protocol comparison** — same operation on all three, comparison table

## Resource Override

```bash
QLAB_MEMORY=1024 QLAB_DISK_SIZE=30G qlab run filesharing-lab
```

## Reset

To reset the lab, stop and re-run:

```bash
qlab stop filesharing-lab
qlab run filesharing-lab
```
