# CMAS — intégration locale et comparaison avec F2G CMAS Hub

Audit statique du 17 octobre 2026, fuseau Africa/Douala. Rapport demandé par Arnaud.

## 1. Résultat principal

Le paquet local contient une chaîne **osmo-cbc REST → SBc-AP/SCTP → Open5GS MME modifié → S1AP → srsRAN 4G modifié → SIB12 et paging CMAS**. Le ciblage par liste de TAI est présent dans les correctifs CBC et le MME. Le ciblage précis par cellule ECGI n'est pas achevé dans les chemins examinés.

Le backend **F2G CMAS Hub examiné n'utilise pas cette chaîne CBC**. Ses deux chemins d'envoi écrivent une configuration SIB12 et envoient `SIGHUP` à srsENB. Ce sont des actions réelles sur les fichiers/processus, et non de simples simulations. Elles présentent des incompatibilités avec les sources srsRAN locales : **SIGHUP y déclenche l'arrêt**, et les générateurs Hub produisent `message_identifier`/`serial_number` alors que le parseur local attend `message_id`/`serial_num`.

Autres écarts déterminants :

- osmo-cbc attend `num_of_bcast`, et non `num_bcast` ; absence du premier champ → défaut zéro, donc pas de timer d'expiration dans ce binaire.
- `DELETE /api/ecbe/v1/message/:message_id` attend un identifiant numérique ; `scripts/alert.sh` utilise un nom CBE pour son arrêt, contrairement au handler observé.
- Les réponses REST CBC examinées sont **du texte**, notamment `Created` et `OK`, et non des objets JSON métier.
- Le MME répond au CBC immédiatement après avoir transmis la demande aux eNB ; il ne rassemble pas leurs résultats radio. Les statuts Hub reposent sur les opérations de fichier/signal. Aucun de ces résultats ne constitue un reçu du téléphone.

Ces constats portent sur les fichiers et binaires présents, pas sur une validation en émission du système actuellement déployé.

## 2. Périmètre et méthode

Racines examinées :

| Racine | Usage |
|---|---|
| `/home/f2g/Videos/F2G_CMAS_FINAL` | Paquet principal : scripts, configurations, correctifs, sources SBc-AP et binaire CBC |
| `/home/f2g/F2G_CMAS_HUB/backend/app` | Backend FastAPI : routes, schémas, modèles et contrôleurs |
| `/home/f2g/Desktop/open5gs-fork/src/mme` | Sources complémentaires du filtrage TAI et des procédures S1AP |
| `/home/f2g/build/srsRAN_4G` | Sources complémentaires RRC, S1AP, parseur SIB et traitement des signaux |

Lecture de sources avec numéros de lignes ; inspection **statique** du binaire CBC par `file`, `strings`, `readelf` et `objdump` ; comparaison SHA-256 de sa copie installée. Aucun lancement de binaire télécom, script métier, backend, test applicatif, conteneur ou service ; aucun appel HTTP, SCTP, SSH, VTY ou équipement ; aucune diffusion ni annulation. Seul ce rapport est créé.

Les `.env`, clés privées, bases de données et identifiants d'abonnés n'ont pas été utilisés pour établir les contrats. Aucune valeur de secret n'est reproduite. Les adresses citées sont des points d'intégration réseau du lab, pas des justificatifs d'authentification.

Niveaux de preuve : **source** = comportement lisible ; **binaire** = comportement identifié dans l'ELF examiné ; **historique** = déclaration de documentation ; **non vérifié** = fonctionnement ou valeur effective nécessitant une observation d'exécution. Les exemples JSON ci-dessous décrivent les contrats ; ils n'ont pas été envoyés.

## 3. Fichiers et points d'intégration locaux

Les références `P`, `H`, `O` et `R` ci-dessous correspondent respectivement aux quatre racines suivantes :

```text
P = /home/f2g/Videos/F2G_CMAS_FINAL
H = /home/f2g/F2G_CMAS_HUB/backend/app
O = /home/f2g/Desktop/open5gs-fork/src/mme
R = /home/f2g/build/srsRAN_4G
```

Chaque référence `P/fichier:ligne` désigne donc un chemin absolu obtenu en remplaçant ce préfixe ; les lignes citées sont celles des fichiers existants lors de l'audit, pas celles des fichiers futurs après application d'un patch.

