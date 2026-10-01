#!/bin/bash
#═══════════════════════════════════════════════════════════════
#  COLLECTE LOGS CMAS MULTI-TAC
#  PC1: 192.168.1.100 | PC2: 192.168.1.101
#═══════════════════════════════════════════════════════════════

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="/home/f2g/Desktop/CMAS_Logs_$TIMESTAMP"
mkdir -p "$LOG_DIR"

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     COLLECTE LOGS CMAS - $TIMESTAMP                       ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "📁 Dossier: $LOG_DIR"
echo ""

# 1. Logs MME
echo "=== 1. Collecte logs MME ==="
docker logs mme > "$LOG_DIR/mme_full.log" 2>&1
docker logs mme 2>&1 | grep -iE "pws|cmas|sbc|cbc|write|kill|warning|alert|TAC" > "$LOG_DIR/mme_cmas.log"
echo "✅ mme_full.log + mme_cmas.log"

# 2. Logs eNB1 (local)
echo "=== 2. Collecte logs eNB1 (PC1) ==="
cp /tmp/enb_tac1.log "$LOG_DIR/enb1_tac1.log" 2>/dev/null || echo "⚠️ Log eNB1 non trouvé"
cp /tmp/enb_tac1.pcap "$LOG_DIR/enb1_tac1.pcap" 2>/dev/null || echo "⚠️ PCAP eNB1 non trouvé"

# 3. Logs eNB2 (PC2)
echo "=== 3. Collecte logs eNB2 (PC2) ==="
sshpass -p "1234" scp f2g@192.168.1.101:/tmp/enb2.log "$LOG_DIR/enb2_tac2.log" 2>/dev/null || echo "⚠️ Log eNB2 non trouvé"

# 4. Config utilisée
echo "=== 4. Copie configs ==="
cp /home/f2g/Telecom/Core-Network/docker_open5gs/srsran/sib_tac1_cmas.conf "$LOG_DIR/config_sib_tac1.conf" 2>/dev/null
sshpass -p "1234" scp f2g@192.168.1.101:/home/f2g/.config/srsran/sib.conf "$LOG_DIR/config_sib_tac2.conf" 2>/dev/null

# 5. Résumé TAC
echo "=== 5. Génération résumé TAC ==="
cat > "$LOG_DIR/RESUME_TAC.txt" << RESUME
═══════════════════════════════════════════════════════════════
              RÉSUMÉ ATTACHEMENTS PAR TAC
              $(date '+%Y-%m-%d %H:%M:%S')
═══════════════════════════════════════════════════════════════

=== UE sur TAC 1 (Yaoundé - eNB1) ===
$(docker logs mme 2>&1 | grep "TAC\[1\]" | tail -10)

=== UE sur TAC 2 (Douala - eNB2) ===
$(docker logs mme 2>&1 | grep "TAC\[2\]" | tail -10)

=== Statistiques ===
TAC 1: $(docker logs mme 2>&1 | grep "TAC\[1\]" | wc -l) attachements
TAC 2: $(docker logs mme 2>&1 | grep "TAC\[2\]" | wc -l) attachements

═══════════════════════════════════════════════════════════════
RESUME

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ COLLECTE TERMINÉE"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "📁 Fichiers générés:"
ls -la "$LOG_DIR/"
echo ""
echo "📂 Ouvrir le dossier: nautilus '$LOG_DIR'"
