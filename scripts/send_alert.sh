#!/bin/bash
#═══════════════════════════════════════════════════════════════
# SEND CMAS ALERT - F2G Lab
# Injecte une alerte en modifiant le SIB12 et relançant l'eNB
# 
# Usage: ./send_alert.sh "Message d'alerte" [tac]
#   tac: 1 (Yaoundé) ou 2 (Douala) ou both (défaut)
#═══════════════════════════════════════════════════════════════

MESSAGE="${1:-TEST ALERT - CMAS Demo F2G}"
TAC="${2:-both}"
TIMESTAMP=$(date +%s)
SERIAL=$((TIMESTAMP % 65535))

echo "═══════════════════════════════════════════════════════════════"
echo "  🚨 ENVOI ALERTE CMAS"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Message: $MESSAGE"
echo "TAC cible: $TAC"
echo "Serial: 0x$(printf '%04X' $SERIAL)"
echo ""

update_sib12() {
    local SIB_FILE=$1
    local MSG=$2
    local SER=$3
    
    # Backup
    cp "$SIB_FILE" "${SIB_FILE}.bak"
    
    # Mettre à jour SIB12
    sed -i "/sib12/,/};/c\\
sib12 =\\
{\\
    message_id = 0x1112;\\
    serial_num = 0x$(printf '%04X' $SER);\\
    data_coding_scheme = 0x01;\\
    warning_message = \"$MSG\";\\
};" "$SIB_FILE"
    
    echo "✅ SIB12 mis à jour dans $SIB_FILE"
}

restart_enb1() {
    echo "=== Redémarrage eNB1 (TAC 1 - Yaoundé) ==="
    sudo pkill -f "enb_tac1" 2>/dev/null
    sleep 1
    cd /home/f2g/Telecom/Core-Network/docker_open5gs/srsran
    sudo nohup srsenb enb_tac1_cmas.conf > /tmp/enb1.log 2>&1 &
    sleep 3
    echo "✅ eNB1 redémarré"
}

restart_enb2() {
    echo "=== Redémarrage eNB2 (TAC 2 - Douala) ==="
    sshpass -p "1234" ssh -o StrictHostKeyChecking=no f2g@192.168.1.101 << 'REMOTE'
echo "1234" | sudo -S pkill srsenb 2>/dev/null
sleep 1
cd /home/f2g/.config/srsran
echo "1234" | sudo -S srsenb enb.conf > /tmp/enb2.log 2>&1 &
sleep 3
REMOTE
    echo "✅ eNB2 redémarré"
}

# Mise à jour selon TAC
if [ "$TAC" = "1" ] || [ "$TAC" = "both" ]; then
    SIB1="/home/f2g/Telecom/Core-Network/docker_open5gs/srsran/sib_tac1_cmas.conf"
    update_sib12 "$SIB1" "$MESSAGE" "$SERIAL"
    restart_enb1
fi

if [ "$TAC" = "2" ] || [ "$TAC" = "both" ]; then
    # Pour PC2, on doit d'abord modifier le fichier à distance
    echo "=== Mise à jour SIB12 sur PC2 ==="
    sshpass -p "1234" ssh -o StrictHostKeyChecking=no f2g@192.168.1.101 << REMOTE
sed -i "/sib12/,/};/c\\
sib12 =\\
{\\
    message_id = 0x1112;\\
    serial_num = 0x$(printf '%04X' $SERIAL);\\
    data_coding_scheme = 0x01;\\
    warning_message = \"$MESSAGE\";\\
};" /home/f2g/.config/srsran/sib.conf
REMOTE
    restart_enb2
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ ALERTE ENVOYÉE"
echo ""
echo "Les téléphones recevront l'alerte dans quelques secondes"
echo "via SIB12 broadcast"
echo "═══════════════════════════════════════════════════════════════"