| Fichier / preuve | Fonction établie |
|---|---|
| `P/scripts/alert.sh:11`, `:37`, `:54` | Client REST CBC, scopes PLMN ou TAI, envoi JSON |
| `P/scripts/alert.sh:61` | Arrêt par lecture VTY puis DELETE par nom : incompatible avec le binaire observé |
| `P/scripts/f2g_cmas_lab.sh:20`, `:70`, `:99` | Orchestration historique : MME fork hors Docker, CBC et eNB ; ne pas exécuter pour cet audit |
| `P/scripts/cmas_tac.sh:14`, `:38`, `:56` | Autre voie, émetteur SBc-AP direct ; expiration par processus shell différé |
| `P/sbcap-send/sbcap_send.c:119`, `:181`, `:216` | Construction ASN.1 Write/Stop et décodage de la réponse MME |
| `P/configs/osmo-cbc/osmo-cbc.cfg:9` | Configuration des interfaces ECBE et SBc-AP |
| `P/configs/mme-fork.yaml:14`, `:21`, `:42` | S1AP, SBc-AP et TAI servis `[1, 2]` |
| `P/patches/osmo-cbc-complete-f2g.patch:51`, `:113`, `:190` | Ajout REST `scope_tai`, encodage SBc-AP et expiration avec Stop |
| `P/source/open5gs-sbcap/sbcap-handler.c:39`, `:164`, `:338` | Extraction TAI et handlers Write/Stop, réponses au CBC |
| `O/sbc-handler.c:25`, `:64` | Sélection des eNB par TAI puis S1AP Write/Kill |
| `P/patches/srsran_sib12_live_paging.patch:121` | Écriture des buffers SIB12 actifs et paging CMAS |
| `R/srsenb/src/stack/rrc/rrc.cc:542`, `:696` | Implémentation locale Write et Kill, plus complète que le patch isolé |
| `P/configs/scripts/send_pws_alert.sh:74` | Ancienne voie de réécriture SIB puis arrêt/redémarrage de srsENB ; distincte du CBC |
| `P/pcap/CMAS_WriteReplaceWarning.pcap`, `P/pcap/CMAS_WRW_Response_fix.pcap` | Captures présentes ; contenu non décodé dans cet audit, donc pas de validation nouvelle fondée sur elles |

### Interfaces configurées

| Liaison | Adresse / protocole trouvé | Preuve |
|---|---|---|
| Client → CBC ECBE | `127.0.0.1:12345`, HTTP JSON entrant | `P/configs/osmo-cbc/osmo-cbc.cfg:12` |
| CBC → MME | CBC local `127.0.0.10:29169`, pair client vers `127.0.0.2:29168`, SBc-AP/SCTP | même fichier `:16` et `:20` |
| MME SBc-AP | serveur `127.0.0.2:29168` | `P/configs/mme-fork.yaml:21` |
| MME S1AP | `127.0.0.2:36412` et `192.168.1.100:36412` pour PC2 | même fichier `:14` |
| Console VTY CBC utilisée par le client | `127.0.0.1:4264`, commande `show messages cbs` | `P/scripts/alert.sh:12`, `:65`, `:77` ; configuration explicite du port VTY non trouvée dans ce fichier CBC |
| eNB1 du scénario SBc-AP | eNB ID `0x19B`, PLMN `001/01`, MME `127.0.0.2`, EARFCN `1450` | `P/configs/enb_sbcap.conf:1`, `:15` |

Il s'agit d'adresses **configurées** : aucune écoute ou association active n'a été testée. `P/configs/srsran/enb_tac1_cmas.conf:10` indique au contraire un MME Docker `172.22.0.9`. Les fichiers représentent plusieurs modes du lab, pas une configuration unique automatiquement cohérente.

## 4. Contrat REST osmo-cbc réellement identifiable

### Binaire examiné

`P/source/osmo-cbc-patched` est un ELF x86-64 PIE, non stripped, avec informations de debug. La copie `/usr/bin/osmo-cbc-patched` a exactement le même SHA-256 :

```text
5edfabb9822421e9e7643c8defc7269a4b79659600914d90675670b3d0d1dbfc
BuildID ELF : 7cc80bea197518262b56aa4d686a18f4341f3b92
```

La source serveur complète `rest_api.c` n'a pas été retrouvée aux anciens emplacements examinés. Les preuves suivantes sont des symboles/adresses virtuelles de ce binaire, non des lignes de source prétendument disponibles.

### Routes et réponses

| Méthode et route | Entrée | Réponse observée dans le code/binaire |
|---|---|---|
| `POST /api/ecbe/v1/message` | Objet JSON CBC décrit ci-dessous | 201, corps texte `Created` dans le chemin ACK |
| `DELETE /api/ecbe/v1/message/:message_id` | Paramètre entier numérique `0..65535` | 200, corps texte `OK` dans le chemin ACK ; ID inconnu : 404 `Unknown message ID` |
| GET de liste / détail / statut | Aucun endpoint enregistré dans le tableau examiné | Ne pas inventer une API GET ; le client local utilise la VTY |

Preuve binaire : symbole `api_endpoints` à `0x26060`, taille 96 octets, deux entrées de 48 octets : POST `/message` → `api_cb_message_post` à `0x13605` ; DELETE `/message/:message_id` → `api_cb_message_del` à `0x13c59`. `rest_api_init:0x1400e..0x14047` enregistre seulement ces deux entrées sous `/api/ecbe/v1`.

