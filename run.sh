#!/usr/bin/env bash
# filesharing-lab run script — boots four VMs for file sharing labs (FTP, NFS, Samba)

set -euo pipefail

PLUGIN_NAME="filesharing-lab"
FTP_VM="filesharing-lab-ftp"
NFS_VM="filesharing-lab-nfs"
SAMBA_VM="filesharing-lab-samba"
CLIENT_VM="filesharing-lab-client"

# Internal LAN — direct VM-to-VM link via QEMU socket multicast
INTERNAL_MCAST="230.0.0.1:10300"
FTP_INTERNAL_IP="192.168.100.1"
NFS_INTERNAL_IP="192.168.100.2"
SAMBA_INTERNAL_IP="192.168.100.3"
CLIENT_INTERNAL_IP="192.168.100.10"
FTP_LAN_MAC="52:54:00:00:09:01"
NFS_LAN_MAC="52:54:00:00:09:02"
SAMBA_LAN_MAC="52:54:00:00:09:03"
CLIENT_LAN_MAC="52:54:00:00:09:04"

echo "============================================="
echo "  filesharing-lab: File Sharing Lab"
echo "  FTP + NFS + Samba"
echo "============================================="
echo ""
echo "  This lab creates four VMs connected by an"
echo "  internal LAN (192.168.100.0/24):"
echo ""
echo "    1. $FTP_VM"
echo "       Internal IP: $FTP_INTERNAL_IP"
echo "       vsftpd (local users + anonymous)"
echo ""
echo "    2. $NFS_VM"
echo "       Internal IP: $NFS_INTERNAL_IP"
echo "       NFS server (rw + ro exports)"
echo ""
echo "    3. $SAMBA_VM"
echo "       Internal IP: $SAMBA_INTERNAL_IP"
echo "       Samba (authenticated + guest shares)"
echo ""
echo "    4. $CLIENT_VM"
echo "       Internal IP: $CLIENT_INTERNAL_IP"
echo "       Client with ftp, nfs, smbclient"
echo ""

# Source QLab core libraries
if [[ -z "${QLAB_ROOT:-}" ]]; then
    echo "ERROR: QLAB_ROOT not set. Run this plugin via 'qlab run ${PLUGIN_NAME}'."
    exit 1
fi

