/*
 * sbcap-send — minimal SBc-AP CBC (TS 29.168) for the F2G CMAS lab.
 *
 * Sends a Write-Replace-Warning-Request (or Stop-Warning-Request) to the MME
 * with an explicit List-of-TAIs, which osmo-cbc 0.5.3 cannot do through its
 * REST API (scope_plmn only). Uses the same asn1c SBc-AP codec as the
 * Open5GS fork MME.
 *
 *   sbcap-send [--mme 127.0.0.2] [--port 29168] [--plmn 00101]
 *              [--tac 1[,2,...]] [--msg-id 4370] [--code N] [--update 0]
 *              [--text "..."] [--stop]
 *
 * Without --tac, no List-of-TAIs is sent (= whole PLMN, like osmo-cbc).
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <getopt.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/sctp.h>
#include <sys/socket.h>
#include <sys/time.h>

#include "ogs-sbcap.h"

#define SBCAP_PPID      24
#define CBS_PAGE_OCTETS 82
#define CBS_PAGE_CHARS  93  /* 82 octets * 8 / 7 */
#define MAX_TAC         16

/* ---------- GSM 7-bit default alphabet (TS 23.038), common subset ---------- */
static uint8_t gsm7_char(char c)
{
    if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'))
        return (uint8_t)c;
    switch (c) {
    case ' ': case '!': case '"': case '#': case '%': case '&': case '\'':
    case '(': case ')': case '*': case '+': case ',': case '-': case '.':
    case '/': case ':': case ';': case '<': case '=': case '>': case '?':
        return (uint8_t)c;
    case '@':  return 0x00;
    case '$':  return 0x02;
    case '_':  return 0x11;
    case '\n': return 0x0A;
    default:   return '?';
    }
}

/* CB data (TS 23.041 9.4.2.2.5): nb_pages | page (82 octets) | info length */
static size_t build_cb_data(const char *text, uint8_t *out)
{
    uint8_t septets[CBS_PAGE_CHARS];
    size_t len = strlen(text), i;
    size_t bit = 0;

    if (len > CBS_PAGE_CHARS) {
        fprintf(stderr, "warning: text truncated to %d characters (1 CBS page)\n",
                CBS_PAGE_CHARS);
        len = CBS_PAGE_CHARS;
    }
    for (i = 0; i < CBS_PAGE_CHARS; i++)
        septets[i] = (i < len) ? gsm7_char(text[i]) : 0x0D; /* pad with <CR> */

    out[0] = 1; /* number of pages */
    memset(&out[1], 0, CBS_PAGE_OCTETS);
    for (i = 0; i < CBS_PAGE_CHARS; i++, bit += 7) {
        size_t byte = bit / 8, shift = bit % 8;
        out[1 + byte] |= (uint8_t)(septets[i] << shift);
        if (shift > 1 && byte + 1 < CBS_PAGE_OCTETS)
            out[1 + byte + 1] |= (uint8_t)(septets[i] >> (8 - shift));
    }
    out[1 + CBS_PAGE_OCTETS] = (uint8_t)((len * 7 + 7) / 8); /* info length */
    return 1 + CBS_PAGE_OCTETS + 1;
}

/* ---------- helpers ---------- */
static void bitstring16(BIT_STRING_t *bs, uint16_t v)
{
    bs->size = 2;
    bs->bits_unused = 0;
    bs->buf = CALLOC(2, 1);
    bs->buf[0] = v >> 8;
    bs->buf[1] = v & 0xFF;
}

static void plmn_tbcd(const char *plmn, uint8_t out[3])
{
    /* "00101" or "001010": MCC 3 digits + MNC 2 or 3 digits */
    int d[6] = {0}, n = (int)strlen(plmn), i;
    for (i = 0; i < n && i < 6; i++) d[i] = plmn[i] - '0';
    out[0] = (uint8_t)((d[1] << 4) | d[0]);
    out[1] = (uint8_t)(((n == 6 ? d[5] : 0xF) << 4) | d[2]);
    out[2] = (uint8_t)((d[4] << 4) | d[3]);
}

static void add_tai_list(SBCAP_List_of_TAIs_t *list, const char *plmn,
        const int *tacs, int ntac)
{
    int i;
    for (i = 0; i < ntac; i++) {
        List_of_TAIs__Member *m = CALLOC(1, sizeof(*m));
        m->tai.pLMNidentity.size = 3;
        m->tai.pLMNidentity.buf = CALLOC(3, 1);
        plmn_tbcd(plmn, m->tai.pLMNidentity.buf);
        m->tai.tAC.size = 2;
        m->tai.tAC.buf = CALLOC(2, 1);
        m->tai.tAC.buf[0] = (uint8_t)(tacs[i] >> 8);
        m->tai.tAC.buf[1] = (uint8_t)(tacs[i] & 0xFF);
        ASN_SEQUENCE_ADD(&list->list, m);
    }
}

