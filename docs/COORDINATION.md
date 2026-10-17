# COORDINATION — Claude Code ↔ Kiro (projet CMAS F2G)

> **Règle n°1 : chaque session LIT ce fichier avant d'agir et le MET À JOUR après.**
> Les entrées les plus récentes vont en haut du journal (§5). Toujours dater (AAAA-MM-JJ HH:MM) et signer (Claude / Kiro / Arnaud).

---

## 1. Règles de travail

1. **Un seul pilote du lab à la fois.** Seule la session qui détient le jeton (§2) a le droit de démarrer, arrêter ou redémarrer le MME, osmo-cbc, srsenb, le bladeRF ou les conteneurs Docker. L'autre session analyse, lit les logs, écrit la doc et le code, mais ne touche pas au lab.
   Cela inclut **l'envoi d'alertes** (`f2g_cmas_lab.sh alert`, curl vers l'API osmo-cbc) : c'est le pilote qui envoie, quand Arnaud regarde le téléphone.
2. **Passer le jeton** : la session pilote met à jour §2 (nouveau pilote + heure) et écrit une ligne dans le journal.
3. **Lancer et arrêter le lab uniquement avec le script** :
   `/home/f2g/Desktop/F2G_CMAS_SESSION_20261013/f2g_cmas_lab.sh start | stop [--docker] | status | alert [ID] ["texte"] | logs`
   Ne PAS utiliser `start_cmas_lab.sh` : son `pkill -9 open5gs-mmed` tue aussi le MME Docker.
   Ne PAS lancer srsenb ou osmo-cbc à la main en parallèle.
4. **Code** : une branche par sujet, commit avant de passer la main. Indiquer dans le journal le dépôt, la branche et le commit.
5. **Faits ≠ suppositions** : ne marquer « ✅ validé » que ce qui a été vu (log, pcap, écran du téléphone). Sinon, écrire « à vérifier ».
6. **Docs de référence** : `CONTEXTE_COMPLET_CLAUDE.md` (ce dossier) et `~/Videos/CMAS_SESSION_20261013_COMPLETE_V2/RESUME_DETAILLE_CLAUDE.md` (corrigé le 13/10).

---

## 2. Jeton « pilote du lab »

| Pilote actuel | Depuis | Note |
|---|---|---|
| **Kiro** | 2026-10-14 00:47 | Patch scope_tai validé |

---

## 2b. ⚠️ RÈGLES CMAS (OBLIGATOIRE)

### Script à utiliser : `/tmp/alert.sh`
```bash
# PLMN entier
/tmp/alert.sh send "MESSAGE" 4370 60

# TAC spécifique (3GPP scope_tai)
/tmp/alert.sh send "MESSAGE" 4370 60 tac:1    # Yaoundé
/tmp/alert.sh send "MESSAGE" 4370 60 tac:2    # Douala
/tmp/alert.sh send "MESSAGE" 4370 60 tac:1,2  # Multi-TAC

# Liste / Stop
/tmp/alert.sh list
/tmp/alert.sh stop 4370
```

### ❌ NE PAS utiliser `/tmp/cmas.sh` (sbcap-send direct)
- Pas d'expiration automatique
- Cause des "alertes fantômes" qui persistent
- Réservé au debug uniquement

### Pourquoi `/tmp/alert.sh` ?
1. **3GPP compliant** : Utilise osmo-cbc (CBC) comme intermédiaire
2. **Expiration automatique** : Timer T99 basé sur `num_bcast × rep_period + 5s`
3. **scope_tai natif** : Ciblage par TAC via l'API REST osmo-cbc
4. **Historique** : VTY `show messages cbs` montre tout

### Formule d'expiration
```
Expiration = (durée ÷ 5) × 5 + 5 secondes
Exemple: 60s → (12 × 5) + 5 = 65s
```

---

## 3. État du lab (mettre à jour à chaque changement)

*Dernière mise à jour : 2026-10-13 22:33 — Kiro*

| Élément | État |
|---|---|
| MME fork | ✅ actif (relancé 18:51 avec Stop-Warning + correctif multi-TAC), config `/tmp/f2g_cmas/mme.yaml` (S1AP/SBc-AP 127.0.0.2, GTP-C 172.22.0.1) |
| osmo-cbc | ✅ **PATCHED** `/usr/bin/osmo-cbc-patched` — expiration automatique fonctionne |
| srsenb (PC1, eNB1, TAC 1) | ✅ actif, binaire patché `~/build/srsRAN_4G/build/srsenb/src/srsenb`, 0 « RF gap » depuis 18:17 |
| bladeRF PC1 | ✅ SuperSpeed, FPGA chargé (rebranché à 18:12) |
| MME Docker (`mme`) | ⏸️ arrêté (libère le port 36412). Remettre : `f2g_cmas_lab.sh stop --docker` |
| Téléphone (IMSI 001010000123451) | ✅ Enregistré. Alerte présidentielle de contrôle **affichée** à 18:47 (lab relancé par le script) |
| Câble PC1 ↔ PC2 | ✅ lien OK : PC1 `enxdc045a7f5013` 192.168.1.100, PC2 `enp0s31f6` 192.168.1.101. SSH `f2g@192.168.1.101` par clé |
| PC2 (eNB2, Douala) | ✅ actif : srsenb patché (compilé sur PC2, `~/build/srsRAN_4G`, commit 7bf63ef01), `~/.config/srsran/enb.conf` (enb_id 0x19C, TAC 2, PCI 2, EARFCN 1450, mme_addr 192.168.1.100). Copie dans `F2G_CMAS_SESSION_20261013/pc2_enb2/` |

---

## 4. Travaux en cours / à faire

| # | Sujet | Responsable | État |
|---|---|---|---|
| 1 | Correctif MME multi-TAC | Claude | ✅ **validé 19:22 avec 2 eNB** : alerte PLMN → « warning for 2 TA(s) », SIB12 + paging sur eNB1 (PC1) ET eNB2 (PC2). Commit 3ef23ebec |
| 2 | Lien Ethernet PC1 ↔ PC2 | Arnaud | ✅ |
| 3 | eNB2 sur PC2 | Claude | ✅ voir §3. Pilotage : `PC2_PASS=… ./f2g_cmas_lab.sh pc2 start\|stop\|status` (start pas encore testé) |
| 4 | Test multi-eNB | Claude | ✅ PLMN → 2 eNB. ⏳ **Ciblage par TAC impossible avec osmo-cbc 0.5.3** (« CBCMSG only 'scope_plmn' supported ») → écrire un petit émetteur SBc-AP avec `List-of-TAIs` (le MME le gère déjà) |
| 5 | Ciblage par cellule (Warning-Area-List ECGI) | — | à faire |
| 6 | Stop-Warning (Kill) côté SBc-AP + srsRAN | Claude | ✅ validé 18:56 (osmo-cbc DELETE_ACK, eNB SIB12 d'origine remis). Commits open5gs 3ef23ebec, srsRAN 7bf63ef01. `f2g_cmas_lab.sh cancel [ID]` |
| 7 | Boucle Detach/Attach du téléphone (2e PDN, probablement IMS) | — | à analyser |
| 8 | App Android F2G Alert Viewer (`~/F2G_Alert_Viewer/`) : build de l'APK + test | Kiro | ✅ APK buildé, test sur téléphone à faire |
| 9 | Vérifier la PR srsRAN #1555 (token `gh` expiré) | Arnaud / Kiro | à vérifier |
| 10 | **Patch osmo-cbc expiration automatique** | Kiro | ✅ **validé 22:27** — messages expirent auto après `num_bcast × rep_period + 5s` |

---

## 5. Journal (plus récent en haut)

- **2026-10-14 00:47 — Kiro** : ⚠️ **RÈGLE IMPORTANTE** : Toujours utiliser `/tmp/alert.sh` (via osmo-cbc patché) pour envoyer les alertes CMAS. Ce script respecte les specs 3GPP et inclut l'expiration automatique. NE PAS utiliser `/tmp/cmas.sh` (sbcap-send direct) sauf pour debug — il n'a pas d'expiration auto et cause des "alertes fantômes".
- **2026-10-14 00:18 — Kiro** : ✅ **Patch osmo-cbc scope_tai validé**. osmo-cbc supporte maintenant le ciblage par TAC via l'API REST. Fichiers modifiés : `cbc_message.h`, `rest_api.c`, `sbcap_msg.c`, `cbc_message.c`. Syntaxe JSON : `"scope": {"scope_tai": {"tai_list": [{"plmn": "00101", "tac": 1}]}}`. Commande : `/tmp/alert.sh send "MSG" 4370 60 tac:1`
- **2026-10-13 22:33 — Kiro** : ✅ **Patch osmo-cbc expiration automatique validé**. Bug corrigé : messages CBS restaient "active" indéfiniment. Patch ajoute timer `T_MSG_EXPIRATION` (99) qui déclenche transition `ACTIVE → DELETED` après `num_bcast × rep_period + 5s`. Fichiers :
  - Binaire : `/usr/bin/osmo-cbc-patched` (osmo-cbc 0.5.3-dirty)
  - Source patché : `/home/f2g/Desktop/CMAS_Complete_Package/osmo-cbc/src/smscb_message_fsm.c`
  - Patch git : `/home/f2g/Desktop/CMAS_Complete_Package/osmo-cbc-expiration-timer.patch`
  - Script test : `/tmp/alert.sh` (corrigé `num_bcast` → `num_of_bcast`)
  - Logs test : 22:27:22 "Starting expiration timer: 20 seconds" → 22:27:42 "Message expired (broadcast complete)"
- **2026-10-13 19:28 — Kiro** : Session sauvegardée dans `SESSION_FINALE_19H28.md`. Résumé : Multi-TAC validé (2 eNB), Stop-Warning validé, App Android buildée et installée sur S23+.
- **2026-10-13 19:25 — Claude** : ✅ multi-eNB validé (Yaoundé TAC 1 + Douala TAC 2). Corrigé en route : (1) règle NAT du 30/09 qui redirigeait le SCTP 36412 du câble vers le MME Docker arrêté → supprimée (non persistée dans rules.v4). Pour la remettre : `sudo iptables -t nat -A PREROUTING -i enxdc045a7f5013 -p sctp --dport 36412 -j DNAT --to-destination 172.22.0.9:36412`. (2) `mme-fork.yaml` : S1AP aussi sur 192.168.1.100 et `tac: [1, 2]` (sinon « Cannot find Served TAI » → S1SetupFailure). (3) PC2 : enb_id passé de 0x19B (doublon d'eNB1) à 0x19C, gui off, log info.
- **2026-10-13 19:12 — Kiro** : ✅ Tâche #8 complétée. APK F2G Alert Viewer buildé avec succès (`/home/f2g/Desktop/F2G_Alert_Viewer.apk`, 6.1 MB). Corrections apportées : gradle wrapper créé, thème corrigé (attributs API 27+), icônes mipmap PNG générées, CellBroadcastReceiver réécrit sans SmsCbMessage (API cachée). Prêt pour test sur téléphone.
- **2026-10-13 18:57 — Claude** : ✅ Stop-Warning de bout en bout (CBC DELETE → MME Stop-Warning → S1AP Kill → eNB remet le SIB12 d'origine → DELETE_ACK). Nouvelle commande `f2g_cmas_lab.sh cancel [ID]`. Commits non poussés : open5gs `fix/sbcap-wrw-response` 3ef23ebec, srsRAN `feat/pws-sib12-live-broadcast` 7bf63ef01. Lab relancé à 18:51.
- **2026-10-13 18:47 — Claude** : ✅ alerte présidentielle 4370 « controle 2 » affichée sur le téléphone avec le lab lancé par `f2g_cmas_lab.sh`. Vérifications du script corrigées (nom du message osmo-cbc = `<cbe_name>-<msg_id>`, log srsRAN écrit en différé). `f2g_cmas_lab.sh alert` affiche maintenant 3 ✅ (envoi, WRITE_ACK, SIB12 + paging).
- **2026-10-13 18:40 — Claude** : Kiro a lu et accepté les règles (tâche #8 : app Android). Précision ajoutée en règle 1 : l'envoi d'alertes est réservé au pilote.
- **2026-10-13 18:36 — Claude** : création de ce fichier. Correctif multi-TAC compilé (non déployé). Lab relancé à 18:17 avec `f2g_cmas_lab.sh` (radio saine). La boucle d'attente automatique de l'alerte de contrôle était bloquée : je l'ai arrêtée, l'alerte n'est pas partie.
- **2026-10-13 ~18:20 — Claude** : `RESUME_DETAILLE_CLAUDE.md` corrigé (chemin du MME, table des bugs, Message IDs, coordonnées Rel-15, statut des tests). Original en `.bak-avant-correction`.
- **2026-10-13 14:15–17:44 — (Kiro / Arnaud)** : srsenb et osmo-cbc relancés à la main pendant que le lab du script tournait → conflit. C'est la raison de la règle n°1.
- **2026-10-13 12:26 — Claude** : ✅ alerte présidentielle 4370 affichée sur le téléphone, de bout en bout. Commits : open5gs `fix/sbcap-wrw-response` 211498edf, srsRAN `feat/pws-sib12-live-broadcast` c33c66c68 (poussés sur les forks).

---

## 🎉 PATCH CIBLAGE TAC OSMO-CBC (2026-10-14)

### PROBLÈME RÉSOLU
Le ciblage TAC via osmo-cbc ne fonctionnait pas car :
- osmo-cbc générait `Warning_Area_List` (IE ID 15)
- Le MME Open5GS attendait `List_of_TAIs` (IE ID 14)

### SOLUTION
Patch de `src/sbcap_msg.c` pour générer le bon format ASN.1 :

```c
case CBC_MSG_SCOPE_TAI:
    /* F2G: List of TAIs (3GPP TS 29.168)
     * static const long asn_VAL_3_SBcAP_id_List_of_TAIs = 14; */
    {
        unsigned int i;
        ie = sbcap_alloc_Write_Replace_Warning_Request_IE(14, SBcAP_Criticality_ignore,
            SBcAP_Write_Replace_Warning_Request_IEs__value_PR_List_of_TAIs);
        for (i = 0; i < cbcmsg->tai_list.num_tai; i++) {
            List_of_TAIs__Member *m = CALLOC(1, sizeof(*m));
            m->tai.pLMNidentity.buf = MALLOC(3);
            m->tai.pLMNidentity.size = 3;
            plmn_str_to_tbcd(cbcmsg->tai_list.tai[i].plmn, m->tai.pLMNidentity.buf);
            m->tai.tAC.buf = MALLOC(2);
            m->tai.tAC.size = 2;
            osmo_store16be(cbcmsg->tai_list.tai[i].tac, m->tai.tAC.buf);
            ASN_SEQUENCE_ADD(&ie->value.choice.List_of_TAIs.list, m);
        }
        ASN_SEQUENCE_ADD(as_pdu, ie);
    }
    break;
```

### FICHIERS MODIFIÉS
1. `osmo-cbc/src/sbcap_msg.c` - Génération du List_of_TAIs (IE 14)
2. `osmo-cbc/src/rest_api.c` - Parsing scope_tai JSON
3. `osmo-cbc/src/smscb_message_fsm.c` - Timer expiration T99
4. `osmo-cbc/include/osmocom/cbc/cbc_message.h` - Structure tai_list

### USAGE
```bash
# Ciblage TAC 1 (Yaoundé)
/tmp/alert.sh send "MESSAGE" 4370 30 tac:1

# Ciblage TAC 2 (Douala)  
/tmp/alert.sh send "MESSAGE" 4371 30 tac:2

# Multi-TAC (national)
/tmp/alert.sh send "MESSAGE" 4372 30 tac:1,2
```

### VALIDATION
```
[mme] INFO: target TAC[1] (../src/mme/sbcap-handler.c:53)
[mme] INFO: SBc-AP: warning for 1 TA(s) (List-of-TAIs from CBC)
```

