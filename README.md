# CMAS/PWS Cell Broadcast Emergency Alert System — Open5GS + srsRAN

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![3GPP Release](https://img.shields.io/badge/3GPP-Rel--15-blue.svg)](https://www.3gpp.org/)
[![Open5GS](https://img.shields.io/badge/Open5GS-v2.7-green.svg)](https://open5gs.org/)
[![srsRAN](https://img.shields.io/badge/srsRAN-v23.11-orange.svg)](https://www.srsran.com/)

Complete implementation of **Cell Broadcast Service (CBS)** for emergency alerts on a private LTE network using Open5GS and srsRAN with bladeRF SDR.

## 🎯 Objective

Enable **Write-Replace-Warning** message broadcast to all UEs in a cell for emergency alerts:
- **CMAS** (Commercial Mobile Alert System) — Presidential, AMBER, Extreme/Severe threats
- **ETWS** (Earthquake and Tsunami Warning System) — Immediate seismic alerts
- **PWS** (Public Warning System) — Generic emergency broadcast

## 📊 Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    CELL BROADCAST ARCHITECTURE                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────────────┐  │
│   │   CBC    │────▶│   MME    │────▶│   eNB    │────▶│    UE Phones     │  │
│   │ (Alert   │     │ (Core    │     │ (Radio   │     │ (Receive Alert)  │  │
│   │  Center) │     │ Network) │     │  Tower)  │     │                  │  │
│   └──────────┘     └──────────┘     └──────────┘     └──────────────────┘  │
│                                                                              │
│   Protocol:         SBc/SBCAP        S1AP             SIB10/11/12           │
│                                                                              │
│   Message:      Write-Replace    WriteReplace       System Info            │
│                 Warning-Request  WarningRequest     Broadcast              │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Network Topology

```
┌─────────────────┐                    ┌─────────────────────────────────────┐
│       PC1       │                    │         DOCKER (172.22.0.x)         │
│  192.168.1.100  │                    │                                     │
│  ┌───────────┐  │      S1AP/SCTP     │  ┌─────┐  ┌─────┐  ┌─────┐        │
│  │  srsENB   │──┼────────────────────┼──│ MME │  │ HSS │  │PCRF │        │
│  │           │  │                    │  │ .9  │  │ .3  │  │ .4  │        │
│  │ bladeRF   │  │                    │  └─────┘  └─────┘  └─────┘        │
│  │   xA4     │  │                    │                                     │
│  └─────┬─────┘  │                    │  ┌─────┐  ┌─────┐  ┌─────┐        │
│        │ RF     │                    │  │SGWC │  │SGWU │  │ UPF │        │
│        ▼        │                    │  │ .5  │  │ .6  │  │ .8  │        │
│  ┌───────────┐  │                    │  └─────┘  └─────┘  └─────┘        │
│  │   UEs     │  │                    │                                     │
│  │ (Phones)  │  │                    │  ┌─────────────────────────────┐   │
│  └───────────┘  │                    │  │          IMS (VoLTE)        │   │
│                 │                    │  │ PCSCF .21  SCSCF .20        │   │
└─────────────────┘                    │  └─────────────────────────────┘   │
                                       └─────────────────────────────────────┘
```

## 📋 Alert Types

### CMAS — Commercial Mobile Alert System (SIB12)

| Alert Type | Message ID | Disable? | Use Case |
|------------|------------|----------|----------|
| **Presidential** | 4370 | ❌ NO | National emergencies, cannot be opted out |
| **Extreme Threat** | 4371-4372 | ✅ Yes | Imminent life-threatening danger |
| **Severe Threat** | 4373-4378 | ✅ Yes | Significant threat to life/property |
| **AMBER Alert** | 4379 | ✅ Yes | Child abduction |
| **Public Safety** | 4383-4391 | ✅ Yes | General safety messages |
| **Test** | 4380 | ✅ Yes | Monthly required tests |

### ETWS — Earthquake & Tsunami Warning (SIB10/11)

| Alert Type | Message ID | Delivery Time |
|------------|------------|---------------|
| **Earthquake** | 4352 | < 4 seconds |
| **Tsunami** | 4353 | < 4 seconds |
| **Combined** | 4354 | < 4 seconds |

## 🚀 Quick Start

### 1. Start Core Network

```bash
cd /home/f2g/Telecom/Core-Network/openimss
docker-compose up -d
```

### 2. Start eNB with PWS Config

```bash
sudo srsenb /home/f2g/Desktop/CMAS-PWS/configs/srsran/enb_pws.conf
```

### 3. Send Alert

```bash
# Presidential Alert
./scripts/send_alert.sh presidential "NATIONAL EMERGENCY - This is a test"

# AMBER Alert
./scripts/send_alert.sh amber "AMBER Alert - Missing child in Yaoundé"

# Earthquake Alert
./scripts/send_alert.sh earthquake "EARTHQUAKE WARNING - Take cover immediately"
```

## 📁 Repository Structure

```
CMAS-PWS/
├── README.md                         # This file
├── LICENSE
├── configs/
│   ├── srsran/
│   │   ├── enb_pws.conf             # eNB config with PWS enabled
│   │   ├── enb_tac1_cmas.conf       # TAC 1 (Yaoundé) config
│   │   ├── enb_tac2_cmas.conf       # TAC 2 (Douala) config
│   │   ├── sib_pws.conf             # SIB with SIB10/11/12 enabled
│   │   └── sib_cmas.conf            # CMAS-specific SIB config
│   └── open5gs/
│       └── mme.yaml                 # MME config for PWS
├── docs/
│   ├── SPECIFICATION.md             # What the system does
│   ├── IMPLEMENTATION.md            # How to build it
│   ├── COMPLETE_SETUP.md            # Full configuration guide
│   └── MANUAL_LAUNCH_GUIDE.md       # Step-by-step launch procedure
├── procedures/
│   ├── 01-PREREQUISITES.md
│   ├── 02-INSTALLATION.md
│   ├── 03-ENB-CONFIGURATION.md
│   ├── 04-ALERT-INJECTION.md
│   ├── 05-TESTING.md
│   └── 06-TROUBLESHOOTING.md
├── scripts/
│   ├── send_alert.sh                # Main alert sending script
│   ├── inject_write_replace_warning.py
│   └── start_cmas_lab.sh            # Lab startup script
├── diagrams/
│   └── pws_message_flow.md          # Mermaid sequence diagrams
├── images/
│   └── architecture_diagram.png
├── pcap/
│   └── CMAS_WriteReplaceWarning.pcap
└── logs/
    └── mme_cmas.log
```

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [SPECIFICATION.md](docs/SPECIFICATION.md) | Goals, non-goals, success criteria |
| [IMPLEMENTATION.md](docs/IMPLEMENTATION.md) | Technical implementation details |
| [COMPLETE_SETUP.md](docs/COMPLETE_SETUP.md) | Full configuration with all parameters |
| [MANUAL_LAUNCH_GUIDE.md](docs/MANUAL_LAUNCH_GUIDE.md) | Step-by-step launch with Wireshark |

## 🔧 Key Configuration

### eNB Configuration (enb_pws.conf)

```ini
[enb]
enb_id = 0x19B
mcc = 001
mnc = 01
mme_addr = 172.22.0.9
n_prb = 50

[enb_files]
sib_config = sib_pws.conf

[rf]
dl_earfcn = 1450
device_name = bladeRF
```

### SIB Configuration for PWS

```
sib10 = {
    messageIdentifier = 0x1112;
    serialNumber = 0x3000;
    warningType = "earthquake";
}

sib12 = {
    messageIdentifier = 0x1112;
    serialNumber = 0x3000;
    warningMessageSegmentType = "notLastSegment";
    warningMessageSegmentNumber = 0;
    warningMessageSegment = "EMERGENCY ALERT";
}
```

## 📡 3GPP Specifications

| Specification | Title |
|---------------|-------|
| TS 23.041 | Technical realization of Cell Broadcast Service (CBS) |
| TS 23.038 | Alphabets and language-specific information |
| TS 36.331 | E-UTRA RRC Protocol specification (SIB10/11/12) |
| TS 29.168 | SBcAP Protocol (CBC ↔ MME) |
| TS 36.413 | S1AP Protocol (WriteReplaceWarningRequest) |

## 🔍 Wireshark Filters

```
# All S1AP PWS messages
s1ap.procedureCode == 36

# WriteReplaceWarningRequest
s1ap.WriteReplaceWarningRequest

# LTE-RRC SIB12 (CMAS)
lte-rrc.systemInformationBlockType12_element

# LTE-RRC SIB10/11 (ETWS)
lte-rrc.systemInformationBlockType10_element || lte-rrc.systemInformationBlockType11_element
```

## 🛠️ Troubleshooting

### Alert not displayed on phone

1. Check SIB12 broadcast: `lte-rrc.systemInformationBlockType12_element`
2. Verify Message ID matches CMAS range (4370-4399)
3. Ensure phone has emergency alerts enabled

### MME not forwarding alert

1. Check SBcAP connection to CBC
2. Verify TAC list includes target cell
3. Check MME logs: `docker logs mme | grep -i warning`

### eNB not broadcasting SIB

1. Verify `sib_config` path in enb.conf
2. Check SIB file syntax
3. Restart eNB after config changes

## 📜 License

MIT License — See [LICENSE](LICENSE) file

## 👨‍💻 Author

**Arnaud DJOUM** — F2G TelcoLab  
Private LTE Lab — Cameroon

---

*Created: 2026-10-01*  
*Based on: Open5GS v2.7 + srsRAN v23.11*
