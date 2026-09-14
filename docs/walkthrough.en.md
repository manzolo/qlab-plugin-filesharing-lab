---
kicker: QLab · filesharing-lab
title: |
  Three ways to hand
  over a file
subtitle: >
  FTP, NFS and SMB, each on its own server, all reached from one client on the
  same wire. Same job, three answers — and three different ideas of who you are.
  From a running lab.
facts:
  - [Command, "`qlab run filesharing-lab`"]
  - [VMs, "`filesharing-lab-ftp` · `-nfs` · `-samba` · `-client`"]
  - [LAN, "`192.168.100.0/24`, isolated between the four VMs"]
  - [Credentials, "`labuser` / `labpass` · lab accounts `alice`, `bob` / `labpass`"]
  - [Outcome, "`qlab test filesharing-lab` → 4 exercises, 52 checks, all passed"]
---

## 1. Four machines, one wire

{{evidence:topology as=shell}}

Three servers, one protocol each, and a client that talks to all of them. The
addresses are fixed, so nothing in this walkthrough depends on what DHCP felt
like doing. The client is the interesting machine: everything after this section
is the same task — read a file that lives somewhere else — carried out three
times from there.

Splitting the servers apart is the point. On one box the three protocols blur
together; on three boxes each one has to bring its own transport, its own
authentication and its own idea of what a "file" is.

## 2. What each server is actually running

{{evidence:services as=shell}}

Three daemons, three configuration styles.

**vsftpd** is configured by flat `key=value` lines. Two of them matter here:
`anonymous_enable` opens a login with no account behind it, rooted at
`anon_root`, and `chroot_local_user` locks a real account into its own home. One
daemon, two quite different experiences depending on the name you type.

The NFS server is **NFS-Ganesha**, which runs in userspace rather than in the
kernel — worth noticing, because most NFS documentation assumes
`nfs-kernel-server` and `/etc/exports`, and neither exists on this machine. Each
export names a real `Path`, a `Pseudo` name clients use instead, an
`Access_Type` and a `Squash` policy. The two exports differ in exactly those
last two fields.

**Samba** answers `testparm` with the config it has actually parsed. `shared`
has `valid users`, `public` has `guest ok` — the same distinction vsftpd draws
with `anonymous_enable`, written in a different dialect.

## 3. FTP: a conversation with numbers in front

{{evidence:ftp-session as=shell}}

FTP is old enough to be readable. Every server reply is a three-digit code and a
sentence: `220` on connect, `230` for a successful login, `150` before data
starts moving, `226` when it is done, `221` on the way out. That is the whole
protocol, and it is why FTP is the protocol people learn to debug by hand with
`telnet`.

Two logins run here against the same daemon. The anonymous one lands on the
directory `anon_root` points at and sees the two files placed there. Then
`alice` logs in with a real password and `pwd` answers `/` — not because she is
at the root of the server, but because `chroot_local_user` has made her home
*look* like the root. She cannot see the anonymous directory, or anything else
on the machine.

:::warn
The password went across in clear text. So does everything in the listing. FTP
predates the assumption that the network is hostile; on a real network this is
FTPS or SFTP, and the reason the lab keeps plain FTP is that you can read it.
:::

## 4. NFS: the file server that disappears

{{evidence:nfs-mount as=shell}}

Nothing here looks like a network protocol, and that is the whole idea. After
`mount`, the remote directory is a directory. `ls` works. Writing works. No
client program, no session, no transfer commands — the kernel turns ordinary
filesystem calls into NFS requests and back.

`showmount -e` asks the server what it offers before committing to anything, and
answers with the real paths. The mount itself uses the **pseudo** path instead:
NFSv4 hangs every export off a single virtual root, so clients ask for `/shared`
and never learn where it lives on the server's disk.

The `mount` line is worth reading once. `vers=4.2` is the negotiated protocol
version, `hard` means a request retries forever instead of failing when the
server is briefly unreachable, and `sec=sys` is the authentication — of which
more in a moment.

