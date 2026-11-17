#include "gcd.h"

/* Binary GCD: only shifts, subtraction and comparison, no divider. */
uint32_t gcd_u32(uint32_t a, uint32_t b)
{
    /* Rule 1: gcd(x, 0) = gcd(0, x) = x. */
    if (a == 0)
        return b;
    if (b == 0)
        return a;

    /* Rule 2: while both are even, gcd(a, b) = 2 * gcd(a / 2, b / 2).
     * Count the shared factors of two in k and put them back at the end.
     */
    unsigned k = 0;
    while (((a | b) & 1) == 0) {
        a >>= 1;
        b >>= 1;
        k++;
    }

    while (a != 0 && b != 0) {
        if ((a & 1) == 0) {
            /* Rule 3: an odd number has no factor of two to share. */
            a >>= 1;
        } else if ((b & 1) == 0) {
            b >>= 1;
        } else if (a > b) {
            /* Rule 4: both odd, so the difference is even. Subtract the
             * smaller from the larger to avoid unsigned wrap-around.
             */
            a -= b;
        } else {
            b -= a;
        }
    }

    /* One of them is now zero, so a | b is the other one. */
    return (a | b) << k;
}
