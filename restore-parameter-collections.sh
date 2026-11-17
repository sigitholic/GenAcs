#!/usr/bin/env bash
# Restore GenieACS Mongo collections from GenAcs repo folder parameter/ (BSON dumps).
# Jalankan di VM cetakan/ACS sebagai root, setelah mongod aktif.
#
# Sumber: sigitholic/GenAcs — parameter/{config,virtualParameters,presets,provisions}.bson
#
# Usage:
#   ./restore-parameter-collections.sh /path/to/GenAcs/parameter
#   GENIEACS_DB=genieacs ./restore-parameter-collections.sh ./parameter
set -euo pipefail

PARAM_DIR="${1:-}"
DB="${GENIEACS_DB:-genieacs}"

if [[ -z "$PARAM_DIR" || ! -d "$PARAM_DIR" ]]; then
  echo "Usage: $0 /path/to/GenAcs/parameter" >&2
  exit 1
fi

if ! command -v mongorestore >/dev/null 2>&1; then
  echo "mongorestore tidak ditemukan — pasang mongodb-database-tools atau paket mongo" >&2
  exit 1
fi

if ! mongosh --quiet --eval 'db.runCommand({ping:1})' >/dev/null 2>&1 && \
   ! mongo --quiet --eval 'db.runCommand({ping:1})' >/dev/null 2>&1; then
  echo "MongoDB belum menjawab — pastikan mongod aktif" >&2
  exit 1
fi

restore_one() {
  local coll="$1"
  local file="$PARAM_DIR/${coll}.bson"
  if [[ ! -f "$file" ]]; then
    echo "  skip $coll (tidak ada $file)"
    return 0
  fi
  echo "  restore $coll ..."
  mongorestore --db "$DB" --collection "$coll" --drop "$file"
}

echo "==> mongorestore db=$DB from $PARAM_DIR"
if [[ "${SKIP_CONFIG:-0}" != "1" ]]; then
  restore_one config
else
  echo "  skip config (SKIP_CONFIG=1)"
fi
for coll in virtualParameters presets provisions; do
  restore_one "$coll"
done

if command -v systemctl >/dev/null 2>&1; then
  for svc in genieacs-nbi genieacs-ui genieacs-cwmp genieacs-fs; do
    if systemctl list-unit-files "${svc}.service" >/dev/null 2>&1; then
      systemctl try-restart "$svc" 2>/dev/null || true
    fi
  done
fi

echo "==> verifikasi katalog VP (mongo)"
vp_count="0"
if command -v mongosh >/dev/null 2>&1; then
  vp_count="$(mongosh --quiet "$DB" --eval 'db.virtualParameters.countDocuments()' 2>/dev/null || echo 0)"
elif command -v mongo >/dev/null 2>&1; then
  vp_count="$(mongo --quiet "$DB" --eval 'db.virtualParameters.count()' 2>/dev/null || echo 0)"
else
  echo "Peringatan: mongo/mongosh tidak ada — lewati hitung VP" >&2
fi
vp_count="${vp_count//[$'\r\n ']/}"
echo "virtualParameters count=${vp_count}"
if [[ "${VERIFY_VP:-0}" == "1" ]] && [[ "${vp_count:-0}" -lt 1 ]]; then
  echo "GAGAL TPL-VP-01: virtualParameters masih kosong setelah mongorestore." >&2
  echo "Cek folder $PARAM_DIR dan journal mongod." >&2
  exit 1
fi
echo "==> selesai. Uji NBI: GET /virtualParameters/?limit=5&projection=_id"