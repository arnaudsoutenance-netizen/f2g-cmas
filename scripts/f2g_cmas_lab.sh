#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
# F2G CMAS/PWS Lab — lancement du lab CMAS de bout en bout
#   osmo-cbc ──SBc-AP──► MME (open5gs-fork) ──S1AP──► srsENB patché ──bladeRF──► UE
#
# Usage:
#   ./f2g_cmas_lab.sh start                 démarre MME fork + osmo-cbc + eNB
#   ./f2g_cmas_lab.sh stop [--docker]       arrête le lab (--docker : relance le MME Docker)
#   ./f2g_cmas_lab.sh status                état des process, liens SBc-AP / S1AP, UE
#   ./f2g_cmas_lab.sh alert [ID] ["texte"]  envoie une alerte CMAS (défaut 4370 Presidential)
#   ./f2g_cmas_lab.sh cancel [ID]           arrête l'alerte ID (Stop-Warning → Kill → SIB12 d'origine)
#   ./f2g_cmas_lab.sh pc2 start|stop|status eNB2 (Douala, TAC 2) sur PC2 via SSH (PC2_PASS=<mdp sudo>)
#   ./f2g_cmas_lab.sh logs                  suit les logs utiles en direct
#
# Validé le 2026-10-13 : alerte présidentielle affichée sur le téléphone.
#═══════════════════════════════════════════════════════════════════════════════

set -u

SESSION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG_0110="/home/f2g/Desktop/F2G_CMAS_SESSION_20261001/configs"
MME_BUILD="/home/f2g/Desktop/CMAS_Complete_Package/open5gs-fork/build"
ENB_BUILD="/home/f2g/build/srsRAN_4G/build"
ENB_BIN="$ENB_BUILD/srsenb/src/srsenb"
CBC_API="http://127.0.0.1:12345/api/ecbe/v1/message"

RUN="/tmp/f2g_cmas"          # logs + pid files
PC1_LAN_IP="192.168.1.100"   # PC1 on the PC1<->PC2 Ethernet cable
PC2="f2g@192.168.1.101"      # eNB2 (Douala, TAC 2, PCI 2, eNB ID 0x19C)
PC2_ENB="/home/f2g/build/srsRAN_4G/build/srsenb/src/srsenb"   # patched build on PC2
SERIAL_FILE="$RUN/serial_counter"

G='\033[0;32m'; R='\033[0;31m'; Y='\033[1;33m'; N='\033[0m'
ok()   { echo -e "${G}✅ $*${N}"; }
ko()   { echo -e "${R}❌ $*${N}"; }
warn() { echo -e "${Y}⚠️  $*${N}"; }

# Waits until "$2" (a command) succeeds, at most $1 seconds
wait_for() {
    local timeout=$1; shift
    for _ in $(seq "$timeout"); do
        if eval "$@" >/dev/null 2>&1; then return 0; fi
        sleep 1
    done
    return 1
}

pid_alive() { [ -f "$RUN/$1.pid" ] && sudo kill -0 "$(cat "$RUN/$1.pid")" 2>/dev/null; }

prepare() {
    mkdir -p "$RUN"
    # Configs proven on 01/10 (freeDiameter, CBC, eNB) + MME yaml of 13/10 (GTP-C on 172.22.0.1)
    rm -rf /tmp/mme-sbcap 2>/dev/null || sudo rm -rf /tmp/mme-sbcap
    cp -r "$CFG_0110/mme-sbcap" /tmp/mme-sbcap
    cp "$CFG_0110/mme-sbcap/freeDiameter/mme.conf" /tmp/mme-fork-fd.conf 2>/dev/null || \
        sudo cp "$CFG_0110/mme-sbcap/freeDiameter/mme.conf" /tmp/mme-fork-fd.conf
    sed "s#path: /tmp/mme-fork.log#path: $RUN/mme.log#" "$SESSION_DIR/mme-fork.yaml" > "$RUN/mme.yaml"
    # PC2 cable unplugged: do not listen on the LAN address (the MME would fail to bind)
    if ! ip -br addr | grep -q "$PC1_LAN_IP/"; then
        warn "câble PC2 débranché ($PC1_LAN_IP absente) → S1AP sur 127.0.0.2 seulement"
        sed -i "/address: $PC1_LAN_IP/,+1d" "$RUN/mme.yaml"
    fi
    mkdir -p "$RUN/cbc" && cp "$CFG_0110/cbc/osmo-cbc.cfg" "$RUN/cbc/osmo-cbc.cfg"
    sed "s#filename = .*#filename = $RUN/enb.log#" "$SESSION_DIR/enb_sbcap.conf" > "$RUN/enb.conf"

    sudo ip addr add 127.0.0.2/8 dev lo 2>/dev/null || true
    sudo ip addr add 127.0.0.10/8 dev lo 2>/dev/null || true
}