Le handler DELETE appelle `atoi` à `0x13ccf`, puis contrôle la plage à `0x13cd7..0x13ce4`. Un nom non numérique n'est pas résolu comme `cbe_name` ; `atoi` peut le convertir en zéro, donc sa validation n'est pas une validation syntaxique stricte de chaîne décimale.

Les deux handlers répondent par `ulfius_set_string_body_response`, POST à `0x13a90`, DELETE à `0x13e17`. Erreurs repérées : POST 400 avec texte de parsing ; défaut d'allocation 500 ; création refusée 409 `Could not allocate` dans `cbc_message_new:0x8d7f..0x8d8e` ; événement FSM illégal 500. Les scripts historiques qui cherchent un champ JSON `id` ne prouvent pas le succès de ce contrat.

### Exemple de corps POST : ciblage d'un TAC

```json
{
  "cbe_name": "hub-operation-exemple",
  "repetition_period": 5,
  "num_of_bcast": 12,
  "scope": {
    "scope_tai": {
      "tai_list": [{"plmn": "00101", "tac": 1}]
    }
  },
  "smscb_message": {
    "message_id": 4380,
    "serial_nr": {
      "serial_nr_decoded": {
        "geo_scope": "plmn_wide",
        "msg_code": 1,
        "update_nr": 0
      }
    },
    "payload": {
      "payload_decoded": {
        "character_set": "gsm",
        "data_utf8": "Texte de demonstration"
      }
    }
  }
}
```

Structure reproduite de `P/scripts/alert.sh:37..56`, avec message d'exemple. `geo_scope` du serial et `scope_tai` de routage sont deux champs distincts : cet exemple conserve `plmn_wide` comme le client local, sans prétendre qu'il représente un routage à toutes les cellules.

Scope PLMN alternatif : `"scope":{"scope_plmn":{"plmn":"00101"}}`. Multi-TAC : ajouter `{"plmn":"00101","tac":2}` à `tai_list`. Ne pas fournir simultanément les deux scopes ; le patch priorise `scope_tai` (`P/patches/osmo-cbc-complete-f2g.patch:60`).

### Champs, validations et limites

| Élément | Preuve / comportement |
|---|---|
| `cbe_name` | Chaîne obligatoire, `json2cbc_message:0x12f80..0x12fae` |
| `category` | Facultatif ; libellés trouvés `normal`, `high_priority`, `background`, défaut interne 2 ; ce n'est pas la catégorie CMAS présidentielle/AMBER du message ID |
| `repetition_period` | Entier `0..4095`, parsing `0x13048..0x13083` |
| `num_of_bcast` | Entier `0..65535`, défaut **0** ; lecture clé à `0x13099..0x130a3`, défaut à `0x130fa..0x13104` |
| `warning_period_sec` | Optionnel `0..65535`, défaut interne −1, `0x13125..0x1316b` ; distinct du timer local fondé sur le nombre de diffusions |
| `scope`, `smscb_message` | Obligatoires ; chaînes d'erreur et appels de parsing dans `json2cbc_message` |
| `scope_tai.tai_list` | Tableau non vide, maximum 16 ; entrée avec PLMN chaîne et TAC ; source : patch complet `:64..110` |
| TAC | Stockage `uint16_t`. Le patch vérifie l'existence de `tac` mais pas explicitement son type/plage avant `json_integer_value` puis conversion ; validation à renforcer côté futur adaptateur |
| Serial / payload | Déclarations `serial_nr_encoded` ou `serial_nr_decoded`, `payload_decoded`, et messages de contrôle des pages hexadécimales trouvés dans les chaînes du binaire ; contrat détaillé de toutes les variantes encodées non reconstruit |

`num_bcast` existe comme nom **interne** dans les structures/debugs, pas comme alias JSON identifié dans le parseur. `P/scripts/f2g_cmas_lab.sh:163` utilise pourtant ce mauvais nom. `P/docs/COORDINATION.md:109` relate sa correction ailleurs en `num_of_bcast`, sans corriger la copie de ce script dans le paquet.

`P/scripts/alert.sh` ne protège pas correctement le texte pour JSON : interpolation shell directe à `:56`. Guillemets et retours ligne peuvent invalider le corps. Le compteur `msg_code` de `:25..26` n'est pas borné, contrairement à celui modulo 1024 de `f2g_cmas_lab.sh:153`.

## 5. Ciblage et propagation SBc-AP / S1AP

### Ciblage prouvé par TAI

