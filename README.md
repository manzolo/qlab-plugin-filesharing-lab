# filesharing-lab — FTP, NFS & SMB Lab

[![QLab Plugin](https://img.shields.io/badge/QLab-Plugin-blue)](https://github.com/manzolo/qlab)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Walkthrough](https://img.shields.io/badge/walkthrough-EN%20%26%20IT-informational)](docs/walkthrough-en.pdf)

A four-VM [QLab](https://github.com/manzolo/qlab) lab — three file servers, one protocol
each, and a client that talks to all of them — for putting FTP, NFS and Samba side by side:
same job, three answers, three different ideas of who you are.

## Quick start

```bash
qlab install filesharing-lab
qlab run filesharing-lab              # boots 4 VMs (~120s)
qlab shell filesharing-lab-client     # talks to all three servers
qlab shell filesharing-lab-ftp        # vsftpd
qlab shell filesharing-lab-nfs        # NFS-Ganesha
qlab shell filesharing-lab-samba      # Samba
qlab test filesharing-lab             # run the automated checks
qlab stop filesharing-lab
```

## What's inside

| Protocol | Server | How it appears | Identity |
|----------|--------|----------------|----------|
| **FTP** | vsftpd | a session; you copy files in and out | username + password, in clear |
| **NFS** | NFS-Ganesha | a directory in your filesystem | numeric uid/gid, trusted |
| **SMB** | Samba | a share you mount or browse | username + password, per share |

The client drives all three so the comparison is the point — see the guide for the full run.

## Network

Private LAN `192.168.100.0/24`, isolated between the four VMs.

| VM | Address | Role |
|----|---------|------|
| `filesharing-lab-ftp` | `192.168.100.1` | vsftpd |
| `filesharing-lab-nfs` | `192.168.100.2` | NFS-Ganesha |
| `filesharing-lab-samba` | `192.168.100.3` | Samba |
| `filesharing-lab-client` | `192.168.100.10` | ftp / nfs / smbclient |

Accounts: `labuser` / `labpass` · lab users `alice`, `bob` / `labpass`. SSH forwarded — see `qlab ports`.

## Learn more

- 📖 **[Step-by-step guide](guide.md)** — every protocol with full commands
- 📄 **Illustrated walkthrough** — a real run, captured live: **[English](docs/walkthrough-en.pdf)** · **[Italiano](docs/walkthrough-it.pdf)**
- 🧩 **[QLab](https://github.com/manzolo/qlab)** — the plugin runner: how install, overlays and cloud-init work
