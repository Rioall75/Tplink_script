#!/bin/bash
# ============================================================
# TP-LINK Omada Software Controller installation for Debian 12/13
# Tested on Debian 13 "Trixie"
# Author: Ben Mvouama 
# ============================================================

set -e

echo "===  Vérification des privilèges root ==="
if [ "$EUID" -ne 0 ]; then
  echo " Veuillez exécuter ce script avec sudo ou en root."
  exit 1
fi

export PATH=$PATH:/usr/local/sbin:/usr/sbin:/sbin

echo "===  Mise à jour du système ==="
apt update && apt upgrade -y

# ------------------------------------------------------------
#  Installer OpenJDK 17
# ------------------------------------------------------------
echo "=== Installation de Java (OpenJDK 17) ==="
echo "deb http://deb.debian.org/debian bookworm main contrib non-free-firmware" | tee /etc/apt/sources.list.d/bookworm-java.list
apt update
apt install -y openjdk-17-jre
java -version

# ------------------------------------------------------------
# Installer MongoDB 6.0 (depuis dépôt officiel)
# ------------------------------------------------------------
echo "=== Installation de MongoDB 6.0 ==="
apt install -y gnupg curl
curl -fsSL https://pgp.mongodb.com/server-6.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-6.0.gpg
echo "deb [signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list
apt update
apt install -y mongodb-org

systemctl enable mongod
systemctl start mongod

# ------------------------------------------------------------
#  Installer JSVC
# ------------------------------------------------------------
echo "===  Installation de JSVC ==="
apt install -y jsvc || (echo " JSVC introuvable, ajout du dépôt Debian Bookworm..." && \
echo "deb http://deb.debian.org/debian bookworm main contrib non-free-firmware" | tee /etc/apt/sources.list.d/bookworm-jsvc.list && \
apt update && apt install -y jsvc)

# ------------------------------------------------------------
# Télécharger et installer Omada Controller
# ------------------------------------------------------------
echo "===  Installation du contrôleur Omada v6.0.0.24 ==="
cd /tmp
OMADA_URL="https://static.tp-link.com/upload/software/2025/202510/20251031/omada_v6.0.0.24_linux_x64_20251027202535.deb"
wget -O omada.deb $OMADA_URL

dpkg -i omada.deb || apt -f install -y

# ------------------------------------------------------------
#  Démarrer Omada
# ------------------------------------------------------------
echo "=== Démarrage du service Omada ==="
systemctl enable tpeap
systemctl start tpeap

# ------------------------------------------------------------
#  Vérifications
# ------------------------------------------------------------
echo "===  Vérifications des services ==="
echo "→ Java version :"
java -version
echo "→ MongoDB :"
systemctl status mongod --no-pager | grep Active
echo "→ Omada :"
systemctl status tpeap --no-pager | grep Active

# ------------------------------------------------------------
#  Infos finales
# ------------------------------------------------------------
echo "============================================================"
echo "Installation terminée avec succès !"
echo "Accédez à votre interface Web :"
hostIP=$(hostname -I | awk '{print $1}')
echo -e "\e[0;32m[~] Interface Web Omada : https://${hostIP}:8043\e[0m"
echo ""
echo ""
echo " Sauvegardes : /opt/tplink/EAPController/data/autobackup"
echo " Service Omada : systemctl status tpeap"
echo "============================================================"

