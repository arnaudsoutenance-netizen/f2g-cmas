# F2G CMAS/PWS - Guide de Déploiement Complet

## Vue d'ensemble

Ce guide permet de déployer le système CMAS/PWS complet depuis zéro, avec ciblage géographique par TAC.

### Architecture

```
┌─────────────┐    SBc-AP     ┌──────────┐    S1-MME    ┌─────────┐
│  osmo-cbc   │◄─────────────►│   MME    │◄────────────►│  eNB1   │ TAC 1 (Yaoundé)
│ 127.0.0.10  │  :29168       │ Open5GS  │  :36412      │ srsRAN  │ PC1
│ REST :12345 │               │127.0.0.2 │              └─────────┘
└─────────────┘               └──────────┘                   
                                   │                         
                                   │ S1-MME                  
                                   ▼                         
                              ┌─────────┐              
                              │  eNB2   │ TAC 2 (Douala)
                              │ srsRAN  │ PC2 (192.168.1.101)
                              └─────────┘              
```

### Prérequis

- **PC1** : Ubuntu 22.04, Open5GS compilé, srsRAN 23.11, bladeRF
- **PC2** : Ubuntu 22.04, srsRAN 23.11, bladeRF (optionnel)
- **UE** : iPhone ou Android avec SIM F2G (IMSI 001010000099901)

---

## PARTIE 1 : Arrêt complet

### 1.1 Arrêter tous les composants

```bash
# Sur PC1
pkill -9 osmo-cbc
pkill -9 open5gs-mmed
pkill -9 srsenb
sudo pkill -9 open5gs

# Arrêter Docker Open5GS si utilisé
cd ~/docker_open5gs
docker-compose -f 4g-volte-deploy.yaml down

# Sur PC2 (si utilisé)
ssh f2g@192.168.1.101 "pkill -9 srsenb"
```

### 1.2 Vérifier que tout est arrêté

```bash
# PC1
ps aux | grep -E "osmo-cbc|open5gs|srsenb" | grep -v grep
# Doit être vide

# Nettoyer les fichiers temporaires
rm -rf /tmp/f2g_cmas
rm -f /tmp/*.log
```

---

## PARTIE 2 : Installation des composants patchés

### 2.1 Open5GS avec SBc-AP (MME)

```bash
# Cloner et appliquer le patch
cd ~/Desktop
git clone https://github.com/open5gs/open5gs.git open5gs-fork
cd open5gs-fork
git checkout v2.7.0

# Appliquer le patch SBc-AP
patch -p1 < /home/f2g/Videos/F2G_CMAS_FINAL/patches/open5gs-fork_sbcap_fixes.patch

# Compiler
meson build --prefix=/usr/local
ninja -C build
sudo ninja -C build install

# Vérifier
/usr/local/bin/open5gs-mmed --version
```

### 2.2 osmo-cbc avec ciblage TAC

```bash
# Cloner osmo-cbc
cd ~/Desktop
git clone https://gitea.osmocom.org/cellular-infrastructure/osmo-cbc.git
cd osmo-cbc
git checkout 0.5.3

# Appliquer les patches F2G
patch -p1 < /home/f2g/Videos/F2G_CMAS_FINAL/patches/osmo-cbc-scope-tai.patch
patch -p1 < /home/f2g/Videos/F2G_CMAS_FINAL/patches/osmo-cbc-expiration-timer.patch

# Compiler
autoreconf -fi
./configure
make -j4

# Installer
sudo cp src/.libs/osmo-cbc /usr/bin/osmo-cbc-patched

# Vérifier
/usr/bin/osmo-cbc-patched --version
```

### 2.3 srsRAN avec SIB12 dynamique (optionnel)

```bash
cd ~/srsRAN_4G
patch -p1 < /home/f2g/Videos/F2G_CMAS_FINAL/patches/srsran_sib12_live_paging.patch
mkdir -p build && cd build
cmake ..
make -j4
sudo make install
```

---

## PARTIE 3 : Configuration

### 3.1 Créer les dossiers de travail

