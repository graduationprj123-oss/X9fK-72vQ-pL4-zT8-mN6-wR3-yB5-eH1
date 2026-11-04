/* ============================================================================
 * main.c  -  UART front-end: PC <-> UART <-> PS <-> ML-KEM accelerator (PL)
 *
 * One command per line, hex payloads (no spaces inside a field):
 *   K <d:64hex> <z:64hex>        ->  EK <1600hex>\r\n DK <3264hex>
 *   E <ek:1600hex> <m:64hex>     ->  CT <1536hex>\r\n SS <64hex>
 *   D <dk:3264hex> <ct:1536hex>  ->  SS <64hex>
 *   I                            ->  ID / last cycle count
 * Every reply ends with "OK <cycles>" or "ERR <reason>".
 * ==========================================================================*/
#include <stdint.h>
#include <string.h>
#include "xparameters.h"
#include "xil_printf.h"
#include "xil_io.h"
#include "mlkem_hw.h"

#ifndef MLKEM_BASEADDR
#define MLKEM_BASEADDR XPAR_MLKEM_AXI_WRAPPER_0_BASEADDR   /* adjust to your design */
#endif

extern char inbyte(void);

#define LINE_MAX 6000
static char    line[LINE_MAX];
static uint8_t ek[MLKEM_EK_BYTES], dk[MLKEM_DK_BYTES], ct[MLKEM_CT_BYTES];
static uint8_t s1[32], s2[32], ss[32];

static int read_line(void)
{
    int n = 0;
    for (;;) {
        char c = inbyte();
        if (c == '\r' || c == '\n') { if (n) break; else continue; }
        if (n < LINE_MAX - 1) line[n++] = c;
    }
    line[n] = 0;
    return n;
}

static int hexval(char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

/* parse exactly n bytes of hex starting at *p, skip leading spaces, advance *p */
static int parse_hex(const char **p, uint8_t *out, int n)
{
    const char *s = *p;
    while (*s == ' ') s++;
    for (int i = 0; i < n; i++) {
        int hi = hexval(s[2 * i]), lo = (hi < 0) ? -1 : hexval(s[2 * i + 1]);
        if (hi < 0 || lo < 0) return -1;
        out[i] = (uint8_t)(hi << 4 | lo);
    }
    s += 2 * n;
    if (*s != ' ' && *s != 0) return -1;
    *p = s;
    return 0;
}

static void print_hex(const char *tag, const uint8_t *b, int n)
{
    xil_printf("%s ", tag);
    for (int i = 0; i < n; i++) xil_printf("%02x", b[i]);
    xil_printf("\r\n");
}

int main(void)
{
    mlkem_init(MLKEM_BASEADDR);
    xil_printf("ML-KEM-512 accelerator ready, ID %08x\r\n", Xil_In32(MLKEM_BASEADDR + 0x100C));

    for (;;) {
        read_line();
        const char *p = line + 1;
        int rc = 0;
        switch (line[0]) {
        case 'K':
            if (parse_hex(&p, s1, 32) || parse_hex(&p, s2, 32)) { xil_printf("ERR args\r\n"); continue; }
            rc = mlkem_keygen(s1, s2, ek, dk);
            if (!rc) { print_hex("EK", ek, sizeof ek); print_hex("DK", dk, sizeof dk); }
            break;
        case 'E':
            if (parse_hex(&p, ek, sizeof ek) || parse_hex(&p, s1, 32)) { xil_printf("ERR args\r\n"); continue; }
            rc = mlkem_encaps(ek, s1, ct, ss);
            if (!rc) { print_hex("CT", ct, sizeof ct); print_hex("SS", ss, sizeof ss); }
            break;
        case 'D':
            if (parse_hex(&p, dk, sizeof dk) || parse_hex(&p, ct, sizeof ct)) { xil_printf("ERR args\r\n"); continue; }
            rc = mlkem_decaps(dk, ct, ss);
            if (!rc) print_hex("SS", ss, sizeof ss);
            break;
        case 'I':
            xil_printf("ID %08x\r\n", Xil_In32(MLKEM_BASEADDR + 0x100C));
            break;
        default:
            xil_printf("ERR cmd\r\n");
            continue;
        }
        if (rc) xil_printf("ERR timeout\r\n");
        else    xil_printf("OK %d\r\n", (int)mlkem_last_cycles());
    }
    return 0;
}
