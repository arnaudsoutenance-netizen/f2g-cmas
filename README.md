# F2G CMAS Lab — Cell Broadcast Emergency Alerts

## Overview

Système d'alertes d'urgence CMAS (Commercial Mobile Alert System) conforme 3GPP pour réseaux LTE privés.

**Flow complet validé :**
```
CBE (alert.sh) → osmo-cbc (REST) → MME (SBc-AP) → eNB (S1AP WriteReplaceWarning) → UE (SIB12)
```

## Architecture

| Composant | Binaire | Port | Rôle |
|-----------|---------|------|------|
| MME patché | `/usr/local/bin/open5gs-mmed` | S1AP:36412, SBc-AP:29168 | Core EPC avec support SBc-AP |
| osmo-cbc | `/usr/bin/osmo-cbc-patched` | REST:12345, VTY:4264 | Cell Broadcast Centre |
| eNB1 (PC1) | srsRAN patché | - | TAC 1 (Yaoundé) |
| eNB2 (PC2) | srsRAN patché | - | TAC 2 (Douala) |
| HSS | Docker Open5GS | Diameter:3868 | Authentification |

## Quick Start

### 1. Lancer le Core Network Docker
```bash
cd /home/f2g/docker_open5gs
docker-compose up -d
```

### 2. Lancer le MME patché
```bash
sudo /usr/local/bin/open5gs-mmed -c /tmp/f2g_cmas/mme.yaml &
```

### 3. Lancer osmo-cbc
```bash
/usr/bin/osmo-cbc-patched -c /tmp/f2g_cmas/osmo-cbc.cfg &
```

### 4. Lancer les eNBs
```bash
# PC1 - eNB1
cd /home/f2g/srsran_ho && sudo ./srsenb enb1.conf

# PC2 - eNB2
ssh f2g@192.168.1.101 "cd /home/f2g/srsran_ho && sudo ./srsenb enb2.conf"
```

### 5. Envoyer une alerte
```bash
# Alerte Presidential sur tout le réseau
/tmp/alert.sh send "MESSAGE D'URGENCE" 4370 60 plmn

# Alerte ciblée TAC 1
/tmp/alert.sh send "ALERTE YAOUNDE" 4370 60 tac:1

# Alerte ciblée TAC 2
/tmp/alert.sh send "ALERTE DOUALA" 4370 60 tac:2

# Lister les alertes actives
/tmp/alert.sh list

# Arrêter une alerte
/tmp/alert.sh stop 4370
```

## Message IDs (3GPP TS 23.041)

| ID | Hex | Type |
|----|-----|------|
| 4370 | 0x1112 | Presidential Alert |
| 4371-4379 | - | Extreme/Severe Alerts |
| 4380 | 0x111C | Test Alert |

## Fichiers de Configuration

```
configs/runtime/
├── mme.yaml          # Config MME Open5GS
├── mme-fd.conf       # FreeDiameter (identité 3GPP)
├── osmo-cbc.cfg      # Cell Broadcast Centre
├── enb1.conf         # eNB1 TAC=1
├── enb2.conf         # eNB2 TAC=2
└── sib.conf          # SIB config avec SIB12
```

## Diagnostic

```bash
# Vérifier CBC
pgrep -a osmo-cbc
(echo "enable"; echo "show peers") | nc -q1 127.0.0.1 4264

# Vérifier MME
pgrep -a open5gs-mmed
ss -Slnp | grep -E "29168|36412"

# Capture Wireshark
sudo wireshark -i any -k -Y "s1ap or sbcap or sctp"
```

## Références 3GPP

- **TS 23.041** — Cell Broadcast Service
- **TS 29.168** — SBc Interface (CBC-MME)
- **TS 36.413** — S1AP (WriteReplaceWarning)
- **TS 36.331** — RRC (SIB12)

## Auteur

**F2G Solutions** — Arnaud DJOUM  
Lab Télécom Cameroun — Octobre 2026
