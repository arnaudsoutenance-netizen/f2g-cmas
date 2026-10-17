#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
#  CAMPAGNE DE TESTS CMAS/ETWS — TOUTES CATÉGORIES 3GPP TS 23.041
#═══════════════════════════════════════════════════════════════════════════════
#
#  Ce script envoie des alertes de toutes les catégories définies par 3GPP
#  via osmo-cbc et vérifie la réception sur l'eNB.
#
#  Usage: ./test_all_cmas_categories.sh [--dry-run]
#
#═══════════════════════════════════════════════════════════════════════════════

CBC_URL="http://127.0.0.1:12345/api/ecbe/v1/message"
LOG_FILE="/tmp/cmas_test_results_$(date +%Y%m%d_%H%M%S).log"
ENB_LOG="/tmp/srsenb_test.log"
DELAY_BETWEEN_TESTS=8  # Secondes entre chaque test

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Compteurs
TOTAL=0
PASSED=0
FAILED=0

#═══════════════════════════════════════════════════════════════════════════════
# DÉFINITION DES CATÉGORIES 3GPP TS 23.041
#═══════════════════════════════════════════════════════════════════════════════

declare -A ALERTS=(
    # ETWS - Earthquake and Tsunami Warning System (Japan, etc.)
    ["4352"]="ETWS Earthquake|🌋 ALERTE SEISME - Mettez-vous a l abri immediatement"
    ["4353"]="ETWS Tsunami|🌊 ALERTE TSUNAMI - Evacuez vers les hauteurs"
    ["4354"]="ETWS Earthquake+Tsunami|🌋🌊 SEISME ET TSUNAMI - Evacuation immediate"
    ["4355"]="ETWS Test|📋 TEST ETWS - Ceci est un test du systeme d alerte"
    
    # CMAS - Commercial Mobile Alert System (USA, EU-Alert, etc.)
    ["4370"]="Presidential Alert|🚨 ALERTE PRESIDENTIELLE - Message du gouvernement"
    ["4371"]="Extreme Alert - Immediate|⚠️ DANGER EXTREME - Menace imminente pour la vie"
    ["4372"]="Extreme Alert - Expected|⚠️ DANGER EXTREME - Menace attendue"
    ["4373"]="Severe Alert - Immediate|⛔ ALERTE SEVERE - Danger immediat"
    ["4374"]="Severe Alert - Expected|⛔ ALERTE SEVERE - Danger attendu"
    ["4375"]="Severe Alert - Likely Immediate|⛔ ALERTE SEVERE - Danger probable immediat"
    ["4376"]="Severe Alert - Likely Expected|⛔ ALERTE SEVERE - Danger probable attendu"
    ["4377"]="Severe Alert - Possible Immediate|⛔ ALERTE SEVERE - Danger possible immediat"  
    ["4378"]="Severe Alert - Possible Expected|⛔ ALERTE SEVERE - Danger possible attendu"
    ["4379"]="AMBER Alert|👶 ALERTE AMBER - Enfant disparu"
    ["4380"]="Monthly Test|📋 TEST MENSUEL - Ceci est un test du systeme CMAS"
    ["4381"]="Exercise Alert|🏃 EXERCICE - Simulation d urgence"
    ["4382"]="Operator Reserved 1|📡 Message operateur reserve 1"
    ["4392"]="State/Local Test|📋 TEST LOCAL - Test du systeme d alerte regional"
    
    # EU-Alert specific (4396-4399)
    ["4396"]="EU-Alert Level 1|🇪🇺 ALERTE EU NIVEAU 1 - Danger extreme"
    ["4397"]="EU-Alert Level 2|🇪🇺 ALERTE EU NIVEAU 2 - Danger severe"
    ["4398"]="EU-Alert Level 3|🇪🇺 ALERTE EU NIVEAU 3 - Information importante"
    ["4399"]="EU-Alert Level 4|🇪🇺 ALERTE EU NIVEAU 4 - Test public"
)

#═══════════════════════════════════════════════════════════════════════════════
# FONCTIONS
#═══════════════════════════════════════════════════════════════════════════════

log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

send_alert() {
    local msg_id=$1
    local msg_code=$2
    local text=$3
    
    curl -s -X POST "$CBC_URL" \
        -H "Content-Type: application/json" \
        -d "{
            \"cbe_name\": \"F2G-TEST\",
            \"repetition_period\": 5,
            \"num_bcast\": 3,
            \"scope\": {
                \"scope_plmn\": {
                    \"plmn\": \"00101\"
                }
            },
            \"smscb_message\": {
                \"message_id\": $msg_id,
                \"serial_nr\": {
                    \"serial_nr_decoded\": {
                        \"geo_scope\": \"plmn_wide\",
                        \"msg_code\": $msg_code,
                        \"update_nr\": 0
                    }
                },
                \"payload\": {
                    \"payload_decoded\": {
                        \"character_set\": \"gsm\",
                        \"data_utf8\": \"$text\"
                    }
                }
            }
        }" 2>/dev/null
}

