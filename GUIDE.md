# File Sharing Lab — Step-by-Step Guide

This guide walks you through configuring and using three file sharing protocols (FTP, NFS, Samba), testing them from a shared client, and comparing their characteristics.

## Prerequisites

Start the lab and wait for all VMs to finish booting (~90 seconds):

```bash
qlab run filesharing-lab
```

Open **two terminals** minimum (recommended: one for the client, one for a server). You can open more to inspect multiple servers simultaneously:

```bash
# Terminal 1 — Client (main workspace)
qlab shell filesharing-lab-client

# Terminal 2 — FTP Server (when needed)
qlab shell filesharing-lab-ftp

# Terminal 3 — NFS Server (when needed)
qlab shell filesharing-lab-nfs

# Terminal 4 — Samba Server (when needed)
qlab shell filesharing-lab-samba
```

On each VM, make sure cloud-init has finished:

```bash
cloud-init status --wait
```

## Network Topology

```
        Host Machine
       ┌────────────┐
       │  SSH :auto  │──────► filesharing-lab-ftp
       │  SSH :auto  │──────► filesharing-lab-nfs
       │  SSH :auto  │──────► filesharing-lab-samba
       │  SSH :auto  │──────► filesharing-lab-client
       └────────────┘

   Internal LAN (192.168.100.0/24)
  ┌───────────────────────────────────────────────────┐
  │                                                   │
  │  ┌──────────────┐  ┌──────────────┐               │
  │  │ ftp-server   │  │ nfs-server   │               │
  │  │ 192.168.100.1│  │ 192.168.100.2│               │
  │  │ FTP:21       │  │ NFS:2049     │               │
  │  └──────┬───────┘  └──────┬───────┘               │
  │         │                 │                       │
  │         ├─────────────────┤                       │
  │         │                 │                       │
  │  ┌──────┴───────┐  ┌─────┴────────┐              │
  │  │ smb-server   │  │ client       │              │
  │  │ 192.168.100.3│  │ 192.168.     │              │
  │  │ SMB:445      │  │   100.10     │              │
  │  └──────────────┘  └──────────────┘              │
  └───────────────────────────────────────────────────┘
```

Credentials for all VMs:

| User | Password | Notes |
|------|----------|-------|
| labuser | labpass | SSH access, sudo |
| alice | labpass | Lab user (UID 2001 on NFS server + client) |
| bob | labpass | Lab user (UID 2002 on NFS server + client) |

> **Important:** The client VM has `/etc/hosts` entries mapping `ftp-server`, `nfs-server`, and `smb-server` to their respective IPs.

---

## Exercise 1: FTP with vsftpd

### 1.1 Connect as an anonymous user

On **filesharing-lab-client**:

```bash
ftp ftp-server
```

When prompted, enter username `anonymous` and any email as password (or press Enter):

```
Name: anonymous
Password: (press Enter)
```

List files and download:

```
ftp> ls
ftp> get README.txt
ftp> get sample.txt
ftp> bye
```

Check the downloaded files:

```bash
cat README.txt
cat sample.txt
```

### 1.2 Connect as alice (authenticated)

```bash
ftp ftp-server
```

Login as alice:

```
Name: alice
Password: labpass
```

You are chrooted to alice's home directory. Try navigating and uploading:

```
ftp> ls
ftp> cd upload
ftp> ls
ftp> put /etc/hostname test-upload.txt
ftp> ls
ftp> bye
```

### 1.3 Verify the upload on the server

On **filesharing-lab-ftp**:

```bash
ls -la /home/alice/upload/
cat /home/alice/upload/test-upload.txt
```

### 1.4 Test chroot isolation

On **filesharing-lab-client**, connect as alice again:

```bash
ftp ftp-server
```

Try to escape the chroot:

```
Name: alice
Password: labpass
ftp> cd /
ftp> ls
ftp> cd ..
ftp> ls
```

Notice that you remain inside alice's home directory — the chroot prevents access to other parts of the filesystem.

### 1.5 Check FTP logs

On **filesharing-lab-ftp**:

```bash
sudo tail -20 /var/log/vsftpd.log
```

---

## Exercise 2: NFS — Network File System

### 2.1 Discover NFS exports

On **filesharing-lab-client**:

```bash
showmount -e nfs-server
```