```bash
mkdir -p /tmp/f2g_cmas/{cbc,mme,enb1,enb2}
```

### 3.2 Copier les configurations

```bash
CMAS_DIR="/home/f2g/Videos/F2G_CMAS_FINAL"

# Config osmo-cbc
cp $CMAS_DIR/configs/osmo-cbc/osmo-cbc.cfg /tmp/f2g_cmas/cbc/

# Config MME
cp $CMAS_DIR/configs/mme-fork.yaml /tmp/f2g_cmas/mme/

# Config SIB (sans alerte statique)
cp $CMAS_DIR/configs/sib/sib_pws_null.conf /tmp/f2g_cmas/

# Config eNB
cp $CMAS_DIR/configs/srsran/enb_pws.conf /tmp/f2g_cmas/enb1/
```

### 3.3 Créer la config freeDiameter pour MME

```bash
cat > /tmp/mme-fork-fd.conf << 'EOF'
Identity = "mme.localdomain";
Realm = "localdomain";
Port = 3868;
SecPort = 0;
NoRelay;
LoadExtension = "/usr/local/lib/x86_64-linux-gnu/freeDiameter/dbg_msg_dumps.fdx" : "0x8888";
LoadExtension = "/usr/local/lib/x86_64-linux-gnu/freeDiameter/dict_rfc5777.fdx";
LoadExtension = "/usr/local/lib/x86_64-linux-gnu/freeDiameter/dict_mip6i.fdx";
LoadExtension = "/usr/local/lib/x86_64-linux-gnu/freeDiameter/dict_nasreq.fdx";
LoadExtension = "/usr/local/lib/x86_64-linux-gnu/freeDiameter/dict_nas_mipv6.fdx";
LoadExtension = "/usr/local/lib/x86_64-linux-gnu/freeDiameter/dict_dcca.fdx";
LoadExtension = "/usr/local/lib/x86_64-linux-gnu/freeDiameter/dict_dcca_3gpp.fdx";
LoadExtension = "/usr/local/lib/x86_64-linux-gnu/freeDiameter/dict_s6a.fdx";
ConnectPeer = "hss.localdomain" { ConnectTo = "127.0.0.8"; Port = 3868; No_TLS; };
EOF
```

### 3.4 Configuration osmo-cbc

Vérifier `/tmp/f2g_cmas/cbc/osmo-cbc.cfg` :

```
log stderr
 logging filter all 1
 logging color 1
 logging print category-hex 0
 logging print category 1
 logging timestamp 1
 logging print file basename last
 logging print level 1
 logging level set-all notice

cbc
 ecbe
  local-ip 127.0.0.1
  local-port 12345
 sbcap
  local-ip 127.0.0.10
  local-port 29169
  remote-ip 127.0.0.2
  remote-port 29168
 peer f2g-mme
  protocol sbcap
  remote-ip 127.0.0.2
  remote-port 29168
```

---

## PARTIE 4 : Lancement

### 4.1 Ordre de lancement

1. Core Network (HSS, SGW, PGW, PCRF)
2. MME avec SBc-AP
3. osmo-cbc
4. eNB(s)

### 4.2 Lancer le Core Network (Docker)

```bash
cd ~/docker_open5gs
docker-compose -f 4g-volte-deploy.yaml up -d

# Vérifier
docker ps | grep open5gs
```

### 4.3 Lancer le MME patché (SBc-AP)

```bash
cd /tmp/f2g_cmas/mme

# Lancer le MME
/usr/local/bin/open5gs-mmed -c /home/f2g/Videos/F2G_CMAS_FINAL/configs/mme-fork.yaml > /tmp/f2g_cmas/mme.log 2>&1 &

# Vérifier
sleep 3
grep -i "sbcap\|sbc" /tmp/f2g_cmas/mme.log
# Doit afficher: "SBc-AP Server started"
```

### 4.4 Lancer osmo-cbc