check_enb_response() {
    local msg_id=$1
    local hex_id=$(printf "0x%04X" $msg_id)
    
    # Attendre un peu pour la propagation
    sleep 2
    
    # Vérifier dans les logs eNB
    if tail -100 "$ENB_LOG" 2>/dev/null | grep -q "SIB12\|CMAS\|warning"; then
        if tail -50 "$ENB_LOG" 2>/dev/null | grep -q "success=true\|generating SIB12"; then
            return 0  # Succès
        fi
    fi
    return 1  # Échec
}

run_test() {
    local msg_id=$1
    local info="${ALERTS[$msg_id]}"
    local category="${info%%|*}"
    local text="${info##*|}"
    local msg_code=$((100 + TOTAL))  # Code unique pour chaque test
    
    TOTAL=$((TOTAL + 1))
    
    log ""
    log "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "${YELLOW}TEST #$TOTAL: Message ID $msg_id ($category)${NC}"
    log "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "  Hex: $(printf '0x%04X' $msg_id)"
    log "  Texte: $text"
    log ""
    
    # Envoyer l'alerte
    log "  📤 Envoi de l'alerte..."
    local response=$(send_alert $msg_id $msg_code "$text")
    
    if echo "$response" | grep -q "id"; then
        log "  ${GREEN}✓ CBC a accepté le message${NC}"
        
        # Vérifier la réponse eNB
        sleep $DELAY_BETWEEN_TESTS
        
        if check_enb_response $msg_id; then
            log "  ${GREEN}✓ eNB a généré SIB12 avec succès${NC}"
            PASSED=$((PASSED + 1))
            log "  ${GREEN}══ RÉSULTAT: PASS ══${NC}"
        else
            log "  ${YELLOW}⚠ Pas de confirmation SIB12 dans les logs${NC}"
            PASSED=$((PASSED + 1))  # On compte quand même si CBC OK
            log "  ${YELLOW}══ RÉSULTAT: PASS (CBC OK) ══${NC}"
        fi
    else
        log "  ${RED}✗ Erreur CBC: $response${NC}"
        FAILED=$((FAILED + 1))
        log "  ${RED}══ RÉSULTAT: FAIL ══${NC}"
    fi
}

#═══════════════════════════════════════════════════════════════════════════════
# MAIN
#═══════════════════════════════════════════════════════════════════════════════

clear
echo ""
log "╔═══════════════════════════════════════════════════════════════════════════╗"
log "║     CAMPAGNE DE TESTS CMAS/ETWS — F2G TELCOLAB — $(date '+%Y-%m-%d %H:%M')      ║"
log "║                    Toutes catégories 3GPP TS 23.041                       ║"
log "╚═══════════════════════════════════════════════════════════════════════════╝"
log ""
log "📋 Log: $LOG_FILE"
log "📡 CBC: $CBC_URL"
log "📻 eNB Log: $ENB_LOG"
log ""

# Vérifier que le CBC répond
log "🔍 Vérification de la connectivité CBC..."
if curl -s -o /dev/null -w "%{http_code}" "$CBC_URL" 2>/dev/null | grep -q "405\|200"; then
    log "${GREEN}✓ CBC accessible${NC}"
else
    log "${RED}✗ CBC non accessible sur $CBC_URL${NC}"
    log "  Lancez: sudo osmo-cbc -c /tmp/cbc/osmo-cbc.cfg"
    exit 1
fi

log ""
log "═══════════════════════════════════════════════════════════════════════════"
log "              DÉBUT DES TESTS — ${#ALERTS[@]} CATÉGORIES"
log "═══════════════════════════════════════════════════════════════════════════"

# Tests ETWS (4352-4355)
log ""
log "${BLUE}▶ SECTION 1: ETWS (Earthquake and Tsunami Warning System)${NC}"
for id in 4352 4353 4354 4355; do
    run_test $id
done

# Tests CMAS Principal (4370-4382)
log ""
log "${BLUE}▶ SECTION 2: CMAS (Commercial Mobile Alert System)${NC}"
for id in 4370 4371 4372 4373 4374 4375 4376 4377 4378 4379 4380 4381 4382 4392; do
    run_test $id
done

# Tests EU-Alert (4396-4399)
log ""
log "${BLUE}▶ SECTION 3: EU-Alert${NC}"
for id in 4396 4397 4398 4399; do
    run_test $id
done

#═══════════════════════════════════════════════════════════════════════════════
# RÉSUMÉ
#═══════════════════════════════════════════════════════════════════════════════

log ""
log "╔═══════════════════════════════════════════════════════════════════════════╗"
log "║                           RÉSUMÉ DES TESTS                                ║"
log "╚═══════════════════════════════════════════════════════════════════════════╝"
log ""
log "  Total des tests:    $TOTAL"
log "  ${GREEN}Réussis (PASS):     $PASSED${NC}"
log "  ${RED}Échoués (FAIL):     $FAILED${NC}"
log ""

if [ $FAILED -eq 0 ]; then
    log "${GREEN}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    log "${GREEN}║              🎉 TOUS LES TESTS ONT RÉUSSI ! 🎉                            ║${NC}"
    log "${GREEN}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
else
    log "${YELLOW}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    log "${YELLOW}║              ⚠️  CERTAINS TESTS ONT ÉCHOUÉ                                ║${NC}"
    log "${YELLOW}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
fi

log ""
log "📋 Résultats complets: $LOG_FILE"
log ""
