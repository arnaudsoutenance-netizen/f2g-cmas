#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
# F2G CMAS/PWS Lab - Script de démarrage
# Write-Replace-Warning via SBc-AP
#═══════════════════════════════════════════════════════════════════════════════

set -e

echo "════════════════════════════════════════════════════════════════════════════════"
echo "  🚀 F2G CMAS LAB - WriteReplaceWarning"
echo "════════════════════════════════════════════════════════════════════════════════"

# Variables
MME_FORK="/home/f2g/Desktop/CMAS_Complete_Package/open5gs-fork/build/src/mme/open5gs-mmed"
LIB_PATH="/home/f2g/Desktop/CMAS_Complete_Package/open5gs-fork/build/lib"
FD_PATH="/home/f2g/Desktop/CMAS_Complete_Package/open5gs-fork/build/subprojects/freeDiameter"

export LD_LIBRARY_PATH="$LIB_PATH:$LIB_PATH/sbcap:$LIB_PATH/s1ap:$LIB_PATH/diameter/s6a:$LIB_PATH/diameter/common:$LIB_PATH/gtp:$LIB_PATH/nas/eps:$LIB_PATH/nas/common:$LIB_PATH/core:$LIB_PATH/crypt:$LIB_PATH/sctp:$LIB_PATH/app:$LIB_PATH/proto:$LIB_PATH/asn1c/s1ap:$LIB_PATH/asn1c/sbcap:$LIB_PATH/asn1c/common:$LIB_PATH/asn1c/util:$FD_PATH/libfdcore:$FD_PATH/libfdproto:$LD_LIBRARY_PATH"

# 1. Arrêter les anciens processus
echo "🛑 Arrêt des anciens processus..."
sudo pkill -9 open5gs-mmed 2>/dev/null || true
sudo pkill -9 osmo-cbc 2>/dev/null || true
sleep 2

# 2. Configurer les IPs loopback
echo "🌐 Configuration IPs loopback..."
sudo ip addr add 127.0.0.2/8 dev lo 2>/dev/null || true
sudo ip addr add 127.0.0.10/8 dev lo 2>/dev/null || true

# 3. Lancer le MME avec SBc-AP
echo "🚀 Lancement MME avec SBc-AP..."
sudo -E bash -c "LD_LIBRARY_PATH=$LD_LIBRARY_PATH nohup $MME_FORK -c /tmp/mme-fork.yaml > /tmp/mme-fork.log 2>&1 &"
sleep 4

if pgrep -f "open5gs-mmed" > /dev/null; then
    echo "✅ MME démarré (S1AP: 127.0.0.2:36412, SBc-AP: 127.0.0.2:29168)"
else
    echo "❌ Échec démarrage MME"
    exit 1
fi

# 4. Lancer osmo-cbc
echo "🚀 Lancement osmo-cbc..."
sudo nohup osmo-cbc -c /tmp/cbc/osmo-cbc.cfg > /tmp/osmo-cbc.log 2>&1 &
sleep 4

if pgrep -f "osmo-cbc" > /dev/null; then
    echo "✅ osmo-cbc démarré (REST API: 127.0.0.1:12345)"
else
    echo "❌ Échec démarrage osmo-cbc"
    exit 1
fi

# 5. Vérifier la connexion SBc-AP
sleep 2
if grep -q "Connected" /tmp/osmo-cbc.log 2>/dev/null; then
    echo "✅ Connexion SBc-AP établie"
else
    echo "⚠️ Connexion SBc-AP en attente..."
fi

echo ""
echo "════════════════════════════════════════════════════════════════════════════════"
echo "  ✅ LAB CMAS PRÊT"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""
echo "Pour envoyer une alerte:"
echo "  ./send_cmas_alert.sh \"Votre message d'alerte\""
echo ""
echo "Logs:"
echo "  MME:      tail -f /tmp/mme-fork.log"
echo "  osmo-cbc: tail -f /tmp/osmo-cbc.log"
