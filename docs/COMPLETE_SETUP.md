# Complete Setup Guide — CMAS/PWS Emergency Alert System

This document contains all configuration details needed to replicate the Cell Broadcast Emergency Alert lab.

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    CELL BROADCAST ARCHITECTURE                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌──────────────┐                                                          │
│   │ Alert Script │   Python/Shell injection                                 │
│   └──────┬───────┘                                                          │
│          │ S1AP WriteReplaceWarningRequest                                  │
│          ▼                                                                   │
│   ┌──────────────┐     ┌──────────────┐     ┌──────────────┐               │
│   │     MME      │────▶│    eNodeB    │────▶│     UEs      │               │
│   │  172.22.0.9  │     │   srsRAN     │     │   Phones     │               │
│   └──────────────┘     └──────────────┘     └──────────────┘               │
│                              │                                               │
│                              │ SIB10/11/12                                   │
│                              │ Broadcast                                     │
│                              ▼                                               │
│                        ┌──────────────┐                                      │
│                        │  LTE-Uu RF   │                                      │
│                        │  bladeRF xA4 │                                      │
│                        └──────────────┘                                      │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Network Configuration

### 2.1 IP Addressing

| Component | IP Address | Interface | Port |
|-----------|------------|-----------|------|
| Host (eNB bind) | 172.22.0.1 | br-docker | - |
| MME | 172.22.0.9 | Docker | 36412 (SCTP) |
| HSS | 172.22.0.3 | Docker | 3868 |
| SGWC | 172.22.0.5 | Docker | 2123 |
| SGWU | 172.22.0.6 | Docker | 2152 |
| UPF | 172.22.0.8 | Docker | 2152 |
| PCSCF | 172.22.0.21 | Docker | 5060 |
| SCSCF | 172.22.0.20 | Docker | 5060 |

### 2.2 Radio Parameters

| Parameter | Value | Notes |
|-----------|-------|-------|
| MCC | 001 | Test network |
| MNC | 01 | Test network |
| TAC | 0x0001 | Tracking Area Code |
| eNB ID | 0x19B | 411 decimal |
| Cell ID | 0x01 | Combined: 0x19B01 |
| EARFCN | 1450 | DL frequency |
| Band | 3 | 1800 MHz |
| DL Freq | 1830 MHz | Calculated from EARFCN |
| UL Freq | 1735 MHz | Band 3 offset |
| Bandwidth | 10 MHz | 50 PRB |
| PCI | 1 | Physical Cell ID |

---

## 3. Subscriber Configuration

### 3.1 Subscriber 1

```yaml
IMSI: 001010000123451
MSISDN: 1001
K: 465B5CE8B199B49FAA5F0A2EE238A6BC
OPC: E8ED289DEBA952E4283B54E88E6183CA
AMF: 8000
SQN: 000000000000

APN Configuration:
  - Name: internet
    QCI: 9
    ARP: 8
```

### 3.2 Subscriber 2

```yaml
IMSI: 001010000099901
MSISDN: 1099
K: 465B5CE8B199B49FAA5F0A2EE238A6BC
OPC: E8ED289DEBA952E4283B54E88E6183CA
AMF: 8000
SQN: 000000000000

APN Configuration:
  - Name: internet
    QCI: 9
    ARP: 8
```

---

## 4. eNodeB Configuration

### 4.1 Main Config (enb_pws.conf)

```ini
#####################################################################
# srsENB Configuration for PWS/CMAS Alerts
# F2G TelcoLab — Open5GS + srsRAN
#####################################################################

[enb]
enb_id = 0x19B
mcc = 001
mnc = 01
mme_addr = 172.22.0.9
gtp_bind_addr = 172.22.0.1
s1c_bind_addr = 172.22.0.1
s1c_bind_port = 0
n_prb = 50

[enb_files]
sib_config = sib_pws.conf
rr_config = /etc/srsran/rr.conf
rb_config = /etc/srsran/rb.conf

[rf]
dl_earfcn = 1450
tx_gain = 80
rx_gain = 40
device_name = bladeRF
device_args = 
time_adv_nsamples = 27

[pcap]
enable = true
filename = /tmp/enb_pws.pcap
s1ap_enable = true
s1ap_filename = /tmp/enb_pws_s1ap.pcap

[log]
all_level = info
all_hex_limit = 32
filename = /tmp/enb_pws.log

[expert]
nof_phy_threads = 3
metrics_period_secs = 1
```