## 5. `sec=sys`: identity is a number you send

{{evidence:nfs-identity as=shell}}

The same two files, listed on both machines, first as numbers and then as names.

The numbers cross the wire; the names never do. `alice` is uid 2001 on the
server, and this lab gives the client an `alice` at uid 2001 as well, so both
sides print the same name and everything looks natural. Change the client's
`alice` to 1001 and the file would show up owned by whoever *is* 2001 there — or
by a bare `2001` if nobody is. Nothing would be broken, and nothing would warn
you.

`from-client.txt` is the other half of the lesson. It was written by `sudo` on
the client and it belongs to `root` on the server, because this export is
configured `Squash = No_Root_Squash`: the server takes uid 0 at its word. The
default — and what the read-only export uses — is `Root_Squash`, which maps a
remote root down to `nobody` precisely so that administrative access on a client
does not become administrative access on the server's files.

:::note
`sec=sys` means the server trusts the client's word about who is asking. That is
an entirely reasonable model on a machine-room network you control, and it is
why NFS is normally kept off any network you do not. The alternative, `sec=krb5`,
puts Kerberos in the path so identity is proven rather than asserted.
:::

## 6. SMB: shares, not filesystems

{{evidence:samba-session as=shell}}

SMB sits between the other two. It is a session protocol like FTP — you connect,
authenticate, and run commands — but what it exposes is a *share*, a named tree
that can be mounted like NFS or browsed like FTP. `smbclient` here is the
browse-it-by-hand version.

The share list is the server's public catalogue: the two configured shares plus
`IPC$`, the control channel SMB uses for the share list itself. Then `get`
pulls a file. The "SMB1 disabled" line is not an error — it is `smbclient`
noting that the ancient workgroup-browsing protocol is switched off, as it
should be.

The last command is the one that matters: the same share, no credentials,
`NT_STATUS_ACCESS_DENIED`. Authorisation is per-share and checked by the server,
which is the structural difference from NFS. Here the server decides; with
`sec=sys` NFS, the client does.

## 7. The three side by side

{{evidence:comparison as=shell}}

The three servers are reachable on their three ports, and exactly one of the
three protocols shows up in `mount` — because only NFS was designed to become
part of the local filesystem. FTP and SMB can be made to look like that too
(`curlftpfs`, `mount -t cifs`), but for FTP that is a client-side illusion, and
for SMB it is a second way of using a protocol that already had a session.

The useful summary is the identity column. FTP names a user per session, in
clear. SMB names a user per share, checked by the server. NFS names nobody at
all: it sends a number and trusts you. Three protocols, three answers to the
only question that really separates them.

## 8. Try it yourself

```
qlab run filesharing-lab
qlab shell filesharing-lab-client
```

From the client:

```
ftp -inv 192.168.100.1                      # anonymous / alice+labpass
sudo mount -t nfs 192.168.100.2:/shared /mnt/nfs-shared
sudo mount -t nfs 192.168.100.2:/readonly /mnt/nfs-readonly
smbclient //192.168.100.3/shared -U alice%labpass -m SMB3
smbclient //192.168.100.3/public -N -m SMB3
```

Three things worth doing after that:

- Write to `/mnt/nfs-readonly` and watch which layer refuses you.
- Change `alice`'s uid on the client, remount, and see the ownership of
  `README.txt` change without a single error message.
- Run `sudo tail -f /var/log/vsftpd.log` on the FTP server while you log in from
  the client — the whole conversation, both sides, in plain text.

{{evidence:qlab-test as=shell grep="Exercise [0-9]|All [0-9]+ (exercise|checks)" }}

`qlab test filesharing-lab` runs 52 checks across the four VMs. The last
exercise is the cross-protocol one, and its `Alice UID matches (2001)` check is
there for the reason section 5 explains: on this lab the number agrees, and the
test says so out loud rather than letting it look like magic.