1. CBC : `P/patches/osmo-cbc-complete-f2g.patch:9..33` ajoute jusqu'à 16 TAI, composés de PLMN et TAC. Le scope est envoyé aux pairs CBC sans filtrage local de pair (`:41..47`).
2. Encodage : PLMN en TBCD trois octets ; TAC sur deux octets, ordre réseau. Le patch ajoute l'IE `List-of-TAIs` numéro 14 aux demandes **Write et Stop** (`:121..185`).
3. MME : `P/source/open5gs-sbcap/sbcap-handler.c:40..55` décode la liste. Sans liste, `:61..85` forme l'union dédupliquée des TAI des eNB connectés.
4. Sélection : `O/sbc-handler.c:31..59` compare les TAI complets avec ceux annoncés par chaque eNB, puis envoie une requête S1AP par eNB sélectionné. Même principe pour Kill, `:70..98`.
5. Radio : `R/srsenb/src/stack/rrc/rrc.cc:588` applique le SIB12 à toutes les cellules internes parcourues. Le filtre est donc **au niveau eNB**, pas une restriction ECGI fine à l'intérieur de cet eNB.

La présence de TAI demandés ne prouve pas qu'un eNB correspondant existe. L'ACK MME est calculé sur `no_of_tai > 0`, et non sur le nombre de transmissions ou de cellules confirmées (`P/source/open5gs-sbcap/sbcap-handler.c:454..461`). Un TAC inexistant peut donc être déclaré accepté si une liste non vide a été reçue.

### Cellules et configurations du lab

La documentation associe TAC 1 à Yaoundé/eNB1, TAC 2 à Douala/eNB2. `P/configs/PC2_eNB2/rr_tac2.conf:57..62` indique `cell_id=0x02`, TAC 2, PCI 2, EARFCN 1450 ; `P/configs/enb_sbcap.conf:2` indique eNB1 `0x19B`. `P/configs/LAB_MULTI_TAC_CONFIG.md:31` et `:46` décrivent la paire.

Le fichier RR PC2 contient une syntaxe de travail à vérifier avant tout futur déploiement (ligne TAC sans point-virgule à `:59`) ; aucune compilation/lecture du fichier par srsENB n'a été testée. Une mention de TAC dans un nom de fichier ne garantit pas sa valeur effective : le RR référencé, les TAI servis MME et les paramètres transmis au lancement doivent concorder.

**ECGI non réalisé de bout en bout** : le patch CBC contient du code `CBC_MSG_SCOPE_EUTRAN_CGI` sous `#if 0` (`P/patches/osmo-cbc-complete-f2g.patch:161`, `:187`) ; le builder MME laisse `/* TODO: optional Warning Area List */` dans `O/s1ap-build.c:3343`. La présence des types ASN.1 ECGI dans la bibliothèque ne suffit pas à prouver leur traitement. `P/docs/COORDINATION.md:92` le classe également « à faire ».

### Voie de secours SBc-AP directe

`P/sbcap-send/sbcap_send.c` est un client SCTP, pas une route HTTP : PPID 24 (`:29`), port par défaut 29168, stream 0 (`:332`), attente réponse de cinq secondes (`:274`, `:339`). Il envoie Write ou Stop avec message ID, serial et éventuelle liste de TAC (`:119..213`).

Son CB-Data est limité à une page : `1 octet nombre de pages + 82 octets GSM7 + 1 octet longueur utile` (`:52..76`). Texte tronqué à 93 octets/caractères du sous-ensemble géré ; caractères non reconnus remplacés par `?` (`:35..49`). DCS `0x0F`, répétition 5, nombre demandé 0 (`:154..169`). Ce n'est pas un encodeur UTF-8 français complet ou multipage.

Serial construit `GS(2) | code(10) | update(4)` par `((gs << 14) | ((code & 0x3ff) << 4) | (update & 0xf))`, `:302..305`. Le client choisit GS=2 avec TAC et GS=1 sans TAC ; le commentaire nommant GS=2 « TA wide » ne constitue pas une validation normative de ce libellé.

**Défaut du wrapper direct** : `P/scripts/cmas_tac.sh:38..47` ajoute `--tac` à Write, mais le Stop différé `:61` et les Stop manuels `:75`, `:82` ne le retransmettent pas. Le client recalcule alors un autre GS, donc un **serial différent** pour le même code : annulation corrélée non fiable. Le suivi `/tmp/.cmas_tac_tracking` et le `sleep` du shell ne sont ni un ACK radio ni un mécanisme durable. Le chemin de binaire codé à `:14` vise de plus un ancien dossier Desktop. Aucun de ces scripts n'a été exécuté.

## 6. Expiration et remontées d'état réelles

### CBC : état de transaction et timer

Le patch complet calcule `N × période + 5 secondes` après WRITE_ACK ; zéro diffusion demandée ne crée aucun timer (`P/patches/osmo-cbc-complete-f2g.patch:221..262`). Pour N=12 et période 5, le délai de nettoyage est 65 secondes après activation, pas une garantie de douze réceptions terminal.

À T99, le patch complet envoie DELETE aux FSM enfants puis attend DELETE_ACK dix secondes (`:280..285`). Le patch isolé `P/patches/osmo-cbc-expiration-timer.patch:91..95` passe directement à DELETED : ces deux fichiers ne sont **pas équivalents**.

