/* ============================================================================
 * mlkem_hw.c  -  bare-metal driver for the ML-KEM-512 PL accelerator
 * Register / buffer map: see rtl/mlkem_axi_top.sv and rtl/mlkem_pkg.sv
 * ==========================================================================*/
#include "mlkem_hw.h"
#include "xil_io.h"

/* byte offsets inside the 4 KB I/O buffer */
#define OFF_DK    0x000u
#define OFF_EK    0x300u
#define OFF_Z     0x640u
#define OFF_CT    0x660u
#define OFF_D     0xC60u
#define OFF_MSG   0xC80u
#define OFF_K     0xCA0u
/* registers */
#define REG_CTRL   0x1000u
#define REG_STATUS 0x1004u
#define REG_CYCLES 0x1008u
#define REG_ID     0x100Cu

#define CMD_KEYGEN 1u
#define CMD_ENCAPS 2u
#define CMD_DECAPS 3u
#define TIMEOUT    10000000u

static uintptr_t g_base;

void mlkem_init(uintptr_t base) { g_base = base; }

static void put(uint32_t off, const uint8_t *src, uint32_t n)
{
    for (uint32_t i = 0; i < n; i += 4) {
        uint32_t w = (uint32_t)src[i] | ((uint32_t)src[i + 1] << 8) |
                     ((uint32_t)src[i + 2] << 16) | ((uint32_t)src[i + 3] << 24);
        Xil_Out32(g_base + off + i, w);
    }
}

static void get(uint32_t off, uint8_t *dst, uint32_t n)
{
    for (uint32_t i = 0; i < n; i += 4) {
        uint32_t w = Xil_In32(g_base + off + i);
        dst[i] = (uint8_t)w;          dst[i + 1] = (uint8_t)(w >> 8);
        dst[i + 2] = (uint8_t)(w >> 16); dst[i + 3] = (uint8_t)(w >> 24);
    }
}

static int run(uint32_t cmd)
{
    Xil_Out32(g_base + REG_CTRL, cmd);
    for (uint32_t t = 0; t < TIMEOUT; t++)
        if (Xil_In32(g_base + REG_STATUS) & 0x2u)      /* done */
            return 0;
    return -1;
}

int mlkem_keygen(const uint8_t d[32], const uint8_t z[32], uint8_t ek[800], uint8_t dk[1632])
{
    put(OFF_D, d, 32);
    put(OFF_Z, z, 32);
    if (run(CMD_KEYGEN)) return -1;
    get(OFF_EK, ek, MLKEM_EK_BYTES);
    get(OFF_DK, dk, MLKEM_DK_BYTES);
    return 0;
}

int mlkem_encaps(const uint8_t ek[800], const uint8_t m[32], uint8_t ct[768], uint8_t ss[32])
{
    put(OFF_EK, ek, MLKEM_EK_BYTES);
    put(OFF_MSG, m, 32);
    if (run(CMD_ENCAPS)) return -1;
    get(OFF_CT, ct, MLKEM_CT_BYTES);
    get(OFF_K, ss, MLKEM_SS_BYTES);
    return 0;
}

int mlkem_decaps(const uint8_t dk[1632], const uint8_t ct[768], uint8_t ss[32])
{
    put(OFF_DK, dk, MLKEM_DK_BYTES);
    put(OFF_CT, ct, MLKEM_CT_BYTES);
    if (run(CMD_DECAPS)) return -1;
    get(OFF_K, ss, MLKEM_SS_BYTES);
    return 0;
}

uint32_t mlkem_last_cycles(void) { return Xil_In32(g_base + REG_CYCLES); }