```bash
cd /tmp/f2g_cmas/cbc

# Lancer osmo-cbc patché
/usr/bin/osmo-cbc-patched -c osmo-cbc.cfg &

# Vérifier la connexion au MME
sleep 3
# Doit afficher: "f2g-mme: Connected"
```

### 4.5 Lancer eNB1 (TAC 1 - PC1)

```bash
cd /tmp/f2g_cmas/enb1

# Créer la config eNB
cat > enb.conf << 'EOF'
[enb]
enb_id = 0x19B01
mcc = 001
mnc = 01
mme_addr = 127.0.0.2
gtp_bind_addr = 127.0.1.1
s1c_bind_addr = 127.0.1.1
s1c_bind_port = 0
n_prb = 50
tm = 4
nof_ports = 2

[enb_files]
sib_config = /tmp/f2g_cmas/sib_pws_null.conf
rr_config = /home/f2g/.config/srsran/rr.conf
rb_config = /home/f2g/.config/srsran/rb.conf

[rf]
device_name = bladeRF
device_args = auto
time_adv_nsamples = auto
tx_gain = 60
rx_gain = 40

[log]
all_level = info
phy_lib_level = none
filename = /tmp/f2g_cmas/enb1.log
file_max_size = 10000000

[scheduler]
nr_of_ue = 64
EOF

# Lancer
sudo srsenb enb.conf &
```

### 4.6 Lancer eNB2 sur PC2 (TAC 2 - optionnel)

```bash
# Sur PC2 (192.168.1.101)
ssh f2g@192.168.1.101

mkdir -p /tmp/f2g_cmas
cat > /tmp/enb2.conf << 'EOF'
[enb]
enb_id = 0x19C01
mcc = 001
mnc = 01
mme_addr = 192.168.1.100   # IP PC1
gtp_bind_addr = 192.168.1.101
s1c_bind_addr = 192.168.1.101
n_prb = 50

[enb_files]
sib_config = /tmp/sib_pws_null.conf

[rf]
device_name = bladeRF
tx_gain = 60
rx_gain = 40
EOF

# Copier la config SIB
scp f2g@192.168.1.100:/home/f2g/Videos/F2G_CMAS_FINAL/configs/sib/sib_pws_null.conf /tmp/

# Lancer
sudo srsenb /tmp/enb2.conf &
```

---

## PARTIE 5 : Vérification

### 5.1 Vérifier les connexions

```bash
# MME connecté aux eNBs
grep -i "S1 Setup" /tmp/f2g_cmas/mme.log

# osmo-cbc connecté au MME
grep -i "Connected" /tmp/f2g_cmas/cbc/*.log 2>/dev/null || echo "Voir stderr osmo-cbc"

# Nombre d'eNBs connectés
grep -c "eNB-UE S1AP" /tmp/f2g_cmas/mme.log
```

### 5.2 Tester une alerte

```bash
# Copier le script alert.sh
cp /home/f2g/Videos/F2G_CMAS_FINAL/scripts/alert.sh /tmp/

# Envoyer une alerte test TAC 1
/tmp/alert.sh send "TEST CMAS" 4370 30 tac:1

# Vérifier dans les logs MME
grep -E "4370|target TAC|warning for" /tmp/f2g_cmas/mme.log | tail -5
```

### 5.3 Résultat attendu

```
[mme] INFO: message_identifier: 4370
[mme] INFO:     target TAC[1]
[mme] INFO: SBc-AP: warning for 1 TA(s) (List-of-TAIs from CBC)
```

---

## PARTIE 6 : Script de lancement automatique

Utiliser le script fourni :

```bash
# Lancer tout automatiquement
/home/f2g/Videos/F2G_CMAS_FINAL/scripts/f2g_cmas_lab.sh start

# Arrêter tout
/home/f2g/Videos/F2G_CMAS_FINAL/scripts/f2g_cmas_lab.sh stop

# Voir le statut
/home/f2g/Videos/F2G_CMAS_FINAL/scripts/f2g_cmas_lab.sh status
```

---

## PARTIE 7 : Envoi d'alertes

### 7.1 Syntaxe alert.sh

