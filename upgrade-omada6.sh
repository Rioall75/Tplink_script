#!/bin/bash
# ============================================================
# TP-LINK Omada Software Controller UPGRADE for Debian 12/13
# Migration 5.x -> 6.0.0.24 (Release Candidate)
# Tested on Debian 13 "Trixie"
# Author: Ben Mvouama - upgrade version
# ============================================================

set -e

echo "===  Vérification des privilèges root ==="
if [ "$EUID" -ne 0 ]; then
  echo " Veuillez exécuter ce script avec sudo ou en root."
  exit 1
fi

export PATH=$PATH:/usr/local/sbin:/usr/sbin:/sbin

echo "============================================================"
echo "ATTENTION : assurez-vous d'avoir :"
echo " - Téléchargé une SAUVEGARDE Omada (Settings → Maintenance → Backup)"
echo " - Éventuellement pris un snapshot de la VM"
echo "============================================================"
sleep 2

# ------------------------------------------------------------
#  (Optionnel) Mise à jour rapide du système
# ------------------------------------------------------------
echo "=== Mise à jour rapide des paquets (optionnel) ==="
apt update && apt upgrade -y

# ------------------------------------------------------------
#  Vérifier la présence de JSVC
# ------------------------------------------------------------
echo "=== Vérification de JSVC ==="
if ! command -v jsvc >/dev/null 2>&1; then
  echo " JSVC n'est pas présent, tentative d'installation..."
  apt install -y jsvc || echo " [!] Impossible d'installer jsvc automatiquement, vérifiez manuellement."
else
  echo " JSVC déjà installé."
fi

# ------------------------------------------------------------
#  Infos sur la version Omada actuelle
# ------------------------------------------------------------
echo "=== Version Omada actuellement installée ==="
dpkg -l | grep -i omada || echo "Aucun paquet Omada trouvé dans dpkg (bizarre si le contrôleur tourne déjà)."

# ------------------------------------------------------------
#  Arrêt propre du contrôleur Omada
# ------------------------------------------------------------
echo "=== Arrêt du service Omada existant ==="
if command -v tpeap >/dev/null 2>&1; then
  tpeap stop || true
else
  systemctl stop tpeap || true
fi

# ------------------------------------------------------------
#  Télécharger et installer Omada v6.0.0.24
# ------------------------------------------------------------
echo "=== Téléchargement du contrôleur Omada v6.0.0.24 ==="
cd /tmp
OMADA_URL="https://static.tp-link.com/upload/software/2025/202510/20251031/omada_v6.0.0.24_linux_x64_20251027202535.deb"
wget -O omada_v6.deb "$OMADA_URL"

echo "=== Installation / Upgrade vers Omada v6.0.0.24 ==="
# On ignore la dépendance jsvc trop stricte dans le .deb TP-Link
if ! dpkg --ignore-depends=jsvc -i omada_v6.deb; then
  echo "dpkg signale un problème de dépendances, tentative de correction..."
  apt -f install -y
  dpkg --ignore-depends=jsvc -i omada_v6.deb
fi

# ------------------------------------------------------------
#  Démarrer Omada
# ------------------------------------------------------------
echo "=== Démarrage du service Omada ==="
if command -v tpeap >/dev/null 2>&1; then
  tpeap start
else
  systemctl enable tpeap
  systemctl start tpeap
fi

# ------------------------------------------------------------
#  Vérifications
# ------------------------------------------------------------
echo "=== Vérifications des services ==="
echo "→ JSVC :"
if command -v jsvc >/dev/null 2>&1; then
  echo "  jsvc OK ($(jsvc -help 2>/dev/null | head -n1 || echo 'version inconnue'))"
else
  echo "  [!] jsvc introuvable (à vérifier si Omada refuse de démarrer)."
fi

echo "→ Omada (tpeap) :"
if command -v tpeap >/dev/null 2>&1; then
  tpeap status || true
fi
systemctl status tpeap --no-pager | grep Active || true

echo "→ Version Omada après upgrade :"
dpkg -l | grep -i omada || echo "Omada n'apparaît pas dans dpkg, vérifiez l'installation."

# ------------------------------------------------------------
#  Infos finales
# ------------------------------------------------------------
echo "============================================================"
echo "Upgrade Omada terminé (si aucune erreur ci-dessus)."
hostIP=$(hostname -I | awk '{print $1}')
echo -e "\e[0;32m[~] Interface Web Omada : https://${hostIP}:8043\e[0m"
echo ""
echo " Sauvegardes automatiques : /opt/tplink/EAPController/data/autobackup"
echo " Service Omada : systemctl status tpeap "
echo " Pense à vérifier dans l'UI (About) que tu es bien en 6.0.0.24."
echo "============================================================"
