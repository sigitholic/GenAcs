#!/usr/bin/env bash
# Instal GenieACS + restore parameter/ (VP, preset, provision) untuk cetakan Proxmox Cloud.
# Jalankan sebagai root di folder clone GenAcs (satu perintah menggantikan ./GACS-Jammy.sh saja).
#
#   git clone https://github.com/sigitholic/GenAcs.git /opt/GenAcs
#   cd /opt/GenAcs
#   dos2unix install-cetakan.sh GACS-Jammy.sh panel-guest.sh restore-parameter-collections.sh
#   chmod +x install-cetakan.sh GACS-Jammy.sh panel-guest.sh restore-parameter-collections.sh
#   ./install-cetakan.sh
#
# Sumber BSON: ./parameter/*.bson (ikut git) — bukan VM lain.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Jalankan sebagai root" >&2
  exit 1
fi

for f in GACS-Jammy.sh panel-guest.sh; do
  if [[ ! -f "$f" ]]; then
    echo "Berkas tidak ada: $ROOT/$f" >&2
    exit 1
  fi
done

if [[ ! -f "$ROOT/parameter/virtualParameters.bson" ]]; then
  echo "parameter/virtualParameters.bson tidak ada — pastikan git clone lengkap." >&2
  exit 1
fi

RESTORE_SH="$ROOT/restore-parameter-collections.sh"
if [[ ! -x "$RESTORE_SH" ]]; then
  echo "restore-parameter-collections.sh tidak ada atau tidak executable." >&2
  echo "Salin dari starnet-nms scripts/genieacs-cetakan/for-genacs-repo/ atau commit patch GenAcs." >&2
  exit 1
fi

if command -v dos2unix >/dev/null 2>&1; then
  dos2unix GACS-Jammy.sh panel-guest.sh restore-parameter-collections.sh install-cetakan.sh 2>/dev/null || true
fi
chmod +x GACS-Jammy.sh panel-guest.sh restore-parameter-collections.sh

echo "==> Fase 1: GACS-Jammy (Mongo, GenieACS, panel-guest) ..."
bash "$ROOT/GACS-Jammy.sh"

echo "==> Fase 2: mongorestore parameter/ (TPL-VP-01) ..."
SKIP_CONFIG=1 VERIFY_VP=1 bash "$RESTORE_SH" "$ROOT/parameter"

echo "==> Cetakan: GenieACS terpasang dan VP dimuat ke Mongo."
echo "    Proxmox: qm set <VMID> --agent 1 && reboot sebelum qm guest cmd."
echo "    Verifikasi: mongo genieacs --quiet --eval 'db.virtualParameters.count()'"
echo "    Matikan VM → convert template → template_id di panel."