#define NEW_IE(type, container, ie) \
    do { ie = CALLOC(1, sizeof(type)); ASN_SEQUENCE_ADD(&(container)->protocolIEs, ie); } while (0)

static ogs_pkbuf_t *build_write(uint16_t msg_id, uint16_t serial, const char *plmn,
        const int *tacs, int ntac, const char *text)
{
    ogs_sbcap_message_t pdu;
    SBCAP_Write_Replace_Warning_Request_t *req;
    SBCAP_Write_Replace_Warning_Request_IEs_t *ie;
    uint8_t cb[1 + CBS_PAGE_OCTETS + 1];
    size_t cblen = build_cb_data(text, cb);

    memset(&pdu, 0, sizeof(pdu));
    pdu.present = SBCAP_SBC_AP_PDU_PR_initiatingMessage;
    pdu.choice.initiatingMessage = CALLOC(1, sizeof(SBCAP_InitiatingMessage_t));
    pdu.choice.initiatingMessage->procedureCode = SBCAP_id_Write_Replace_Warning;
    pdu.choice.initiatingMessage->criticality = SBCAP_Criticality_reject;
    pdu.choice.initiatingMessage->value.present =
        SBCAP_InitiatingMessage__value_PR_Write_Replace_Warning_Request;
    req = &pdu.choice.initiatingMessage->value.choice.Write_Replace_Warning_Request;

    NEW_IE(SBCAP_Write_Replace_Warning_Request_IEs_t, req, ie);
    ie->id = SBCAP_id_Message_Identifier; ie->criticality = SBCAP_Criticality_reject;
    ie->value.present = SBCAP_Write_Replace_Warning_Request_IEs__value_PR_Message_Identifier;
    bitstring16(&ie->value.choice.Message_Identifier, msg_id);

    NEW_IE(SBCAP_Write_Replace_Warning_Request_IEs_t, req, ie);
    ie->id = SBCAP_id_Serial_Number; ie->criticality = SBCAP_Criticality_reject;
    ie->value.present = SBCAP_Write_Replace_Warning_Request_IEs__value_PR_Serial_Number;
    bitstring16(&ie->value.choice.Serial_Number, serial);

    if (ntac > 0) {
        NEW_IE(SBCAP_Write_Replace_Warning_Request_IEs_t, req, ie);
        ie->id = SBCAP_id_List_of_TAIs; ie->criticality = SBCAP_Criticality_ignore;
        ie->value.present = SBCAP_Write_Replace_Warning_Request_IEs__value_PR_List_of_TAIs;
        add_tai_list(&ie->value.choice.List_of_TAIs, plmn, tacs, ntac);
    }

    NEW_IE(SBCAP_Write_Replace_Warning_Request_IEs_t, req, ie);
    ie->id = SBCAP_id_Repetition_Period; ie->criticality = SBCAP_Criticality_reject;
    ie->value.present = SBCAP_Write_Replace_Warning_Request_IEs__value_PR_Repetition_Period;
    ie->value.choice.Repetition_Period = 5;

    NEW_IE(SBCAP_Write_Replace_Warning_Request_IEs_t, req, ie);
    ie->id = SBCAP_id_Number_of_Broadcasts_Requested; ie->criticality = SBCAP_Criticality_reject;
    ie->value.present = SBCAP_Write_Replace_Warning_Request_IEs__value_PR_Number_of_Broadcasts_Requested;
    ie->value.choice.Number_of_Broadcasts_Requested = 0;

    NEW_IE(SBCAP_Write_Replace_Warning_Request_IEs_t, req, ie);
    ie->id = SBCAP_id_Data_Coding_Scheme; ie->criticality = SBCAP_Criticality_ignore;
    ie->value.present = SBCAP_Write_Replace_Warning_Request_IEs__value_PR_Data_Coding_Scheme;
    ie->value.choice.Data_Coding_Scheme.size = 1;
    ie->value.choice.Data_Coding_Scheme.buf = CALLOC(1, 1);
    ie->value.choice.Data_Coding_Scheme.buf[0] = 0x0F; /* GSM 7-bit, language unspecified */

    NEW_IE(SBCAP_Write_Replace_Warning_Request_IEs_t, req, ie);
    ie->id = SBCAP_id_Warning_Message_Content; ie->criticality = SBCAP_Criticality_ignore;
    ie->value.present = SBCAP_Write_Replace_Warning_Request_IEs__value_PR_Warning_Message_Content;
    ie->value.choice.Warning_Message_Content.size = cblen;
    ie->value.choice.Warning_Message_Content.buf = CALLOC(cblen, 1);
    memcpy(ie->value.choice.Warning_Message_Content.buf, cb, cblen);

    return ogs_sbcap_encode(&pdu); /* frees the PDU contents */
}

