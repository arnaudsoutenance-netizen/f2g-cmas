#!/usr/bin/env python3
"""
═══════════════════════════════════════════════════════════════════════════════
  S1AP PWS INJECTOR - F2G CMAS Lab
  
  Injecte un Write-Replace-Warning Request directement vers l'eNB
  via l'interface S1AP (SCTP).
  
  Ref: 3GPP TS 36.413 Section 8.12 (Warning Message Transmission)
       3GPP TS 23.041 (CBS)
═══════════════════════════════════════════════════════════════════════════════
"""

import sys
import socket
import struct
import argparse
from datetime import datetime

# Import pycrate pour encoder S1AP
try:
    from pycrate_asn1dir import S1AP
    from pycrate_core.utils import *
except ImportError:
    print("❌ pycrate non installé. Activez le venv:")
    print("   source /home/f2g/Desktop/CMAS_Complete_Package/venv/bin/activate")
    sys.exit(1)

# Import SCTP
try:
    import sctp
except ImportError:
    print("⚠️  pysctp non installé, utilisation socket TCP (fallback)")
    sctp = None


# ═══════════════════════════════════════════════════════════════════════════════
# CONSTANTES
# ═══════════════════════════════════════════════════════════════════════════════

# Message IDs CMAS (3GPP TS 23.041 Section 9.4.1.2.2)
CMAS_MSG_IDS = {
    'presidential': 4370,      # 0x1112
    'extreme': 4371,           # 0x1113
    'severe': 4373,            # 0x1115  
    'amber': 4379,             # 0x111B
    'test': 4380,              # 0x111C
    'exercise': 4381,          # 0x111D
}

# S1AP Procedure Codes
S1AP_WRITE_REPLACE_WARNING = 36  # id-WriteReplaceWarning


# ═══════════════════════════════════════════════════════════════════════════════
# FONCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

def encode_plmn(mcc, mnc):
    """Encode MCC/MNC en format 3GPP (3 octets)"""
    # MCC = 001, MNC = 01 -> bytes
    mcc_digits = [int(d) for d in mcc.zfill(3)]
    mnc_digits = [int(d) for d in mnc.zfill(2)]
    
    # Format: MCC2 MCC1 | MNC3 MCC3 | MNC2 MNC1
    if len(mnc) == 2:
        mnc_digits = [0xF] + mnc_digits  # MNC3 = 0xF pour MNC à 2 chiffres
    else:
        mnc_digits = [int(d) for d in mnc.zfill(3)]
    
    byte1 = (mcc_digits[1] << 4) | mcc_digits[0]
    byte2 = (mnc_digits[0] << 4) | mcc_digits[2]
    byte3 = (mnc_digits[2] << 4) | mnc_digits[1]
    
    return bytes([byte1, byte2, byte3])


def encode_warning_message(text, dcs=0x01):
    """
    Encode le message en CBS Data Coding Scheme
    DCS=0x01 : GSM 7-bit default alphabet
    DCS=0x48 : UCS2
    """
    # Simplification : ISO-8859-1 (proche GSM 7-bit pour ce demo)
    encoded = text.encode('iso-8859-1', errors='replace')
    
    # CBS: max 82 caractères par page
    pages = []
    for i in range(0, len(encoded), 82):
        page = encoded[i:i+82]
        page = page.ljust(82, b'\x0d')  # Padding avec CR
        pages.append(page)
    
    return pages


