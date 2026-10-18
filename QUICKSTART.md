# F2G CMAS Lab — Quick Start Guide

## Prérequis

- Ubuntu 22.04+
- Docker + docker-compose
- srsRAN 4G patché (branche feat/pws-sib12-live-broadcast)
- Open5GS MME patché (avec SBc-AP)
- osmo-cbc patché

## Démarrage rapide (5 minutes)

### 1. Core Network Docker
```bash
cd /home/f2g/docker_open5gs
docker-compose up -d hss sgwc sgwu smf upf
```

### 2. MME patché (avec SBc-AP)
```bash
# Copier les configs
mkdir -p /tmp/f2g_cmas
cp configs/runtime/* /tmp/f2g_cmas/

# Lancer le MME
sudo /usr/local/bin/open5gs-mmed -c /tmp/f2g_cmas/mme.yaml &
```

### 3. Cell Broadcast Centre
```bash
/usr/bin/osmo-cbc-patched -c /tmp/f2g_cmas/osmo-cbc.cfg &
```

### 4. eNB (PC1)
```bash
cd /home/f2g/srsran_ho
sudo /home/f2g/build/srsRAN_4G/build/srsenb/src/srsenb enb1.conf
```

### 5. Envoyer une alerte
```bash
# Alerte sur tout le réseau
./alert.sh send "ALERTE URGENTE" 4370 60 plmn

# Alerte ciblée TAC 1
./alert.sh send "ALERTE YAOUNDE" 4370 60 tac:1

# Lister les alertes
./alert.sh list

# Arrêter une alerte
./alert.sh stop 4370
```

## Vérification

```bash
# CBC actif ?
pgrep -a osmo-cbc

# MME actif ?
pgrep -a open5gs-mmed

# Peers SBc-AP ?
(echo "enable"; echo "show peers") | nc -q1 127.0.0.1 4264

# Capture Wireshark
sudo wireshark -i any -k -Y "s1ap or sbcap"
```

## Message IDs

| ID | Type |
|----|------|
| 4370 | Presidential Alert |
| 4380 | Test Alert |

## Contacts

**F2G Solutions** — Arnaud DJOUM
- Email: arnaud@f2g.cm
- Lab: Yaoundé, Cameroun