static ogs_pkbuf_t *build_stop(uint16_t msg_id, uint16_t serial, const char *plmn,
        const int *tacs, int ntac)
{
    ogs_sbcap_message_t pdu;
    SBCAP_Stop_Warning_Request_t *req;
    SBCAP_Stop_Warning_Request_IEs_t *ie;

    memset(&pdu, 0, sizeof(pdu));
    pdu.present = SBCAP_SBC_AP_PDU_PR_initiatingMessage;
    pdu.choice.initiatingMessage = CALLOC(1, sizeof(SBCAP_InitiatingMessage_t));
    pdu.choice.initiatingMessage->procedureCode = SBCAP_id_Stop_Warning;
    pdu.choice.initiatingMessage->criticality = SBCAP_Criticality_reject;
    pdu.choice.initiatingMessage->value.present =
        SBCAP_InitiatingMessage__value_PR_Stop_Warning_Request;
    req = &pdu.choice.initiatingMessage->value.choice.Stop_Warning_Request;

    NEW_IE(SBCAP_Stop_Warning_Request_IEs_t, req, ie);
    ie->id = SBCAP_id_Message_Identifier; ie->criticality = SBCAP_Criticality_reject;
    ie->value.present = SBCAP_Stop_Warning_Request_IEs__value_PR_Message_Identifier;
    bitstring16(&ie->value.choice.Message_Identifier, msg_id);

    NEW_IE(SBCAP_Stop_Warning_Request_IEs_t, req, ie);
    ie->id = SBCAP_id_Serial_Number; ie->criticality = SBCAP_Criticality_reject;
    ie->value.present = SBCAP_Stop_Warning_Request_IEs__value_PR_Serial_Number;
    bitstring16(&ie->value.choice.Serial_Number, serial);

    if (ntac > 0) {
        NEW_IE(SBCAP_Stop_Warning_Request_IEs_t, req, ie);
        ie->id = SBCAP_id_List_of_TAIs; ie->criticality = SBCAP_Criticality_ignore;
        ie->value.present = SBCAP_Stop_Warning_Request_IEs__value_PR_List_of_TAIs;
        add_tai_list(&ie->value.choice.List_of_TAIs, plmn, tacs, ntac);
    }
    return ogs_sbcap_encode(&pdu);
}

/* Print the outcome and Cause of the MME answer. Returns 0 if accepted. */
static int print_answer(const uint8_t *buf, int len)
{
    ogs_sbcap_message_t msg;
    ogs_pkbuf_t *pkbuf = ogs_pkbuf_alloc(NULL, len);
    int rv = 1, i;

    ogs_pkbuf_put_data(pkbuf, buf, len);
    if (ogs_sbcap_decode(&msg, pkbuf) != OGS_OK) {
        fprintf(stderr, "cannot decode the MME answer (%d bytes)\n", len);
        ogs_pkbuf_free(pkbuf);
        return 1;
    }
    if (msg.present == SBCAP_SBC_AP_PDU_PR_successfulOutcome) {
        SBCAP_SuccessfulOutcome_t *so = msg.choice.successfulOutcome;
        long cause = -1;
        if (so->procedureCode == SBCAP_id_Write_Replace_Warning) {
            SBCAP_Write_Replace_Warning_Response_t *r =
                &so->value.choice.Write_Replace_Warning_Response;
            for (i = 0; i < r->protocolIEs.list.count; i++)
                if (r->protocolIEs.list.array[i]->id == SBCAP_id_Cause)
                    cause = r->protocolIEs.list.array[i]->value.choice.Cause;
            printf("MME -> Write-Replace-Warning-Response, Cause=%ld%s\n", cause,
                    cause == 0 ? " (message-accepted)" : "");
        } else if (so->procedureCode == SBCAP_id_Stop_Warning) {
            SBCAP_Stop_Warning_Response_t *r = &so->value.choice.Stop_Warning_Response;
            for (i = 0; i < r->protocolIEs.list.count; i++)
                if (r->protocolIEs.list.array[i]->id == SBCAP_id_Cause)
                    cause = r->protocolIEs.list.array[i]->value.choice.Cause;
            printf("MME -> Stop-Warning-Response, Cause=%ld%s\n", cause,
                    cause == 0 ? " (message-accepted)" : "");
        } else {
            printf("MME -> successfulOutcome procedureCode=%ld\n", so->procedureCode);
        }
        rv = (cause == 0) ? 0 : 1;
    } else {
        printf("MME -> PDU type %d (not a successful outcome)\n", msg.present);
    }
    ogs_sbcap_free(&msg);
    ogs_pkbuf_free(pkbuf);
    return rv;
}

