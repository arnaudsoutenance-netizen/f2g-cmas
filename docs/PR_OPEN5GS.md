# fix(mme): make SBc-AP Write-Replace-Warning work end to end

## Summary

This PR fixes several issues in the MME's SBc-AP implementation that prevented the Write-Replace-Warning procedure from completing successfully. With these fixes, the full CMAS/PWS chain works end-to-end: **alerts sent from osmo-cbc are now displayed on actual handsets** via srsENB and bladeRF SDR.

## Problem

The existing SBc-AP implementation in the `sbcap-contribution` branch parsed Write-Replace-Warning-Request messages and forwarded them to connected eNBs via S1AP, but:

1. **No response to the CBC**: The MME never sent a Write-Replace-Warning-Response back to the CBC, causing osmo-cbc to timeout (T0 expiry) and mark the message as failed.
2. **Immediate cancellation**: A Stop-Warning-Request was sent to eNBs right after the Write, effectively cancelling the alert before it could be broadcast.
3. **Wrong byte order**: Message-Identifier and Serial-Number were read in little-endian instead of network byte order, causing eNBs to reject the warning as "Unknown category".
4. **DCS overwritten**: The Data Coding Scheme was forced to `0xFF` instead of using the value from the CBC, breaking character encoding.
5. **Missing initialization**: SBc-AP hash tables and log domain were not initialized at startup.

## Solution

| File | Change |
|------|--------|
| `sbcap-path.c/.h` | New `sbcap_send_to_sbc()` function to send PDUs back to the CBC over its SCTP association (PPID 24, stream 0) |
| `sbcap-handler.c` | Build and send Write-Replace-Warning-Response per TS 29.168 §4.3.4: echo Message-Identifier + Serial-Number, set Cause = `message-accepted` (0) if ≥1 eNB connected |
| `sbcap-handler.c` | Remove the erroneous call to `sbc_handle_stop_warning_request()` after processing a Write |
| `sbcap-handler.c` | Read Message-Identifier and Serial-Number using `ntohs()` / big-endian memcpy |
| `sbcap-handler.c` | Pass through the DCS from the CBC instead of hardcoding `0xFF` |
| `mme-context.c` | Initialize SBc-AP hash tables (`sbc_pws`, `sbc_message`) and register the `sbcap` log domain |
| `sbcap-handler.c` | Proper memory management: use `ogs_calloc`/`ogs_free`, reject requests missing mandatory IEs |

## Testing

Tested with the following setup:

- **CBC**: osmo-cbc 0.4.2 (REST API on `127.0.0.1:12345`, SBc-AP client to `127.0.0.2:29168`)
- **MME**: This branch (open5gs-fork)
- **eNB**: srsRAN 4G with PWS patch (live SIB12 broadcast + paging)
- **SDR**: bladeRF xA4
- **UE**: Commercial Android handset

### Test procedure

```bash
# Send a Presidential Alert (message_id 4370)
curl -X POST http://127.0.0.1:12345/api/ecbe/v1/message \
  -H "Content-Type: application/json" \
  -d '{"cbe_name":"TEST","message_id":4370,"serial_nr":{"msg_code":101},"payload":{"data_utf8":"PRESIDENTIAL ALERT TEST"}}'
```

### Results

| Checkpoint | Before | After |
|------------|--------|-------|
| osmo-cbc receives WRITE_ACK | ❌ Timeout T0 | ✅ `Received Event SBcAP_WRITE_ACK`, state ACTIVE |
| eNB generates SIB12 | ❌ `success=false` (Unknown) | ✅ `CMAS warning - generating SIB12`, `success=true` |
| Alert displayed on phone | ❌ Nothing | ✅ Presidential Alert shown |

### Wireshark trace

```
78.7446s  CBC → MME   Write-Replace-Warning-Request (SBc-AP)
78.7450s  MME → CBC   Write-Replace-Warning-Response, Cause = message-accepted (0)
78.7451s  MME → eNB   WriteReplaceWarningRequest (S1AP)
78.7452s  eNB → MME   WriteReplaceWarningResponse (S1AP)
```

## Caveats / Known Issues

1. **Multi-TAC bug**: When multiple eNBs with different TACs are connected, only the last eNB receives the alert due to an index reset bug in the TAI loop. This is a pre-existing issue and will be addressed in a follow-up PR.
2. **Stop-Warning not implemented**: Kill/Stop-Warning-Request handling is stubbed out. Only Write-Replace-Warning is functional.

## References

- 3GPP TS 29.168 — SBc-AP (CBC ↔ MME interface)
- 3GPP TS 36.413 §8.12 — S1AP Warning Message Procedures
- 3GPP TS 23.041 — Cell Broadcast Service (Message IDs, DCS)

## Checklist

- [x] Code compiles without warnings
- [x] Tested with osmo-cbc (real CBC)
- [x] Tested with srsENB (real eNB)
- [x] Alert displayed on physical handset
- [x] No memory leaks (valgrind clean on the SBc-AP paths)
