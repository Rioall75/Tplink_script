#!/bin/bash
# ============================================================
# Install Omada Software Controller 5.15.24.19 on Ubuntu 22.04 (jammy)
# - Installe Java 17 (JDK) + jsvc
# - Ajoute repo MongoDB 8.0 (jammy) + installe mongodb-org
# - Installe Omada via .deb (URL figée)
# - Fix permissions /opt/tplink/EAPController
# - Démarre tpeap
# ============================================================

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

OMADA_DEB_URL="https://static.tp-link.com/upload/software/2025/202508/20250802/omada_v5.15.24.19_linux_x64_20250724152622.deb"
OMADA_DEB_NAME="omada_v5.15.24.19_linux_x64_20250724152622.deb"

log() { echo -e "\n[+] $*"; }
warn() { echo -e "\n[!] $*" >&2; }

# ---- Root check
log "Vérification exécution en root"
if [ "$(id -u)" -ne 0 ]; then
  warn "Lance le script avec sudo : sudo ./install-omada-5.15.24.19-jammy.sh"
  exit 1
fi

# ---- OS check (jammy)
log "Vérification OS (Ubuntu 22.04 jammy)"
. /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
  warn "OS non supporté : ${ID:-unknown} (Ubuntu requis)"
  exit 1
fi
if [[ "${VERSION_ID:-}" != "22.04" && "${UBUNTU_CODENAME:-}" != "jammy" ]]; then
  warn "Ce script est prévu pour Ubuntu 22.04 (jammy). Détecté : ${VERSION_ID:-unknown} / ${UBUNTU_CODENAME:-unknown}"
  exit 1
fi

# ---- CPU AVX check (MongoDB >= 5)
log "Vérification CPU (AVX requis pour MongoDB 5+)"
if ! lscpu | grep -iq avx; then
  warn "CPU sans AVX détecté. MongoDB récent ne tournera pas → Omada aussi."
  exit 1
fi

# ---- Base packages
log "Installation des prérequis (wget/curl/gnupg/ca-certificates/lsb-release)"
apt-get update -y
apt-get install -y wget curl gnupg ca-certificates lsb-release

# ---- Java + jsvc
log "Installation Java 17 (JDK) + JSVC"
apt-get install -y openjdk-17-jdk jsvc

# Force java 17 si plusieurs java installés
if update-alternatives --list java >/dev/null 2>&1; then
  if [ -x /usr/lib/jvm/java-17-openjdk-amd64/bin/java ]; then
    update-alternatives --set java /usr/lib/jvm/java-17-openjdk-amd64/bin/java || true
  fi
fi

log "Vérification Java"
java -version || true

# ---- MongoDB 8.0 repo + install
log "Ajout du dépôt MongoDB 8.0 (jammy) + installation mongodb-org"
curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc \
  | gpg --dearmor -o /usr/share/keyrings/mongodb-server-8.0.gpg

echo "deb [ arch=amd64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/8.0 multiverse" \
  > /etc/apt/sources.list.d/mongodb-org-8.0.list

apt-get update -y
apt-get install -y mongodb-org
systemctl enable --now mongod

log "Vérification MongoDB"
systemctl is-active mongod >/dev/null && echo "mongod: active" || (warn "mongod n'est pas actif" && exit 1)
ss -lntp | grep -q ":27017" && echo "Mongo écoute sur 27017" || warn "Mongo ne semble pas écouter sur 27017 (à vérifier)"

# ---- Download + install Omada
log "Téléchargement Omada 5.15.24.19"
cd /tmp
wget -O "${OMADA_DEB_NAME}" "${OMADA_DEB_URL}"

log "Installation Omada (.deb)"
dpkg -i "/tmp/${OMADA_DEB_NAME}" || apt-get -f install -y

# ---- Ensure omada user exists (normalement créé par le .deb)
if ! id omada >/dev/null 2>&1; then
  log "Utilisateur 'omada' absent → création (system user)"
  useradd -r -s /usr/sbin/nologin omada
fi

# ---- Permissions
log "Fix permissions /opt/tplink/EAPController"
if [ -d /opt/tplink/EAPController ]; then
  chown -R omada:omada /opt/tplink/EAPController
else
  warn "/opt/tplink/EAPController introuvable après install (à vérifier)"
fi

# ---- Start Omada
log "Démarrage Omada (tpeap)"
systemctl enable tpeap >/dev/null 2>&1 || true
systemctl restart tpeap || true

log "Attente démarrage (20s)"
sleep 20

log "Statut tpeap"
systemctl status tpeap --no-pager || true

# ---- Ports check (indicatif)
log "Vérification ports Omada (8043/8088/29810-29814)"
ss -lntp | grep -E ":8043|:8088|:2981[0-4]" || warn "Ports Omada non détectés (si 1er démarrage, attendre encore 30-60s)"

# ---- Final info
HOST_IP="$(hostname -I | awk '{print $1}')"
echo -e "\n============================================================"
echo "[✓] Installation terminée"
echo "[~] Accès Omada : https://${HOST_IP}:8043"
echo "Logs : /opt/tplink/EAPController/logs/server.log"
echo "============================================================"
