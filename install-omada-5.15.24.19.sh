#!/bin/bash
# ============================================================
# TP-Link Omada Software Controller INSTALL
# Version : 5.15.24.19 (Linux x64)
# OS      : Ubuntu 20.04 / 22.04 / 24.04
# Author  : Adapted by Ben Mvouama
# ============================================================

set -e

echo -e "\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "TP-Link Omada Software Controller - Installer"
echo "Version : 5.15.24.19"
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n"

# ------------------------------------------------------------
# Root check
# ------------------------------------------------------------
echo "[+] Vérification exécution en root"
if [ "$(id -u)" -ne 0 ]; then
  echo -e "\e[1;31m[!] Le script doit être exécuté avec sudo.\e[0m"
  exit 1
fi

# ------------------------------------------------------------
# CPU AVX check (MongoDB >= 5)
# ------------------------------------------------------------
echo "[+] Vérification support CPU AVX"
if ! lscpu | grep -iq avx; then
  echo -e "\e[1;31m[!] CPU sans AVX détecté. MongoDB requis par Omada 5.x ne fonctionnera pas.\e[0m"
  exit 1
fi

# ------------------------------------------------------------
# OS check
# ------------------------------------------------------------
echo "[+] Vérification OS"
. /etc/os-release

if [[ "$ID" != "ubuntu" ]]; then
  echo -e "\e[1;31m[!] OS non supporté (Ubuntu requis).\e[0m"
  exit 1
fi

case "$VERSION_ID" in
  20.04) OsVer=focal ;;
  22.04) OsVer=jammy ;;
  24.04) OsVer=noble ;;
  *)
    echo -e "\e[1;31m[!] Version Ubuntu non supportée.\e[0m"
    exit 1
    ;;
esac

echo "[~] Ubuntu $VERSION_ID détecté"

# ------------------------------------------------------------
# Pré-requis
# ------------------------------------------------------------
echo "[+] Installation des prérequis"
apt update -qq
apt install -y wget curl gnupg ca-certificates lsb-release

# ------------------------------------------------------------
# MongoDB 8.0 (compatible Omada 5.15.x)
# ------------------------------------------------------------
echo "[+] Installation MongoDB 8.0"
curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc \
  | gpg --dearmor -o /usr/share/keyrings/mongodb-server-8.0.gpg

echo "deb [ arch=amd64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] \
https://repo.mongodb.org/apt/ubuntu ${OsVer}/mongodb-org/8.0 multiverse" \
> /etc/apt/sources.list.d/mongodb-org-8.0.list

apt update -qq
apt install -y mongodb-org

systemctl enable mongod
systemctl start mongod

# ------------------------------------------------------------
# Java (Omada 5.x recommandé : Java 17)
# ------------------------------------------------------------
echo "[+] Installation OpenJDK 17"
apt install -y openjdk-17-jre-headless

# ------------------------------------------------------------
# JSVC
# ------------------------------------------------------------
echo "[+] Installation JSVC"
apt install -y jsvc

# ------------------------------------------------------------
# Télécharger Omada 5.15.24.19
# ------------------------------------------------------------
echo "[+] Téléchargement Omada Software Controller 5.15.24.19"
cd /tmp

OMADA_DEB="omada_v5.15.24.19_linux_x64_20250724152622.deb"
OMADA_URL="https://static.tp-link.com/upload/software/2025/202508/20250802/${OMADA_DEB}"

wget -O "${OMADA_DEB}" "${OMADA_URL}"

# ------------------------------------------------------------
# Installation Omada
# ------------------------------------------------------------
echo "[+] Installation Omada Software Controller 5.15.24.19"
dpkg -i "${OMADA_DEB}" || apt -f install -y

# ------------------------------------------------------------
# Démarrage service
# ------------------------------------------------------------
echo "[+] Démarrage du service Omada"
systemctl enable tpeap
systemctl start tpeap

# ------------------------------------------------------------
# Résultat
# ------------------------------------------------------------
hostIP=$(hostname -I | awk '{print $1}')

echo -e "\n\e[0;32m[✓] Omada Software Controller 5.15.24.19 installé avec succès\e[0m"
echo -e "\e[0;32m[~] Accès Web : https://${hostIP}:8043\e[0m"
echo ""
echo "Logs       : /opt/tplink/EAPController/logs/"
echo "Sauvegardes: /opt/tplink/EAPController/data/autobackup"
echo "Service    : systemctl status tpeap"
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
