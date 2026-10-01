#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
# F2G CMAS - Envoi d'alerte WriteReplaceWarning
#═══════════════════════════════════════════════════════════════════════════════

MESSAGE="${1:-ALERTE URGENTE F2G - Test CMAS}"
MSG_ID="${2:-4370}"
SERIAL="${3:-49153}"

echo "📤 Envoi alerte CMAS..."
echo "   Message: $MESSAGE"
echo "   Message ID: $MSG_ID"

curl -s -X POST http://127.0.0.1:12345/api/ecbe/v1/message \
  -H "Content-Type: application/json" \
  -d "{
    \"cbe_name\": \"F2G-CMAS\",
    \"repetition_period\": 5,
    \"num_bcast\": 10,
    \"scope\": {\"scope_plmn\": {\"plmn\": \"00101\"}},
    \"smscb_message\": {
      \"message_id\": $MSG_ID,
      \"serial_nr\": {\"serial_nr_encoded\": $SERIAL},
      \"payload\": {\"payload_decoded\": {\"character_set\": \"gsm\", \"data_utf8\": \"$MESSAGE\"}}
    }
  }"

echo ""
echo "✅ Alerte envoyée!"
echo ""
echo "Vérifier les logs:"
echo "  grep -i 'WriteReplace' /tmp/mme-fork.log | tail -5"