### 4.2 SIB Configuration with PWS (sib_pws.conf)

```
sib1 =
{
    intra_freq_reselection = "Allowed";
    q_rx_lev_min = -70;
    cell_barred = "NotBarred";
    si_window_length = 20;
    sched_info =
    (
        {
            si_periodicity = 16;
            si_mapping_info = [3];  // SIB3
        },
        {
            si_periodicity = 16;
            si_mapping_info = [12]; // SIB12 for CMAS
        },
        {
            si_periodicity = 16;
            si_mapping_info = [10, 11]; // SIB10, SIB11 for ETWS
        }
    );
    system_info_value_tag = 0;
};

sib2 =
{
    rr_config_common_sib =
    {
        rach_cnfg =
        {
            num_ra_preambles = 52;
            preamble_init_rx_target_pwr = -104;
            pwr_ramping_step = 6;
            preamble_trans_max = 10;
            ra_resp_win_size = 10;
            mac_con_res_timer = 64;
            max_harq_msg3_tx = 4;
        };
        bcch_cnfg = { modification_period_coeff = 16; };
        pcch_cnfg = { default_paging_cycle = 128; nB = "1"; };
        prach_cnfg = { root_sequence_index = 128; prach_cnfg_info = { high_speed_flag = false; prach_config_index = 3; prach_freq_offset = 2; zero_correlation_zone_config = 5; }; };
        pdsch_cnfg = { p_b = 1; rs_power = 0; };
        pusch_cnfg = { n_sb = 1; hopping_mode = "inter-subframe"; pusch_hopping_offset = 2; enable_64_qam = false; ul_rs = { cyclic_shift = 0; group_hopping_enabled = false; group_assignment_pusch = 0; }; };
        pucch_cnfg = { delta_pucch_shift = 2; n_rb_cqi = 2; n_cs_an = 0; n1_pucch_an = 12; };
        ul_pwr_ctrl = { p0_nominal_pusch = -85; alpha = 0.7; p0_nominal_pucch = -107; delta_flist_pucch = { format_1 = 0; format_1b = 3; format_2 = 1; format_2a = 2; format_2b = 2; }; delta_preamble_msg3 = 4; };
        ul_cp_length = "Normal";
    };
    ue_timers_and_constants = { t300 = 2000; t301 = 100; t310 = 200; n310 = 1; t311 = 10000; n311 = 1; };
    freqInfo = { ul_carrier_freq_present = true; ul_bw_present = true; additional_spectrum_emission = 1; };
    time_alignment_timer = "INFINITY";
};

sib3 =
{
    cell_reselection_common = { q_hyst = 2; };
    cell_reselection_serving = { s_non_intra_search = 3; thresh_serving_low = 2; cell_resel_prio = 6; };
    intra_freq_reselection = { q_rx_lev_min = -61; p_max = 23; s_intra_search = 5; presence_ant_port_1 = true; neigh_cell_cnfg = 1; t_resel_eutra = 1; };
};

// ═══════════════════════════════════════════════════════════════════════════
// SIB10 — ETWS Primary Notification (Earthquake/Tsunami)
// ═══════════════════════════════════════════════════════════════════════════
sib10 =
{
    // Message Identifier (16 bits)
    // 4352 (0x1100) = Earthquake
    // 4353 (0x1101) = Tsunami
    // 4354 (0x1102) = Earthquake + Tsunami
    messageIdentifier = "0x1100";
    
    // Serial Number (16 bits)
    // Bits 0-1: Geographic scope (00=cell, 01=PLMN, 10=LA, 11=cell)
    // Bits 2-11: Message code
    // Bits 12-15: Update number
    serialNumber = "0x3000";
    
    // Warning Type (16 bits)
    // Bits 0-6: Warning type value
    //   0 = Earthquake
    //   1 = Tsunami
    //   2 = Earthquake + Tsunami
    //   3 = Test
    //   4 = Other
    // Bit 7: Emergency user alert
    // Bit 8: Popup indicator
    warningType = "0x0080";  // Earthquake with popup
};

// ═══════════════════════════════════════════════════════════════════════════
// SIB11 — ETWS Secondary Notification (Detailed message)
// ═══════════════════════════════════════════════════════════════════════════
sib11 =
{
    messageIdentifier = "0x1100";
    serialNumber = "0x3000";
    
    // Segment type: "notLastSegment" or "lastSegment"
    warningMessageSegmentType = "lastSegment";
    warningMessageSegmentNumber = 0;
    
    // Warning message content (hex-encoded)
    // "EARTHQUAKE WARNING - Take cover immediately"
    // UTF-8 hex: 454152544851554B4520...
    warningMessageSegment = "454152544851554B45205741524E494E47202D2054616B6520636F76657220696D6D6564696174656C79";
};

// ═══════════════════════════════════════════════════════════════════════════
// SIB12 — CMAS Warning Messages (Presidential, AMBER, etc.)
// ═══════════════════════════════════════════════════════════════════════════
sib12 =
{
    // Message Identifier (16 bits)
    // 4370 (0x1112) = Presidential Alert
    // 4371-4372 = Extreme threat
    // 4373-4378 = Severe threat
    // 4379 (0x111B) = AMBER Alert
    // 4380 (0x111C) = Monthly test
    messageIdentifier = "0x1112";  // Presidential
    
    serialNumber = "0x3000";
    
    warningMessageSegmentType = "lastSegment";
    warningMessageSegmentNumber = 0;
    
    // Data Coding Scheme (8 bits)
    // 0x01 = GSM 7-bit default
    // 0x48 = UCS-2 (Unicode)
    dataCodingScheme = "0x01";
    
    // Warning message (hex-encoded GSM 7-bit or UCS-2)
    // "PRESIDENTIAL ALERT - This is a test of the emergency alert system"
    warningMessageSegment = "505245534944454E5449414C20414C455254202D205468697320697320612074657374";
};
```