start_mme() {
    local L="$MME_BUILD/lib" FD="$MME_BUILD/subprojects/freeDiameter"
    local LDP="$L:$L/sbcap:$L/s1ap:$L/diameter/s6a:$L/diameter/common:$L/gtp:$L/nas/eps:$L/nas/common:$L/core:$L/crypt:$L/sctp:$L/app:$L/proto:$L/asn1c/s1ap:$L/asn1c/sbcap:$L/asn1c/common:$L/asn1c/util:$FD/libfdcore:$FD/libfdproto"
    sudo bash -c "LD_LIBRARY_PATH='$LDP' nohup '$MME_BUILD/src/mme/open5gs-mmed' -c '$RUN/mme.yaml' \
        > '$RUN/mme.stdout' 2>&1 & echo \$! > '$RUN/mme.pid'"
}

cmd_start() {
    echo "════════ F2G CMAS LAB — START ════════"

    # 1. The Docker MME holds S1AP port 36412: stop it (restored with 'stop --docker')
    if docker ps --format '{{.Names}}' | grep -qx mme; then
        docker stop mme >/dev/null && ok "MME Docker arrêté (port 36412 libéré)"
    fi
    for c in sgwc sgwu smf upf; do
        docker ps --format '{{.Names}}' | grep -qx "$c" || warn "conteneur Docker '$c' non actif (attach UE impossible)"
    done
    if pid_alive mme || pid_alive cbc || pid_alive enb; then
        warn "lab déjà (partiellement) lancé → ./$(basename "$0") stop d'abord"; exit 1
    fi
    lsusb | grep -qi nuand || warn "bladeRF non détecté (lsusb)"

    prepare

    # 2. MME (open5gs fork, SBc-AP fixes)
    start_mme
    if wait_for 10 "grep -q 's1ap_server()' '$RUN/mme.log'"; then ok "MME fork démarré (S1AP 127.0.0.2:36412, SBc-AP :29168, GTP-C 172.22.0.1)"
    else ko "MME n'a pas démarré — voir $RUN/mme.stdout"; tail -5 "$RUN/mme.stdout"; exit 1; fi

    # 3. osmo-cbc
    sudo bash -c "nohup osmo-cbc -c '$RUN/cbc/osmo-cbc.cfg' > '$RUN/cbc.log' 2>&1 & echo \$! > '$RUN/cbc.pid'"
    if wait_for 15 "grep -q 'f2g-mme: Connected' '$RUN/cbc.log'"; then ok "osmo-cbc connecté au MME (SBc-AP), API REST 127.0.0.1:12345"
    else ko "osmo-cbc non connecté — voir $RUN/cbc.log"; exit 1; fi

    # 4. srsENB (patched: live SIB12 + CMAS paging)
    sudo bash -c "cd '$ENB_BUILD' || exit 1; nohup '$ENB_BIN' '$RUN/enb.conf' > '$RUN/enb.stdout' 2>&1 & echo \$! > '$RUN/enb.pid'"
    if wait_for 40 "grep -q 'eNB-S1 accepted' '$RUN/mme.log'"; then ok "eNB connecté au MME (S1 Setup) — bladeRF en émission"
    else ko "eNB non connecté — voir $RUN/enb.stdout"; tail -5 "$RUN/enb.stdout"; exit 1; fi

    echo
    ok "LAB PRÊT. Allume le téléphone (4G, réseau 00101), puis :"
    warn "Téléphone déjà enregistré avant le redémarrage ? Mode avion ON/OFF, sinon il reste bloqué"
    warn "en Service reject (le nouveau MME ne le connaît pas)."
    echo "   ./$(basename "$0") status          → vérifier que l'UE est attaché"
    echo "   ./$(basename "$0") alert           → alerte présidentielle 4370"
    echo "   ./$(basename "$0") alert 4371 \"texte\""
}

