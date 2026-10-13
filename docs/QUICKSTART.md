# F2G CMAS - Quick Start Guide

This guide helps you set up a complete CMAS/PWS system from scratch.

## Prerequisites

### Hardware
- Linux PC (Ubuntu 20.04/22.04 recommended)
- bladeRF xA4 or compatible SDR (USB 3.0)
- LTE-capable phone with CMAS/WEA enabled

### Software Dependencies
```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y build-essential cmake git libsctp-dev \
    libgnutls28-dev libgcrypt20-dev libssl-dev libidn11-dev \
    libmongoc-dev libbson-dev libyaml-dev libnghttp2-dev \
    libmicrohttpd-dev libcurl4-gnutls-dev libjansson-dev \
    meson ninja-build flex bison libtalloc-dev

# For srsRAN
sudo apt install -y libfftw3-dev libmbedtls-dev libboost-program-options-dev \
    libconfig++-dev libzmq3-dev libuhd-dev uhd-host
```

## Step 1: Clone This Repository

```bash
git clone https://github.com/arnaudsoutenance-netizen/f2g-cmas.git
cd f2g-cmas
```

## Step 2: Build osmo-cbc (with expiration patch)

```bash
# Clone osmo-cbc
git clone https://gitea.osmocom.org/cellular-infrastructure/osmo-cbc.git
cd osmo-cbc

# Apply the expiration patch
git apply ../patches/osmo-cbc-expiration-timer.patch

# Build
autoreconf -fi
./configure
make -j$(nproc)

# Install patched binary
sudo cp src/.libs/osmo-cbc /usr/bin/osmo-cbc-patched
cd ..
```

## Step 3: Build Open5GS MME (with SBc-AP support)

```bash
# Clone the fork with SBc-AP support
git clone https://github.com/open5gs/open5gs.git
cd open5gs
git fetch origin pull/4864/head:sbcap-branch
git checkout sbcap-branch

# Build
meson build --prefix=/usr/local
ninja -C build
sudo ninja -C build install
cd ..
```

## Step 4: Build srsRAN (with PWS support)

```bash
# Clone the fork with PWS support
git clone https://github.com/srsran/srsRAN_4G.git
cd srsRAN_4G
git fetch origin pull/1555/head:pws-branch
git checkout pws-branch

# Build
mkdir build && cd build
cmake ..
make -j$(nproc)
sudo make install
cd ../..
```

## Step 5: Configure the System

### 5.1 Create working directory
```bash
sudo mkdir -p /tmp/f2g_cmas/cbc
```

### 5.2 Copy configurations
```bash
# osmo-cbc
cp configs/osmo-cbc/osmo-cbc.cfg /tmp/f2g_cmas/cbc/

# Open5GS MME
sudo cp configs/open5gs/mme.yaml /etc/open5gs/

# srsRAN eNB
cp configs/srsran/enb.conf ~/.config/srsran/
```

### 5.3 Configure IP addresses (if needed)
Edit `/tmp/f2g_cmas/cbc/osmo-cbc.cfg`:
- `local-ip` for ECBE REST API (default: 127.0.0.1:12345)
- `remote-ip` for MME SBc-AP connection (default: 127.0.0.2:29168)

## Step 6: Start the System

### Terminal 1 - Start MME
```bash
sudo open5gs-mmed -c /etc/open5gs/mme.yaml
```

### Terminal 2 - Start osmo-cbc
```bash
cd /tmp/f2g_cmas/cbc
/usr/bin/osmo-cbc-patched -c osmo-cbc.cfg
```

### Terminal 3 - Start eNB
```bash
sudo srsenb ~/.config/srsran/enb.conf
```

## Step 7: Send Alerts

```bash
# Copy the alert script
cp scripts/alert.sh /tmp/

# Send a test alert (60 seconds)
/tmp/alert.sh send "EARTHQUAKE WARNING - TAKE COVER" 4370 60

# List active messages
/tmp/alert.sh list

# Stop an alert
/tmp/alert.sh stop 4370
```

## Verification

### Check osmo-cbc logs
```bash
grep -E "Starting expiration|expired|ACTIVE" /tmp/osmo.log
```

### Check MME logs
```bash
journalctl -u open5gs-mmed -f
```

### Expected flow
```
1. alert.sh sends POST to osmo-cbc REST API
2. osmo-cbc sends Write-Replace-Warning via SBc-AP to MME
3. MME sends Write-Replace-Warning-Request via S1AP to eNB
4. eNB broadcasts SIB12 with alert message
5. Phone displays alert
6. After timeout, message auto-expires (or use stop command)
```

## Troubleshooting

### "Could not allocate" error
An alert with the same msg_id is already active. Wait for expiration or use a different msg_id.

### "Connection refused" on port 12345
osmo-cbc is not running. Start it first.

### Phone doesn't receive alert
- Check eNB is broadcasting (look for SIB12 in logs)
- Ensure phone has CMAS/WEA enabled in settings
- Verify phone is attached to your network

### MME doesn't receive SBc-AP messages
- Check IP addresses in osmo-cbc.cfg match mme.yaml
- Verify SCTP connectivity: `ss -tlnp | grep 29168`

## Network Diagram

```
┌──────────┐     REST API      ┌──────────┐     SBc-AP      ┌──────────┐
│ alert.sh │ ────────────────► │ osmo-cbc │ ──────────────► │   MME    │
└──────────┘   127.0.0.1:12345 └──────────┘  127.0.0.2:29168└──────────┘
                                                                  │
                                                              S1AP│
                                                                  ▼
┌──────────┐      LTE Air      ┌──────────┐
│  Phone   │ ◄──────────────── │   eNB    │
└──────────┘     (SIB12)       └──────────┘
```

## Support

- GitHub Issues: https://github.com/arnaudsoutenance-netizen/f2g-cmas/issues
- Open5GS PR: https://github.com/open5gs/open5gs/pull/4864
- srsRAN PR: https://github.com/srsran/srsRAN_4G/pull/1555