def build_write_replace_warning_request(msg_id, serial_nr, repetition_period, 
                                          num_broadcasts, plmn, tac_list, 
                                          warning_type, warning_message):
    """
    Construit le PDU S1AP Write-Replace-Warning Request
    
    IE obligatoires selon TS 36.413:
    - Message Identifier
    - Serial Number  
    - Repetition Period
    - Number of Broadcast Requested
    - Warning Area List (TAI)
    - Warning Type
    - Warning Security Info (optionnel)
    - Data Coding Scheme
    - Warning Message Contents
    """
    
    # Utiliser pycrate pour construire le message
    pdu = S1AP.S1AP_PDU_Descriptions.S1AP_PDU
    
    # InitiatingMessage pour WriteReplaceWarning
    msg = {
        'initiatingMessage': {
            'procedureCode': S1AP_WRITE_REPLACE_WARNING,
            'criticality': 'reject',
            'value': ('WriteReplaceWarningRequest', {
                'protocolIEs': [
                    # Message Identifier (IE id=111)
                    {
                        'id': 111,  # id-MessageIdentifier
                        'criticality': 'reject',
                        'value': ('MessageIdentifier', (msg_id, 16))
                    },
                    # Serial Number (IE id=112)  
                    {
                        'id': 112,  # id-SerialNumber
                        'criticality': 'reject', 
                        'value': ('SerialNumber', (serial_nr, 16))
                    },
                    # Repetition Period (IE id=113)
                    {
                        'id': 113,  # id-RepetitionPeriod
                        'criticality': 'reject',
                        'value': ('RepetitionPeriod', repetition_period)
                    },
                    # Number of Broadcasts Requested (IE id=116)
                    {
                        'id': 116,  # id-NumberofBroadcastRequest
                        'criticality': 'reject',
                        'value': ('NumberofBroadcastRequest', num_broadcasts)
                    },
                    # Warning Area List - TAI List
                    {
                        'id': 122,  # id-WarningAreaList
                        'criticality': 'ignore',
                        'value': ('WarningAreaList', 
                            ('trackingAreaListforWarning', [
                                {
                                    'pLMNidentity': plmn,
                                    'tAC': bytes([0, tac]) 
                                } for tac in tac_list
                            ])
                        )
                    },
                    # Warning Type
                    {
                        'id': 118,  # id-WarningType
                        'criticality': 'ignore',
                        'value': ('WarningType', bytes([0, warning_type]))
                    },
                    # Data Coding Scheme
                    {
                        'id': 114,  # id-DataCodingScheme  
                        'criticality': 'ignore',
                        'value': ('DataCodingScheme', bytes([0x01]))
                    },
                    # Warning Message Contents
                    {
                        'id': 119,  # id-WarningMessageContents
                        'criticality': 'ignore',
                        'value': ('WarningMessageContents', warning_message)
                    },
                ]
            })
        }
    }
    
    # Encoder le PDU
    pdu.set_val(msg)
    return pdu.to_aper()


def send_to_enb(host, port, pdu_bytes):
    """
    Envoie le PDU S1AP vers l'eNB via SCTP
    
    Note: Normalement le MME envoie ceci à l'eNB.
    Pour ce lab, on simule le comportement du MME.
    """
    
    print(f"\n📡 Connexion à l'eNB {host}:{port}...")
    
    if sctp:
        # SCTP natif
        try:
            sk = sctp.sctpsocket_tcp(socket.AF_INET)
            sk.connect((host, port))
            sk.sctp_send(pdu_bytes)
            print("✅ Message envoyé via SCTP")
            sk.close()
            return True
        except Exception as e:
            print(f"❌ Erreur SCTP: {e}")
            return False
    else:
        print("⚠️  SCTP non disponible")
        return False


# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser(
        description='Injecte un Write-Replace-Warning S1AP vers eNB',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Exemples:
  # Alerte test sur TAC 1 (Yaoundé)
  python inject_s1ap_pws.py "ALERTE TEST" --tac 1

  # Alerte présidentielle sur tous les TAC  
  python inject_s1ap_pws.py "EVACUATION IMMEDIATE" --type presidential --tac 1 2

  # Alerte AMBER sur TAC 2 (Douala)
  python inject_s1ap_pws.py "ENFANT DISPARU" --type amber --tac 2
        """
    )
    
    parser.add_argument('message', help='Texte de l\'alerte')
    parser.add_argument('--type', '-t', choices=CMAS_MSG_IDS.keys(), 
                        default='test', help='Type d\'alerte CMAS')
    parser.add_argument('--tac', '-T', type=int, nargs='+', default=[1, 2],
                        help='TAC cibles (défaut: 1 2)')
    parser.add_argument('--repeat', '-r', type=int, default=5,
                        help='Période de répétition en secondes')
    parser.add_argument('--count', '-c', type=int, default=10,
                        help='Nombre de broadcasts')
    parser.add_argument('--mme', '-m', default='172.22.0.9',
                        help='Adresse IP du MME')
    parser.add_argument('--port', '-p', type=int, default=36412,
                        help='Port S1AP')
    parser.add_argument('--dry-run', '-n', action='store_true',
                        help='Affiche le PDU sans l\'envoyer')
    
    args = parser.parse_args()
    
    # Paramètres
    msg_id = CMAS_MSG_IDS[args.type]
    serial_nr = int(datetime.now().timestamp()) % 65535
    plmn = encode_plmn('001', '01')  # Test PLMN
    
    # Encoder le message
    pages = encode_warning_message(args.message)
    warning_contents = b''.join(pages)
    
    print("""
╔═══════════════════════════════════════════════════════════════════════════════╗
║  🚨 S1AP WRITE-REPLACE-WARNING INJECTOR                                       ║
║                                                                               ║
║  Ce script simule l'envoi d'une alerte PWS depuis le MME vers l'eNB          ║
║  Ref: 3GPP TS 36.413 Section 8.12                                            ║
╚═══════════════════════════════════════════════════════════════════════════════╝
    """)
    
    print(f"""
═══════════════════════════════════════════════════════════════════════════════
  PARAMÈTRES DE L'ALERTE
═══════════════════════════════════════════════════════════════════════════════

  Type:              {args.type.upper()}
  Message ID:        0x{msg_id:04X} ({msg_id})
  Serial Number:     0x{serial_nr:04X}
  
  TAC cibles:        {args.tac}
  PLMN:              001-01
  
  Répétition:        {args.repeat} secondes
  Nombre bcast:      {args.count}
  
  Message:           {args.message}
  Taille:            {len(warning_contents)} octets
  
═══════════════════════════════════════════════════════════════════════════════
    """)
    
    # Construction du PDU
    print("🔧 Construction du PDU S1AP...")
    
    try:
        pdu_bytes = build_write_replace_warning_request(
            msg_id=msg_id,
            serial_nr=serial_nr,
            repetition_period=args.repeat,
            num_broadcasts=args.count,
            plmn=plmn,
            tac_list=args.tac,
            warning_type=0x01,  # Emergency
            warning_message=warning_contents
        )
        
        print(f"✅ PDU construit: {len(pdu_bytes)} octets")
        print(f"\n   Hex: {pdu_bytes[:50].hex()}...")
        
    except Exception as e:
        print(f"❌ Erreur construction PDU: {e}")
        print("\n⚠️  L'API pycrate S1AP est complexe.")
        print("   Pour une démo simple, utiliser send_alert.sh (méthode SIB12)")
        return 1
    
    if args.dry_run:
        print("\n🔍 Mode dry-run - PDU non envoyé")
        return 0
    
    # Envoi
    # Note: En réalité, on ne peut pas envoyer directement à l'eNB
    # car l'eNB attend les messages du MME sur la connexion existante
    print("\n⚠️  IMPORTANT:")
    print("   On ne peut pas injecter directement vers l'eNB.")
    print("   L'eNB n'accepte que les messages du MME sur la connexion S1 établie.")
    print("")
    print("   Pour voir Write-Replace-Warning dans Wireshark:")
    print("   → Il faudrait modifier le code source du MME Open5GS")
    print("   → Ou utiliser OpenAirInterface qui supporte PWS")
    print("")
    print("   SOLUTION ALTERNATIVE: ./send_alert.sh modifie le SIB12")
    
    return 0


if __name__ == '__main__':
    sys.exit(main())