cmd_stop() {
    echo "════════ F2G CMAS LAB — STOP ════════"
    for p in enb cbc mme; do
        if pid_alive "$p"; then
            sudo kill -INT "$(cat "$RUN/$p.pid")"
            wait_for 10 "! sudo kill -0 $(cat "$RUN/$p.pid")" || sudo kill -9 "$(cat "$RUN/$p.pid")" 2>/dev/null
            ok "$p arrêté"
        fi
        rm -f "$RUN/$p.pid" 2>/dev/null || sudo rm -f "$RUN/$p.pid"
    done
    if [ "${1:-}" = "--docker" ]; then
        docker start mme >/dev/null && ok "MME Docker relancé"
    else
        warn "MME Docker toujours arrêté (relancer : docker start mme, ou stop --docker)"
    fi
}

cmd_status() {
    echo "════════ F2G CMAS LAB — STATUS ════════"
    for p in mme cbc enb; do
        if pid_alive "$p"; then ok "$p actif (pid $(cat "$RUN/$p.pid"))"; else ko "$p arrêté"; fi
    done
    [ -f "$RUN/cbc.log" ] && { sed 's/\x1b\[[0-9;]*m//g' "$RUN/cbc.log" | grep -E "f2g-mme: (Connected|Disconnected)" | tail -1; }
    [ -f "$RUN/mme.log" ] && {
        echo "-- eNB / UE (MME) :"
        sed 's/\x1b\[[0-9;]*m//g' "$RUN/mme.log" | grep -E "eNB-S1 (accepted|removed)|Attach complete|Detach request" | tail -4
    }
    [ -f "$RUN/enb.log" ] && { echo "-- dernières alertes (eNB) :"; grep -E "PWS: CMAS Alert Broadcast|PWS paging" "$RUN/enb.log" | tail -2; }
}

cmd_alert() {
    local msg_id="${1:-4370}"
    local text="${2:-F2G ALERTE TEST}"
    mkdir -p "$RUN"
    # New serial (msg_code) each time, otherwise the UE drops it as a duplicate
    local code; code=$(( ( $(cat "$SERIAL_FILE" 2>/dev/null || echo 200) + 1 ) % 1024 ))
    echo "$code" > "$SERIAL_FILE"

    # osmo-cbc refuses a message_id that is still active (HTTP 409): delete it first
    curl -s -o /dev/null -X DELETE "$CBC_API/$msg_id" || true

    local before; before=$(grep -a -c "PWS paging: cmas" "$RUN/enb.log" 2>/dev/null || echo 0)
    local http
    http=$(curl -s -o "$RUN/alert_resp.txt" -w "%{http_code}" -X POST "$CBC_API" \
        -H "Content-Type: application/json" \
        -d "{\"cbe_name\":\"F2G-$msg_id-$code\",\"repetition_period\":5,\"num_bcast\":10,
             \"scope\":{\"scope_plmn\":{\"plmn\":\"00101\"}},
             \"smscb_message\":{\"message_id\":$msg_id,
               \"serial_nr\":{\"serial_nr_decoded\":{\"geo_scope\":\"plmn_wide\",\"msg_code\":$code,\"update_nr\":0}},
               \"payload\":{\"payload_decoded\":{\"character_set\":\"gsm\",\"data_utf8\":\"$text\"}}}}")
    if [ "$http" != "201" ]; then ko "osmo-cbc HTTP $http : $(cat "$RUN/alert_resp.txt")"; exit 1; fi
    ok "alerte $msg_id envoyée (msg_code=$code) : \"$text\""

    # osmo-cbc names the message "<cbe_name>-<message_id>"
    if wait_for 10 "grep -a 'SMSCB(F2G-$msg_id-$code-$msg_id)' '$RUN/cbc.log' | grep -q 'Received Event WRITE_ACK'"; then
        ok "CBC : WRITE_ACK"
    else ko "CBC : pas de WRITE_ACK"; fi
    # srsRAN log is flushed asynchronously: allow up to 15 s
    if wait_for 15 "[ \$(grep -a -c 'PWS paging: cmas' '$RUN/enb.log') -gt $before ]"; then
        ok "eNB : SIB12 à l'antenne + paging cmas-Indication"
    else ko "eNB : SIB12 non diffusé — voir $RUN/enb.log"; fi
}