static void usage(void)
{
    fprintf(stderr,
        "usage: sbcap-send [--mme IP] [--port 29168] [--plmn 00101] [--tac 1[,2]]\n"
        "                  [--msg-id 4370] [--code N] [--update 0] [--text \"...\"] [--stop]\n");
}

int main(int argc, char **argv)
{
    const char *mme = "127.0.0.2", *plmn = "00101", *text = "F2G ALERTE CIBLEE";
    int port = 29168, msg_id = 4370, code = 300, update = 0, stop = 0;
    int tacs[MAX_TAC], ntac = 0, gs, fd, n, c;
    uint16_t serial;
    ogs_pkbuf_t *pkbuf;
    struct sockaddr_in sa;
    struct timeval tv = { 5, 0 };
    uint8_t rbuf[4096];

    static struct option opts[] = {
        {"mme", 1, 0, 'm'}, {"port", 1, 0, 'p'}, {"plmn", 1, 0, 'P'},
        {"tac", 1, 0, 't'}, {"msg-id", 1, 0, 'i'}, {"code", 1, 0, 'c'},
        {"update", 1, 0, 'u'}, {"text", 1, 0, 'x'}, {"stop", 0, 0, 's'},
        {"help", 0, 0, 'h'}, {0, 0, 0, 0}
    };
    while ((c = getopt_long(argc, argv, "", opts, NULL)) != -1) {
        switch (c) {
        case 'm': mme = optarg; break;
        case 'p': port = atoi(optarg); break;
        case 'P': plmn = optarg; break;
        case 'i': msg_id = atoi(optarg); break;
        case 'c': code = atoi(optarg); break;
        case 'u': update = atoi(optarg); break;
        case 'x': text = optarg; break;
        case 's': stop = 1; break;
        case 't': {
            char *tok = strtok(optarg, ",");
            while (tok && ntac < MAX_TAC) { tacs[ntac++] = atoi(tok); tok = strtok(NULL, ","); }
            break;
        }
        default: usage(); return 2;
        }
    }

    /* Serial Number (TS 23.041 9.4.1.2.1): GS(2) | Message Code(10) | Update(4).
     * GS = 2 (TA wide) when a TAC list is given, 1 (PLMN wide) otherwise. */
    gs = ntac > 0 ? 2 : 1;
    serial = (uint16_t)((gs << 14) | ((code & 0x3FF) << 4) | (update & 0xF));

    ogs_core_initialize();
    /* the SBc-AP library logs in its own domain: it must be installed */
    ogs_log_install_domain(&__ogs_sbcap_domain, "sbcap", OGS_LOG_ERROR);

    pkbuf = stop ? build_stop(msg_id, serial, plmn, tacs, ntac)
                 : build_write(msg_id, serial, plmn, tacs, ntac, text);
    if (!pkbuf) { fprintf(stderr, "encoding failed\n"); return 1; }

    fd = socket(AF_INET, SOCK_STREAM, IPPROTO_SCTP);
    if (fd < 0) { perror("socket(SCTP)"); return 1; }
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    sa.sin_port = htons(port);
    inet_pton(AF_INET, mme, &sa.sin_addr);
    if (connect(fd, (struct sockaddr *)&sa, sizeof(sa)) < 0) { perror("connect"); return 1; }

    printf("CBC -> %s msg_id=%d serial=0x%04x (GS=%d code=%d) TAC=",
            stop ? "Stop-Warning-Request" : "Write-Replace-Warning-Request",
            msg_id, serial, gs, code);
    if (ntac == 0) printf("(none: whole PLMN)");
    for (c = 0; c < ntac; c++) printf("%s%d", c ? "," : "", tacs[c]);
    if (!stop) printf(" text=\"%s\"", text);
    printf("\n");

    if (sctp_sendmsg(fd, pkbuf->data, pkbuf->len, NULL, 0,
                htonl(SBCAP_PPID), 0, 0, 0, 0) < 0) {
        perror("sctp_sendmsg");
        return 1;
    }
    ogs_pkbuf_free(pkbuf);

    n = recv(fd, rbuf, sizeof(rbuf), 0);
    if (n <= 0) { fprintf(stderr, "no answer from the MME within 5 s\n"); return 1; }
    c = print_answer(rbuf, n);

    close(fd);
    ogs_core_terminate();
    return c;
}
