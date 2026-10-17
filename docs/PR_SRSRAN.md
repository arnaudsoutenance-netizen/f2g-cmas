# feat(rrc): broadcast CMAS SIB12 on Write-Replace-Warning and page UEs

## Summary

This PR extends the PWS (Public Warning System) support in srsENB to **dynamically broadcast SIB12 when a Write-Replace-Warning-Request is received**, and to **page UEs with the cmas-Indication** so they acquire the new system information. With this change, CMAS/ETWS alerts sent from a Cell Broadcast Centre are displayed on real handsets.

## Problem

The existing `pws-cmas-support` branch added S1AP handling for Write-Replace-Warning-Request and basic SIB12 generation, but:

1. **SIB12 not broadcast live**: The generated SIB12 was not written into the active broadcast buffers. UEs never saw the warning.
2. **No paging notification**: Per TS 36.331 §5.2.1.5, UEs must be notified via Paging with `cmas-Indication-r9` (or `etws-Indication`) to re-acquire SI. Without this, idle UEs ignore the new SIB12.

## Solution

### 1. Live SIB12 broadcast (`rrc.cc`)

In `rrc::write_replace_warning()`:

- Re-encode SIB12 with the warning content from the S1AP message
- Split the encoded SIB12 across the configured number of segments
- **Write in place** into the existing `sib_buffer` array used by MAC for BCCH transmission
- Zero-pad each segment to maintain alignment
- Only trigger MAC SIB reconfiguration if a segment size increases (avoids unnecessary interruption)

### 2. PWS Paging indication (`rrc_paging.h`)

New `paging_manager::add_pws_indication()`:

- Adds `cmas-Indication-r9` (for CMAS alerts, message_id 4370–4399) or `etws-Indication` (for ETWS, message_id 4352–4359) to the Paging message
- Transmits in **every paging occasion** of one default paging cycle (T = 128 frames by default) to ensure all UEs — idle and connected — receive the notification promptly (per TS 36.304 §7)
- Clears the indication flags after the paging cycle completes

### Files changed

| File | Lines | Description |
|------|-------|-------------|
| `srsenb/src/stack/rrc/rrc.cc` | +108 | Live SIB12 broadcast logic |
| `srsenb/hdr/stack/rrc/rrc_paging.h` | +74 | PWS paging indication |

## Testing

### Setup

- **CBC**: osmo-cbc 0.4.2
- **MME**: Open5GS with SBc-AP fix (separate PR)
- **eNB**: This branch
- **SDR**: bladeRF xA4
- **UE**: Commercial Android handset (Samsung, Xiaomi tested)

### Test procedure

```bash
# Send Presidential Alert (cannot be opted out)
curl -X POST http://127.0.0.1:12345/api/ecbe/v1/message \
  -H "Content-Type: application/json" \
  -d '{"cbe_name":"F2G","message_id":4370,"serial_nr":{"msg_code":101},"payload":{"data_utf8":"PRESIDENTIAL ALERT - THIS IS A TEST"}}'
```

### Results

**Before (pws-cmas-support branch):**
```
[RRC] Received WriteReplaceWarningRequest
[RRC] CMAS warning - generating SIB12, success=true
# But nothing displayed on phone — SIB12 not actually broadcast
```

**After (this PR):**
```
[RRC] Received WriteReplaceWarningRequest  
[RRC] CMAS warning - generating SIB12, success=true
[RRC] SIB12 written to broadcast buffer (3 segments, 142 bytes)
[RRC] PWS paging: cmas-Indication set for next paging cycle
[MAC] Paging: cmas-Indication-r9 transmitted in PO 0,1,2,3
# Phone displays: "Presidential Alert - THIS IS A TEST"
```

### Message categories tested

| Message ID | Type | Displayed |
|------------|------|-----------|
| 4370 | Presidential Alert | ✅ |
| 4371 | Extreme Alert | ✅ |
| 4380 | Monthly Test | ✅ |
| 4352 | ETWS Earthquake | ✅ |

## Compliance

- **TS 36.331 §5.2.1.5**: SI change notification via Paging with `systemInfoModification`
- **TS 36.331 §6.2.2 (SIB12)**: Warning message segment structure
- **TS 36.304 §7**: Paging for PWS notifications
- **TS 36.413 §8.12**: S1AP Write-Replace-Warning procedure

## Known limitations

1. **Stop-Warning**: Kill/cancellation is not yet implemented (warning broadcasts until repetition count exhausted)
2. **Concurrent warnings**: Only one active warning at a time; a new Write-Replace-Warning overwrites the previous SIB12
3. **SI scheduling**: Assumes default SI window; custom SI configurations may need adjustment

## Related PRs

- **Open5GS**: `fix/sbcap-wrw-response` — MME must send Write-Replace-Warning-Response for the chain to work

## Checklist

- [x] Compiles without warnings (`-Wall -Werror`)
- [x] Tested with real CBC (osmo-cbc)
- [x] Tested with real MME (Open5GS fork)
- [x] Alert displayed on multiple handset models
- [x] No regressions in normal RRC operation (attach, handover tested)
