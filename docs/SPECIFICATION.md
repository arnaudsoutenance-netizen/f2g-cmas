# CMAS/PWS Specification — F2G TelcoLab

## 1. Overview

This document defines what the CMAS/PWS Cell Broadcast Emergency Alert System does.

### 1.1 Purpose

Enable broadcast of emergency alerts to all mobile devices within a geographic area using LTE Cell Broadcast Service (CBS).

### 1.2 Scope

| In Scope | Out of Scope |
|----------|--------------|
| CMAS alerts (Presidential, AMBER, Severe) | Commercial advertising via CBS |
| ETWS alerts (Earthquake, Tsunami) | Carrier-specific messages |
| Multi-TAC targeting | 5G NR CBS (N2/PWS) |
| SIB10/11/12 broadcast | SBcAP full implementation |
| Wireshark verification | Commercial CBC platform |

---

## 2. Goals

### 2.1 Primary Goals

1. **Broadcast emergency alerts** to all UEs attached to specific cells
2. **Support multiple alert types** (CMAS, ETWS, Public Safety)
3. **Target alerts by TAC** (Tracking Area Code) for geographic precision
4. **Demonstrate 3GPP-compliant** Write-Replace-Warning procedure

### 2.2 Success Criteria

| Metric | Target | Verification |
|--------|--------|--------------|
| Alert delivery time | < 10 seconds | Wireshark timestamp |
| UE display | 100% of attached phones | Visual confirmation |
| SIB12 broadcast | Visible in Wireshark | LTE-RRC filter |
| Presidential alert | Cannot be disabled | Phone settings check |
| Multi-TAC support | 2 TACs minimum | eNB1 + eNB2 test |

---

## 3. Non-Goals

1. Full CBC (Cell Broadcast Center) with SBcAP protocol
2. Commercial CBS for advertising
3. Integration with national emergency services (out of lab scope)
4. 5G NR PWS (future enhancement)
5. Alert message internationalization

---

## 4. System Requirements

### 4.1 Hardware

| Component | Specification | Quantity |
|-----------|---------------|----------|
| PC | Ubuntu 22.04, 16GB RAM, SSD | 1 |
| SDR | bladeRF xA4 or x115 | 1 |
| Phones | LTE-capable, emergency alerts enabled | 2+ |
| SIM Cards | Programmable USIM | 2+ |

### 4.2 Software

| Component | Version | Purpose |
|-----------|---------|---------|
| Open5GS | 2.7.x | EPC Core (MME, HSS, SGW, PGW) |
| srsRAN | 23.11 | eNodeB with SIB broadcasting |
| Docker | 24.x | Container orchestration |
| Wireshark | 4.x | Protocol analysis |
| Python | 3.10+ | Alert injection scripts |

### 4.3 Network

| Parameter | Value |
|-----------|-------|
| MCC | 001 |
| MNC | 01 |
| TAC 1 | 0x0001 (1) — Yaoundé |
| TAC 2 | 0x0002 (2) — Douala |
| EARFCN | 1450 |
| Band | 3 (1800 MHz) |

---

## 5. Alert Types

### 5.1 CMAS (Commercial Mobile Alert System)

Broadcast via **SIB12** (System Information Block Type 12).

| Type | Message ID | Description | User Can Disable |
|------|------------|-------------|------------------|
| Presidential | 4370 | National emergency, highest priority | No |
| Extreme Imminent | 4371 | Extreme threat, expected to occur | Yes |
| Extreme Expected | 4372 | Extreme threat, may occur | Yes |
| Severe Imminent | 4373 | Severe threat, expected to occur | Yes |
| Severe Expected | 4374 | Severe threat, may occur | Yes |
| AMBER | 4379 | Child abduction emergency | Yes |
| Monthly Test | 4380 | Required monthly test | Yes |
| Public Safety | 4383-4391 | General public safety | Yes |

### 5.2 ETWS (Earthquake and Tsunami Warning System)

Broadcast via **SIB10** (primary) and **SIB11** (secondary).

| Type | Message ID | Delivery Requirement |
|------|------------|---------------------|
| Earthquake | 4352 | < 4 seconds |
| Tsunami | 4353 | < 4 seconds |
| Earthquake + Tsunami | 4354 | < 4 seconds |
| Test | 4355 | < 4 seconds |

### 5.3 Message Structure

```
┌─────────────────────────────────────────────────────┐
│           CBS Message Structure (TS 23.041)         │
├─────────────────────────────────────────────────────┤
│ Message ID (16 bits)      │ Identifies alert type   │
│ Serial Number (16 bits)   │ Unique message instance │
│ Data Coding Scheme        │ GSM 7-bit or UCS-2      │
│ Warning Type              │ ETWS specific           │
│ Warning Message Content   │ Up to 1395 bytes        │
└─────────────────────────────────────────────────────┘
```

---

## 6. Protocol Flow

### 6.1 Write-Replace-Warning Procedure

