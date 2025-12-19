#!/bin/bash
# ============================================================
# TP-Link Omada Software Controller - UPGRADE (FR)
# Cible : Omada Controller v6.0.0.25 (Linux x64)
# OS    : Ubuntu 20.04 / 22.04 / 24.04
# ============================================================

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Omada v6.0.0.25 (Linux x64) - lien direct officiel (static.tp-link)
OMADA_DEB_URL="https://static.tp-link.com/upload/software/2025/202512/20251203/omada_v6.0.0.25_linux_x64_20251120205747.deb"
OMADA_DEB_NAME="omada_v6.0.0.25_linux_x64.deb"

log(){ echo -e "\n[+] $*"; }
warn(){ echo -e "\n[!] $*" >&2; }

echo -e "\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "TP-Link Omada Software Controller - UPGRADE"
echo "Cible : v6.0.0.25"
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n"

# --- Root
log "Vérification exécution en root"
if [ "$(id -u)" -ne 0 ]; then
  warn "Exécute avec sudo : sudo ./UB-Upgrade-Omada6.sh"
  exit 1
fi

# --- OS
log "Vérification OS Ubuntu"
. /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
  warn "OS non supporté : ${ID:-unknown} (Ubuntu requis)"
  exit 1
fi

case "${VERSION_ID:-}" in
  20.04) OsVer="focal" ;;
  22.04) OsVer="jammy" ;;
  24.04) OsVer="noble" ;;
  *) warn "Version Ubuntu non supportée : ${VERSION_ID:-unknown}"; exit 1 ;;
esac
echo "[~] Ubuntu ${VERSION_ID} (${OsVer})"

# --- Contrôleur déjà installé ?
log "Vérification présence contrôleur (tpeap)"
if ! command -v tpeap >/dev/null 2>&1 && [ ! -f /etc/init.d/tpeap ]; then
  warn "tpeap introuvable → ce script est prévu pour un UPGRADE (contrôleur déjà installé)."
  exit 1
fi

# --- CPU AVX (important pour MongoDB récent)
log "Vérification CPU (AVX)"
if ! lscpu | grep -iq avx; then
  warn "CPU sans AVX : MongoDB récent (et donc Omada) peut ne pas fonctionner."
  exit 1
fi

echo "============================================================"
echo "IMPORTANT AVANT UPGRADE :"
echo " - Fais un backup dans l'UI : Settings → Maintenance → Backup"
echo " - Idéalement snapshot VM"
echo "============================================================"
sleep 2

# --- Pré-requis
log "Installation prérequis (wget/curl/gnupg/ca-certificates/lsb-release)"
apt-get update -y
apt-get install -y wget curl gnupg ca-certificates lsb-release

# --- Backup local data
DATA_DIR="/opt/tplink/EAPController/data"
BACKUP_DIR="/opt/tplink/EAPController/data-backup"
TS="$(date +%Y%m%d-%H%M%S)"

log "Sauvegarde locale du dossier data (si présent)"
if [ -d "${DATA_DIR}" ]; then
  mkdir -p "${BACKUP_DIR}"
  tar -C "/opt/tplink/EAPController" -czf "${BACKUP_DIR}/data_${TS}.tar.gz" "data" || true
  echo "[~] Backup local : ${BACKUP_DIR}/data_${TS}.tar.gz"
else
  echo "[~] Pas de dossier data trouvé."
fi

# --- Stop Omada
log "Arrêt du contrôleur Omada"
systemctl stop tpeap 2>/dev/null || true
/etc/init.d/tpeap stop 2>/dev/null || true

# --- Java + JSVC (safe : JDK 17 + jsvc)
log "Installation / validation Java 17 (JDK) + JSVC"
apt-get install -y openjdk-17-jdk jsvc
if update-alternatives --list java >/dev/null 2>&1; then
  [ -x /usr/lib/jvm/java-17-openjdk-amd64/bin/java ] && update-alternatives --set java /usr/lib/jvm/java-17-openjdk-amd64/bin/java || true
fi
java -version || true

# --- MongoDB 8.0 (repo officiel Mongo) - recommandé pour Omada récent
log "Installation / mise à jour MongoDB 8.0"
curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-8.0.gpg
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu ${OsVer}/mongodb-org/8.0 multiverse" \
  > /etc/apt/sources.list.d/mongodb-org-8.0.list
apt-get update -y
apt-get install -y mongodb-org
systemctl enable --now mongod || true

# --- Download + upgrade Omada v6
log "Téléchargement Omada v6.0.0.25"
cd /tmp
wget -O "${OMADA_DEB_NAME}" "${OMADA_DEB_URL}"

log "Installation / Upgrade Omada v6"
dpkg -i "/tmp/${OMADA_DEB_NAME}" || apt-get -f install -y

# --- Fix droits (selon user utilisé par le service)
log "Correction des droits sur /opt/tplink/EAPController"
if id omada >/dev/null 2>&1; then
  chown -R omada:omada /opt/tplink/EAPController
  echo "[~] chown appliqué : omada:omada"
elif id tp-link >/dev/null 2>&1; then
  chown -R tp-link:tp-link /opt/tplink/EAPController
  echo "[~] chown appliqué : tp-link:tp-link"
else
  warn "Aucun user omada/tp-link trouvé → chown ignoré."
fi

# --- Start Omada
log "Démarrage du contrôleur Omada"
systemctl daemon-reload || true
systemctl enable tpeap >/dev/null 2>&1 || true
systemctl start tpeap 2>/dev/null || true
/etc/init.d/tpeap start 2>/dev/null || true

log "Attente démarrage (25s)"
sleep 25

log "Statut tpeap"
systemctl status tpeap --no-pager || true

log "Vérification ports (8043/8088/29810-29814)"
ss -lntp | grep -E ":8043|:8088|:2981[0-4]" || warn "Ports non détectés (attendre 30-60s ou consulter les logs)"

HOST_IP="$(hostname -I | awk '{print $1}')"
echo -e "\n============================================================"
echo "[✓] Upgrade terminé"
echo "[~] Accès Omada : https://${HOST_IP}:8043"
echo "Logs : /opt/tplink/EAPController/logs/server.log"
echo "Backup data : ${BACKUP_DIR}/data_${TS}.tar.gz"
echo "============================================================"