Expected output:

```
Export list for nfs-server:
/readonly (everyone)
/shared   (everyone)
```

> **Note:** This lab uses nfs-ganesha (user-space NFS server) which exposes pseudo-paths. The actual server directories are `/srv/nfs/shared` and `/srv/nfs/readonly`.

### 2.2 Mount the read-write share

```bash
sudo mount -t nfs4 nfs-server:/shared /mnt/nfs-shared
```

Verify:

```bash
ls -la /mnt/nfs-shared/
cat /mnt/nfs-shared/README.txt
```

### 2.3 Test write access

As alice (UID 2001, matching the NFS server):

```bash
sudo -u alice bash
echo "Written by alice from the client" > /mnt/nfs-shared/alice-note.txt
ls -la /mnt/nfs-shared/
exit
```

Verify on **filesharing-lab-nfs**:

```bash
ls -la /srv/nfs/shared/
cat /srv/nfs/shared/alice-note.txt
```

### 2.4 Test UID mapping

On **filesharing-lab-client**:

```bash
ls -la /mnt/nfs-shared/alice-note.txt
```

The file should show `alice` as the owner because UID 2001 matches on both client and server. This is how NFS maps permissions — it relies on matching UIDs, not usernames.

### 2.5 Mount the read-only share

```bash
sudo mount -t nfs4 nfs-server:/readonly /mnt/nfs-readonly
ls -la /mnt/nfs-readonly/
cat /mnt/nfs-readonly/sample-data.txt
```

Try to write (this should fail):

```bash
touch /mnt/nfs-readonly/test.txt
```

Expected error: `touch: cannot touch '/mnt/nfs-readonly/test.txt': Read-only file system`

### 2.6 Check NFS Ganesha status on the server

On **filesharing-lab-nfs**:

```bash
systemctl status nfs-ganesha
showmount -e localhost
sudo journalctl -u nfs-ganesha --no-pager -n 20
cat /etc/ganesha/ganesha.conf
```

---

## Exercise 3: Samba — SMB/CIFS

### 3.1 List available shares

On **filesharing-lab-client**:

```bash
smbclient -L smb-server -U alice
```

Enter password `labpass` when prompted. You should see:

```
	Sharename       Type      Comment
	---------       ----      -------
	shared          Disk      Authenticated Read-Write Share
	public          Disk      Public Read-Only Share
	IPC$            IPC       IPC Service
```

### 3.2 Access the public share (guest)

```bash
smbclient //smb-server/public -N
```

The `-N` flag connects without authentication (guest access):

```
smb: \> ls
smb: \> get README.txt
smb: \> get sample-data.txt
smb: \> exit
```

Check the downloaded files:

```bash
cat README.txt
cat sample-data.txt
```

### 3.3 Access the authenticated share

```bash
smbclient //smb-server/shared -U alice
```

Enter password `labpass`:

```
smb: \> ls
smb: \> put /etc/hostname alice-upload.txt
smb: \> ls
smb: \> exit
```

### 3.4 Mount Samba share with CIFS

```bash
sudo mount -t cifs //smb-server/shared /mnt/smb-shared -o username=alice,password=labpass
ls -la /mnt/smb-shared/
```

Write a file:

```bash
echo "Written via CIFS mount" > /mnt/smb-shared/cifs-test.txt
ls -la /mnt/smb-shared/
```

### 3.5 Mount the public share

```bash
sudo mount -t cifs //smb-server/public /mnt/smb-public -o guest
ls -la /mnt/smb-public/
cat /mnt/smb-public/README.txt
```

Try to write (this should fail):

```bash
touch /mnt/smb-public/test.txt
```

### 3.6 Check Samba status on the server

On **filesharing-lab-samba**:

```bash
sudo smbstatus
sudo pdbedit -L
sudo tail -20 /var/log/samba/log.*
```

---

## Exercise 4: Cross-Protocol Comparison

This exercise uses all three protocols to perform the same operations, highlighting differences.

### 4.1 Prepare a test file

On **filesharing-lab-client**:

```bash
echo "Cross-protocol test file created at $(date)" > /tmp/testfile.txt
```

### 4.2 Upload via FTP

```bash
ftp ftp-server
```

