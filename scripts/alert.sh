#!/bin/bash
# /tmp/alert.sh - 3GPP compliant CMAS via osmo-cbc
# Usage: /tmp/alert.sh send "MESSAGE" [msg_id] [duration_sec]
#        /tmp/alert.sh stop [msg_id]
#        /tmp/alert.sh list

CBC_API="http://127.0.0.1:12345/api/ecbe/v1/message"
CBC_VTY="127.0.0.1 4264"

# Persistent code counter
CODE_FILE="/tmp/.alert_code"
[ -f "$CODE_FILE" ] || echo "1" > "$CODE_FILE"

case "$1" in
  send)
    MSG="${2:-CMAS Test Alert}"
    MSGID="${3:-4370}"
    DURATION="${4:-30}"
    
    # Increment code for unique serial_nr
    CODE=$(cat "$CODE_FILE")
    echo $((CODE + 1)) > "$CODE_FILE"
    
    NAME="alert${MSGID}c${CODE}"
    
    # Calculate num_bcast (5 sec period)
    NUM_BCAST=$((DURATION / 5))
    [ $NUM_BCAST -lt 1 ] && NUM_BCAST=1
    
    echo "Sending: $NAME (msg_id=$MSGID, code=$CODE)"
    echo "Duration: ${DURATION}s - Auto-expiration: $((NUM_BCAST * 5 + 5))s"
    
    result=$(curl -s -X POST "$CBC_API" \
      -H "Content-Type: application/json" \
      -d "{\"cbe_name\":\"$NAME\",\"repetition_period\":5,\"num_of_bcast\":$NUM_BCAST,\"scope\":{\"scope_plmn\":{\"plmn\":\"00101\"}},\"smscb_message\":{\"message_id\":$MSGID,\"serial_nr\":{\"serial_nr_decoded\":{\"geo_scope\":\"plmn_wide\",\"msg_code\":$CODE,\"update_nr\":0}},\"payload\":{\"payload_decoded\":{\"character_set\":\"gsm\",\"data_utf8\":\"$MSG\"}}}}")
    
    echo "Result: $result"
    
    if echo "$result" | grep -q "Created"; then
      echo "Alert active"
    else
      echo "Failed"
    fi
    ;;
    
  stop)
    MSGID="${2:-4370}"
    echo "Stopping msg_id=$MSGID..."
    
    # Find active message via VTY
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
    # Use VTY to list messages
    output=$( (echo "enable"; echo "show messages cbs"; sleep 0.3) | nc -q 1 $CBC_VTY 2>/dev/null | strings | grep -E "^\|" )
    
    if [ -z "$output" ]; then
      echo "No messages"
    else
      echo "Messages:"
      echo "$output"
    fi
    ;;
    
  *)
    echo "Usage: $0 {send|stop|list} [args]"
    echo "  send \"MESSAGE\" [msg_id] [duration_sec]"
    echo "  stop [msg_id]"
    echo "  list"
    ;;
esac
