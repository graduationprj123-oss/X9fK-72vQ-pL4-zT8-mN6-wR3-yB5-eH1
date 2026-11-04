/* ============================================================================
 * mlkem_hw.h  -  bare-metal driver for the ML-KEM-512 PL accelerator (Zynq-7000)
 * ==========================================================================*/
#ifndef MLKEM_HW_H
#define MLKEM_HW_H
#include <stdint.h>

#define MLKEM_EK_BYTES   800
#define MLKEM_DK_BYTES   1632
#define MLKEM_CT_BYTES   768
#define MLKEM_SS_BYTES   32
#define MLKEM_SEED_BYTES 32

/* base address of the AXI slave (from xparameters.h, e.g.
 * XPAR_MLKEM_AXI_WRAPPER_0_BASEADDR); set once with mlkem_init(). */
void mlkem_init(uintptr_t base);

/* All functions return 0 on success, -1 on timeout.
 * d, z, m must come from a cryptographically secure RNG.               */
int mlkem_keygen(const uint8_t d[32], const uint8_t z[32],
                 uint8_t ek[MLKEM_EK_BYTES], uint8_t dk[MLKEM_DK_BYTES]);
int mlkem_encaps(const uint8_t ek[MLKEM_EK_BYTES], const uint8_t m[32],
                 uint8_t ct[MLKEM_CT_BYTES], uint8_t ss[MLKEM_SS_BYTES]);
int mlkem_decaps(const uint8_t dk[MLKEM_DK_BYTES], const uint8_t ct[MLKEM_CT_BYTES],
                 uint8_t ss[MLKEM_SS_BYTES]);

/* clock cycles used by the last operation */
uint32_t mlkem_last_cycles(void);

#endif