```
Name: alice
Password: labpass
ftp> cd upload
ftp> put /tmp/testfile.txt ftp-upload.txt
ftp> bye
```

### 4.3 Upload via NFS

Make sure the share is mounted (if not already):

```bash
sudo mount -t nfs4 nfs-server:/shared /mnt/nfs-shared 2>/dev/null
sudo -u alice cp /tmp/testfile.txt /mnt/nfs-shared/nfs-upload.txt
```

### 4.4 Upload via Samba

Make sure the share is mounted (if not already):

```bash
sudo mount -t cifs //smb-server/shared /mnt/smb-shared -o username=alice,password=labpass 2>/dev/null
cp /tmp/testfile.txt /mnt/smb-shared/smb-upload.txt
```

### 4.5 Verify on each server

On **filesharing-lab-ftp**:

```bash
cat /home/alice/upload/ftp-upload.txt
```

On **filesharing-lab-nfs**:

```bash
cat /srv/nfs/shared/nfs-upload.txt
```

On **filesharing-lab-samba**:

```bash
cat /srv/samba/shared/smb-upload.txt
```

### 4.6 Comparison table

Fill in this table as you work through the exercises:

| Feature | FTP | NFS | Samba |
|---------|-----|-----|-------|
| **Port** | 21 (+ passive range) | 2049 | 445 |
| **Authentication** | Username/password | UID mapping | Username/password |
| **Mount as filesystem?** | No (file transfer) | Yes (native) | Yes (CIFS mount) |
| **Guest/anonymous access** | Yes (anonymous) | No | Yes (guest ok) |
| **Chroot isolation** | Yes (per user) | No | No (path-based) |
| **Permission model** | Unix (server-side) | Unix (UID-based) | ACL + Unix |
| **Best for** | File transfer, downloads | Shared storage (Linux) | Mixed OS environments |
| **Encryption** | FTPS (optional) | Kerberos (optional) | SMB3 encryption |
| **OS compatibility** | Universal | Linux/Unix native | Windows + Linux + macOS |

---

## Troubleshooting

### FTP: "Connection refused"

- Cloud-init may still be running: `cloud-init status --wait`
- Check that vsftpd is running on the FTP server: `systemctl status vsftpd`
- Verify connectivity: `ping ftp-server`

### FTP: "500 OOPS: vsftpd: refusing to run with writable root inside chroot()"

This should not happen in this lab (we use `allow_writeable_chroot=YES`). If it does, check `/etc/vsftpd.conf` on the FTP server.

### FTP: passive mode issues

The lab configures passive mode on 192.168.100.1 ports 30000-30100. If you experience timeout issues with `ls` or transfers, try using `lftp` instead of `ftp`:

```bash
lftp -u alice,labpass ftp-server
```

### NFS: "mount.nfs: access denied by server"

- Check the server config: `cat /etc/ganesha/ganesha.conf` on the NFS server
- Verify nfs-ganesha is running: `systemctl status nfs-ganesha`
- Restart NFS server: `sudo systemctl restart nfs-ganesha`
- Use NFSv4 pseudo-paths: mount `nfs-server:/shared` not `nfs-server:/srv/nfs/shared`

### NFS: permission denied when writing

- Check the UID of the user on the client matches the UID on the server
- For the `shared` export, `No_Root_Squash` is set, so root can write
- For the `readonly` export, writing is not allowed by design

### Samba: "NT_STATUS_LOGON_FAILURE"

- Verify the user has a Samba password: `sudo pdbedit -L` on the Samba server
- Re-add the password: `sudo printf "labpass\nlabpass\n" | sudo smbpasswd -a -s alice`
- Check that the user exists in the system: `id alice`

### Samba: "mount error(13): Permission denied"

- Make sure you use the correct username and password in mount options
- For the public share, use `-o guest` instead of specifying a username
- Check that smbd is running: `systemctl status smbd`

### General: packages not installed

If commands like `ftp`, `smbclient`, or `showmount` are not found, cloud-init may still be running:

```bash
cloud-init status --wait
```

### General: "Name or service not known"

Make sure `/etc/hosts` on the client has the correct entries:

```bash
cat /etc/hosts | grep -E "ftp|nfs|smb"
```

Expected:

```
192.168.100.1 ftp-server
192.168.100.2 nfs-server
192.168.100.3 smb-server
```