```
┌─────┐         ┌─────┐         ┌─────┐         ┌─────┐
│ CBC │         │ MME │         │ eNB │         │ UE  │
└──┬──┘         └──┬──┘         └──┬──┘         └──┬──┘
   │                │               │               │
   │ SBcAP Write-   │               │               │
   │ Replace-Warning│               │               │
   │ Request        │               │               │
   │───────────────▶│               │               │
   │                │               │               │
   │                │ S1AP Write-   │               │
   │                │ Replace-Warning│               │
   │                │ Request        │               │
   │                │──────────────▶│               │
   │                │               │               │
   │                │               │ SIB10/11/12   │
   │                │               │ Broadcast     │
   │                │               │──────────────▶│
   │                │               │               │
   │                │ S1AP Write-   │               │
   │                │ Replace-Warning│               │
   │                │ Response       │               │
   │                │◀──────────────│               │
   │                │               │               │
   │ SBcAP Write-   │               │               │
   │ Replace-Warning│               │               │
   │ Response       │               │               │
   │◀───────────────│               │               │
   │                │               │               │
```

### 6.2 S1AP Message (TS 36.413)

```
WriteReplaceWarningRequest ::= SEQUENCE {
    protocolIEs ProtocolIE-Container {
        { ID id-MessageIdentifier          CRITICALITY reject TYPE MessageIdentifier          PRESENCE mandatory }
        { ID id-SerialNumber               CRITICALITY reject TYPE SerialNumber               PRESENCE mandatory }
        { ID id-WarningAreaList            CRITICALITY ignore TYPE WarningAreaList            PRESENCE optional  }
        { ID id-RepetitionPeriod           CRITICALITY reject TYPE RepetitionPeriod           PRESENCE mandatory }
        { ID id-NumberofBroadcastRequest   CRITICALITY reject TYPE NumberofBroadcastRequest   PRESENCE mandatory }
        { ID id-WarningType                CRITICALITY ignore TYPE WarningType                PRESENCE optional  }
        { ID id-WarningSecurityInfo        CRITICALITY ignore TYPE WarningSecurityInfo        PRESENCE optional  }
        { ID id-DataCodingScheme           CRITICALITY ignore TYPE DataCodingScheme           PRESENCE optional  }
        { ID id-WarningMessageContents     CRITICALITY ignore TYPE WarningMessageContents     PRESENCE optional  }
    }
}
```

---

## 7. Geographic Targeting

### 7.1 Warning Area List Options

| Method | Granularity | Use Case |
|--------|-------------|----------|
| Cell ID List | Single cell | Precise local alert |
| TAC List | Tracking Area | Regional alert |
| Emergency Area ID | Operator-defined | Custom zones |

### 7.2 Multi-TAC Configuration

| TAC | Region | eNB ID | Cell ID |
|-----|--------|--------|---------|
| 0x0001 | Yaoundé | 0x19B | 0x19B01 |
| 0x0002 | Douala | 0x19C | 0x19C01 |

---

## 8. UE Behavior

### 8.1 Alert Reception

1. UE monitors **SIB10/11/12** in connected or idle mode
2. UE matches Message ID against enabled alert categories
3. UE displays alert with appropriate sound/vibration
4. User acknowledges alert (except Presidential)

### 8.2 User Settings

| Setting | Default | Modifiable |
|---------|---------|------------|
| Presidential Alerts | ON | No |
| Extreme Alerts | ON | Yes |
| Severe Alerts | ON | Yes |
| AMBER Alerts | ON | Yes |
| Test Alerts | OFF | Yes |

---

## 9. Testing Requirements

### 9.1 Functional Tests

| Test | Description | Pass Criteria |
|------|-------------|---------------|
| TC-01 | Send Presidential Alert | Alert displayed, cannot disable |
| TC-02 | Send AMBER Alert | Alert displayed with amber indicator |
| TC-03 | Send Earthquake ETWS | Alert in < 4 seconds |
| TC-04 | Multi-TAC broadcast | Both TACs receive alert |
| TC-05 | Kill alert | Alert stops broadcasting |

### 9.2 Protocol Verification

| Checkpoint | Tool | Filter |
|------------|------|--------|
| S1AP WriteReplaceWarningRequest | Wireshark | `s1ap.procedureCode == 36` |
| SIB12 broadcast | Wireshark | `lte-rrc.systemInformationBlockType12_element` |
| Message ID | Wireshark | `s1ap.MessageIdentifier` |

---

## 10. References

| Document | Title |
|----------|-------|
| 3GPP TS 23.041 | Technical realization of Cell Broadcast Service |
| 3GPP TS 23.038 | Alphabets and language-specific information |
| 3GPP TS 36.331 | E-UTRA RRC Protocol specification |
| 3GPP TS 29.168 | Cell Broadcast Centre interfaces with EPC |
| 3GPP TS 36.413 | S1 Application Protocol (S1AP) |
| ATIS-0700008 | CMAS via EPS |

---

*Version: 1.0*  
*Date: 2026-10-01*  
*Author: Arnaud DJOUM — F2G*