Le **binaire examiné confirme la version complète** : `calc_expiration_timeout:0x1af5a..0x1af9d` calcule N×période+5 ; `smscb_fsm_timer_cb:0x1bd65..0x1bd6d` diffuse `SMSCB_PEER_E_DELETE=3`, puis `0x1bd83..0x1bd95` passe à `SMSCB_S_WAIT_DELETE_ACK=5`, timeout 10, timer 3. La version installée comparée a le même hash. Aucun état vivant n'en est déduit.

Liste et diagnostics disponibles dans les clients : VTY `show messages cbs` ; journaux de connexion `f2g-mme: Connected`, `WRITE_ACK`, `WRITE_NACK`, expiration ; MME `Tx Write-Replace-Warning-Response`, `Tx Stop-Warning-Response` ; RRC `CMAS Alert Broadcast`, `PWS paging: cmas`, `SIB12 restored`. Preuves d'utilisation : `P/scripts/f2g_cmas_lab.sh:135..145`, `:171..192`, `:219..221`. Ces chemins de logs sont décrits, pas consultés comme événements actuels.

### Ce que prouvent les ACK

| Niveau | Preuve trouvée | Limite |
|---|---|---|
| HTTP CBC 201 / WRITE_ACK | CBC a terminé son chemin de création ACK | Ne prouve pas une réception UE |
| SBc-AP Write Response | MME renvoie ID, serial, Cause ; réponse après l'appel de forwarding | Cause acceptée basée sur présence TAI, sans attente S1AP ni agrégation de cellules |
| SBc-AP Stop Response | Même principe après transmission Kill, `sbcap-handler.c:208..223` | Pas de preuve d'arrêt constaté à chaque eNB |
| S1AP Write/Kill Response | eNB construit des successfulOutcome ID+serial, `R/srsenb/src/stack/s1ap/s1ap.cc:2401..2439` | `result.success` est journalisé mais ne modifie pas ces réponses ; liste de cellules achevées non fournie |
| Traitement MME des réponses S1AP | `O/s1ap-handler.c:4973..5020` | Lecture de l'enveloppe et journal IP/eNB seulement ; pas d'agrégation ni remontée de résultat détaillé au CBC |
| SIB12 et paging | Buffers actifs réencodés et `add_pws_indication(false,true)` ; `R/srsenb/src/stack/rrc/rrc.cc:542..669` | État logiciel émetteur, sans reçu du téléphone |

Kill restaure le SIB12 sauvegardé avant la première modification dynamique, sans retirer le scheduling SIB12 (`R/srsenb/src/stack/rrc/rrc.cc:678..736`). Il ne compare pas ici l'ID/serial demandé à une alerte active avant la restauration. Une seule image SIB12 dynamique est gérée ; plusieurs messages CBC ne deviennent pas automatiquement plusieurs alertes simultanées sur l'eNB.

Les paramètres répétition/nombre sont extraits dans S1AP (`s1ap.cc:2322..2330`) ; aucun usage de ces champs n'a été trouvé dans le chemin RRC `write_replace_warning` examiné. Le timer CBC et sa procédure Stop sont donc essentiels : ne pas déduire une extinction autonome radio du seul `num_of_bcast` transmis.

## 7. Backend F2G CMAS Hub : routes et formats

Préfixe par défaut `/api/v1` dans `H/core/config.py:26`, appliqué dans `H/main.py:199`. Valeur d'environnement effective non lue. Routes enregistrées dans `H/api/__init__.py:10..15`.

### API métier alertes

| Route par défaut | Contrat / comportement | Preuve |
|---|---|---|
| `GET /api/v1/alerts` | Filtres status/type, page, limit 1..100, tri ; `{data,pagination:{page,limit,total,total_pages}}` | `H/api/endpoints/alerts.py:30..82` |
| `POST /api/v1/alerts` | `AlertCreate`, 201 `AlertResponse` ; contrôle existence cellules et refus cellules offline | même fichier `:85..155` |
| `GET /api/v1/alerts/{alert_id}` | `AlertDetailResponse`, avec logs et créateur | `:158` |
| `PATCH /api/v1/alerts/{alert_id}` | `AlertUpdate` : contenu, programmation, durée, cellules | `:185` ; schéma `H/schemas/__init__.py:135` |
| `DELETE /api/v1/alerts/{alert_id}` | Suppression en base, 204, DRAFT seulement | `:261..284` |
| `POST /api/v1/alerts/{alert_id}/send` | `{"immediate":true}` ; dispatch immédiat SSH/SFTP, réponse `AlertSendResponse` | `:287..367` |
| `POST /api/v1/alerts/{alert_id}/cancel` | SCHEDULED seulement, changement de statut en base ; aucun Stop radio | `:370..410` |

Exemple descriptif de création :

