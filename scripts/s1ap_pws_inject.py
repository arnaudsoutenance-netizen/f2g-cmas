#!/usr/bin/env python3
"""
S1AP PWS (Public Warning System) Message Injector
Envoie Write-Replace-Warning Request directement vers l'eNB
Ref: 3GPP TS 36.413 - S1AP, TS 23.041 - CBS

Note: Ce script simule ce que ferait le MME s'il recevait une requête SBc-AP
"""

import socket
import struct
import sys
import binascii
from datetime import datetime

# Message IDs pour CMAS (3GPP TS 23.041)
CMAS_MSG_IDS = {
    'presidential': 4370,      # 0x1112 - Presidential Alert
    'extreme': 4371,           # 0x1113 - Extreme Threat (Immediate)
    'severe': 4373,            # 0x1115 - Severe Threat
    'amber': 4379,             # 0x111B - AMBER Alert
    'test': 4380,              # 0x111C - CMAS Test
    'exercise': 4381,          # 0x111D - Exercise
    'monthly_test': 4396,      # 0x112C - Monthly Test
}

def encode_warning_message(text, max_pages=15):
    """Encode le message en GSM 7-bit (DCS=0x01) ou UCS2 si caractères spéciaux"""
    # Pour simplifier, on utilise ISO-8859-1
    encoded = text.encode('iso-8859-1', errors='replace')
    # Chaque page CBS = 82 octets max
    pages = []
    for i in range(0, len(encoded), 82):
        page = encoded[i:i+82]
        # Padding avec CR (0x0D)
        page = page.ljust(82, b'\x0d')
        pages.append(page)
    return pages[:max_pages]

def build_write_replace_warning(msg_id, serial, tai_list, warning_msg, repetition=5, num_bcast=10):
    """
    Construit un Write-Replace-Warning Request S1AP
    C'est une version simplifiée - pour une vraie implémentation, utiliser pycrate
    """
    
    # S1AP PDU structure (ASN.1 APER encoded)
    # Message Type: initiatingMessage
    # Procedure Code: id-WriteReplaceWarning (36)
    # Criticality: reject (0)
    
    # Ceci est un template simplifié
    # En production, utiliser pycrate pour encoder correctement
    
    print(f"""
═══════════════════════════════════════════════════════════════
  📡 PWS WRITE-REPLACE-WARNING REQUEST
═══════════════════════════════════════════════════════════════

  Message ID:        0x{msg_id:04X} ({msg_id})
  Serial Number:     0x{serial:04X}
  Repetition Period: {repetition} seconds
  Number of Bcast:   {num_bcast}
  
  TAI List:          {tai_list}
  
  Warning Message:   {warning_msg}
  
═══════════════════════════════════════════════════════════════
    """)
    
    # Structure S1AP simplifiée (pour démo)
    # En réalité, il faut encoder en ASN.1 APER
    pdu = bytes([
        0x00,  # initiatingMessage
        0x24,  # procedureCode = 36 (WriteReplaceWarning)
        0x00,  # criticality = reject
    ])
    
    return pdu

def main():
    print("""
╔═══════════════════════════════════════════════════════════════╗
║  🚨 S1AP PWS INJECTOR - F2G Lab                               ║
║                                                               ║
║  ATTENTION: Ce script montre le concept.                      ║
║  Open5GS MME ne supporte pas SBc-AP nativement.               ║
║                                                               ║
║  Pour voir Write-Replace-Warning dans Wireshark, il faut:     ║
║  1. Un CBC connecté au MME via SBc-AP                         ║
║  2. Ou modifier Open5GS pour ajouter le support               ║
║                                                               ║
║  Alternative utilisée: Injection SIB12 directe sur eNB        ║
╚═══════════════════════════════════════════════════════════════╝
    """)
    
    if len(sys.argv) < 2:
        print("Usage: python3 s1ap_pws_inject.py \"Message d'alerte\" [msg_type]")
        print("")
        print("Types disponibles:")
        for name, mid in CMAS_MSG_IDS.items():
            print(f"  {name}: 0x{mid:04X}")
        sys.exit(1)
    
    message = sys.argv[1]
    msg_type = sys.argv[2] if len(sys.argv) > 2 else 'test'
    
    msg_id = CMAS_MSG_IDS.get(msg_type, CMAS_MSG_IDS['test'])
    serial = int(datetime.now().timestamp()) % 65535
    
    # TAI pour notre lab
    tai_list = [
        {'mcc': '001', 'mnc': '01', 'tac': 1},  # TAC 1 - Yaoundé
        {'mcc': '001', 'mnc': '01', 'tac': 2},  # TAC 2 - Douala
    ]
    
    pdu = build_write_replace_warning(
        msg_id=msg_id,
        serial=serial,
        tai_list=tai_list,
        warning_msg=message,
    )
    
    print("\n⚠️  Ce script est pour DÉMONSTRATION CONCEPTUELLE uniquement.")
    print("    L'injection S1AP réelle nécessite:")
    print("    - Un CBC (Cell Broadcast Center) fonctionnel")
    print("    - Une connexion SBc-AP au MME")
    print("    - Ou modification du code MME Open5GS")
    print("")
    print("💡 SOLUTION RECOMMANDÉE pour ce lab:")
    print("   Utiliser le script send_alert.sh qui modifie le SIB12")
    print("   directement sur l'eNB (méthode statique mais fonctionnelle)")

if __name__ == '__main__':
    main()
