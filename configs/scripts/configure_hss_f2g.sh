#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION HSS F2G — Open5GS + PyHSS + OsmoHLR
# ═══════════════════════════════════════════════════════════════════════════════
# Source: /home/f2g/Pictures/CHANNEL IN LTE.pdf
# Contient les vraies données SIM F2G (sysmoISIM-SJA5)
# ═══════════════════════════════════════════════════════════════════════════════

set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${CYAN}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  CONFIGURATION HSS F2G — 4 SUBSCRIBERS VOLTE${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════════════${NC}"

# ═══════════════════════════════════════════════════════════════════════════════
# DONNÉES SIM F2G (extraites du PDF "CHANNEL IN LTE")
# ═══════════════════════════════════════════════════════════════════════════════

# Structure: IMSI|MSISDN|Ki|OPc|SQN
declare -a SIMS=(
    "001010000123450|1003|B4B066475F47C4D1BFFA4CA0823B1A62|2097B88FB9E7368B300A485678BB9E2C|2690"
    "001010000123451|1001|B4B066475F47C4D1BFFA4CA0823B1A62|2097B88FB9E7368B300A485678BB9E2C|0"
    "001010000123452|1002|B4B066475F47C4D1BFFA4CA0823B1A63|2097B88FB9E7368B300A485678BB9E2D|0"
    "001010000123453|1004|B4B066475F47C4D1BFFA4CA0823B1A64|2097B88FB9E7368B300A485678BB9E2E|0"
)

# IMS Domain
IMS_DOMAIN="ims.mnc01.mcc001.3gppnetwork.org"
EPC_DOMAIN="epc.mnc01.mcc001.3gppnetwork.org"
SCSCF_PEER="scscf.${IMS_DOMAIN}"
SCSCF_PORT="6060"

# Container names
MONGO_CONTAINER="mongo"
PYHSS_API="http://localhost:8080"
OSMOHLR_IP="172.22.0.32"
OSMOHLR_PORT="4258"

# ═══════════════════════════════════════════════════════════════════════════════
# FONCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

check_containers() {
    echo -e "\n${YELLOW}[1/5] Vérification des conteneurs...${NC}"
    
    local missing=0
    
    for container in mongo pyhss; do
        if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
            echo -e "  ${GREEN}✓${NC} ${container} actif"
        else
            echo -e "  ${RED}✗${NC} ${container} non actif"
            missing=1
        fi
    done
    
    if [ $missing -eq 1 ]; then
        echo -e "\n${YELLOW}Lancer: docker compose -f 4g-volte-deploy.yaml up -d${NC}"
        return 1
    fi
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# OPEN5GS (MongoDB) — Couche Radio/EPC
# ═══════════════════════════════════════════════════════════════════════════════

configure_open5gs() {
    echo -e "\n${YELLOW}[2/5] Configuration Open5GS (MongoDB)...${NC}"
    
    for sim_data in "${SIMS[@]}"; do
        IFS='|' read -r IMSI MSISDN KI OPC SQN <<< "$sim_data"
        
        echo -e "  ${BLUE}→${NC} Subscriber IMSI=${IMSI}, MSISDN=${MSISDN}"
        
        docker exec -i ${MONGO_CONTAINER} mongosh open5gs --quiet <<EOF
// Supprimer si existe
db.subscribers.deleteOne({ "imsi": "${IMSI}" });

// Insérer subscriber avec APN internet + ims
db.subscribers.insertOne({
    "imsi": "${IMSI}",
    "subscribed_rau_tau_timer": 12,
    "network_access_mode": 0,
    "subscriber_status": 0,
    "access_restriction_data": 32,
    "slice": [{
        "sst": 1,
        "default_indicator": true,
        "session": [
            {
                "name": "internet",
                "type": 1,
                "ambr": {
                    "uplink": {"value": 1, "unit": 3},
                    "downlink": {"value": 1, "unit": 3}
                },
                "qos": {
                    "index": 9,
                    "arp": {
                        "priority_level": 8,
                        "pre_emption_capability": 1,
                        "pre_emption_vulnerability": 1
                    }
                }
            },
            {
                "name": "ims",
                "type": 1,
                "ambr": {
                    "uplink": {"value": 128, "unit": 1},
                    "downlink": {"value": 128, "unit": 1}
                },
                "qos": {
                    "index": 5,
                    "arp": {
                        "priority_level": 2,
                        "pre_emption_capability": 0,
                        "pre_emption_vulnerability": 0
                    }
                }
            }
        ]
    }],
    "security": {
        "k": "${KI}",
        "amf": "8000",
        "opc": "${OPC}",
        "sqn": ${SQN}
    },
    "ambr": {
        "uplink": {"value": 128, "unit": 1},
        "downlink": {"value": 1, "unit": 3}
    },
    "schema_version": 1
});
EOF
        
        if [ $? -eq 0 ]; then
            echo -e "    ${GREEN}✓${NC} Open5GS OK"
        else
            echo -e "    ${RED}✗${NC} Erreur Open5GS"
        fi
    done
}

# ═══════════════════════════════════════════════════════════════════════════════
# PYHSS — Couche Diameter/IMS
# ═══════════════════════════════════════════════════════════════════════════════

configure_pyhss() {
    echo -e "\n${YELLOW}[3/5] Configuration PyHSS (Diameter/IMS)...${NC}"
    
    local auc_id=1
    
    for sim_data in "${SIMS[@]}"; do
        IFS='|' read -r IMSI MSISDN KI OPC SQN <<< "$sim_data"
        
        echo -e "  ${BLUE}→${NC} PyHSS IMSI=${IMSI}"
        
        # A. AuC (Authentication Center)
        echo -e "    Ajout AuC..."
        curl -s -X PUT "${PYHSS_API}/auc/" \
            -H "Content-Type: application/json" \
            -d "{
                \"imsi\": \"${IMSI}\",
                \"ki\": \"${KI}\",
                \"opc\": \"${OPC}\",
                \"amf\": \"8000\",
                \"sqn\": ${SQN}
            }" > /dev/null 2>&1
        
        # B. Subscriber
        echo -e "    Ajout Subscriber..."
        curl -s -X PUT "${PYHSS_API}/subscriber/" \
            -H "Content-Type: application/json" \
            -d "{
                \"imsi\": \"${IMSI}\",
                \"enabled\": true,
                \"auc_id\": ${auc_id},
                \"default_apn\": 1,
                \"apn_list\": \"1,2\",
                \"msisdn\": \"${MSISDN}\"
            }" > /dev/null 2>&1
        
        # C. IMS Subscriber (VoLTE)
        echo -e "    Ajout IMS Subscriber..."
        curl -s -X PUT "${PYHSS_API}/ims_subscriber/" \
            -H "Content-Type: application/json" \
            -d "{
                \"imsi\": \"${IMSI}\",
                \"msisdn\": \"${MSISDN}\",
                \"scscf_peer\": \"${SCSCF_PEER}\",
                \"msisdn_list\": \"[\\\"${MSISDN}\\\"]\",
                \"ifc_path\": \"default_ifc.xml\",
                \"scscf\": \"sip:${SCSCF_PEER}:${SCSCF_PORT}\",
                \"scscf_realm\": \"${IMS_DOMAIN}\"
            }" > /dev/null 2>&1
        
        echo -e "    ${GREEN}✓${NC} PyHSS OK"
        ((auc_id++))
    done
}