```bash
/tmp/alert.sh send "MESSAGE" MSG_ID DURATION [SCOPE]

# Paramètres:
#   MESSAGE  : Texte de l'alerte (max 93 caractères)
#   MSG_ID   : 4370-4383 (catégories CMAS)
#   DURATION : Durée en secondes
#   SCOPE    : tac:1 | tac:2 | tac:1,2 (optionnel, défaut: tous)
```

### 7.2 Exemples

```bash
# Alerte TAC 1 uniquement (Yaoundé)
/tmp/alert.sh send "URGENCE YAOUNDE" 4370 60 tac:1

# Alerte TAC 2 uniquement (Douala)
/tmp/alert.sh send "URGENCE DOUALA" 4371 60 tac:2

# Alerte nationale (tous les TACs)
/tmp/alert.sh send "ALERTE NATIONALE" 4372 120 tac:1,2

# Arrêter une alerte manuellement
/tmp/alert.sh stop 4370
```

### 7.3 Catégories CMAS (Message ID)

| MSG_ID | Catégorie | Description |
|--------|-----------|-------------|
| 4370 | Presidential | Alerte présidentielle |
| 4371 | Extreme | Menace extrême imminente |
| 4372 | Severe | Menace grave |
| 4373 | AMBER | Enlèvement d'enfant |
| 4374-4379 | Reserved | Réservé |
| 4380 | Public Safety | Sécurité publique |
| 4381 | State/Local Test | Test local |
| 4382 | RMT | Test mensuel requis |
| 4383 | Exercise | Exercice |

---

## PARTIE 8 : Dépannage

### 8.1 osmo-cbc ne se connecte pas au MME

```bash
# Vérifier que le MME écoute sur SBc-AP
ss -tlnp | grep 29168

# Vérifier les IPs
ping 127.0.0.2
ping 127.0.0.10
```

### 8.2 Alerte non reçue sur le téléphone

```bash
# Vérifier que l'eNB est connecté
grep "S1 Setup Response" /tmp/f2g_cmas/mme.log

# Vérifier le TAC de l'UE
grep "TAI" /tmp/f2g_cmas/mme.log | tail -5

# Vérifier la config SIB (pas d'alerte statique)
grep "msg_id" /tmp/f2g_cmas/sib_pws_null.conf
# Doit être 0x0001 (hors plage CMAS)
```

### 8.3 "warning for 2 TA(s) (all eNBs)" au lieu de ciblage

Cela signifie que osmo-cbc n'est pas correctement patché :

```bash
# Vérifier le binaire
/usr/bin/osmo-cbc-patched --version

# Recompiler si nécessaire
cd ~/Desktop/osmo-cbc
patch -p1 < /home/f2g/Videos/F2G_CMAS_FINAL/patches/osmo-cbc-scope-tai.patch
make -j4
sudo cp src/.libs/osmo-cbc /usr/bin/osmo-cbc-patched
```

---

## Fichiers de référence

| Fichier | Emplacement |
|---------|-------------|
| Script alert.sh | `/home/f2g/Videos/F2G_CMAS_FINAL/scripts/alert.sh` |
| Config MME | `/home/f2g/Videos/F2G_CMAS_FINAL/configs/mme-fork.yaml` |
| Config osmo-cbc | `/home/f2g/Videos/F2G_CMAS_FINAL/configs/osmo-cbc/osmo-cbc.cfg` |
| Config SIB | `/home/f2g/Videos/F2G_CMAS_FINAL/configs/sib/sib_pws_null.conf` |
| Patches | `/home/f2g/Videos/F2G_CMAS_FINAL/patches/` |

---

## Specs 3GPP de référence

- **TS 29.168** : Cell Broadcast Centre Interfaces (SBc-AP)
- **TS 23.041** : Cell Broadcast Service
- **TS 36.413** : S1 Application Protocol
- **TS 36.331** : RRC (SIB10/11/12)

---

*F2G Telecom - Octobre 2026*
*Document créé le 14/10/2026*
