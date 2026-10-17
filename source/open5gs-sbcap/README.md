# Open5GS avec Support SBc-AP (PR #4864)

## Source
- Repository: https://github.com/open5gs/open5gs
- PR: https://github.com/open5gs/open5gs/pull/4864
- Branche: sbcap-pr

## Récupération
```bash
git clone https://github.com/open5gs/open5gs.git
cd open5gs
git fetch origin pull/4864/head:sbcap-pr
git checkout sbcap-pr
```

## Compilation
```bash
meson setup build --prefix=/usr/local
ninja -C build
sudo ninja -C build install
```

## Fichiers SBc-AP ajoutés
- src/mme/sbcap-handler.c/h - Gestion des messages SBc-AP
- src/mme/sbcap-path.c/h - Fonctions d'envoi SBc-AP
- src/mme/sbcap-sctp.c - Serveur SCTP SBc-AP
- src/mme/sbcap-sm.c - State machine SBc-AP
- lib/sbcap/ - Bibliothèque SBc-AP
- lib/asn1c/sbcap/ - Codec ASN.1 SBc-AP

## Configuration MME (mme.yaml)
```yaml
mme:
  sbcap:
    server:
      - address: 127.0.0.2
        port: 29168
```

## Specs 3GPP
- TS 29.168: Cell Broadcast Centre Interfaces (SBc-AP)
- TS 23.041: Cell Broadcast Service

---
*Sauvegardé le $(date)*
*F2G Telecom - CMAS/PWS Implementation*
