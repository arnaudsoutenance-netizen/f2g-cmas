#!/bin/bash
# /tmp/alert.sh - 3GPP CMAS via osmo-cbc (with scope_tai support)
#
# Usage:
#   /tmp/alert.sh send "MESSAGE" [msg_id] [duration] [scope]
#   /tmp/alert.sh stop [msg_id]
#   /tmp/alert.sh list
#
# Scope: plmn (default), tac:1, tac:2, tac:1,2

CBC_API="http://127.0.0.1:12345/api/ecbe/v1/message"
CBC_VTY="127.0.0.1 4264"
PLMN="00101"

CODE_FILE="/tmp/.alert_code"
[ -f "$CODE_FILE" ] || echo "1" > "$CODE_FILE"

case "$1" in
  send)
    MSG="${2:-CMAS Test Alert}"
    MSGID="${3:-4370}"
    DURATION="${4:-30}"
    SCOPE="${5:-plmn}"
    
    CODE=$(cat "$CODE_FILE")
    echo $((CODE + 1)) > "$CODE_FILE"
    NAME="alert${MSGID}c${CODE}"
    
    NUM_BCAST=$((DURATION / 5))
    [ $NUM_BCAST -lt 1 ] && NUM_BCAST=1
    EXPIRATION=$((NUM_BCAST * 5 + 5))
    
    echo "Sending: $NAME (msg_id=$MSGID, code=$CODE)"
    echo "Duration: ${DURATION}s - Expiration: ${EXPIRATION}s"
    echo "Scope: $SCOPE"
    
    # Build scope JSON
    if [[ "$SCOPE" == "plmn" ]]; then
      SCOPE_JSON="\"scope_plmn\":{\"plmn\":\"$PLMN\"}"
    elif [[ "$SCOPE" == tac:* ]]; then
      TACS="${SCOPE#tac:}"
      TAI_LIST=""
      IFS=',' read -ra TAC_ARRAY <<< "$TACS"
      for tac in "${TAC_ARRAY[@]}"; do
        [ -n "$TAI_LIST" ] && TAI_LIST="$TAI_LIST,"
        TAI_LIST="$TAI_LIST{\"plmn\":\"$PLMN\",\"tac\":$tac}"
      done
      SCOPE_JSON="\"scope_tai\":{\"tai_list\":[$TAI_LIST]}"
    else
      echo "Error: Invalid scope. Use: plmn, tac:1, tac:2, tac:1,2"
      exit 1
    fi
    
    result=$(curl -s -X POST "$CBC_API" \
      -H "Content-Type: application/json" \
      -d "{\"cbe_name\":\"$NAME\",\"repetition_period\":5,\"num_of_bcast\":$NUM_BCAST,\"scope\":{$SCOPE_JSON},\"smscb_message\":{\"message_id\":$MSGID,\"serial_nr\":{\"serial_nr_decoded\":{\"geo_scope\":\"plmn_wide\",\"msg_code\":$CODE,\"update_nr\":0}},\"payload\":{\"payload_decoded\":{\"character_set\":\"gsm\",\"data_utf8\":\"$MSG\"}}}}")
    
    echo "Result: $result"
    ;;
    
  stop)
    MSGID="${2:-4370}"
    echo "Stopping msg_id=$MSGID..."
    
    messages=$( (echo "enable"; echo "show messages cbs"; sleep 0.3) | nc -q 1 $CBC_VTY 2>/dev/null | strings | grep "active" | awk -F'|' '{print $3}' | tr -d ' ')
    
    for name in $messages; do
      if [[ "$name" == *"$MSGID"* ]]; then
        echo "Deleting: $name"
        curl -s -X DELETE "$CBC_API/$name" > /dev/null
      fi
    done
    echo "Done"
    ;;
    
  list)
    output=$( (echo "enable"; echo "show messages cbs"; sleep 0.3) | nc -q 1 $CBC_VTY 2>/dev/null | strings | grep -E "^\|" )
    if [ -n "$output" ]; then
      echo "Messages:"
      echo "$output"
    else
      echo "No active messages"
    fi
    ;;
    
  *)
    echo "Usage: $0 {send|stop|list}"
    echo ""
    echo "  send \"MSG\" [msg_id] [duration] [scope]"
    echo "    scope: plmn, tac:1, tac:2, tac:1,2"
    echo ""
    echo "  stop [msg_id]"
    echo "  list"
    echo ""
    echo "Examples:"
    echo "  $0 send \"Emergency\" 4370 60"
    echo "  $0 send \"Yaounde\" 4370 60 tac:1"
    echo "  $0 send \"Douala\" 4370 60 tac:2"
    echo "  $0 send \"Both\" 4370 60 tac:1,2"
    ;;
esac
