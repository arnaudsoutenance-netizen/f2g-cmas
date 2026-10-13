# F2G CMAS - Command Reference

## Quick Start

### 1. Start osmo-cbc (patched with auto-expiration)
```bash
pkill -9 -f osmo-cbc
cd /tmp/f2g_cmas/cbc && /usr/bin/osmo-cbc-patched -c osmo-cbc.cfg > /tmp/osmo.log 2>&1 &
```

### 2. Check status
```bash
pgrep -a osmo
```

## Alert Commands

### Send Alert
```bash
./scripts/alert.sh send "MESSAGE" [msg_id] [duration_sec]
```

**Arguments:**
| Argument | Default | Description |
|----------|---------|-------------|
| MESSAGE | "CMAS Test Alert" | Text displayed on phone |
| msg_id | 4370 | 3GPP Message ID |
| duration_sec | 30 | Broadcast duration in seconds |

**Examples:**
```bash
./scripts/alert.sh send "EARTHQUAKE WARNING" 4370 60
./scripts/alert.sh send "AMBER ALERT: Missing child" 4379 120
./scripts/alert.sh send "Test message" 4380 30
```

### List Messages
```bash
./scripts/alert.sh list
```

### Stop/Kill Alert
```bash
./scripts/alert.sh stop [msg_id]
./scripts/alert.sh stop 4370
```

## 3GPP Message IDs

| ID | Type | Priority |
|----|------|----------|
| 4370 | Presidential Alert | Highest |
| 4371-4372 | Extreme Alert | High |
| 4373-4378 | Severe Alert | Medium |
| 4379 | AMBER Alert | Medium |
| 4380 | Public Safety | Normal |
| 4381-4392 | State/Local Test | Low |

## Auto-Expiration Formula

```
Expiration = (num_bcast × rep_period) + 5 seconds

Where:
  num_bcast  = duration ÷ 5
  rep_period = 5 seconds (fixed)
```

**Examples:**
| Duration | num_bcast | Expiration |
|----------|-----------|------------|
| 15s | 3 | 20s |
| 20s | 4 | 25s |
| 30s | 6 | 35s |
| 60s | 12 | 65s |

## View Logs

```bash
# All logs
tail -50 /tmp/osmo.log

# Expiration events
grep -E "expired|ACTIVE|Starting" /tmp/osmo.log | tail -10
```

## Troubleshooting

### "Could not allocate" error
- An alert with the same msg_id is already active
- Wait for expiration OR use a different msg_id OR stop the current alert

### "No active messages" in list
- All messages have expired (normal behavior)
- osmo-cbc shows history with expiration timestamps

### Check osmo-cbc version
```bash
/usr/bin/osmo-cbc-patched --version
# Should show: OsmoCBC version 0.5.3-dirty
```
