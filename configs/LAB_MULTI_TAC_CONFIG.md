# 📡 LAB CMAS MULTI-TAC — CONFIGURATION DE RÉFÉRENCE

**Date de validation** : 2026-09-30 13:40
**Statut** : ✅ FONCTIONNEL

---

## 🏗️ Architecture

```
PC1 (192.168.1.100)                    PC2 (192.168.1.101)
├── Open5GS Docker (172.22.0.x)        └── srsENB (eNB2)
│   └── MME (172.22.0.9:36412)             ├── TAC 2 (Douala)
├── srsENB (eNB1)                          ├── PCI 2
│   ├── TAC 1 (Yaoundé)                    ├── Cell ID 0x02
│   ├── PCI 1                              ├── EARFCN 1450
│   ├── Cell ID 0x01                       └── bladeRF xA4
│   ├── EARFCN 1450
│   └── bladeRF xA4
└── Port forward 36412 → 172.22.0.9
```

---

## 📻 PARAMÈTRES RADIO CRITIQUES

### eNB1 (PC1 - Yaoundé)

| Paramètre | Valeur |
|-----------|--------|
| **TAC** | 1 (0x0001) |
| **PCI** | 1 |
| **Cell ID** | 0x01 |
| **EARFCN** | 1450 |
| **Fréquence DL** | 1830 MHz |
| **Fréquence UL** | 1735 MHz |
| **Bande** | Band 3 |
| **PRB** | 50 (10 MHz) |

**Config** : `/home/f2g/Telecom/Core-Network/docker_open5gs/srsran/enb_tac1_cmas.conf`

### eNB2 (PC2 - Douala)

| Paramètre | Valeur |
|-----------|--------|
| **TAC** | 2 (0x0002) |
| **PCI** | 2 |
| **Cell ID** | 0x02 |
| **EARFCN** | 1450 |
| **Fréquence DL** | 1830 MHz |
| **Fréquence UL** | 1735 MHz |
| **Bande** | Band 3 |
| **PRB** | 50 (10 MHz) |

**Config** : `/home/f2g/.config/srsran/enb.conf` (sur PC2)
**Backup** : `/home/f2g/Desktop/CMAS_Complete_Package/configs/PC2_eNB2/`

---

## ⚠️ RÈGLES IMPORTANTES

### Les paramètres qui DOIVENT être DIFFÉRENTS entre eNB :
- **PCI** (Physical Cell ID) — Sinon collision, UE confus
- **Cell ID** — Identifiant unique de cellule
- **TAC** — Pour le ciblage géographique des alertes

### Les paramètres qui DOIVENT être IDENTIQUES :
- **EARFCN** — Même fréquence pour que les UE voient les 2 cellules
- **PLMN** (MCC/MNC) — 001/01 pour le lab

---

## 🔧 CONFIGURATION MME (PC1)

### Adresse S1AP
```
IP: 172.22.0.9
Port: 36412 (SCTP)
```

### Port Forwarding (iptables sur PC1)
```bash
# DNAT pour S1AP depuis PC2
sudo iptables -t nat -A PREROUTING -i enxdc045a7f5013 -p sctp --dport 36412 -j DNAT --to-destination 172.22.0.9:36412

# MASQUERADE pour le retour
sudo iptables -t nat -A POSTROUTING -o br-223479cb0310 -j MASQUERADE

# IP Forwarding
sudo sysctl -w net.ipv4.ip_forward=1
```

---

## 🚀 COMMANDES DE DÉMARRAGE

### PC1 — Core + eNB1

```bash
# 1. Démarrer Open5GS
cd /home/f2g/Telecom/Core-Network/docker_open5gs
docker compose -f sa-deploy.yaml up -d

# 2. Configurer port forwarding
sudo iptables -t nat -A PREROUTING -i enxdc045a7f5013 -p sctp --dport 36412 -j DNAT --to-destination 172.22.0.9:36412
sudo sysctl -w net.ipv4.ip_forward=1

# 3. Démarrer eNB1
cd /home/f2g/Telecom/Core-Network/docker_open5gs/srsran
sudo srsenb enb_tac1_cmas.conf
```

### PC2 — eNB2

```bash
# Connexion SSH
ssh f2g@192.168.1.101  # password: 1234

# Démarrer eNB2
cd /home/f2g/.config/srsran
sudo srsenb enb.conf
```

---

## ✅ VÉRIFICATION

### Vérifier les eNB connectés au MME
```bash
docker logs mme 2>&1 | grep "Number of eNBs" | tail -1
# Attendu: Number of eNBs is now 2
```

### Vérifier les TAC des UE
```bash
docker logs mme 2>&1 | grep -E "TAC\[" | tail -10
```

### Vérifier par UE spécifique
```bash
# UE1
docker logs mme 2>&1 | grep -B2 '001010000123451' | grep 'TAC' | tail -1

# UE2
docker logs mme 2>&1 | grep -B2 '001010000123453' | grep 'TAC' | tail -1

# UE3
docker logs mme 2>&1 | grep -B2 '001010000099901' | grep 'TAC' | tail -1
```

---

## 📁 FICHIERS DE CONFIG (BACKUP)

```
/home/f2g/Desktop/CMAS_Complete_Package/configs/
├── PC2_eNB2/
│   ├── enb_tac2.conf      # Config principale eNB2
│   ├── rr_tac2.conf       # Radio Resource (PCI, Cell ID, TAC)
│   └── sib_tac2.conf      # System Information Block
├── srsran/
│   ├── enb_tac1_cmas.conf # Config eNB1
│   └── sib_tac1_cmas.conf # SIB eNB1
└── LAB_MULTI_TAC_CONFIG.md # Ce fichier
```

---

## 🐛 PROBLÈMES RÉSOLUS

### Problème : UE ne s'attachent pas sur eNB2
**Cause** : PCI=1 et Cell ID=0x01 identiques à eNB1, EARFCN différent (3350 vs 1450)
**Solution** : 
- PCI → 2
- Cell ID → 0x02  
- EARFCN → 1450

### Problème : eNB2 ne se connecte pas au MME
**Cause** : Config pointait vers 172.22.0.9 (Docker interne) inaccessible depuis PC2
**Solution** :
- mme_addr → 192.168.1.100 (IP LAN de PC1)
- s1c_bind_addr → 192.168.1.101 (IP de PC2)
- gtp_bind_addr → 192.168.1.101

---

*Config validée le 2026-09-30*
