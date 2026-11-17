/* Worst-case sweep: every state at distance 11 through both solvers, with the
 * instructions of the most expensive call. Not part of the graded build; see
 * mytests/Makefile.
 */
#include <stddef.h>
#include <stdint.h>

#include "print.h"
#include "src/rubik/rubik.h"

extern uint64_t get_instret(void);

static const char *const states[] = {
#include "dist11.inc"
};

typedef int (*solve_fn)(const char *, char *, size_t);

static void sweep(const char *name, solve_fn solve)
{
    uint64_t worst = 0;
    size_t at = 0;
    int bad = 0;
    char out[64];
    for (size_t i = 0; i < sizeof states / sizeof states[0]; i++) {
        uint64_t t0 = get_instret();
        int n = solve(states[i], out, sizeof out);
        uint64_t used = get_instret() - t0;
        if (n != 11)
            bad++;
        if (used > worst) {
            worst = used;
            at = i;
        }
    }
    /* The printf has no 64-bit conversion; the worst count fits 32 bits. */
    bm_printf("%s: worst %u (%s), wrong %d\n", name, (unsigned) worst,
              states[at], bad);
}

int main(void)
{
    sweep("C", rubik_solve);
    sweep("asm", rubik_solve_asm);
    return 0;
}
