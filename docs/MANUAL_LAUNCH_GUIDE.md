# Manual Launch Guide — CMAS/PWS Emergency Alert Lab

Complete step-by-step procedure to launch the lab manually, from cold start to live Wireshark capture during alert broadcast.

**Duration:** ~8 minutes  
**Prerequisites:** All hardware connected, SIM cards provisioned

---

## Quick Reference

| Component | Machine | Command |
|-----------|---------|---------|
| Core Network | PC1 | `docker-compose up -d` |
| eNB | PC1 | `sudo srsenb enb_pws.conf` |
| Wireshark | PC1 | `wireshark -i any -k -f "sctp"` |
| Send Alert | PC1 | `./send_alert.sh presidential "Test"` |

---

## Phase 1: Pre-flight Checks (2 min)

### 1.1 Verify Docker is Running

```bash
docker ps
# Should show: Running containers or empty list
```

### 1.2 Check bladeRF Device

```bash
bladeRF-cli -p
# Expected: Serial XXXXXXXXXX, bladeRF 2.0 (bladeRF xA4)

# If not detected:
sudo bladeRF-cli -L /usr/share/bladerf/fpga/hostedx40.rbf
```

### 1.3 Verify Config Files

```bash
ls -la /home/f2g/Desktop/CMAS-PWS/configs/srsran/
# Should see: enb_pws.conf, sib_pws.conf, etc.
```

### 1.4 Check Phone Settings

On each phone:
- Settings → Safety & Emergency → Wireless Emergency Alerts
- Enable: Presidential, Extreme, Severe, AMBER
- For testing: Enable "Test alerts"

---

## Phase 2: Start Core Network (2 min)

### 2.1 Start Docker Containers

```bash
cd /home/f2g/Telecom/Core-Network/openimss
docker-compose up -d
```

Wait 10 seconds for all services to initialize.

### 2.2 Verify Core Services

```bash
# Check containers running
docker ps --format "table {{.Names}}\t{{.Status}}" | head -10

# Check MME is listening
docker logs mme 2>&1 | tail -5
# Look for: "s1ap_server() [INFO]: Waiting for eNB connection"
```

### 2.3 Verify MME Ready for PWS

```bash
docker logs mme 2>&1 | grep -i "pws\|warning\|cbc"
# May show: PWS/CBS related initialization messages
```

---

## Phase 3: Start Wireshark Live Capture (1 min)

### 3.1 Launch Wireshark

Open a new terminal:

```bash
# Option A: Capture all interfaces with SCTP filter
sudo wireshark -i any -k -f "sctp"

# Option B: Capture specific interface
sudo wireshark -i enp3s0 -k -f "sctp port 36412"

# Option C: CLI capture with tshark
sudo tshark -i any -f "sctp" -Y "s1ap"
```

### 3.2 Apply Display Filters

In Wireshark filter bar:

```
# All S1AP messages
s1ap

# Only WriteReplaceWarning
s1ap.procedureCode == 36

# CMAS SIB12
lte-rrc.systemInformationBlockType12_element

# ETWS SIB10/11
lte-rrc.systemInformationBlockType10_element || lte-rrc.systemInformationBlockType11_element
```

### 3.3 Key Messages to Watch

| Message | Direction | Meaning |
|---------|-----------|---------|
| S1SetupRequest | eNB → MME | eNB connecting |
| S1SetupResponse | MME → eNB | Connection accepted |
| WriteReplaceWarningRequest | MME → eNB | Alert sent to eNB |
| WriteReplaceWarningResponse | eNB → MME | Alert acknowledged |

---

## Phase 4: Start eNodeB (1 min)

### 4.1 Launch srsENB

```bash
cd /home/f2g/Desktop/CMAS-PWS/configs/srsran
sudo srsenb enb_pws.conf
```

### 4.2 Expected Output

```
---  Software Radio Systems LTE eNodeB  ---

Opening 1 channels in RF device=bladeRF with args=
Set RX antenna to RX
...
==== eNodeB started ===
Type <t> to view trace
Setting frequency: DL=1830.0 MHz, UL=1735.0 MHz
Found bladeRF serial XXXXXXXXXX
```

### 4.3 Verify S1 Connection

In Wireshark, you should see:
- `S1SetupRequest` from eNB
- `S1SetupResponse` from MME

Check MME logs:
```bash
docker logs mme 2>&1 | grep -i "enb\|s1ap"
# Look for: "eNB-S1 accepted[172.22.0.1]"
# Look for: "Number of eNBs is now 1"
```

---

## Phase 5: Attach UEs (2 min)

### 5.1 Power On Phones

1. Insert SIM cards with correct IMSI/K/OPC
2. Power on phones
3. Wait for LTE attachment (signal bars appear)

### 5.2 Verify Attachment

On eNB terminal, press `t` for trace:

```
------DL-------------------------------UL--------------------------------
rnti  cqi  ri  mcs  brate   ok  nok  (%)  pusch  pucch  phr  mcs  brate
  46   15   1   28   5.2M  100    2   2%   -8.0   -4.5   20   24   2.1M
```

### 5.3 Check Phone Connectivity

- Phone should show LTE symbol
- Try opening a webpage to verify data
- Check PLMN: Should show "00101" or "Test PLMN"

---

## Phase 6: Send Emergency Alert (1 min)

### 6.1 Using Shell Script