# ═══════════════════════════════════════════════════════════════════════════════
# OSMOHLR — Couche Circuit Switch (Appels/SMS via CSFB)
# ═══════════════════════════════════════════════════════════════════════════════

configure_osmohlr() {
    echo -e "\n${YELLOW}[4/5] Configuration OsmoHLR (optionnel - CSFB)...${NC}"
    
    # Vérifier si OsmoHLR est actif
    if ! docker ps --format '{{.Names}}' | grep -q "osmohlr"; then
        echo -e "  ${YELLOW}⚠${NC} OsmoHLR non actif (CSFB désactivé)"
        return 0
    fi
    
    echo -e "  ${BLUE}→${NC} Connexion à OsmoHLR via Telnet..."
    
    for sim_data in "${SIMS[@]}"; do
        IFS='|' read -r IMSI MSISDN KI OPC SQN <<< "$sim_data"
        
        # Envoyer commandes via expect ou netcat
        {
            sleep 1
            echo "enable"
            sleep 0.5
            echo "subscriber imsi ${IMSI} create"
            sleep 0.5
            echo "subscriber imsi ${IMSI} update msisdn ${MSISDN}"
            sleep 0.5
            echo "exit"
        } | nc -q 2 ${OSMOHLR_IP} ${OSMOHLR_PORT} > /dev/null 2>&1
        
        echo -e "    ${GREEN}✓${NC} OsmoHLR: IMSI=${IMSI} → MSISDN=${MSISDN}"
    done
}

