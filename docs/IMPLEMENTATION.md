# CMAS/PWS Implementation Guide

This document explains how to build and operate the Cell Broadcast Emergency Alert System.

---

## 1. Prerequisites

### 1.1 Hardware

| Component | Specification | Notes |
|-----------|---------------|-------|
| PC | Ubuntu 22.04 LTS, 16GB RAM | Bare metal recommended |
| SDR | bladeRF xA4 or x115 | USB 3.0 connection required |
| Phones | Android or iPhone with LTE | Emergency alerts enabled |
| SIM | Programmable USIM | K, OPC pre-configured |

### 1.2 Software Installation

```bash
# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Install srsRAN dependencies
sudo apt install -y cmake libfftw3-dev libmbedtls-dev libsctp-dev \
    libconfig++-dev libboost-all-dev

# Install bladeRF tools
sudo apt install -y bladerf libbladerf-dev bladerf-fpga-hostedx40

# Install Wireshark
sudo apt install -y wireshark tshark
sudo usermod -aG wireshark $USER

# Install Python dependencies
pip install scapy pysctp
```

### 1.3 Network Configuration

Ensure Docker bridge network exists:

```bash
docker network create --subnet=172.22.0.0/24 open5gs-net
```

---

## 2. Core Network Setup

### 2.1 Start Open5GS Containers

```bash
cd /home/f2g/Telecom/Core-Network/openimss
docker-compose up -d
```

### 2.2 Verify Services

```bash
# Check all containers running
docker ps --format "table {{.Names}}\t{{.Status}}"

# Verify MME listening
docker logs mme 2>&1 | grep -i "s1ap_server"
# Expected: "Waiting for eNB connection"
```

### 2.3 Container IP Addresses

| Service | IP | Port |
|---------|-----|------|
| MME | 172.22.0.9 | 36412 (SCTP) |
| HSS | 172.22.0.3 | 3868 |
| SGWC | 172.22.0.5 | 2123 |
| SGWU | 172.22.0.6 | 2152 |
| UPF | 172.22.0.8 | 2152 |

---

## 3. eNodeB Configuration

### 3.1 Main eNB Config (enb_pws.conf)

```ini
#####################################################################
# srsENB Configuration for PWS/CMAS
#####################################################################

[enb]
enb_id = 0x19B
mcc = 001
mnc = 01
mme_addr = 172.22.0.9
gtp_bind_addr = 172.22.0.1
s1c_bind_addr = 172.22.0.1
n_prb = 50

[enb_files]
sib_config = sib_pws.conf
rr_config = rr.conf
rb_config = rb.conf

[rf]
dl_earfcn = 1450
tx_gain = 80
rx_gain = 40
device_name = bladeRF

[log]
all_level = info
filename = /tmp/enb_pws.log

[expert]
nof_phy_threads = 3
```

### 3.2 SIB Configuration for PWS (sib_pws.conf)

The key sections are **SIB10**, **SIB11**, and **SIB12** which carry emergency alerts.

#### SIB10 — ETWS Primary Notification

```
sib10 = {
    messageIdentifier = "0x1112";        // 4370 = Presidential
    serialNumber = "0x3000";
    warningType = "earthquake";          // earthquake, tsunami, other
};
```

#### SIB11 — ETWS Secondary Notification

```
sib11 = {
    messageIdentifier = "0x1112";
    serialNumber = "0x3000";
    warningMessageSegmentType = "notLastSegment";
    warningMessageSegmentNumber = 0;
    warningMessageSegment = "48656C6C6F";  // Hex-encoded "Hello"
};
```

#### SIB12 — CMAS Warning Message

```
sib12 = {
    messageIdentifier = "0x1112";        // 4370 = Presidential
    serialNumber = "0x3000";
    warningMessageSegmentType = "notLastSegment";
    warningMessageSegmentNumber = 0;
    warningMessageSegment = "454D455247454E435920414C455254";  // "EMERGENCY ALERT"
};
```

### 3.3 Message ID Reference

| Alert Type | Message ID (Decimal) | Message ID (Hex) |
|------------|---------------------|------------------|
| Presidential | 4370 | 0x1112 |
| Extreme Imminent | 4371 | 0x1113 |
| Extreme Expected | 4372 | 0x1114 |
| Severe Imminent | 4373 | 0x1115 |
| Severe Expected | 4374 | 0x1116 |
| AMBER | 4379 | 0x111B |
| Monthly Test | 4380 | 0x111C |
| Earthquake | 4352 | 0x1100 |
| Tsunami | 4353 | 0x1101 |

---

## 4. Alert Injection Methods

### 4.1 Method A: SIB Configuration (Static)

Edit `sib_pws.conf` and restart eNB.

Pros: Simple, no external tools
Cons: Requires eNB restart

### 4.2 Method B: Python Script Injection (Dynamic)

Use `inject_write_replace_warning.py` to send S1AP WriteReplaceWarningRequest.

