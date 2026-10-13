# F2G CMAS - Cell Broadcast Emergency Alert System

Complete implementation of **CMAS/ETWS** (Commercial Mobile Alert System / Earthquake and Tsunami Warning System) using open-source components.

## 🎯 Features

- ✅ **Full 3GPP Compliant** - PWS (Public Warning System) per 3GPP TS 23.041, TS 29.168
- ✅ **End-to-End Chain** - CBC → MME → eNB → UE validated
- ✅ **Auto-Expiration** - Messages automatically expire after broadcast duration
- ✅ **Stop-Warning** - Kill command to stop ongoing alerts
- ✅ **Multi-TAC** - Support for multiple Tracking Areas (multi-eNB)
- ✅ **All Alert Types** - Presidential, Extreme, Severe, AMBER, Public Safety

## 📦 Components

| Component | Version | Role |
|-----------|---------|------|
| **osmo-cbc** | 0.5.3 (patched) | Cell Broadcast Centre |
| **Open5GS MME** | Fork with SBc-AP | Mobility Management Entity |
| **srsRAN** | Fork with PWS | eNodeB (LTE base station) |
| **bladeRF** | xA4 | Software Defined Radio |

## 🚀 Quick Start

### 1. Start osmo-cbc (patched)
```bash
cd /tmp/f2g_cmas/cbc
/usr/bin/osmo-cbc-patched -c osmo-cbc.cfg > /tmp/osmo.log 2>&1 &
```

### 2. Send an alert
```bash
./scripts/alert.sh send "EARTHQUAKE WARNING" 4370 60
```

### 3. List messages
```bash
./scripts/alert.sh list
```

### 4. Stop an alert
```bash
./scripts/alert.sh stop 4370
```

## 📁 Repository Structure

```
f2g-cmas/
├── configs/
│   ├── osmo-cbc/        # CBC configuration
│   ├── open5gs/         # MME configuration
│   └── srsran/          # eNB configuration
├── patches/
│   └── osmo-cbc-expiration-timer.patch  # Auto-expiration fix
├── scripts/
│   └── alert.sh         # Main alert script
├── docs/
│   ├── COMMANDS.md      # Command reference
│   ├── COMPLETE_SETUP.md
│   └── ...
└── README.md
```

## 🔧 Patches Applied

### osmo-cbc Auto-Expiration Patch
**Bug fixed:** Messages stayed "active" forever instead of expiring.

**Solution:** Added timer `T_MSG_EXPIRATION` that triggers `ACTIVE → DELETED` transition after `num_bcast × rep_period + 5s`.

Apply patch:
```bash
cd osmo-cbc-source/
git apply patches/osmo-cbc-expiration-timer.patch
make -j$(nproc)
sudo cp src/.libs/osmo-cbc /usr/bin/osmo-cbc-patched
```

## ⏱️ Auto-Expiration Formula

```
Expiration = (num_bcast × rep_period) + 5 seconds
```

| Duration | Expiration |
|----------|------------|
| 15s | 20s |
| 30s | 35s |
| 60s | 65s |

## 📋 Message IDs (3GPP)

| ID | Type |
|----|------|
| 4370 | Presidential Alert |
| 4371-4372 | Extreme Alert |
| 4373-4378 | Severe Alert |
| 4379 | AMBER Alert |
| 4380 | Public Safety |

## 🔗 Related PRs

- **Open5GS**: [PR #4864](https://github.com/open5gs/open5gs/pull/4864) - SBc-AP Write-Replace-Warning
- **srsRAN**: [PR #1555](https://github.com/srsran/srsRAN_4G/pull/1555) - PWS SIB12 broadcast

## 📚 References

- 3GPP TS 23.041 - Cell Broadcast Service
- 3GPP TS 29.168 - SBc-AP Protocol
- 3GPP TS 36.331 - RRC Protocol (SIB12)
- ETSI TS 123 041 - CBS Technical Realization

## 👤 Author

**Arnaud DJOUM** - F2G TelcoLab  
Cameroon, October 2026

## 📄 License

MIT License - See [LICENSE](LICENSE)

## 🔧 Required Forks

To run this system, you need these modified versions:

| Component | Fork/Branch | Description |
|-----------|-------------|-------------|
| Open5GS | [PR #4864](https://github.com/open5gs/open5gs/pull/4864) | Adds SBc-AP Write-Replace-Warning support |
| srsRAN | [PR #1555](https://github.com/srsran/srsRAN_4G/pull/1555) | Adds PWS SIB12 live broadcast |
| osmo-cbc | Patch in `patches/` | Fixes auto-expiration bug |

See [docs/QUICKSTART.md](docs/QUICKSTART.md) for complete installation instructions.
