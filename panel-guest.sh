#!/bin/bash
# Aturan tamu untuk cetakan Proxmox yang di-clone panel (fork cetakan Cloud StarnetNMS).
# Berlaku untuk setiap kartu jaringan bridge yang ditemukan, tanpa alamat lab.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Jalankan sebagai root"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y qemu-guest-agent cloud-init curl ca-certificates iproute2

GA_UNIT=""
if systemctl cat qemu-guest-agent >/dev/null 2>&1; then
  GA_UNIT="qemu-guest-agent"
elif systemctl cat qemu-ga >/dev/null 2>&1; then
  GA_UNIT="qemu-ga"
else
  echo "Layanan qemu-guest-agent tidak ditemukan setelah dipasang"
  exit 1
fi

# Unit static di Ubuntu 22.04 — enable bisa gagal; yang wajib start/restart.
systemctl enable "$GA_UNIT" 2>/dev/null || true
systemctl restart "$GA_UNIT" 2>/dev/null || systemctl start "$GA_UNIT"

VIRTIO="/dev/virtio-ports/org.qemu.guest_agent.0"
if [ ! -e "$VIRTIO" ]; then
  echo "PERINGATAN: $VIRTIO belum ada — qm guest cmd/exec belum akan jalan."
  echo "  Di node Proxmox: qm set <VMID> --agent 1 && qm reboot <VMID>"
  echo "  Setelah reboot tamu, ulangi: systemctl restart $GA_UNIT"
elif ! systemctl is-active --quiet "$GA_UNIT"; then
  echo "PERINGATAN: $GA_UNIT belum active — cek: journalctl -u $GA_UNIT -n 20"
else
  echo "qemu-guest-agent: active (virtio channel OK)."
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

echo "Aturan cetakan tertulis untuk ${primary}: DHCP berdasarkan MAC, nama genieacs-template."
echo "Sebelum convert template di Proxmox:"
echo "  qm set <VMID> --agent 1"
echo "  qm set <VMID> --ipconfig0 ip=dhcp   # disarankan"
echo "  qm reboot <VMID>  →  qm guest cmd <VMID> ping"
echo "Matikan VM bersih, lalu jadikan template (hindari boot lagi sebelum convert)."