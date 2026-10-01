# PWS Message Flow — Write-Replace-Warning

## Complete S1AP Sequence

```mermaid
sequenceDiagram
    participant CBC as Cell Broadcast Center
    participant MME as MME (172.22.0.9)
    participant eNB as eNodeB (srsRAN)
    participant UE as UE (Phones)

    Note over CBC,UE: Initial Setup
    eNB->>MME: S1SetupRequest
    MME->>eNB: S1SetupResponse
    UE->>eNB: RRCConnectionRequest
    eNB->>UE: RRCConnectionSetup
    UE->>eNB: RRCConnectionSetupComplete
    
    Note over CBC,UE: Alert Injection
    CBC->>MME: SBcAP Write-Replace-Warning-Request
    Note right of CBC: MessageID: 4370 (Presidential)<br/>Serial: 0x3000<br/>Message: "EMERGENCY ALERT"
    
    MME->>eNB: S1AP WriteReplaceWarningRequest
    Note right of MME: Procedure Code: 36<br/>Warning Area List: TAC 1<br/>Repetition Period: 1<br/>Number of Broadcasts: 10
    
    eNB->>MME: S1AP WriteReplaceWarningResponse
    Note left of eNB: Broadcast Completed List<br/>indicates success

    Note over eNB,UE: SIB Broadcasting
    eNB->>UE: SIB12 (CMAS)<br/>System Information Broadcast
    Note right of eNB: messageIdentifier<br/>serialNumber<br/>warningMessageSegment
    
    UE->>UE: Display Alert<br/>Play Alert Tone
    
    Note over CBC,UE: Optional: Stop Alert
    CBC->>MME: SBcAP Stop-Warning-Request
    MME->>eNB: S1AP KillRequest
    eNB->>MME: S1AP KillResponse
    eNB->>UE: Stop SIB12 broadcast
```

## ETWS Flow (Earthquake/Tsunami)

```mermaid
sequenceDiagram
    participant MME as MME
    participant eNB as eNodeB
    participant UE as UE

    Note over MME,UE: ETWS Primary (SIB10)
    MME->>eNB: WriteReplaceWarningRequest<br/>(MessageID: 4352)
    eNB->>UE: SIB10 Broadcast
    Note right of UE: Immediate display<br/>< 4 seconds

    Note over MME,UE: ETWS Secondary (SIB11)
    eNB->>UE: SIB11 Broadcast
    Note right of UE: Detailed message<br/>content
```

## Message ID Mapping

```mermaid
graph TD
    A[Alert Type] --> B{Message ID Range}
    B -->|4352-4359| C[ETWS]
    B -->|4370| D[Presidential]
    B -->|4371-4372| E[Extreme Threat]
    B -->|4373-4378| F[Severe Threat]
    B -->|4379| G[AMBER Alert]
    B -->|4380| H[Monthly Test]
    B -->|4383-4391| I[Public Safety]
    
    C --> J[SIB10 + SIB11]
    D --> K[SIB12]
    E --> K
    F --> K
    G --> K
    H --> K
    I --> K
```

## Protocol Stack

```mermaid
graph LR
    subgraph "CBC Layer"
        A[Cell Broadcast Center]
    end
    
    subgraph "Core Network"
        B[SBcAP]
        C[MME]
    end
    
    subgraph "RAN"
        D[S1AP]
        E[eNodeB]
    end
    
    subgraph "Air Interface"
        F[LTE-RRC]
        G[SIB10/11/12]
    end
    
    subgraph "UE"
        H[Phone]
    end
    
    A -->|SBcAP| C
    C -->|S1AP| E
    E -->|RRC| H
```

## Warning Area Targeting

```mermaid
graph TD
    A[WriteReplaceWarningRequest] --> B{Warning Area List}
    B --> C[Cell ID List]
    B --> D[TAC List]
    B --> E[Emergency Area ID]
    
    C --> F[Single Cell Alert]
    D --> G[Regional Alert]
    E --> H[Custom Zone Alert]
    
    G --> I[TAC 1: Yaoundé]
    G --> J[TAC 2: Douala]
```

---

*Generated: 2026-10-01*  
*Reference: 3GPP TS 36.413, TS 23.041*