```json
{
  "alert_type": "CMAS",
  "message_id": 4380,
  "content": "Texte de demonstration",
  "duration": 3600,
  "cell_ids": ["UUID-interne-cell_sites"]
}
```

`H/schemas/__init__.py:110..132` : type CMAS/ETWS, contenu 1..1395 caractères, durée 60..86400 secondes, défaut 3600 ; IDs CMAS 4370..4399, ETWS 4352..4359 ; `scheduled_at` et `template_id` optionnels. Les plages sont celles de la validation Hub, pas une certification de prise en charge de chaque ID par la radio.

Réponse de création déclarée : champs de base plus `id,status,scheduled_at,sent_at,expires_at,created_at,updated_at,created_by,template_id,cells` (`:142..155`). Réponse d'envoi : `{"id":"…","status":"SENT|FAILED|…","message":"…","job_id":null}` (`:167..171`) ; aucun job n'est créé dans cette route. Réponses HTTP explicitement codées pour erreurs métier : 400 (état incompatible/cellules absentes), 404 (alerte inconnue), champs `detail` via `HTTPException` (`alerts.py:302..318`). Les corps effectifs n'ont pas été testés.

Statuts déclarés : `DRAFT,SCHEDULED,SENDING,SENT,FAILED,CANCELLED` (`H/schemas/__init__.py:25..31`). `send_request.immediate` n'est pas utilisé dans la fonction d'envoi ; aucun scheduler/worker de programmation retrouvé dans les Python du backend. Une programmation stockée n'est donc pas une exécution différée prouvée.

### Ciblage métier et persistance

`cell_ids` désigne `CellSite.id`, UUID SQL interne, pas directement TAC, PCI, identifiant ECGI ou `CellSite.cell_id` (`H/api/endpoints/alerts.py:93..95`, `:130..133`). `H/schemas/__init__.py:213..224` expose entre autres `cell_id,tac,enb_ip,enb_port,enb_username,enb_config_path,earfcn,pci,location,zone_name`, TAC 1..65535 ; port SSH par défaut 22, fichier SIB par défaut `/etc/srsenb/sib.conf`.

La sélection effective se fait par destination SSH du catalogue ; ni TAC ni ECGI ne sont insérés dans le SIB12 généré (`H/services/enb_controller.py:52..71`, `:77..102`). Plusieurs cellules visant le même eNB peuvent conduire à plusieurs écritures sur le même équipement, sans protocole d'aire radio.

Tables `alerts`, `alert_cells`, `alert_logs` dans `H/models/alert.py:27..88`. États par cellule `pending/sent/failed`, timestamp et erreur. Aucune corrélation persistante CBC/serial/SBc-AP ou cellule confirmée n'a été trouvée dans ces modèles. Base par défaut SQLite async (`H/core/config.py:29`), base effective non ouverte.

### Deuxième voie : API infrastructure

`POST /api/v1/network/broadcast-alert`, schéma `H/api/endpoints/network.py:272..279`, implémentation `:320..391` :

```json
{
  "message_id": 4380,
  "content": "Texte de demonstration",
  "enb_ids": ["enb1"],
  "serial_number": 12288,
  "warning_type": 3,
  "force": false
}
```

Réponse déclarée : `{success:bool,message:str,details?:object}` ; détails `{success,enbs:{identifiant:résultat},ues_notified:n}`. Le contrôle préalable d'UE peut renvoyer HTTP normal avec `success:false`. Le compteur `ues_notified` est une **estimation de connexions**, pas une confirmation de réception. Le texte de doc annonce succès sur au moins un eNB, alors que le code met le résultat global à faux dès qu'un eNB échoue (`:371..377`).

`enb_ids` cible une table **distincte** du catalogue SQL : `H/services/infra_controller.py:264..288` prédéfinit `enb1/enb2`, TAC1/TAC2, EARFCN3350 et des fichiers locaux sous `/home/f2g/Telecom/Core-Network/docker_open5gs/srsran`. Le chemin du binaire y est `/usr/bin/srsenb`, différent du build modifié utilisé par le lab. Il n'est pas prouvé qu'il s'agisse du même exécutable ou de la même configuration effective.

Autres routes utiles à l'état, identifiées sans les appeler :

- `/api/v1/network/status`, `/open5gs/status`, `/enb/status` (`H/api/endpoints/network.py:51`, `:67`, `:75`).
- `/api/v1/network/open5gs/logs`, `/enb/{enb_id}/logs` (`:132`, `:195`).
- `/api/v1/network/ue/connected`, `/ue/check`, `/hardware` (`:282`, `:301`, `:398`).
- Catalogue `/api/v1/cells` : GET/POST, GET/PATCH/DELETE `/{cell_id}`, GET `/{cell_id}/status`, POST `/health-check` (`H/api/endpoints/cells.py:25..205`). **Le GET status effectue SSH et met à jour la base** : il n'a pas été utilisé pour cet audit en lecture seule.

