#!/bin/bash
# /tmp/cmas_tac.sh - CMAS avec ciblage TAC et expiration automatique
#
# Usage:
#   /tmp/cmas_tac.sh send "MESSAGE" [msg_id] [duration] [tac]
#   /tmp/cmas_tac.sh stop [msg_id] [code]
#   /tmp/cmas_tac.sh list
#
# Exemples:
#   /tmp/cmas_tac.sh send "ALERTE YAOUNDE" 4370 60 1      # TAC 1, 60s
#   /tmp/cmas_tac.sh send "ALERTE DOUALA" 4371 60 2       # TAC 2, 60s
#   /tmp/cmas_tac.sh send "ALERTE NATIONALE" 4370 60      # Tous TAC

SBCAP_SEND="/home/f2g/Desktop/F2G_CMAS_SESSION_20261013/sbcap-send/sbcap-send"
MME_IP="127.0.0.2"
MME_PORT="29168"
PLMN="00101"
TRACKING_FILE="/tmp/.cmas_tac_tracking"

# Compteur pour les codes
get_next_code() {
    local code_file="/tmp/.cmas_code_counter"
    local code=$(cat "$code_file" 2>/dev/null || echo "100")
    echo $((code + 1)) > "$code_file"
    echo $code
}

case "$1" in
  send)
    MESSAGE="$2"
    MSG_ID="${3:-4370}"
    DURATION="${4:-60}"
    TAC="$5"
    
    CODE=$(get_next_code)
    
    # Construire la commande
    CMD="$SBCAP_SEND --mme $MME_IP --port $MME_PORT --plmn $PLMN --msg-id $MSG_ID --code $CODE"
    
    if [ -n "$TAC" ]; then
      CMD="$CMD --tac $TAC"
      echo "📍 Ciblage: TAC $TAC"
    else
      echo "📍 Ciblage: PLMN entier (tous les TAC)"
    fi
    
    CMD="$CMD --text \"$MESSAGE\""
    
    echo "📤 Envoi: msg_id=$MSG_ID code=$CODE duration=${DURATION}s"
    eval $CMD
    
    # Enregistrer pour expiration
    EXPIRY=$(($(date +%s) + DURATION))
    echo "$MSG_ID|$CODE|$TAC|$EXPIRY|$MESSAGE" >> "$TRACKING_FILE"
    
    # Programmer le stop en arrière-plan
    (
      sleep $DURATION
      echo ""
      echo "⏰ Expiration: msg_id=$MSG_ID code=$CODE"
      $SBCAP_SEND --mme $MME_IP --port $MME_PORT --plmn $PLMN --msg-id $MSG_ID --code $CODE --stop
      # Retirer du tracking
      sed -i "/^$MSG_ID|$CODE|/d" "$TRACKING_FILE" 2>/dev/null
    ) &
    
    echo "⏱️  Expiration automatique dans ${DURATION}s"
    ;;
    
  stop)
    MSG_ID="${2:-4370}"
    CODE="$3"
    
    if [ -n "$CODE" ]; then
      echo "🛑 Stop: msg_id=$MSG_ID code=$CODE"
      $SBCAP_SEND --mme $MME_IP --port $MME_PORT --plmn $PLMN --msg-id $MSG_ID --code $CODE --stop
      sed -i "/^$MSG_ID|$CODE|/d" "$TRACKING_FILE" 2>/dev/null
    else
      echo "🛑 Stop all for msg_id=$MSG_ID"
      # Stop tous les codes pour ce msg_id
      grep "^$MSG_ID|" "$TRACKING_FILE" 2>/dev/null | while read line; do
        code=$(echo "$line" | cut -d'|' -f2)
        $SBCAP_SEND --mme $MME_IP --port $MME_PORT --plmn $PLMN --msg-id $MSG_ID --code $code --stop
      done
      sed -i "/^$MSG_ID|/d" "$TRACKING_FILE" 2>/dev/null
    fi
    ;;
    
  list)
    echo "📋 Alertes actives:"
    echo "MSG_ID|CODE|TAC|EXPIRY|MESSAGE"
    echo "------|----|----|------|-------"
    if [ -f "$TRACKING_FILE" ]; then
      while read line; do
        msg_id=$(echo "$line" | cut -d'|' -f1)
        code=$(echo "$line" | cut -d'|' -f2)
        tac=$(echo "$line" | cut -d'|' -f3)
        expiry=$(echo "$line" | cut -d'|' -f4)
        msg=$(echo "$line" | cut -d'|' -f5)
        remaining=$((expiry - $(date +%s)))
        [ -z "$tac" ] && tac="ALL"
        if [ $remaining -gt 0 ]; then
          echo "$msg_id|$code|$tac|${remaining}s|$msg"
        fi
      done < "$TRACKING_FILE"
    else
      echo "(aucune)"
    fi
    ;;
    
  *)
    echo "Usage:"
    echo "  $0 send \"MESSAGE\" [msg_id] [duration] [tac]"
    echo "  $0 stop [msg_id] [code]"
    echo "  $0 list"
    echo ""
    echo "Exemples:"
    echo "  $0 send \"ALERTE YAOUNDE\" 4370 60 1    # TAC 1, 60s"
    echo "  $0 send \"ALERTE DOUALA\" 4371 60 2     # TAC 2, 60s"
    echo "  $0 send \"ALERTE NATIONALE\" 4370 60    # Tous TAC"
    ;;
esac
