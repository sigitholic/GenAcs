#!/bin/bash
# Aturan tamu untuk cetakan Proxmox yang di-clone panel.
# Berlaku untuk setiap kartu jaringan bridge yang ditemukan, tanpa alamat lab.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Jalankan sebagai root"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y qemu-guest-agent cloud-init curl ca-certificates iproute2

if systemctl cat qemu-guest-agent >/dev/null 2>&1; then
  systemctl enable qemu-guest-agent
elif systemctl cat qemu-ga >/dev/null 2>&1; then
  systemctl enable qemu-ga
else
  echo "Layanan qemu-guest-agent tidak ditemukan setelah dipasang"
  exit 1
fi

hostnamectl set-hostname genieacs-template
printf '%s\n' 'genieacs-template' > /etc/hostname
if grep -q '^127\.0\.1\.1[[:space:]]' /etc/hosts; then
  sed -i 's/^127\.0\.1\.1[[:space:]].*/127.0.1.1 genieacs-template/' /etc/hosts
else
  printf '%s\n' '127.0.1.1 genieacs-template' >> /etc/hosts
fi

primary="$(ip -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
if [ -z "$primary" ]; then
  primary="$(ip -o link show | awk -F': ' '$2 ~ /^(ens|enp|eth)[0-9]+/ {print $2; exit}')"
fi
primary="${primary%%@*}"
primary="${primary%% *}"
if [ -z "$primary" ]; then
  echo "Kartu jaringan bridge tidak ditemukan"
  exit 1
fi

mkdir -p /etc/netplan /etc/cloud/cloud.cfg.d
printf '%s\n' 'network: {config: disabled}' > /etc/cloud/cloud.cfg.d/99-starnet-dhcp.cfg
printf '%s\n' 'preserve_hostname: true' > /etc/cloud/cloud.cfg.d/99-starnet-hostname.cfg

shopt -s nullglob
for f in /etc/netplan/*.yaml /etc/netplan/*.yml; do
  case "$f" in
    */99-starnet-dhcp.yaml) continue ;;
  esac
  mv "$f" "$f.bak-starnet"
done
shopt -u nullglob

cat > /etc/netplan/99-starnet-dhcp.yaml <<EOF
network:
  version: 2
  ethernets:
    ${primary}:
      dhcp4: true
      dhcp-identifier: mac
EOF
chmod 600 /etc/netplan/99-starnet-dhcp.yaml
netplan generate

rm -f /var/lib/dhcp/dhclient.leases /var/lib/dhcp/dhclient6.leases
rm -f /var/lib/dhcpcd/*.lease /run/systemd/netif/leases/* /var/lib/systemd/network/*.lease 2>/dev/null || true

cloud-init clean --logs --machine-id

echo "Aturan cetakan tertulis untuk ${primary}: DHCP berdasarkan MAC, agen tamu aktif, nama genieacs-template."
echo "Matikan VM dari Proxmox, lalu jadikan template. Jangan menyalakan lagi sebelum dikonversi, supaya sewa DHCP tidak kembali ke disk."
