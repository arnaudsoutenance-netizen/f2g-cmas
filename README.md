# F2G CMAS/PWS System

![PKF Telco](https://img.shields.io/badge/PKF-Telco-blue)
![LTE](https://img.shields.io/badge/LTE-4G-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## 🚨 Cell Broadcast Emergency Alert System

Système complet d'alertes d'urgence CMAS (Commercial Mobile Alert System) / PWS (Public Warning System) pour réseau LTE privé.

### Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   API REST  │────▶│  osmo-cbc   │────▶│  Open5GS    │────▶│  srsRAN     │────▶ UE
│   (curl)    │     │  (CBC)      │     │  MME        │     │  eNB        │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
                         │                    │                    │
                    SBc-AP (29168)      S1AP (36412)          SIB12 (Air)
```

### Composants

| Composant | Version | Rôle |
|-----------|---------|------|
| Open5GS | PR #4864 | MME avec support SBc-AP |
| osmo-cbc | latest | Cell Broadcast Centre |
| srsRAN 4G | pws-cmas-support | eNB avec génération SIB12 |

### Quick Start

```bash
# 1. Démarrer le Core Network Docker
cd /home/f2g/docker_open5gs
docker-compose up -d mongo hss sgwc sgwu smf upf

# 2. Démarrer le MME
/usr/local/bin/open5gs-mmed -c configs/mme/mme-sbcap.yaml &

# 3. Démarrer osmo-cbc
cd configs/cbc && osmo-cbc -c osmo-cbc.cfg &

# 4. Démarrer l'eNB
cd configs/enb && sudo srsenb enb.conf &

# 5. Envoyer une alerte
./scripts/alert.sh send "ALERTE URGENCE" 4370 60 tac:1
```

### Documentation

📄 **Guide complet** : [docs/CMAS_PKF_TELCO_GUIDE.pdf](docs/CMAS_PKF_TELCO_GUIDE.pdf)

### Structure du projet

```
f2g-cmas/
├── configs/
│   ├── mme/
│   │   ├── mme-sbcap.yaml      # Config MME avec SBc-AP
│   │   └── mme-fork-fd.conf    # Config freeDiameter
│   ├── cbc/
│   │   └── osmo-cbc.cfg        # Config Cell Broadcast Centre
│   └── enb/
│       ├── enb.conf            # Config eNB srsRAN
│       └── sib_pws.conf        # Config SIB avec SIB12
├── scripts/
│   └── alert.sh                # Script d'envoi d'alertes
├── docs/
│   ├── CMAS_PKF_TELCO_GUIDE.pdf  # Guide complet (24 pages)
│   └── CMAS_PKF_TELCO_GUIDE.tex  # Source LaTeX
├── patches/                    # Patches srsRAN si nécessaire
├── diagrams/                   # Diagrammes d'architecture
├── pcap/                       # Captures réseau exemples
└── images/                     # Screenshots
```

### Commandes d'alertes

```bash
# Envoyer une alerte sur TAC 1
./scripts/alert.sh send "MESSAGE D'URGENCE" 4370 60 tac:1

# Envoyer une alerte sur TAC 2
./scripts/alert.sh send "ALERTE SEISME" 4370 120 tac:2

# Lister les alertes actives
./scripts/alert.sh list

# Stopper une alerte
./scripts/alert.sh stop 4370
```

### Message IDs (3GPP TS 23.041)

| ID | Type | Description |
|----|------|-------------|
| 4370 | Presidential | Alerte présidentielle |
| 4371-4372 | Extreme | Menace extrême |
| 4373-4378 | Severe | Menace sévère |
| 4379-4392 | Amber | Alerte enlèvement |

### Références

- [3GPP TS 23.041](https://www.3gpp.org/DynaReport/23041.htm) - Cell Broadcast Service
- [3GPP TS 29.168](https://www.3gpp.org/DynaReport/29168.htm) - SBc-AP Interface
- [3GPP TS 36.331](https://www.3gpp.org/DynaReport/36331.htm) - RRC Protocol (SIB12)
- [Open5GS](https://open5gs.org/)
- [srsRAN](https://www.srsran.com/)
- [osmo-cbc](https://osmocom.org/projects/osmo-cbc)

### Auteur

**Arnaud DJOUM** — F2G / PKF Telco — Cameroun

### License

MIT License - voir [LICENSE](LICENSE)
