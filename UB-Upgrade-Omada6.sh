#!/bin/bash
# ============================================================
# TP-Link Omada Software Controller - UPGRADE (FR)
# Cible : Omada v5.15.24.19 (Linux x64)
# OS    : Ubuntu 20.04 / 22.04 / 24.04
# ============================================================

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

OMADA_DEB_URL="https://static.tp-link.com/upload/software/2025/202508/20250802/omada_v5.15.24.19_linux_x64_20250724152622.deb"
OMADA_DEB_NAME="omada_v5.15.24.19_linux_x64_20250724152622.deb"

log(){ echo -e "\n[+] $*"; }
warn(){ echo -e "\n[!] $*" >&2; }

echo -e "\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "TP-Link Omada Software Controller - UPGRADE"
echo "Cible : v5.15.24.19"
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n"

# --- Root check
log "Vérification exécution en root"
if [ "$(id -u)" -ne 0 ]; then
  warn "Exécute avec sudo : sudo ./upgrade-omada-5.15.24.19.sh"
  exit 1
fi

# --- OS check
log "Vérification OS Ubuntu"
. /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
  warn "OS non supporté : ${ID:-unknown} (Ubuntu requis)"
  exit 1
fi

case "${VERSION_ID:-}" in
  20.04) UB_CODENAME="focal" ;;
  22.04) UB_CODENAME="jammy" ;;
  24.04) UB_CODENAME="noble" ;;
  *) warn "Version Ubuntu non supportée : ${VERSION_ID:-unknown}"; exit 1 ;;
esac
echo "[~] Ubuntu ${VERSION_ID} (${UB_CODENAME})"

# --- Controller already installed?
log "Vérification présence contrôleur (tpeap)"
if ! command -v tpeap >/dev/null 2>&1 && [ ! -f /etc/init.d/tpeap ]; then
  warn "Le contrôleur Omada ne semble pas installé (tpeap introuvable)."
  warn "Ce script est prévu pour un UPGRADE (pas une nouvelle install)."
  exit 1
fi

# --- CPU AVX logic (prudente)
log "Vérification CPU (AVX) - utile si MongoDB >= 5"
HAS_AVX=0
if lscpu | grep -iq avx; then HAS_AVX=1; fi

if command -v mongod >/dev/null 2>&1; then
  MONGO_MAJOR="$(mongod --version 2>/dev/null | awk '/db version/ {print $3}' | cut -d. -f1 || true)"
  if [[ -n "${MONGO_MAJOR}" && "${MONGO_MAJOR}" -ge 5 && "${HAS_AVX}" -ne 1 ]]; then
    warn "MongoDB ${MONGO_MAJOR}.x détecté mais CPU sans AVX → Mongo ne peut pas tourner correctement."
    exit 1
  fi
else
  if [[ "${HAS_AVX}" -ne 1 ]]; then
    warn "CPU sans AVX et MongoDB absent : installation MongoDB 5+ impossible sur ce CPU."
    warn "Upgrade annulé."
    exit 1
  fi
fi

# --- Prérequis
log "Installation prérequis (wget/curl/gnupg/ca-certificates/lsb-release)"
apt-get update -y
apt-get install -y wget curl gnupg ca-certificates lsb-release

# --- Backup data (si présent)
DATA_DIR="/opt/tplink/EAPController/data"
BACKUP_DIR="/opt/tplink/EAPController/data-backup"
TS="$(date +%Y%m%d-%H%M%S)"

log "Sauvegarde locale des données (si présentes)"
if [ -d "${DATA_DIR}" ]; then
  mkdir -p "${BACKUP_DIR}"
  tar -C "/opt/tplink/EAPController" -czf "${BACKUP_DIR}/data_${TS}.tar.gz" "data" || true
  echo "[~] Backup : ${BACKUP_DIR}/data_${TS}.tar.gz"
else
  echo "[~] Pas de dossier data trouvé (OK si installation incomplète)."
fi

# --- Stop Omada
log "Arrêt du contrôleur Omada"
systemctl stop tpeap 2>/dev/null || true
/etc/init.d/tpeap stop 2>/dev/null || true

# --- Java + jsvc (recommandé : JDK 17)
log "Installation / validation Java 17 (JDK) + JSVC"
apt-get install -y openjdk-17-jdk jsvc

# Force Java 17 si possible
if update-alternatives --list java >/dev/null 2>&1; then
  if [ -x /usr/lib/jvm/java-17-openjdk-amd64/bin/java ]; then
    update-alternatives --set java /usr/lib/jvm/java-17-openjdk-amd64/bin/java || true
  fi
fi
java -version || true

# --- Mongo : on ne force pas un changement de version en upgrade
log "Vérification MongoDB (démarrage si présent)"
if systemctl list-unit-files | grep -q "^mongod\.service"; then
  systemctl start mongod || true
  systemctl enable mongod >/dev/null 2>&1 || true
fi

# --- Download + install Omada deb
log "Téléchargement du .deb Omada v5.15.24.19"
cd /tmp
wget -O "${OMADA_DEB_NAME}" "${OMADA_DEB_URL}"

log "Installation / Upgrade du contrôleur Omada"
dpkg -i "/tmp/${OMADA_DEB_NAME}" || apt-get -f install -y

# --- Ensure user + permissions
log "Correction des droits (omada:omada)"
if ! id omada >/dev/null 2>&1; then
  useradd -r -s /usr/sbin/nologin omada
fi
if [ -d /opt/tplink/EAPController ]; then
  chown -R omada:omada /opt/tplink/EAPController
fi

# --- Start Omada
log "Démarrage du contrôleur Omada"
systemctl daemon-reload || true
systemctl enable tpeap >/dev/null 2>&1 || true
systemctl start tpeap 2>/dev/null || true
/etc/init.d/tpeap start 2>/dev/null || true

log "Attente démarrage (20s)"
sleep 20

log "Statut tpeap"
systemctl status tpeap --no-pager || true

log "Vérification ports (8043/8088/29810-29814)"
ss -lntp | grep -E ":8043|:8088|:2981[0-4]" || warn "Ports Omada non détectés (attendre 30-60s ou consulter les logs)"

HOST_IP="$(hostname -I | awk '{print $1}')"
echo -e "\n============================================================"
echo "[✓] Upgrade terminé"
echo "[~] Accès Omada : https://${HOST_IP}:8043"
echo "Logs : /opt/tplink/EAPController/logs/server.log"
echo "Backup data (si existant) : ${BACKUP_DIR}/data_${TS}.tar.gz"
echo "============================================================"
