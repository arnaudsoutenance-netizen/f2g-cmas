#!/usr/bin/env python3
"""
F2G CMAS Lab - S1AP Write-Replace-Warning Injector
===================================================
This script sends PWS (Public Warning System) messages directly via S1AP
to trigger Write-Replace-Warning messages visible in Wireshark.

IMPORTANT: This injects SCTP/S1AP packets to the eNB through the MME.
The MME will forward the message to the connected eNBs.

Reference: 3GPP TS 36.413 Section 8.13.3
"""

import socket
import struct
import sys
import argparse
from datetime import datetime

# S1AP Message Types (Procedure Codes)
S1AP_PROC_WRITE_REPLACE_WARNING = 36
S1AP_PROC_KILL = 37

# S1AP Protocol IEs
S1AP_IE_MESSAGE_IDENTIFIER = 111
S1AP_IE_SERIAL_NUMBER = 139
S1AP_IE_WARNING_AREA_LIST = 122
S1AP_IE_REPETITION_PERIOD = 138
S1AP_IE_NUMBER_OF_BROADCAST_REQUEST = 112
S1AP_IE_WARNING_TYPE = 123
S1AP_IE_WARNING_SECURITY_INFO = 124
S1AP_IE_DATA_CODING_SCHEME = 53
S1AP_IE_WARNING_MESSAGE_CONTENTS = 121
S1AP_IE_CONCURRENT_WARNING_MESSAGE_INDICATOR = 143
S1AP_IE_EXTENDED_REPETITION_PERIOD = 144

# CMAS Message Identifiers (3GPP TS 23.041)
CMAS_PRESIDENTIAL = 4370      # 0x1112 - Presidential Alert
CMAS_EXTREME_IMMEDIATE = 4371 # 0x1113 - Extreme Threat - Immediate
CMAS_EXTREME_EXPECTED = 4372  # 0x1114 - Extreme Threat - Expected  
CMAS_SEVERE_IMMEDIATE = 4373  # 0x1115 - Severe Threat - Immediate
CMAS_SEVERE_EXPECTED = 4374   # 0x1116 - Severe Threat - Expected
CMAS_AMBER_ALERT = 4379       # 0x111B - AMBER Alert
CMAS_MONTHLY_TEST = 4380      # 0x111C - Monthly Test
CMAS_EXERCISE = 4381          # 0x111D - Exercise
CMAS_OPERATOR_DEFINED = 4382  # 0x111E - Operator Defined

def encode_plmn_id(mcc, mnc):
    """
    Encode PLMN ID according to 3GPP TS 24.008
    MCC = Mobile Country Code
    MNC = Mobile Network Code
    """
    mcc_str = str(mcc).zfill(3)
    mnc_str = str(mnc).zfill(2)
    
    # PLMN encoding: MCC digit 2 | MCC digit 1 | MNC digit 3 | MCC digit 3 | MNC digit 2 | MNC digit 1
    if len(mnc_str) == 2:
        plmn = bytes([
            (int(mcc_str[1]) << 4) | int(mcc_str[0]),
            0xF0 | int(mcc_str[2]),  # 0xF for 2-digit MNC
            (int(mnc_str[1]) << 4) | int(mnc_str[0])
        ])
    else:
        mnc_str = mnc_str.zfill(3)
        plmn = bytes([
            (int(mcc_str[1]) << 4) | int(mcc_str[0]),
            (int(mnc_str[0]) << 4) | int(mcc_str[2]),
            (int(mnc_str[2]) << 4) | int(mnc_str[1])
        ])
    return plmn

def encode_tai(mcc, mnc, tac):
    """Encode Tracking Area Identity (TAI)"""
    plmn = encode_plmn_id(mcc, mnc)
    tac_bytes = struct.pack('>H', tac)  # TAC is 2 bytes, big-endian
    return plmn + tac_bytes

def encode_warning_message(text, coding_scheme=0x01):
    """
    Encode warning message content
    coding_scheme: 0x01 = GSM 7-bit, 0x48 = UCS2
    """
    if coding_scheme == 0x01:
        # GSM 7-bit encoding (simplified - ASCII subset)
        return text.encode('ascii', errors='replace')
    else:
        # UCS2 encoding
        return text.encode('utf-16-be')