for lib_file in "$QLAB_ROOT"/lib/*.bash; do
    # shellcheck source=/dev/null
    [[ -f "$lib_file" ]] && source "$lib_file"
done

# Configuration
WORKSPACE_DIR="${WORKSPACE_DIR:-.qlab}"
LAB_DIR="lab"
IMAGE_DIR="$WORKSPACE_DIR/images"
CLOUD_IMAGE_URL=$(get_config CLOUD_IMAGE_URL "https://cloud-images.ubuntu.com/minimal/releases/jammy/release/ubuntu-22.04-minimal-cloudimg-amd64.img")
CLOUD_IMAGE_FILE="$IMAGE_DIR/ubuntu-22.04-minimal-cloudimg-amd64.img"
MEMORY="${QLAB_MEMORY:-$(get_config DEFAULT_MEMORY 512)}"

# Ensure directories exist
mkdir -p "$LAB_DIR" "$IMAGE_DIR"

# =============================================
# Step 1: Download cloud image (shared by all VMs)
# =============================================
info "Step 1: Cloud image"
if [[ -f "$CLOUD_IMAGE_FILE" ]]; then
    success "Cloud image already downloaded: $CLOUD_IMAGE_FILE"
else
    echo ""
    echo "  Cloud images are pre-built OS images designed for cloud environments."
    echo "  All VMs will share the same base image via overlay disks."
    echo ""
    info "Downloading Ubuntu cloud image..."
    echo "  URL: $CLOUD_IMAGE_URL"
    echo "  This may take a few minutes depending on your connection."
    echo ""
    check_dependency curl || exit 1
    curl -L -o "$CLOUD_IMAGE_FILE" "$CLOUD_IMAGE_URL" || {
        error "Failed to download cloud image."
        echo "  Check your internet connection and try again."
        exit 1
    }
    success "Cloud image downloaded: $CLOUD_IMAGE_FILE"
fi
echo ""

# =============================================
# Step 2: Cloud-init configurations
# =============================================
info "Step 2: Cloud-init configuration for all VMs"
echo ""

# --- FTP Server VM cloud-init ---
info "Creating cloud-init for $FTP_VM..."
cat > "$LAB_DIR/user-data-ftp" <<'USERDATA'
#cloud-config
hostname: filesharing-lab-ftp
package_update: true
users:
  - name: labuser
    plain_text_passwd: labpass
    lock_passwd: false
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - "__QLAB_SSH_PUB_KEY__"
ssh_pwauth: true
packages:
  - vsftpd
  - rsyslog
  - nano
  - net-tools
  - iputils-ping
  - tcpdump
write_files:
  - path: /etc/profile.d/cloud-init-status.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      if command -v cloud-init >/dev/null 2>&1; then
        status=$(cloud-init status 2>/dev/null)
        if echo "$status" | grep -q "running"; then
          printf '\033[1;33m'
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          echo "  Cloud-init is still running..."
          echo "  Some packages and services may not be ready yet."
          echo "  Run 'cloud-init status --wait' to wait for completion."
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          printf '\033[0m\n'
        fi
      fi
  - path: /etc/netplan/60-internal.yaml
    content: |
      network:
        version: 2
        ethernets:
          fslan:
            match:
              macaddress: "52:54:00:00:09:01"
            addresses:
              - 192.168.100.1/24
  - path: /etc/vsftpd.conf.lab
    permissions: '0644'
    content: |
      listen=YES
      listen_ipv6=NO
      anonymous_enable=YES
      anon_root=/srv/ftp/shared
      local_enable=YES
      write_enable=YES
      local_umask=022
      dirmessage_enable=YES
      use_localtime=YES
      xferlog_enable=YES
      vsftpd_log_file=/var/log/vsftpd.log
      log_ftp_protocol=YES
      connect_from_port_20=YES
      chroot_local_user=YES
      allow_writeable_chroot=YES
      pasv_enable=YES
      pasv_min_port=30000
      pasv_max_port=30100
      pasv_address=192.168.100.1
      seccomp_sandbox=NO
      pam_service_name=vsftpd
  - path: /etc/motd.raw
    content: |
      \033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m
        \033[1;32mfilesharing-lab-ftp\033[0m — \033[1mFTP Server (vsftpd)\033[0m
      \033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m

        \033[1;33mRole:\033[0m  FTP Server
        \033[1;33mInternal IP:\033[0m  \033[1;36m192.168.100.1\033[0m

        \033[1;33mServices:\033[0m
          \033[0;32mvsftpd\033[0m   FTP on port 21, passive 30000-30100

        \033[1;33mShared directories:\033[0m
          \033[0;32m/srv/ftp/shared\033[0m      anonymous read-only
          \033[0;32m/home/alice\033[0m          alice's home (chrooted)
          \033[0;32m/home/bob\033[0m            bob's home (chrooted)

        \033[1;33mUsers:\033[0m
          \033[0;32malice\033[0m / labpass
          \033[0;32mbob\033[0m   / labpass

        \033[1;33mUseful Commands:\033[0m
          \033[0;32msudo tail -f /var/log/vsftpd.log\033[0m    follow FTP logs
          \033[0;32msystemctl status vsftpd\033[0m             vsftpd status
          \033[0;32mcat /etc/vsftpd.conf\033[0m                show config

        \033[1;33mCredentials:\033[0m  \033[1;36mlabuser\033[0m / \033[1;36mlabpass\033[0m
        \033[1;33mExit:\033[0m         type '\033[1;31mexit\033[0m'

      \033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m


runcmd:
  - netplan apply
  # Create users alice and bob
  - useradd -m -s /bin/bash alice
  - echo "alice:labpass" | chpasswd
  - useradd -m -s /bin/bash bob
  - echo "bob:labpass" | chpasswd
  # Create anonymous FTP directory
  - mkdir -p /srv/ftp/shared
  - echo "Welcome to the filesharing-lab FTP server." > /srv/ftp/shared/README.txt
  - echo "This is a sample file for anonymous download." > /srv/ftp/shared/sample.txt
  - chown -R ftp:ftp /srv/ftp/shared
  - chmod -R 555 /srv/ftp/shared
  # Create upload directories for users
  - mkdir -p /home/alice/upload
  - chown alice:alice /home/alice/upload
  - echo "Alice's test file" > /home/alice/upload/alice-file.txt
  - chown alice:alice /home/alice/upload/alice-file.txt
  - mkdir -p /home/bob/upload
  - chown bob:bob /home/bob/upload
  - echo "Bob's test file" > /home/bob/upload/bob-file.txt
  - chown bob:bob /home/bob/upload/bob-file.txt
  # Configure vsftpd
  - cp /etc/vsftpd.conf.lab /etc/vsftpd.conf
  - systemctl restart vsftpd
  - systemctl enable vsftpd
  # MOTD setup
  - chmod -x /etc/update-motd.d/*
  - sed -i 's/^#\?PrintMotd.*/PrintMotd yes/' /etc/ssh/sshd_config
  - sed -i 's/^session.*pam_motd.*/# &/' /etc/pam.d/sshd
  - printf '%b\n' "$(cat /etc/motd.raw)" > /etc/motd
  - rm -f /etc/motd.raw
  - systemctl restart sshd
  - echo "=== filesharing-lab-ftp VM is ready! ==="
