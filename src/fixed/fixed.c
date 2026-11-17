#include "fixed.h"

/* Bitwise adder: a ^ b is the sum without carries, (a & b) << 1 the carries.
 * Feed the carries back in until none is left.
 */
uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    int passes = 0;
    while (b != 0) {
        uint32_t c = (a & b) << 1;
        a ^= b;
        b = c;
        passes++;
    }
    *n = passes;
    return a;
}

uint32_t op2(uint32_t a, uint32_t b)
{
    return a - b;
}

/* a + b = 2 * (a & b) + (a ^ b): the shared bits count twice, the others once.
 * Halving each part keeps the sum within 32 bits.
 */
uint32_t op3(uint32_t a, uint32_t b)
{
    return (a & b) + ((a ^ b) >> 1);
}

/* Q11.20 multiply. The 64-bit product is built from four 16 x 16 -> 32
 * partial products, so only __mulsi3 is needed and never __muldi3.
 */
int32_t q_mul(int32_t a, int32_t b)
{
    uint32_t ua = (uint32_t) a, ub = (uint32_t) b;
    uint32_t al = ua & 0xFFFFu, ah = ua >> 16;
    uint32_t bl = ub & 0xFFFFu, bh = ub >> 16;

    uint32_t ll = al * bl, lh = al * bh, hl = ah * bl, hh = ah * bh;

    /* Unsigned 64-bit product hi:lo. */
    uint32_t mid = (ll >> 16) + (lh & 0xFFFFu) + (hl & 0xFFFFu);
    uint32_t lo = (ll & 0xFFFFu) | (mid << 16);
    uint32_t hi = hh + (lh >> 16) + (hl >> 16) + (mid >> 16);

    /* Signed product: a negative operand x stands for x - 2^32, which
     * subtracts the other operand from the high word.
     */
    if (a < 0)
        hi -= ub;
    if (b < 0)
        hi -= ua;

    /* Add half a unit, then take bits 20..51 of the 64-bit sum. Adding
     * 2^19 carries out of the low word exactly when bits 19..31 are all set.
     */
    hi += (lo >> (Q - 1)) == (1u << (33 - Q)) - 1;
    uint32_t sum = lo + (1u << (Q - 1));
    return (int32_t) ((sum >> Q) | (hi << (32 - Q)));
}