## 8. Comparaison et anomalies d'intégration

| Sujet | Chaîne locale CBC | Hub examiné | Conséquence |
|---|---|---|---|
| Transport d'envoi | REST CBC puis SBc-AP/S1AP | SSH/SFTP ou fichier local + signal | Aucun raccord CBC effectif trouvé |
| Ciblage | PLMN / liste TAI, eNB sélectionnés par TAI | UUID SQL ou enb1/enb2 prédéfinis | Nécessité d'un mapping explicite, pas d'équivalence automatique cellule→TAC |
| Serial | Structuré code/update/GS, conservé dans la transaction CBC | Aléatoire par génération ou défaut 0x3000 ; non persisté pour corrélation | Déduplication et arrêt cohérent non garantis |
| Encodage | SMSCB/CB-Data ; client direct GSM7 limité | Texte dans configuration SIB12 | Contrats différents ; caractères, pages et DCS à valider |
| Expiration | Timer CBC puis Stop→Kill | `expires_at` calculé en base | Pas d'arrêt radio Hub automatique identifié |
| Annulation | DELETE numérique → Stop SBc-AP → Kill S1AP | cancel seulement SCHEDULED | Aucune annulation radio des alertes déjà envoyées |
| État | FSM CBC et logs MME/eNB, ACK partiels | Statut SQL / retour d'opération fichier et signal | Aucun reçu UE ; ne pas afficher « livré » |
| Retour HTTP | Texte CBC, pas JSON | JSON FastAPI | Adaptateur doit parser code HTTP + corps texte |

### Défauts prioritaires, avec preuves

1. **SIGHUP ne recharge pas le build srsRAN examiné.** `R/lib/src/support/signal_handler.cc:57..64` enregistre SIGHUP avec les signaux d'arrêt ; `:43..52` appelle le handler d'arrêt ; `R/srsenb/src/main.cc:614..621` met `running=false`. Le Hub l'envoie dans `H/services/enb_controller.py:148..174` et `H/services/infra_controller.py:738..750`. Pour ces sources, cela provoque un arrêt demandé, pas une mise à jour à chaud. Le comportement d'un autre binaire `/usr/bin/srsenb` n'a pas été établi.
2. **Champs SIB12 incompatibles avec le parseur local.** Hub : `message_identifier`, `serial_number`, `warning_type`, `number_of_pages`, parfois `cb_data` (`enb_controller.py:58..68`, `infra_controller.py:772..780`). Parseur local : `message_id`, `serial_num`, `data_coding_scheme`, `warning_message` (`R/srsenb/src/enb_cfg_parser.cc:2727..2733`). Le parseur encode lui-même le CB-Data GSM7/UCS2 (`:2739..2759`). Le calcul de pages du Hub n'établit pas un contrat accepté par ce parseur.
3. **Remplacement intégral du SIB en voie SSH.** `H/services/enb_controller.py:120..138` renomme le fichier complet en `.backup`, puis écrit seulement le bloc SIB12 ; les autres sections sont perdues dans le nouveau fichier. La voie locale `infra_controller.py:719..736` fusionne par expression régulière, mais ne corrige pas les noms de champs.
4. **Succès Hub insuffisant.** `infra_controller.py:747..750` renvoie `success=True` même quand l'eNB est arrêté et seul son fichier a été modifié. La voie métier passe à SENT aussi en succès partiel (`H/api/endpoints/alerts.py:338..350`). Aucun ACK radio n'est collecté.
5. **Journalisation incohérente.** Le modèle définit `AlertLog.extra_data` (`H/models/alert.py:85`) ; les routes utilisent `metadata=` à la création et après envoi (`H/api/endpoints/alerts.py:141`, `:358`), et le schéma attend `metadata` (`H/schemas/__init__.py:103`). Anomalie statique à corriger/vérifier ; peut empêcher le flux ou sa sérialisation, sans preuve d'exécution dans cet audit.
6. **Arrêt script CBC par mauvais identifiant.** `P/scripts/alert.sh:65..70` extrait un nom depuis une table VTY puis le place dans DELETE ; le handler binaire utilise un ID numérique. `f2g_cmas_lab.sh:185` utilise le numéro mais son POST `:163` a encore `num_bcast`.
7. **Contrôles d'accès divergents.** Envoi métier : `get_current_sender`, rôles ADMIN/OPERATOR (`H/core/security.py:101..111`, `alerts.py:292`). Diffusion infrastructure : seulement `get_current_user` (`network.py:323`). Pas de preuve d'une restriction d'envoi identique dans ce deuxième chemin.
8. **Valeurs zéro remplacées en infrastructure.** `request.warning_type or 3` et `request.serial_number or 0x3000` (`network.py:366..367`) remplacent des zéros explicites ; `warning_type=0` documenté ne serait donc pas conservé.
9. **Limites radio cachées par les ACK.** L'ETWS dans le RRC examiné reste un TODO mais retourne succès (`R/srsenb/src/stack/rrc/rrc.cc:551..555`). Les plages ETWS acceptées par le Hub ne prouvent donc pas son implémentation complète. Le handler SBc-AP copie aussi une longueur reçue vers un tampon local de 1024 octets sans contrôle de borne visible (`P/source/open5gs-sbcap/sbcap-handler.c:423..430`) : ne pas supposer une capacité multipage quelconque à partir de la seule limite Hub de 1395 caractères.