```bash
python3 scripts/inject_write_replace_warning.py \
    --mme-ip 172.22.0.9 \
    --message-id 4370 \
    --message "PRESIDENTIAL ALERT - This is a test"
```

### 4.3 Method C: Shell Script (Recommended)

```bash
./scripts/send_alert.sh presidential "Emergency test message"
./scripts/send_alert.sh amber "Child abduction alert - Yaoundé"
./scripts/send_alert.sh earthquake "Earthquake detected - Take cover"
```

---

## 5. Multi-TAC Configuration

### 5.1 TAC Setup

| TAC | Value | Region | eNB Config |
|-----|-------|--------|------------|
| TAC 1 | 0x0001 | Yaoundé | enb_tac1_cmas.conf |
| TAC 2 | 0x0002 | Douala | enb_tac2_cmas.conf |

### 5.2 eNB TAC 1 Config

```ini
[enb]
enb_id = 0x19B
mcc = 001
mnc = 01
tac = 0x0001
mme_addr = 172.22.0.9

[enb_files]
sib_config = sib_tac1_cmas.conf
```

### 5.3 eNB TAC 2 Config (PC2)

```ini
[enb]
enb_id = 0x19C
mcc = 001
mnc = 01
tac = 0x0002
mme_addr = 172.22.0.9

[enb_files]
sib_config = sib_tac2_cmas.conf
```

### 5.4 Targeting Specific TACs

When injecting alerts, specify the TAC list:

```bash
python3 inject_write_replace_warning.py \
    --mme-ip 172.22.0.9 \
    --tac-list 1,2 \
    --message-id 4370 \
    --message "Alert for both regions"
```

---

## 6. Verification

### 6.1 Wireshark Capture

Start capture before sending alert:

```bash
sudo wireshark -i any -k -f "sctp port 36412"
```

### 6.2 Display Filters

| Filter | Purpose |
|--------|---------|
| `s1ap` | All S1AP messages |
| `s1ap.procedureCode == 36` | WriteReplaceWarning |
| `lte-rrc.systemInformationBlockType12_element` | SIB12 (CMAS) |
| `lte-rrc.systemInformationBlockType10_element` | SIB10 (ETWS primary) |
| `lte-rrc.systemInformationBlockType11_element` | SIB11 (ETWS secondary) |

### 6.3 Expected S1AP Sequence

```
MME ← eNB: S1SetupRequest
MME → eNB: S1SetupResponse
[Alert Injection]
MME → eNB: WriteReplaceWarningRequest
MME ← eNB: WriteReplaceWarningResponse
[eNB broadcasts SIB10/11/12]
[Phone displays alert]
```

### 6.4 Phone Verification

1. Alert popup appears with correct message
2. Alert sound plays (if not silenced)
3. For Presidential: no "Stop" option available
4. Check Settings > Safety & Emergency > Wireless Emergency Alerts

---

## 7. Troubleshooting

### 7.1 Alert Not Displayed

| Symptom | Cause | Solution |
|---------|-------|----------|
| No popup | SIB not broadcast | Check eNB config, restart |
| SIB visible but no alert | Message ID wrong | Use correct range (4370-4399) |
| Only some phones | Alert disabled | Check phone settings |
| Popup but no sound | Phone silenced | Unmute, retest |

### 7.2 Common Errors

**Error: "MME not reachable"**
```bash
# Check MME container
docker ps | grep mme
docker logs mme | tail -20
```

**Error: "S1AP connection failed"**
```bash
# Verify SCTP connectivity
nc -zv 172.22.0.9 36412
```

**Error: "bladeRF not found"**
```bash
# Check USB connection
bladeRF-cli -p
# Reload firmware if needed
bladeRF-cli -L /usr/share/bladerf/fpga/hostedx40.rbf
```

### 7.3 Log Locations

| Log | Path | Content |
|-----|------|---------|
| eNB | /tmp/enb_pws.log | Radio and S1AP |
| MME | `docker logs mme` | Core network |
| PCAP | /tmp/enb.pcap | S1AP captures |

---

## 8. Quick Reference Commands

### Start Lab

```bash
# 1. Start core
cd /home/f2g/Telecom/Core-Network/openimss && docker-compose up -d

# 2. Start Wireshark
sudo wireshark -i any -k &

# 3. Start eNB
sudo srsenb /home/f2g/Desktop/CMAS-PWS/configs/srsran/enb_pws.conf

# 4. Send alert
./scripts/send_alert.sh presidential "Test message"
```

### Stop Lab

```bash
# Stop eNB (Ctrl+C)
# Stop core
docker-compose down
```

### View Logs

```bash
# eNB log
tail -f /tmp/enb_pws.log

# MME log
docker logs -f mme 2>&1 | grep -i "warning\|pws\|cbs"
```

---

*Version: 1.0*  
*Date: 2026-10-01*  
*Author: Arnaud DJOUM — F2G*