USERDATA

sed -i "s|__QLAB_SSH_PUB_KEY__|${QLAB_SSH_PUB_KEY:-}|g" "$LAB_DIR/user-data-ftp"

cat > "$LAB_DIR/meta-data-ftp" <<METADATA
instance-id: ${FTP_VM}-001
local-hostname: ${FTP_VM}
METADATA

success "Created cloud-init for $FTP_VM"

# --- NFS Server VM cloud-init ---
info "Creating cloud-init for $NFS_VM..."
cat > "$LAB_DIR/user-data-nfs" <<'USERDATA'
#cloud-config
hostname: filesharing-lab-nfs
package_update: true
users:
  - name: labuser
    plain_text_passwd: labpass
    lock_passwd: false
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - "__QLAB_SSH_PUB_KEY__"
ssh_pwauth: true
packages:
  - nfs-ganesha
  - nfs-ganesha-vfs
  - rsyslog
  - nano
  - net-tools
  - iputils-ping
  - tcpdump
write_files:
  - path: /etc/profile.d/cloud-init-status.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      if command -v cloud-init >/dev/null 2>&1; then
        status=$(cloud-init status 2>/dev/null)
        if echo "$status" | grep -q "running"; then
          printf '\033[1;33m'
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          echo "  Cloud-init is still running..."
          echo "  Some packages and services may not be ready yet."
          echo "  Run 'cloud-init status --wait' to wait for completion."
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          printf '\033[0m\n'
        fi
      fi
  - path: /etc/netplan/60-internal.yaml
    content: |
      network:
        version: 2
        ethernets:
          fslan:
            match:
              macaddress: "52:54:00:00:09:02"
            addresses:
              - 192.168.100.2/24
  - path: /etc/ganesha/ganesha.conf.lab
    permissions: '0644'
    content: |
      NFS_CORE_PARAM {
          Protocols = 3, 4;
          Bind_addr = 0.0.0.0;
      }

      EXPORT {
          Export_Id = 1;
          Path = /srv/nfs/shared;
          Pseudo = /shared;
          Access_Type = RW;
          Squash = No_Root_Squash;
          SecType = sys;
          Transports = UDP, TCP;
          FSAL {
              Name = VFS;
          }
          CLIENT {
              Clients = 192.168.100.0/24;
              Access_Type = RW;
          }
      }

      EXPORT {
          Export_Id = 2;
          Path = /srv/nfs/readonly;
          Pseudo = /readonly;
          Access_Type = RO;
          Squash = Root_Squash;
          SecType = sys;
          Transports = UDP, TCP;
          FSAL {
              Name = VFS;
          }
          CLIENT {
              Clients = 192.168.100.0/24;
              Access_Type = RO;
          }
      }

      LOG {
          Default_Log_Level = EVENT;
          Components {
              ALL = EVENT;
          }
      }
  - path: /etc/motd.raw
    content: |
      \033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m
        \033[1;32mfilesharing-lab-nfs\033[0m — \033[1mNFS Server (Ganesha)\033[0m
      \033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m

        \033[1;33mRole:\033[0m  NFS Server (user-space, nfs-ganesha)
        \033[1;33mInternal IP:\033[0m  \033[1;36m192.168.100.2\033[0m

        \033[1;33mExports:\033[0m
          \033[0;32m/srv/nfs/shared\033[0m     rw, no_root_squash (pseudo: /shared)
          \033[0;32m/srv/nfs/readonly\033[0m   ro                 (pseudo: /readonly)

        \033[1;33mUsers (UID fixed for NFS mapping):\033[0m
          \033[0;32malice\033[0m (UID 2001) / labpass
          \033[0;32mbob\033[0m   (UID 2002) / labpass

        \033[1;33mUseful Commands:\033[0m
          \033[0;32mcat /etc/ganesha/ganesha.conf\033[0m        show config
          \033[0;32mshowmount -e localhost\033[0m               show exports
          \033[0;32msystemctl status nfs-ganesha\033[0m         NFS status
          \033[0;32msudo journalctl -u nfs-ganesha -f\033[0m    follow logs
          \033[0;32mls -la /srv/nfs/shared\033[0m               list shared files

        \033[1;33mCredentials:\033[0m  \033[1;36mlabuser\033[0m / \033[1;36mlabpass\033[0m
        \033[1;33mExit:\033[0m         type '\033[1;31mexit\033[0m'

      \033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m


runcmd:
  - netplan apply
  # Create users with fixed UIDs for NFS mapping
  - useradd -m -s /bin/bash -u 2001 alice
  - echo "alice:labpass" | chpasswd
  - useradd -m -s /bin/bash -u 2002 bob
  - echo "bob:labpass" | chpasswd
  # Create NFS shared directories
  - mkdir -p /srv/nfs/shared
  - mkdir -p /srv/nfs/readonly
  - echo "Welcome to the NFS shared directory." > /srv/nfs/shared/README.txt
  - echo "This is a read-only NFS export." > /srv/nfs/readonly/README.txt
  - echo "Sample data file for NFS testing." > /srv/nfs/readonly/sample-data.txt
  - chown -R alice:alice /srv/nfs/shared
  - chmod 775 /srv/nfs/shared
  - chmod 755 /srv/nfs/readonly
  # Configure NFS Ganesha
  - cp /etc/ganesha/ganesha.conf.lab /etc/ganesha/ganesha.conf
  - systemctl enable nfs-ganesha
  - systemctl restart nfs-ganesha
  # MOTD setup
  - chmod -x /etc/update-motd.d/*
  - sed -i 's/^#\?PrintMotd.*/PrintMotd yes/' /etc/ssh/sshd_config
  - sed -i 's/^session.*pam_motd.*/# &/' /etc/pam.d/sshd
  - printf '%b\n' "$(cat /etc/motd.raw)" > /etc/motd
  - rm -f /etc/motd.raw
  - systemctl restart sshd
  - echo "=== filesharing-lab-nfs VM is ready! ==="
USERDATA

sed -i "s|__QLAB_SSH_PUB_KEY__|${QLAB_SSH_PUB_KEY:-}|g" "$LAB_DIR/user-data-nfs"

cat > "$LAB_DIR/meta-data-nfs" <<METADATA
instance-id: ${NFS_VM}-001
local-hostname: ${NFS_VM}
METADATA

success "Created cloud-init for $NFS_VM"

# --- Samba Server VM cloud-init ---
info "Creating cloud-init for $SAMBA_VM..."
cat > "$LAB_DIR/user-data-samba" <<'USERDATA'
#cloud-config
hostname: filesharing-lab-samba
package_update: true
users:
  - name: labuser
    plain_text_passwd: labpass
    lock_passwd: false
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - "__QLAB_SSH_PUB_KEY__"
ssh_pwauth: true
packages:
  - samba
  - rsyslog
  - nano
  - net-tools
  - iputils-ping
  - tcpdump
write_files:
  - path: /etc/profile.d/cloud-init-status.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      if command -v cloud-init >/dev/null 2>&1; then
        status=$(cloud-init status 2>/dev/null)
        if echo "$status" | grep -q "running"; then
          printf '\033[1;33m'
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          echo "  Cloud-init is still running..."
          echo "  Some packages and services may not be ready yet."
          echo "  Run 'cloud-init status --wait' to wait for completion."
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          printf '\033[0m\n'
        fi
      fi
  - path: /etc/netplan/60-internal.yaml
    content: |
      network:
        version: 2
        ethernets:
          fslan:
            match:
              macaddress: "52:54:00:00:09:03"
            addresses:
              - 192.168.100.3/24
  - path: /etc/samba/smb.conf.lab
    permissions: '0644'
    content: |
      [global]
      workgroup = LABNET
      server string = filesharing-lab Samba Server
      security = user
      map to guest = Bad User
      logging = file
      log file = /var/log/samba/log.%m
      max log size = 1000
      server role = standalone server

      [shared]
      comment = Authenticated Read-Write Share
      path = /srv/samba/shared
      browseable = yes
      read only = no
      valid users = alice bob
      create mask = 0664
      directory mask = 0775

      [public]
      comment = Public Read-Only Share
      path = /srv/samba/public
      browseable = yes
      read only = yes
      guest ok = yes
  - path: /etc/motd.raw
    content: |
      \033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m
        \033[1;32mfilesharing-lab-samba\033[0m — \033[1mSamba Server\033[0m
      \033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m

        \033[1;33mRole:\033[0m  Samba Server
        \033[1;33mInternal IP:\033[0m  \033[1;36m192.168.100.3\033[0m
        \033[1;33mWorkgroup:\033[0m  LABNET

        \033[1;33mShares:\033[0m
          \033[0;32m[shared]\033[0m   /srv/samba/shared  (rw, authenticated)
          \033[0;32m[public]\033[0m   /srv/samba/public  (ro, guest ok)

        \033[1;33mUsers:\033[0m
          \033[0;32malice\033[0m / labpass
          \033[0;32mbob\033[0m   / labpass

        \033[1;33mUseful Commands:\033[0m
          \033[0;32mcat /etc/samba/smb.conf\033[0m              show config
          \033[0;32msudo smbstatus\033[0m                       active connections
          \033[0;32msudo pdbedit -L\033[0m                      list Samba users
          \033[0;32msudo tail -f /var/log/samba/log.smbd\033[0m  follow logs
          \033[0;32msystemctl status smbd\033[0m                Samba status

        \033[1;33mCredentials:\033[0m  \033[1;36mlabuser\033[0m / \033[1;36mlabpass\033[0m
        \033[1;33mExit:\033[0m         type '\033[1;31mexit\033[0m'

      \033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m


runcmd:
  - netplan apply
  # Create users alice and bob
  - useradd -m -s /bin/bash alice
  - echo "alice:labpass" | chpasswd
  - useradd -m -s /bin/bash bob
  - echo "bob:labpass" | chpasswd
  # Create Samba share directories
  - mkdir -p /srv/samba/shared
  - mkdir -p /srv/samba/public
  - echo "Welcome to the Samba shared directory." > /srv/samba/shared/README.txt
  - chown -R alice:alice /srv/samba/shared
  - chmod 775 /srv/samba/shared
  - chgrp -R bob /srv/samba/shared
  - echo "This is a public read-only Samba share." > /srv/samba/public/README.txt
  - echo "Sample data for Samba testing." > /srv/samba/public/sample-data.txt
  - chmod 755 /srv/samba/public
  # Add Samba passwords (non-interactive)
  - printf "labpass\nlabpass\n" | smbpasswd -a -s alice
  - printf "labpass\nlabpass\n" | smbpasswd -a -s bob
  # Configure Samba
  - cp /etc/samba/smb.conf.lab /etc/samba/smb.conf
  - mkdir -p /var/log/samba
  - systemctl restart smbd
  - systemctl enable smbd
  - systemctl restart nmbd
  - systemctl enable nmbd
  # MOTD setup
  - chmod -x /etc/update-motd.d/*
  - sed -i 's/^#\?PrintMotd.*/PrintMotd yes/' /etc/ssh/sshd_config
  - sed -i 's/^session.*pam_motd.*/# &/' /etc/pam.d/sshd
  - printf '%b\n' "$(cat /etc/motd.raw)" > /etc/motd
  - rm -f /etc/motd.raw
  - systemctl restart sshd
  - echo "=== filesharing-lab-samba VM is ready! ==="
USERDATA

sed -i "s|__QLAB_SSH_PUB_KEY__|${QLAB_SSH_PUB_KEY:-}|g" "$LAB_DIR/user-data-samba"

cat > "$LAB_DIR/meta-data-samba" <<METADATA
instance-id: ${SAMBA_VM}-001
local-hostname: ${SAMBA_VM}
METADATA

success "Created cloud-init for $SAMBA_VM"

# --- Client VM cloud-init ---
info "Creating cloud-init for $CLIENT_VM..."
cat > "$LAB_DIR/user-data-client" <<'USERDATA'
#cloud-config
hostname: filesharing-lab-client
package_update: true
users:
  - name: labuser
    plain_text_passwd: labpass
    lock_passwd: false
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - "__QLAB_SSH_PUB_KEY__"
ssh_pwauth: true
packages:
  - ftp
  - lftp
  - nfs-common
  - smbclient
  - cifs-utils
  - nano
  - net-tools
  - iputils-ping
  - tcpdump
  - curl
write_files:
  - path: /etc/profile.d/cloud-init-status.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      if command -v cloud-init >/dev/null 2>&1; then
        status=$(cloud-init status 2>/dev/null)
        if echo "$status" | grep -q "running"; then
          printf '\033[1;33m'
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          echo "  Cloud-init is still running..."
          echo "  Some packages and services may not be ready yet."
          echo "  Run 'cloud-init status --wait' to wait for completion."
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          printf '\033[0m\n'
        fi
      fi
  - path: /etc/netplan/60-internal.yaml
    content: |
      network:
        version: 2
        ethernets:
          fslan:
            match:
              macaddress: "52:54:00:00:09:04"
            addresses:
              - 192.168.100.10/24
  - path: /etc/motd.raw
    content: |
      \033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m
        \033[1;31mfilesharing-lab-client\033[0m — \033[1mFile Sharing Client\033[0m
      \033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m

        \033[1;33mRole:\033[0m  Client for FTP, NFS, Samba
        \033[1;33mInternal IP:\033[0m  \033[1;36m192.168.100.10\033[0m

        \033[1;33mServers:\033[0m
          \033[0;32mftp-server\033[0m   192.168.100.1  (vsftpd)
          \033[0;32mnfs-server\033[0m   192.168.100.2  (NFS)
          \033[0;32msmb-server\033[0m   192.168.100.3  (Samba)

        \033[1;33mMount Points:\033[0m
          \033[0;32m/mnt/nfs-shared\033[0m     NFS rw mount
          \033[0;32m/mnt/nfs-readonly\033[0m   NFS ro mount
          \033[0;32m/mnt/smb-shared\033[0m     Samba rw mount
          \033[0;32m/mnt/smb-public\033[0m     Samba public mount

        \033[1;33mQuick Test Commands:\033[0m
          \033[0;32mftp ftp-server\033[0m                         FTP connect
          \033[0;32mshowmount -e nfs-server\033[0m                list NFS exports
          \033[0;32msmbclient -L smb-server -U alice\033[0m       list Samba shares

        \033[1;33mUsers (UID matched for NFS):\033[0m
          \033[0;32malice\033[0m (UID 2001) / labpass
          \033[0;32mbob\033[0m   (UID 2002) / labpass

        \033[1;33mCredentials:\033[0m  \033[1;36mlabuser\033[0m / \033[1;36mlabpass\033[0m
        \033[1;33mExit:\033[0m         type '\033[1;31mexit\033[0m'

      \033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m


runcmd:
  - netplan apply
  # Add server hostnames to /etc/hosts
  - echo "192.168.100.1 ftp-server" >> /etc/hosts
  - echo "192.168.100.2 nfs-server" >> /etc/hosts
  - echo "192.168.100.3 smb-server" >> /etc/hosts
  # Create users with fixed UIDs (matching NFS server for UID mapping)
  - useradd -m -s /bin/bash -u 2001 alice
  - echo "alice:labpass" | chpasswd
  - useradd -m -s /bin/bash -u 2002 bob
  - echo "bob:labpass" | chpasswd
  # Create mount points
  - mkdir -p /mnt/nfs-shared
  - mkdir -p /mnt/nfs-readonly
  - mkdir -p /mnt/smb-shared
  - mkdir -p /mnt/smb-public
  # MOTD setup
  - chmod -x /etc/update-motd.d/*
  - sed -i 's/^#\?PrintMotd.*/PrintMotd yes/' /etc/ssh/sshd_config
  - sed -i 's/^session.*pam_motd.*/# &/' /etc/pam.d/sshd
  - printf '%b\n' "$(cat /etc/motd.raw)" > /etc/motd
  - rm -f /etc/motd.raw
  - systemctl restart sshd
  - echo "=== filesharing-lab-client VM is ready! ==="
USERDATA

sed -i "s|__QLAB_SSH_PUB_KEY__|${QLAB_SSH_PUB_KEY:-}|g" "$LAB_DIR/user-data-client"

cat > "$LAB_DIR/meta-data-client" <<METADATA
instance-id: ${CLIENT_VM}-001
local-hostname: ${CLIENT_VM}
METADATA

success "Created cloud-init for $CLIENT_VM"
echo ""

# =============================================
# Step 3: Generate cloud-init ISOs
# =============================================
info "Step 3: Cloud-init ISOs"
echo ""
check_dependency genisoimage || {
    warn "genisoimage not found. Install it with: sudo apt install genisoimage"
    exit 1
}

CIDATA_FTP="$LAB_DIR/cidata-ftp.iso"
genisoimage -output "$CIDATA_FTP" -volid cidata -joliet -rock \
    -graft-points "user-data=$LAB_DIR/user-data-ftp" "meta-data=$LAB_DIR/meta-data-ftp" 2>/dev/null
success "Created cloud-init ISO: $CIDATA_FTP"

CIDATA_NFS="$LAB_DIR/cidata-nfs.iso"
genisoimage -output "$CIDATA_NFS" -volid cidata -joliet -rock \
    -graft-points "user-data=$LAB_DIR/user-data-nfs" "meta-data=$LAB_DIR/meta-data-nfs" 2>/dev/null
success "Created cloud-init ISO: $CIDATA_NFS"

CIDATA_SAMBA="$LAB_DIR/cidata-samba.iso"
genisoimage -output "$CIDATA_SAMBA" -volid cidata -joliet -rock \
    -graft-points "user-data=$LAB_DIR/user-data-samba" "meta-data=$LAB_DIR/meta-data-samba" 2>/dev/null
success "Created cloud-init ISO: $CIDATA_SAMBA"

CIDATA_CLIENT="$LAB_DIR/cidata-client.iso"
genisoimage -output "$CIDATA_CLIENT" -volid cidata -joliet -rock \
    -graft-points "user-data=$LAB_DIR/user-data-client" "meta-data=$LAB_DIR/meta-data-client" 2>/dev/null
success "Created cloud-init ISO: $CIDATA_CLIENT"
echo ""

# =============================================
# Step 4: Create overlay disks
# =============================================
info "Step 4: Overlay disks"
echo ""
echo "  Each VM gets its own overlay disk (copy-on-write) so the"
echo "  base cloud image is never modified."
echo ""

OVERLAY_FTP="$LAB_DIR/${FTP_VM}-disk.qcow2"
if [[ -f "$OVERLAY_FTP" ]]; then rm -f "$OVERLAY_FTP"; fi
create_overlay "$CLOUD_IMAGE_FILE" "$OVERLAY_FTP" "${QLAB_DISK_SIZE:-}"

OVERLAY_NFS="$LAB_DIR/${NFS_VM}-disk.qcow2"
if [[ -f "$OVERLAY_NFS" ]]; then rm -f "$OVERLAY_NFS"; fi
create_overlay "$CLOUD_IMAGE_FILE" "$OVERLAY_NFS" "${QLAB_DISK_SIZE:-}"

OVERLAY_SAMBA="$LAB_DIR/${SAMBA_VM}-disk.qcow2"
if [[ -f "$OVERLAY_SAMBA" ]]; then rm -f "$OVERLAY_SAMBA"; fi
create_overlay "$CLOUD_IMAGE_FILE" "$OVERLAY_SAMBA" "${QLAB_DISK_SIZE:-}"

OVERLAY_CLIENT="$LAB_DIR/${CLIENT_VM}-disk.qcow2"
if [[ -f "$OVERLAY_CLIENT" ]]; then rm -f "$OVERLAY_CLIENT"; fi
create_overlay "$CLOUD_IMAGE_FILE" "$OVERLAY_CLIENT" "${QLAB_DISK_SIZE:-}"
echo ""

# =============================================
# Step 5: Start all VMs
# =============================================
info "Step 5: Starting VMs (internal LAN: 192.168.100.0/24)"
echo ""

# Multi-VM: resource check, cleanup trap, rollback on failure
MEMORY_TOTAL=$(( MEMORY * 4 ))
check_host_resources "$MEMORY_TOTAL" 4
declare -a STARTED_VMS=()
register_vm_cleanup STARTED_VMS

info "Starting $FTP_VM..."
start_vm_or_fail STARTED_VMS "$OVERLAY_FTP" "$CIDATA_FTP" "$MEMORY" "$FTP_VM" auto \
    "-netdev" "socket,id=vlan1,mcast=${INTERNAL_MCAST}" \
    "-device" "virtio-net-pci,netdev=vlan1,mac=${FTP_LAN_MAC}" || exit 1

echo ""

info "Starting $NFS_VM..."
start_vm_or_fail STARTED_VMS "$OVERLAY_NFS" "$CIDATA_NFS" "$MEMORY" "$NFS_VM" auto \
    "-netdev" "socket,id=vlan1,mcast=${INTERNAL_MCAST}" \
    "-device" "virtio-net-pci,netdev=vlan1,mac=${NFS_LAN_MAC}" || exit 1

echo ""

info "Starting $SAMBA_VM..."
start_vm_or_fail STARTED_VMS "$OVERLAY_SAMBA" "$CIDATA_SAMBA" "$MEMORY" "$SAMBA_VM" auto \
    "-netdev" "socket,id=vlan1,mcast=${INTERNAL_MCAST}" \
    "-device" "virtio-net-pci,netdev=vlan1,mac=${SAMBA_LAN_MAC}" || exit 1

echo ""

info "Starting $CLIENT_VM..."
start_vm_or_fail STARTED_VMS "$OVERLAY_CLIENT" "$CIDATA_CLIENT" "$MEMORY" "$CLIENT_VM" auto \
    "-netdev" "socket,id=vlan1,mcast=${INTERNAL_MCAST}" \
    "-device" "virtio-net-pci,netdev=vlan1,mac=${CLIENT_LAN_MAC}" || exit 1

# Successful start — disable cleanup trap
trap - EXIT

echo ""
echo "============================================="
echo "  filesharing-lab: All VMs are booting"
echo "============================================="
echo ""
echo "  FTP Server VM:"
echo "    SSH:          qlab shell $FTP_VM"
echo "    Log:          qlab log $FTP_VM"
echo "    Internal IP:  $FTP_INTERNAL_IP"
echo "    Services:     vsftpd (FTP:21, passive 30000-30100)"
echo ""
echo "  NFS Server VM:"
echo "    SSH:          qlab shell $NFS_VM"
echo "    Log:          qlab log $NFS_VM"
echo "    Internal IP:  $NFS_INTERNAL_IP"
echo "    Services:     NFS server (port 2049)"
echo ""
echo "  Samba Server VM:"
echo "    SSH:          qlab shell $SAMBA_VM"
echo "    Log:          qlab log $SAMBA_VM"
echo "    Internal IP:  $SAMBA_INTERNAL_IP"
echo "    Services:     Samba (SMB:445)"
echo ""
echo "  Client VM:"
echo "    SSH:          qlab shell $CLIENT_VM"
echo "    Log:          qlab log $CLIENT_VM"
echo "    Internal IP:  $CLIENT_INTERNAL_IP"
echo "    Tools:        ftp, lftp, nfs-common, smbclient, cifs-utils"
echo ""
echo "  Internal LAN:  192.168.100.0/24"
echo "  Credentials:   labuser / labpass"
echo "  Lab users:     alice / labpass, bob / labpass"
echo ""
echo "  Quick test (after boot ~90s):"
echo "    qlab shell $CLIENT_VM"
echo "    ftp ftp-server                          # FTP test"
echo "    showmount -e nfs-server                 # NFS exports"
echo "    smbclient -L smb-server -U alice        # Samba shares"
echo ""
echo "  Stop all VMs:"
echo "    qlab stop $PLUGIN_NAME"
echo ""
echo "  Tip: override resources with environment variables:"
echo "    QLAB_MEMORY=1024 QLAB_DISK_SIZE=30G qlab run ${PLUGIN_NAME}"
echo "============================================="