def build_s1ap_write_replace_warning(
    message_id=CMAS_PRESIDENTIAL,
    serial_number=0xC001,
    tai_list=None,
    repetition_period=5,
    number_of_broadcasts=10,
    warning_type=None,
    data_coding_scheme=0x01,
    warning_message="F2G CMAS ALERT TEST"
):
    """
    Build S1AP Write-Replace-Warning-Request message
    Reference: 3GPP TS 36.413 Section 9.1.13.1
    """
    
    if tai_list is None:
        # Default: TAC 1 and TAC 2 with MCC=001, MNC=01
        tai_list = [
            {'mcc': 1, 'mnc': 1, 'tac': 1},  # TAC 1 - Yaoundé
            {'mcc': 1, 'mnc': 1, 'tac': 2},  # TAC 2 - Douala
        ]
    
    # This is a simplified ASN.1 PER encoding
    # In production, you would use a proper ASN.1 library like pyasn1
    
    ies = []
    
    # IE: Message Identifier (M)
    msg_id_bytes = struct.pack('>H', message_id)
    ies.append((S1AP_IE_MESSAGE_IDENTIFIER, msg_id_bytes))
    
    # IE: Serial Number (M)
    serial_bytes = struct.pack('>H', serial_number)
    ies.append((S1AP_IE_SERIAL_NUMBER, serial_bytes))
    
    # IE: Warning Area List (O) - TAI List
    # Encoding simplified for demonstration
    tai_data = b''
    for tai in tai_list:
        tai_data += encode_tai(tai['mcc'], tai['mnc'], tai['tac'])
    ies.append((S1AP_IE_WARNING_AREA_LIST, tai_data))
    
    # IE: Repetition Period (M)
    rep_bytes = struct.pack('>H', repetition_period)
    ies.append((S1AP_IE_REPETITION_PERIOD, rep_bytes))
    
    # IE: Number of Broadcast Requested (M)
    num_bytes = struct.pack('>H', number_of_broadcasts)
    ies.append((S1AP_IE_NUMBER_OF_BROADCAST_REQUEST, num_bytes))
    
    # IE: Warning Type (O) - for ETWS
    if warning_type:
        wt_bytes = struct.pack('>H', warning_type)
        ies.append((S1AP_IE_WARNING_TYPE, wt_bytes))
    
    # IE: Data Coding Scheme (O)
    dcs_bytes = bytes([data_coding_scheme])
    ies.append((S1AP_IE_DATA_CODING_SCHEME, dcs_bytes))
    
    # IE: Warning Message Contents (O)
    msg_content = encode_warning_message(warning_message, data_coding_scheme)
    ies.append((S1AP_IE_WARNING_MESSAGE_CONTENTS, msg_content))
    
    return ies

def create_hex_dump(data):
    """Create hex dump for display"""
    lines = []
    for i in range(0, len(data), 16):
        chunk = data[i:i+16]
        hex_part = ' '.join(f'{b:02x}' for b in chunk)
        ascii_part = ''.join(chr(b) if 32 <= b < 127 else '.' for b in chunk)
        lines.append(f'{i:04x}  {hex_part:<48}  {ascii_part}')
    return '\n'.join(lines)

