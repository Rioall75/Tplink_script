#!/bin/bash
#title           :upgrade-omada-controller.sh
#description     :Upgrade for TP-Link Omada Software Controller
#supported       :Ubuntu 20.04, Ubuntu 22.04, Ubuntu 24.04
#author          :adapted from monsn0 (upgrade version)
#updated         :2025-12-19

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# (Optionnel) Forcer une version précise (recommandé en prod) :
# OMADA_DEB_URL="https://static.tp-link.com/upload/software/2025/202508/20250802/omada_v5.15.24.19_linux_x64_20250724152622.deb"
OMADA_DEB_URL=""

echo -e "\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "TP-Link Omada Software Controller - UPGRADE"
echo "Base : https://github.com/monsn0/omada-installer"
echo -e "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n"

echo "[+] Vérification exécution en root"
if [ "$(id -u)" -ne 0 ]; then
  echo -e "\e[1;31m[!] Le script doit être exécuté en root (sudo). \e[0m"
  exit 1
fi

echo "[+] Vérification présence du contrôleur (tpeap)"
if ! command -v tpeap >/dev/null 2>&1 && [ ! -f /etc/init.d/tpeap ]; then
  echo -e "\e[1;31m[!] Contrôleur non détecté (tpeap introuvable). Script prévu pour UPGRADE uniquement. \e[0m\n"
  exit 1
fi

echo "[+] Vérification CPU (AVX)"
if ! lscpu | grep -iq avx; then
  echo -e "\e[1;31m[!] CPU sans AVX. MongoDB 5+ (donc Omada récent) requiert AVX. \e[0m"
  exit 1
fi

echo "[+] Vérification OS"
OS=$(hostnamectl status | grep "Operating System" | sed 's/^[ \t]*//')
echo "[~] $OS"

if [[ $OS = *"Ubuntu 20.04"* ]]; then
  OsVer=focal
elif [[ $OS = *"Ubuntu 22.04"* ]]; then
  OsVer=jammy
elif [[ $OS = *"Ubuntu 24.04"* ]]; then
  OsVer=noble
else
  echo -e "\e[1;31m[!] Support Ubuntu : 20.04 / 22.04 / 24.04 uniquement. \e[0m"
  exit 1
fi

echo "============================================================"
echo "ATTENTION : avant upgrade, fais un backup dans l’UI Omada :"
echo "Settings → Maintenance → Backup"
echo "============================================================"
sleep 2

echo "[+] Sauvegarde locale du dossier data (si présent)"
if [ -d /opt/tplink/EAPController/data ]; then
  TS=$(date +%Y%m%d-%H%M%S)
  mkdir -p /opt/tplink/EAPController/data-backup
  tar -C /opt/tplink/EAPController -czf "/opt/tplink/EAPController/data-backup/data_${TS}.tar.gz" data || true
  echo "[~] Backup local : /opt/tplink/EAPController/data-backup/data_${TS}.tar.gz"
fi

echo "[+] Arrêt Omada (tpeap)"
systemctl stop tpeap 2>/dev/null || true
/etc/init.d/tpeap stop 2>/dev/null || true

echo "[+] Installation prérequis"
apt-get -qq update
apt-get -qq install gnupg curl ca-certificates &> /dev/null

echo "[+] Ajout dépôt MongoDB 8.0 + installation/maj"
curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | gpg -o /usr/share/keyrings/mongodb-server-8.0.gpg --dearmor
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu $OsVer/mongodb-org/8.0 multiverse" > /etc/apt/sources.list.d/mongodb-org-8.0.list
apt-get -qq update
apt-get -qq install mongodb-org &> /dev/null
systemctl enable mongod &>/dev/null || true
systemctl start mongod &>/dev/null || true

echo "[+] Installation Java (recommandé : JDK 17) + JSVC"
apt-get -qq install openjdk-17-jdk jsvc &> /dev/null

echo "[+] Téléchargement du package Omada (.deb)"
if [ -z "$OMADA_DEB_URL" ]; then
  OmadaPackageUrl=$(curl -fsSL "https://support.omadanetworks.com/us/product/omada-software-controller/?resourceType=download" \
    | grep -oPi '<a[^>]*href="\K[^"]*linux_x64_[0-9]*\.deb[^"]*' \
    | head -n 1)
else
  OmadaPackageUrl="$OMADA_DEB_URL"
fi

if [ -z "${OmadaPackageUrl:-}" ]; then
  echo -e "\e[1;31m[!] Impossible de récupérer l’URL du .deb Omada. Renseigne OMADA_DEB_URL en haut du script. \e[0m"
  exit 1
fi

OmadaPackageBasename=$(basename "$OmadaPackageUrl")
curl -sLo "/tmp/$OmadaPackageBasename" "$OmadaPackageUrl"

echo "[+] Upgrade Omada via dpkg (fallback apt -f si besoin)"
set +e
dpkg -i "/tmp/$OmadaPackageBasename" &> /dev/null
RC=$?
set -e
if [ $RC -ne 0 ]; then
  apt-get -f install -y &> /dev/null
  dpkg -i "/tmp/$OmadaPackageBasename" &> /dev/null
fi

echo "[+] Réparation des droits (important)"
# Selon le .deb, le user peut être 'omada' (souvent) ou 'tp-link'
if id omada >/dev/null 2>&1; then
  chown -R omada:omada /opt/tplink/EAPController
  echo "[~] chown appliqué : omada:omada"
elif id tp-link >/dev/null 2>&1; then
  chown -R tp-link:tp-link /opt/tplink/EAPController
  echo "[~] chown appliqué : tp-link:tp-link"
else
  echo "[!] Aucun user omada/tp-link trouvé, chown ignoré."
fi

echo "[+] Démarrage Omada (tpeap)"
systemctl daemon-reload || true
systemctl enable tpeap &>/dev/null || true
systemctl start tpeap 2>/dev/null || true
/etc/init.d/tpeap start 2>/dev/null || true

sleep 15

echo "[+] Vérification statut"
systemctl status tpeap --no-pager | sed -n '1,12p' || true

hostIP=$(hostname -I | cut -f1 -d' ')
echo -e "\e[0;32m[~] Upgrade terminé.\e[0m"
echo -e "\e[0;32m[~] Accès : https://${hostIP}:8043 \e[0m\n"
