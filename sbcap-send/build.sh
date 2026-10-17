#!/bin/bash
# Build sbcap-send against the Open5GS fork SBc-AP codec (same as the MME)
S=/home/f2g/Desktop/CMAS_Complete_Package/open5gs-fork
B=$S/build
cd "$(dirname "$0")"
gcc -O2 -Wall -o sbcap-send sbcap_send.c \
  -I$B/lib -I$S/lib -I$B/lib/core -I$S/lib/core -I$S/lib/sbcap -I$S/lib/asn1c/sbcap \
  -I$S/lib/asn1c/common -I$S/lib/asn1c/util \
  -L$B/lib/sbcap -L$B/lib/asn1c/sbcap -L$B/lib/asn1c/common -L$B/lib/asn1c/util -L$B/lib/core \
  -logssbcap -logsasn1c-sbcap -logsasn1c-util -logsasn1c-common -logscore -lsctp \
  -Wl,-rpath,$B/lib/sbcap:$B/lib/asn1c/sbcap:$B/lib/asn1c/common:$B/lib/asn1c/util:$B/lib/core