```bash
cd /home/f2g/Desktop/CMAS-PWS/scripts

# Presidential Alert (cannot be disabled)
./send_alert.sh presidential "PRESIDENTIAL ALERT - This is a test"

# AMBER Alert
./send_alert.sh amber "AMBER Alert - Missing child in Yaoundé"

# Earthquake Alert (ETWS)
./send_alert.sh earthquake "EARTHQUAKE WARNING - Take cover immediately"

# Severe Weather Alert
./send_alert.sh severe "SEVERE WEATHER - Flash flood warning"
```

### 6.2 Using Python Script

```bash
python3 inject_write_replace_warning.py \
    --mme-ip 172.22.0.9 \
    --message-id 4370 \
    --message "EMERGENCY ALERT - This is a test"
```

### 6.3 Alert Types Reference

| Command | Message ID | Description |
|---------|------------|-------------|
| presidential | 4370 | Cannot be disabled, highest priority |
| extreme | 4371 | Imminent extreme threat |
| severe | 4373 | Severe threat |
| amber | 4379 | Child abduction |
| earthquake | 4352 | ETWS earthquake |
| tsunami | 4353 | ETWS tsunami |
| test | 4380 | Monthly test |

---

## Phase 7: Verify Alert Reception

### 7.1 Phone Display

- Alert popup should appear on all attached phones
- Alert sound plays (if not silenced)
- Message content visible
- For Presidential: NO "Stop" option available

### 7.2 Wireshark Verification

Check for these messages in order:

| # | Message | Filter |
|---|---------|--------|
| 1 | WriteReplaceWarningRequest | `s1ap.procedureCode == 36` |
| 2 | WriteReplaceWarningResponse | `s1ap.procedureCode == 36` |
| 3 | SIB12 broadcast | `lte-rrc.systemInformationBlockType12_element` |

### 7.3 Check Message Content

In Wireshark, expand:
- S1AP → WriteReplaceWarningRequest
- Look for: `messageIdentifier`, `warningMessageContents`

### 7.4 Save Capture

File → Save As → `CMAS_test_YYYYMMDD_HHMM.pcapng`

---

## Phase 8: Multi-Alert Test Sequence

### 8.1 Test Different Alert Types

```bash
# Wait 30 seconds between alerts for phones to clear

# Test 1: Presidential
./send_alert.sh presidential "Test 1 - Presidential Alert"
sleep 30

# Test 2: AMBER
./send_alert.sh amber "Test 2 - AMBER Alert"
sleep 30

# Test 3: Earthquake
./send_alert.sh earthquake "Test 3 - Earthquake ETWS"
sleep 30

# Test 4: Monthly Test
./send_alert.sh test "Test 4 - Monthly Required Test"
```

### 8.2 Verify Each Alert

For each alert, confirm:
- [ ] Wireshark shows WriteReplaceWarningRequest
- [ ] Phone displays alert popup
- [ ] Correct message content
- [ ] Appropriate alert tone

---

## Troubleshooting Quick Reference

### Alert not appearing on phone

```bash
# Check SIB broadcast in Wireshark
Filter: lte-rrc.systemInformationBlockType12_element

# Check Message ID is in valid range
Valid CMAS: 4370-4399
Valid ETWS: 4352-4359

# Check phone settings
Settings → Safety → Emergency Alerts → Enable all
```

### MME not forwarding alert

```bash
# Check MME logs
docker logs mme 2>&1 | grep -i "warning\|pws"

# Restart MME
docker restart mme
sleep 5

# Re-check
docker logs mme | tail -10
```

### eNB not connected

```bash
# Check S1 connection
docker logs mme 2>&1 | grep "Number of eNBs"

# Restart eNB
# (Ctrl+C to stop, then restart)
sudo srsenb enb_pws.conf
```

### No WriteReplaceWarningResponse

```bash
# eNB may not support PWS
# Check eNB configuration has SIB10/11/12 enabled
grep -i "sib1[012]" configs/srsran/sib_pws.conf
```

---

## Complete Startup Script

Save as `start_cmas_lab.sh`:

```bash
#!/bin/bash
# Complete CMAS lab startup script

echo "=== Starting CMAS/PWS Lab ==="

# 1. Start Core
cd /home/f2g/Telecom/Core-Network/openimss
docker-compose up -d
sleep 10

# 2. Verify Core
echo ""
echo "=== Core Status ==="
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "mme|hss"

# 3. Start Wireshark in background
echo ""
echo "=== Starting Wireshark ==="
sudo wireshark -i any -k -f "sctp" &
sleep 2

# 4. Start eNB
echo ""
echo "=== Starting eNB ==="
gnome-terminal --title="eNB PWS" -- bash -c "sudo srsenb /home/f2g/Desktop/CMAS-PWS/configs/srsran/enb_pws.conf; exec bash"

echo ""
echo "=== Lab Started ==="
echo "1. Wait for 'eNB-S1 accepted' in MME logs"
echo "2. Power on phones"
echo "3. Run: ./scripts/send_alert.sh presidential \"Test message\""
```

---

## Shutdown Procedure

```bash
# 1. Stop eNB (Ctrl+C in eNB terminal)

# 2. Stop Core
cd /home/f2g/Telecom/Core-Network/openimss
docker-compose down

# 3. Save Wireshark capture before closing
```

---

*Document created: 2026-10-01*  
*Lab: F2G TelcoLab — CMAS/PWS Emergency Alert System*