cmd_cancel() {
    local msg_id="${1:-4370}"
    local before; before=$(grep -a -c "SIB12 restored" "$RUN/enb.log" 2>/dev/null || echo 0)
    local http
    http=$(curl -s -o "$RUN/cancel_resp.txt" -w "%{http_code}" -X DELETE "$CBC_API/$msg_id")
    if [ "$http" != "200" ]; then ko "osmo-cbc HTTP $http : $(cat "$RUN/cancel_resp.txt")"; exit 1; fi
    ok "Stop-Warning $msg_id demandé au CBC"
    if wait_for 10 "sed 's/\\x1b\\[[0-9;]*m//g' '$RUN/mme.log' | grep -q 'Tx Stop-Warning-Response'"; then
        ok "MME : Stop-Warning-Response envoyé au CBC (Kill transmis aux eNB)"
    else ko "MME : pas de Stop-Warning-Response"; fi
    if wait_for 15 "[ \$(grep -a -c 'SIB12 restored' '$RUN/enb.log') -gt $before ]"; then
        ok "eNB : alerte retirée, SIB12 d'origine remis"
    else ko "eNB : alerte non retirée — voir $RUN/enb.log"; fi
}

pc2_sudo() {
    # sudo password of PC2 is read from $PC2_PASS (never stored in this script)
    if [ -z "${PC2_PASS:-}" ]; then ko "export PC2_PASS=<mot de passe sudo de PC2> d'abord"; exit 1; fi
    ssh -o ConnectTimeout=5 "$PC2" "echo '$PC2_PASS' | sudo -S -p '' bash -c \"$1\""
}

cmd_pc2() {
    case "${1:-status}" in
        start)
            ping -c1 -W1 "${PC2#*@}" >/dev/null || { ko "PC2 injoignable (câble ?)"; exit 1; }
            # stop a running eNB2 first (SIGINT, wait), otherwise the bladeRF stays busy
            pc2_sudo "pkill -INT -x srsenb; for i in \\\$(seq 20); do pgrep -x srsenb >/dev/null || break; sleep 1; done; pkill -9 -x srsenb; true"
            local before; before=$(grep -a -c "eNB-S1 accepted\[${PC2#*@}" "$RUN/mme.log" 2>/dev/null || echo 0)
            pc2_sudo "rm -f /tmp/enb2.log; cd /home/f2g/.config/srsran && nohup $PC2_ENB enb.conf > /tmp/enb2.stdout 2>&1 & echo \\\$! > /tmp/enb2.pid"
            if wait_for 40 "[ \$(grep -a -c 'eNB-S1 accepted\[${PC2#*@}' '$RUN/mme.log') -gt $before ]"; then ok "eNB2 (PC2, TAC 2) connecté au MME"
            else ko "eNB2 non connecté — voir PC2:/tmp/enb2.stdout et $RUN/mme.log (Served TAI ?)"; fi ;;
        stop)
            pc2_sudo "pkill -INT -x srsenb" && ok "eNB2 arrêté" ;;
        status)
            ssh -o ConnectTimeout=5 "$PC2" 'pgrep -a -x srsenb || echo "srsenb arrêté"; grep -a "PWS: CMAS Alert" /tmp/enb2.log 2>/dev/null | tail -1' ;;
    esac
}

cmd_logs() {
    tail -n0 -F "$RUN/enb.log" "$RUN/mme.log" "$RUN/cbc.log" 2>/dev/null | sed -u 's/\x1b\[[0-9;]*m//g' |
        grep --line-buffered -E "PWS|SIB12|Attach (complete|request)|Detach|SBc-AP\]|WRITE_ACK|WRITE_NACK|Timeout|eNB-S1|ERROR|\[E\]"
}

case "${1:-}" in
    start)  cmd_start ;;
    stop)   shift; cmd_stop "${1:-}" ;;
    status) cmd_status ;;
    alert)  shift; cmd_alert "${1:-}" "${2:-}" ;;
    cancel) shift; cmd_cancel "${1:-}" ;;
    pc2)    shift; cmd_pc2 "${1:-}" ;;
    logs)   cmd_logs ;;
    *) sed -n '2,16p' "$0"; exit 1 ;;
esac