---

## 5. Alert Message IDs

### 5.1 CMAS (Commercial Mobile Alert System)

| Alert Type | Message ID (Dec) | Message ID (Hex) | Can Disable |
|------------|------------------|------------------|-------------|
| Presidential | 4370 | 0x1112 | No |
| Extreme Imminent | 4371 | 0x1113 | Yes |
| Extreme Expected | 4372 | 0x1114 | Yes |
| Severe Imminent | 4373 | 0x1115 | Yes |
| Severe Expected | 4374 | 0x1116 | Yes |
| Severe Likely | 4375 | 0x1117 | Yes |
| Child Abduction | 4376 | 0x1118 | Yes |
| Required Test | 4377 | 0x1119 | Yes |
| Exercise/Drill | 4378 | 0x111A | Yes |
| AMBER Alert | 4379 | 0x111B | Yes |
| Monthly Test | 4380 | 0x111C | Yes |
| Public Safety | 4383-4391 | 0x111F-0x1127 | Yes |

### 5.2 ETWS (Earthquake/Tsunami Warning)

| Alert Type | Message ID (Dec) | Message ID (Hex) | Delivery |
|------------|------------------|------------------|----------|
| Earthquake | 4352 | 0x1100 | < 4 sec |
| Tsunami | 4353 | 0x1101 | < 4 sec |
| Earthquake + Tsunami | 4354 | 0x1102 | < 4 sec |
| Test | 4355 | 0x1103 | < 4 sec |
| Other | 4356 | 0x1104 | < 4 sec |

---

## 6. Alert Injection Scripts

### 6.1 Shell Script (send_alert.sh)