def main():
    parser = argparse.ArgumentParser(
        description='F2G CMAS - S1AP Write-Replace-Warning Generator',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --message "EARTHQUAKE ALERT - Seek shelter immediately"
  %(prog)s --type amber --tac 1 2 --message "AMBER Alert: Missing child"
  %(prog)s --type test --tac 1 --message "Monthly CMAS Test"

Message Types:
  presidential  - Presidential Alert (highest priority)
  extreme       - Extreme Threat - Immediate
  severe        - Severe Threat - Immediate  
  amber         - AMBER Alert (child abduction)
  test          - Monthly Test
  exercise      - Exercise Alert
        """
    )
    
    parser.add_argument('--type', '-t', 
                        choices=['presidential', 'extreme', 'severe', 'amber', 'test', 'exercise'],
                        default='test',
                        help='Alert type (default: test)')
    
    parser.add_argument('--message', '-m',
                        default='F2G CMAS ALERT - This is a test emergency alert',
                        help='Warning message content')
    
    parser.add_argument('--tac', '-T', type=int, nargs='+',
                        default=[1, 2],
                        help='Tracking Area Code(s) to target (default: 1 2)')
    
    parser.add_argument('--mcc', type=int, default=1,
                        help='Mobile Country Code (default: 001)')
    
    parser.add_argument('--mnc', type=int, default=1,
                        help='Mobile Network Code (default: 01)')
    
    parser.add_argument('--repeat', '-r', type=int, default=5,
                        help='Repetition period in seconds (default: 5)')
    
    parser.add_argument('--count', '-c', type=int, default=10,
                        help='Number of broadcasts (default: 10)')
    
    parser.add_argument('--output', '-o',
                        help='Save raw packet to file (for pcap analysis)')
    
    parser.add_argument('--trigger', action='store_true',
                        help='Create trigger file for patched MME')
    
    args = parser.parse_args()
    
    # Map type to message ID
    type_map = {
        'presidential': CMAS_PRESIDENTIAL,
        'extreme': CMAS_EXTREME_IMMEDIATE,
        'severe': CMAS_SEVERE_IMMEDIATE,
        'amber': CMAS_AMBER_ALERT,
        'test': CMAS_MONTHLY_TEST,
        'exercise': CMAS_EXERCISE,
    }
    
    message_id = type_map[args.type]
    
    # Build TAI list
    tai_list = [{'mcc': args.mcc, 'mnc': args.mnc, 'tac': tac} for tac in args.tac]
    
    # Generate serial number (includes timestamp)
    now = datetime.now()
    serial_number = (now.hour << 11) | (now.minute << 5) | (now.second >> 1)
    serial_number = serial_number & 0xFFFF
    
    print("=" * 70)
    print("  F2G CMAS Lab - Write-Replace-Warning Generator")
    print("=" * 70)
    print()
    print(f"Alert Type:        {args.type.upper()}")
    print(f"Message ID:        0x{message_id:04X} ({message_id})")
    print(f"Serial Number:     0x{serial_number:04X}")
    print(f"Target TACs:       {args.tac}")
    print(f"PLMN:              MCC={args.mcc:03d}, MNC={args.mnc:02d}")
    print(f"Repetition:        {args.repeat} seconds")
    print(f"Broadcasts:        {args.count}")
    print(f"Message:           {args.message[:50]}...")
    print()
    
    # Build the message
    ies = build_s1ap_write_replace_warning(
        message_id=message_id,
        serial_number=serial_number,
        tai_list=tai_list,
        repetition_period=args.repeat,
        number_of_broadcasts=args.count,
        warning_message=args.message
    )
    
    print("S1AP Information Elements:")
    print("-" * 40)
    for ie_id, ie_data in ies:
        print(f"  IE {ie_id:3d}: {ie_data.hex()}")
    print()
    
    if args.trigger:
        # Create trigger file for patched MME
        import json
        trigger_data = {
            'message_id': message_id,
            'serial_number': serial_number,
            'tac_list': args.tac,
            'mcc': args.mcc,
            'mnc': args.mnc,
            'repetition_period': args.repeat,
            'number_of_broadcasts': args.count,
            'message': args.message,
            'timestamp': now.isoformat()
        }
        
        trigger_file = '/tmp/f2g-pws-trigger.json'
        with open(trigger_file, 'w') as f:
            json.dump(trigger_data, f, indent=2)
        
        print(f"✅ Trigger file created: {trigger_file}")
        print("   The patched MME will send Write-Replace-Warning on next poll.")
        print()
        print("To verify in Wireshark:")
        print("  Filter: s1ap.procedureCode == 36")
        print()
    
    if args.output:
        # Save raw IE data for analysis
        with open(args.output, 'wb') as f:
            for ie_id, ie_data in ies:
                f.write(struct.pack('>HH', ie_id, len(ie_data)))
                f.write(ie_data)
        print(f"✅ Raw IEs saved to: {args.output}")
    
    print("=" * 70)
    print("NOTE: To see Write-Replace-Warning in Wireshark, use the patched MME")
    print("      or osmo-cbc with SBc-AP support.")
    print("=" * 70)

if __name__ == '__main__':
    main()