## 9. Écarts entre documentation, copies et déploiement

`P/README.md:11..16` annonce Write, Stop, multi-TAC et expiration validés. `P/docs/COORDINATION.md:88..109` décrit des correctifs ultérieurs cohérents avec plusieurs sources trouvées. À l'inverse, `P/docs/PR_OPEN5GS.md:67..68`, `P/docs/PR_SRSRAN.md:97..98` et `P/docs/SESSION_SUMMARY.md:82..83` parlent encore de Stop non implémenté et de bug multi-TAC. Ce sont des états historiques, pas des garanties opposables aux sources plus récentes.

Dépendances historiques absentes lors de l'audit : `/home/f2g/Desktop/CMAS_Complete_Package` et `/home/f2g/Desktop/F2G_CMAS_SESSION_20261001`. Elles restent référencées dans `P/scripts/f2g_cmas_lab.sh:21..22`. Ce script cherche également `mme-fork.yaml` et `enb_sbcap.conf` dans son propre dossier `scripts/` (`:57`, `:64`), alors que les copies du paquet se trouvent sous `configs/`. Il lance `osmo-cbc` à `:100`, tandis que le binaire comparé est `osmo-cbc-patched`. Le paquet n'est donc pas prouvé relançable tel quel.

Sources supplémentaires Open5GS réellement trouvées : `/home/f2g/Desktop/open5gs-fork`. Leur identité exacte avec le binaire installé `/usr/local/bin/open5gs-mmed` n'a pas été démontrée. Même limite pour les sources srsRAN et le binaire actif. Les états « actif » d'un compte rendu ancien ne sont pas des états observés aujourd'hui.

## 10. Raccordement envisageable, sans mise en œuvre

Le point de raccord le mieux étayé est un **adaptateur Hub → API ECBE du CBC patché**, en remplacement du dispatcher SIB/SIGHUP pour ce scénario. Il reste à concevoir et valider ; aucun code n'a été changé ici.

L'adaptateur devrait :

1. Conserver l'UUID métier et ajouter une corrélation d'opération avec message ID CBC, serial complet, code/update, scope demandé et temps d'expiration. Gérer les collisions du message ID CBC au lieu de supprimer implicitement une alerte existante.
2. Résoudre les UUID cellules vers des PLMN/TAI validés. Refuser explicitement une précision cellule/ECGI tant qu'elle n'est pas mise en œuvre de bout en bout. Sélectionner un TAC peut toucher d'autres cellules de la même aire/eNB.
3. Construire du JSON sûr, utiliser exactement `num_of_bcast`, borner les champs et vérifier encodage, segmentation et capacité des tampons. Ne pas réutiliser sans validation les corps des anciens scripts.
4. Traiter les réponses CBC comme texte et code HTTP ; distinguer refus, acceptation MME, activation radio observée et arrêt confirmé. Maintenir les résultats par cible et les succès partiels sans les réduire à SENT.
5. Faire correspondre expiration métier et procédure d'arrêt CBC ; pour une alerte active, DELETE **numérique**, suivi Stop/Kill, corrélation et résultat séparé. Éviter la voie directe shell avec `sleep` comme mécanisme de production.
6. Prévoir un collecteur d'état CBC/MME/RAN avec stockage des causes, cibles demandées et cibles confirmées. Aucune route GET CBC ou webhook de statut ne doit être supposé disponible ; le binaire audité n'en fournit pas dans son tableau REST.

Les références normatives citées dans les sources locales sont TS 23.041 (CBS), TS 23.038 (encodage/DCS), TS 29.168 (SBc-AP), TS 36.413 (S1AP) et TS 36.331 (RRC/SIB12/paging). Cet audit n'a pas vérifié une version particulière de ces normes et ne constitue pas une certification de conformité.

## 11. État de livraison et limites

Rapport enregistré à `/home/f2g/Videos/F2G_CMAS_FINAL/CMAS_LOCAL_INTEGRATION.md`.

Les conclusions sont fondées sur les routes et sources présentes, les patches locaux et le binaire CBC identifié. Aucun essai de diffusion, annulation, rechargement ou démarrage n'a été effectué. Aucun état de téléphone, de service, d'association SCTP ou d'écoute réseau n'est revendiqué. Aucune configuration, source applicative ou donnée de production n'a été modifiée.