```bash
#!/bin/bash
# Send CMAS/ETWS Alert via S1AP

ALERT_TYPE=$1
MESSAGE=$2
MME_IP="172.22.0.9"

case $ALERT_TYPE in
    presidential)
        MSG_ID=4370
        ;;
    extreme)
        MSG_ID=4371
        ;;
    severe)
        MSG_ID=4373
        ;;
    amber)
        MSG_ID=4379
        ;;
    test)
        MSG_ID=4380
        ;;
    earthquake)
        MSG_ID=4352
        ;;
    tsunami)
        MSG_ID=4353
        ;;
    *)
        echo "Usage: $0 {presidential|extreme|severe|amber|test|earthquake|tsunami} \"message\""
        exit 1
        ;;
esac

python3 inject_write_replace_warning.py \
    --mme-ip $MME_IP \
    --message-id $MSG_ID \
    --message "$MESSAGE"
```

### 6.2 Python Injection Script (inject_write_replace_warning.py)

Key parameters:
- `--mme-ip`: MME IP address (172.22.0.9)
- `--message-id`: Alert type (4370 for Presidential)
- `--message`: Alert text content
- `--tac-list`: Target TAC(s) (default: all)
- `--repetition`: Number of broadcasts (default: 10)

---

## 7. Wireshark Filters

### 7.1 S1AP Filters

```
# All S1AP messages
s1ap

# WriteReplaceWarning procedure (code 36)
s1ap.procedureCode == 36

# WriteReplaceWarningRequest only
s1ap.WriteReplaceWarningRequest

# WriteReplaceWarningResponse only
s1ap.WriteReplaceWarningResponse

# Kill procedure (stop alert)
s1ap.procedureCode == 37
```

### 7.2 LTE-RRC Filters

```
# SIB12 (CMAS)
lte-rrc.systemInformationBlockType12_element

# SIB10 (ETWS primary)
lte-rrc.systemInformationBlockType10_element

# SIB11 (ETWS secondary)
lte-rrc.systemInformationBlockType11_element

# All emergency SIBs
lte-rrc.systemInformationBlockType10_element || lte-rrc.systemInformationBlockType11_element || lte-rrc.systemInformationBlockType12_element
```

---

## 8. Startup Sequence

### 8.1 Start Core Network

```bash
cd /home/f2g/Telecom/Core-Network/openimss
docker-compose up -d
sleep 10
docker logs mme 2>&1 | grep -i "waiting"
```

### 8.2 Start Wireshark

```bash
sudo wireshark -i any -k -f "sctp port 36412" &
```

### 8.3 Start eNodeB

```bash
sudo srsenb /home/f2g/Desktop/CMAS-PWS/configs/srsran/enb_pws.conf
```

### 8.4 Verify Connection

```bash
docker logs mme 2>&1 | grep "Number of eNBs"
# Expected: "Number of eNBs is now 1"
```

### 8.5 Attach Phones

1. Power on phones with SIM cards
2. Wait for LTE signal
3. Verify attachment in eNB trace (press `t`)

### 8.6 Send Alert

```bash
cd /home/f2g/Desktop/CMAS-PWS/scripts
./send_alert.sh presidential "EMERGENCY ALERT TEST"
```

---

## 9. Troubleshooting

### 9.1 Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| No alert popup | SIB not broadcast | Check sib_config path |
| Wrong message | Message ID error | Verify ID in valid range |
| No S1AP message | Script error | Check Python/scapy |
| eNB won't start | Config error | Check enb.conf syntax |
| Phone not attached | RF/SIM issue | Check bladeRF, SIM K/OPC |

### 9.2 Log Locations

| Log | Path | Content |
|-----|------|---------|
| eNB | /tmp/enb_pws.log | Radio, S1AP |
| MME | `docker logs mme` | Core network |
| S1AP PCAP | /tmp/enb_pws_s1ap.pcap | Protocol capture |

---

*Document created: 2026-10-01*  
*F2G TelcoLab — CMAS/PWS Emergency Alert System*
