#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
# 📢 PWS ALERT SENDER - F2G TelcoLab
# Envoie des alertes CMAS/ETWS via srsENB (SIB11/SIB12)
#
# Usage: ./send_pws_alert.sh <type> "<message>"
#
# Types: test, presidential, extreme, severe, amber, earthquake, tsunami
#═══════════════════════════════════════════════════════════════════════════════

CONFIG_DIR="/home/f2g/Telecom/Core-Network/docker_open5gs/srsran"
SIB_FILE="$CONFIG_DIR/sib_complete_pws.conf"
ENB_CONF="$CONFIG_DIR/enb_pws.conf"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  📢 PWS ALERT SENDER - F2G TelcoLab${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Usage: $0 <type> \"<message>\""
    echo ""
    echo "Alert Types:"
    echo "  ${GREEN}CMAS (Commercial Mobile Alert System):${NC}"
    echo "    test         - Required Monthly Test (4380)"
    echo "    presidential - Presidential Alert (4370) - Cannot be disabled"
    echo "    extreme      - Extreme Threat (4371)"
    echo "    severe       - Severe Threat (4373)"
    echo "    amber        - AMBER Alert - Child abduction (4379)"
    echo ""
    echo "  ${GREEN}ETWS (Earthquake & Tsunami Warning):${NC}"
    echo "    earthquake   - Earthquake Warning (4352)"
    echo "    tsunami      - Tsunami Warning (4353)"
    echo ""
    echo "Example:"
    echo "  $0 test \"This is a test of the Emergency Alert System\""
    echo "  $0 earthquake \"Strong earthquake detected. Take cover immediately.\""
    echo ""
}

update_sib_config() {
    local alert_type=$1
    local sib_type=$2   # 11 or 12
    local msg_id=$3
    local message=$4
    local serial=$(( (RANDOM % 65535) ))
    
    # Backup current config
    cp $SIB_FILE ${SIB_FILE}.bak
    
    if [ "$sib_type" == "11" ]; then
        # Update SIB11 (ETWS)
        sed -i "/^sib11/,/^sib12\|^$/{
            s/message_id = 0x[0-9a-fA-F]*;/message_id = ${msg_id};/
            s/serial_num = 0x[0-9a-fA-F]*;/serial_num = 0x$(printf '%04X' $serial);/
            s/warning_message = \".*\";/warning_message = \"${message}\";/
        }" $SIB_FILE
    else
        # Update SIB12 (CMAS)
        sed -i "/^sib12/,/^$/{
            s/message_id = 0x[0-9a-fA-F]*;/message_id = ${msg_id};/
            s/serial_num = 0x[0-9a-fA-F]*;/serial_num = 0x$(printf '%04X' $serial);/
            s/warning_message = \".*\";/warning_message = \"${message}\";/
        }" $SIB_FILE
    fi
}

restart_enb() {
    echo -e "${YELLOW}Redémarrage srsENB pour diffuser l'alerte...${NC}"
    sudo pkill -9 srsenb 2>/dev/null
    sleep 2
    cd /home/f2g/Telecom/Core-Network/docker_open5gs
    nohup sudo srsenb $ENB_CONF > /tmp/srsenb_pws.log 2>&1 &
    sleep 10
    echo -e "${GREEN}srsENB redémarré avec la nouvelle alerte${NC}"
}

send_alert() {
    local alert_type=$1
    local message=$2
    local sib_type=""
    local msg_id=""
    local alert_name=""
    
    case $alert_type in
        # ETWS (SIB11)
        earthquake)
            sib_type="11"
            msg_id="0x1100"
            alert_name="ETWS EARTHQUAKE"
            ;;
        tsunami)
            sib_type="11"
            msg_id="0x1101"
            alert_name="ETWS TSUNAMI"
            ;;
        # CMAS (SIB12)
        presidential)
            sib_type="12"
            msg_id="0x1112"
            alert_name="PRESIDENTIAL ALERT"
            ;;
        extreme)
            sib_type="12"
            msg_id="0x1113"
            alert_name="EXTREME THREAT"
            ;;
        severe)
            sib_type="12"
            msg_id="0x1115"
            alert_name="SEVERE THREAT"
            ;;
        amber)
            sib_type="12"
            msg_id="0x111B"
            alert_name="AMBER ALERT"
            ;;
        test)
            sib_type="12"
            msg_id="0x111C"
            alert_name="MONTHLY TEST"
            ;;
        *)
            echo -e "${RED}Type d'alerte inconnu: $alert_type${NC}"
            usage
            exit 1
            ;;
    esac
    
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}  🚨 ENVOI ALERTE: ${alert_name} 🚨${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "Type: ${GREEN}$alert_name${NC}"
    echo -e "SIB: ${GREEN}SIB$sib_type${NC}"
    echo -e "Message ID: ${GREEN}$msg_id${NC}"
    echo -e "Message: ${YELLOW}$message${NC}"
    echo -e "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    # Mettre à jour la config
    echo -e "${YELLOW}Mise à jour de la configuration SIB...${NC}"
    update_sib_config "$alert_type" "$sib_type" "$msg_id" "$message"
    
    # Redémarrer srsENB
    restart_enb
    
    # Afficher les UEs qui recevront l'alerte
    echo ""
    echo -e "${CYAN}📱 UEs connectés qui recevront l'alerte:${NC}"
    docker logs mme 2>&1 | grep "Attach complete" | tail -5 | while read line; do
        imsi=$(echo "$line" | grep -oP '\[\K[0-9]{15}')
        [ ! -z "$imsi" ] && echo -e "  • IMSI: ${GREEN}${imsi}${NC}"
    done
    
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ✅ ALERTE DIFFUSÉE VIA SIB${sib_type}${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${RED}┌────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${RED}│  ⚠️  ${alert_name}${NC}"
    echo -e "${RED}│                                                                │${NC}"
    printf "${RED}│  %-62s│${NC}\n" "${message:0:62}"
    echo -e "${RED}│                                                                │${NC}"
    echo -e "${RED}│  Les téléphones devraient afficher cette alerte!               │${NC}"
    echo -e "${RED}└────────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    
    # Log
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $alert_name: $message" >> /tmp/pws_alerts.log
}

# Main
if [ $# -lt 2 ]; then
    usage
    exit 1
fi

TYPE=$1
shift
MESSAGE="$*"

send_alert "$TYPE" "$MESSAGE"

#═══════════════════════════════════════════════════════════════════════════════
# EXEMPLES AMBER ALERT - Commandes prêtes à l'emploi
#═══════════════════════════════════════════════════════════════════════════════
#
# ./send_pws_alert.sh amber "AMBER - Marie 8 ans robe bleue Yaounde. Toyota grise LT-456. Tel 117"
#
# ./send_pws_alert.sh amber "ENLEVEMENT - Jean 5 ans short rouge Douala port. Moto noire. Police 117"
#
# ./send_pws_alert.sh amber "AMBER URGENT - Sophie 4 ans Bafoussam marche. Homme suspect 40 ans. 117"
#
# Pour GARANTIR la réception (même si AMBER désactivé):
# ./send_pws_alert.sh presidential "ALERTE ENLEVEMENT - Marie 8 ans Yaounde. Appelez 117!"
#
#═══════════════════════════════════════════════════════════════════════════════