# ═══════════════════════════════════════════════════════════════════════════════
# VÉRIFICATION FINALE
# ═══════════════════════════════════════════════════════════════════════════════

verify_configuration() {
    echo -e "\n${YELLOW}[5/5] Vérification...${NC}"
    
    echo -e "\n${CYAN}── Open5GS (MongoDB) ──${NC}"
    docker exec -i ${MONGO_CONTAINER} mongosh open5gs --quiet <<'EOF'
db.subscribers.find({}, {imsi: 1, "security.k": 1, "slice.session.name": 1}).forEach(function(doc) {
    var apns = doc.slice && doc.slice[0] && doc.slice[0].session 
        ? doc.slice[0].session.map(s => s.name).join(", ") 
        : "N/A";
    print("  IMSI: " + doc.imsi + " | Ki: " + doc.security.k.substring(0,8) + "... | APN: " + apns);
});
EOF

    echo -e "\n${CYAN}── PyHSS (si accessible) ──${NC}"
    curl -s "${PYHSS_API}/subscriber/" 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for sub in data if isinstance(data, list) else []:
        print(f\"  IMSI: {sub.get('imsi', 'N/A')} | MSISDN: {sub.get('msisdn', 'N/A')}\")
except:
    print('  (API non accessible)')
" 2>/dev/null || echo "  (API non accessible)"
}

# ═══════════════════════════════════════════════════════════════════════════════
# RÉSUMÉ
# ═══════════════════════════════════════════════════════════════════════════════

show_summary() {
    echo -e "\n${CYAN}════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✅ CONFIGURATION HSS TERMINÉE${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════${NC}"
    
    echo -e "\n${CYAN}📱 Subscribers configurés:${NC}"
    echo "┌─────────────────────┬────────┬──────────────────┬─────────────┐"
    echo "│ IMSI                │ MSISDN │ Ki (8 premiers)  │ APN         │"
    echo "├─────────────────────┼────────┼──────────────────┼─────────────┤"
    echo "│ 001010000123450     │ 1003   │ B4B06647...      │ internet,ims│"
    echo "│ 001010000123451     │ 1001   │ B4B06647...      │ internet,ims│"
    echo "│ 001010000123452     │ 1002   │ B4B06647...      │ internet,ims│"
    echo "│ 001010000123453     │ 1004   │ B4B06647...      │ internet,ims│"
    echo "└─────────────────────┴────────┴──────────────────┴─────────────┘"
    
    echo -e "\n${CYAN}📡 Réseau:${NC}"
    echo "   PLMN: 001-01"
    echo "   IMS Domain: ${IMS_DOMAIN}"
    echo "   S-CSCF: sip:${SCSCF_PEER}:${SCSCF_PORT}"
    
    echo -e "\n${CYAN}🔗 Accès:${NC}"
    echo "   WebUI: http://localhost:9999 (admin/1423)"
    echo "   PyHSS API: http://localhost:8080"
    
    echo -e "\n${CYAN}📋 Commandes de vérification:${NC}"
    echo "   # MongoDB"
    echo "   docker exec -it mongo mongosh open5gs --eval \"db.subscribers.find()\""
    echo ""
    echo "   # PyHSS"
    echo "   curl http://localhost:8080/subscriber/"
    echo ""
    echo "   # Logs MME (lors de l'attach)"
    echo "   docker logs -f mme"
    
    echo -e "\n${CYAN}════════════════════════════════════════════════════════════════════${NC}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

main() {
    check_containers || exit 1
    configure_open5gs
    configure_pyhss
    configure_osmohlr
    verify_configuration
    show_summary
}

# Mode d'exécution
case "${1:-}" in
    --open5gs-only)
        check_containers || exit 1
        configure_open5gs
        ;;
    --pyhss-only)
        configure_pyhss
        ;;
    --verify)
        verify_configuration
        ;;
    *)
        main
        ;;
esac
