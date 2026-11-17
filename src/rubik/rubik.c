#include "rubik.h"

#include "rubik_tables.h"

/* Optimal 2x2x2 solver: iterative deepening A* over three coordinates.
 *
 *   p  rank of the cubie permutation, 0..5039 (Lehmer code)
 *   o  orientations of the first six cubies in base 3, 0..728
 *   q  where cubies 0 and 1 sit and how they are twisted, 0..440
 *
 * Each coordinate has a move table per face (a clockwise quarter turn), so a
 * turn costs three loads. The heuristic is max(D, G), two pattern databases
 * from rubik_tables.h:
 *
 *   D[o * 49 + pair_pos[q]]    orientation plus the places of cubies 0, 1
 *   G[p * 9 + pair_twist[q]]   permutation plus the twists of cubies 0, 1
 *
 * Both are exact distances of a relaxed cube, so their maximum is admissible
 * and the first solution found under the bound is a shortest one. Every index
 * product is by a constant, written as shifts and adds: RV32I has no multiply.
 */

enum { CUBIES = 7, FACES = 3, MAX_DEPTH = 11 };

static const char move_text[9][2] = {
    {'R', 0},    {'R', '2'}, {'R', '\''}, {'B', 0},    {'B', '2'},
    {'B', '\''}, {'D', 0},   {'D', '2'},  {'D', '\''},
};

static inline unsigned heuristic(unsigned p, unsigned o, unsigned q)
{
    unsigned a = d_tab[(o << 5) + (o << 4) + o + pair_pos[q]];
    unsigned b = g_tab[(p << 3) + p + pair_twist[q]];
    return a > b ? a : b;
}

/* Iterative deepening with an explicit stack, no recursion. Level d holds the
 * state reached after d moves; face[d] and turn[d] name the move being tried
 * from it, and turn[d] == 2 means the current face is exhausted.
 */
static int search(unsigned p0, unsigned o0, unsigned q0, uint8_t *path)
{
    uint16_t p[MAX_DEPTH + 1], o[MAX_DEPTH + 1], q[MAX_DEPTH + 1];
    uint8_t face[MAX_DEPTH], turn[MAX_DEPTH], next_face[MAX_DEPTH];

    unsigned h0 = heuristic(p0, o0, q0);
    if (h0 == 0)
        return 0;
    p[0] = (uint16_t) p0;
    o[0] = (uint16_t) o0;
    q[0] = (uint16_t) q0;
    for (int bound = (int) h0; bound <= MAX_DEPTH; bound++) {
        int d = 0;
        next_face[0] = 0;
        turn[0] = 2;
        while (d >= 0) {
            if (turn[d] == 2) {
                /* Next face; never turn the face of the previous move. */
                unsigned f = next_face[d];
                if (d > 0 && f == face[d - 1])
                    f++;
                if (f == FACES) {
                    d--;
                    continue;
                }
                face[d] = (uint8_t) f;
                next_face[d] = (uint8_t) (f + 1);
                turn[d] = 0;
                p[d + 1] = p[d];
                o[d + 1] = o[d];
                q[d + 1] = q[d];
            } else {
                turn[d]++;
            }
            unsigned f = face[d];
            unsigned np = perm_move[f][p[d + 1]];
            unsigned no = ori_move[f][o[d + 1]];
            unsigned nq = pair_move[f][q[d + 1]];
            p[d + 1] = (uint16_t) np;
            o[d + 1] = (uint16_t) no;
            q[d + 1] = (uint16_t) nq;
            unsigned h = heuristic(np, no, nq);
            if (d + 1 + (int) h > bound)
                continue;
            path[d] = (uint8_t) ((f << 1) + f + turn[d]);
            if (h == 0)
                return d + 1;
            d++;
            next_face[d] = 0;
            turn[d] = 2;
        }
    }
    return -1; /* unreachable: the diameter is 11 */
}

/* Validates the 14-character state and computes its coordinates. */
static int parse(const char *s, unsigned *pp, unsigned *po, unsigned *pq)
{
    uint8_t perm[CUBIES], ori[CUBIES];
    unsigned seen = 0, sum = 0;
    for (int i = 0; i < CUBIES; i++) {
        unsigned v = (unsigned) (uint8_t) s[i] - '1';
        if (v >= CUBIES || (seen & (1u << v)))
            return 0;
        seen |= 1u << v;
        perm[i] = (uint8_t) v;
    }
    for (int i = 0; i < CUBIES; i++) {
        unsigned v = (unsigned) (uint8_t) s[CUBIES + i] - '1';
        if (v >= 3)
            return 0;
        ori[i] = (uint8_t) v;
        sum += v;
    }
    if (s[2 * CUBIES] != '\0')
        return 0;
    while (sum >= 3)
        sum -= 3;
    if (sum != 0)
        return 0;

    /* Lehmer rank by Horner's rule, multiplying by constants only. */
    unsigned c_less[CUBIES - 1];
    for (int i = 0; i < CUBIES - 1; i++) {
        unsigned smaller = 0;
        for (int j = i + 1; j < CUBIES; j++)
            smaller += perm[j] < perm[i];
        c_less[i] = smaller;
    }
    unsigned p = c_less[0];
    p = (p << 2) + (p << 1) + c_less[1]; /* x6 */
    p = (p << 2) + p + c_less[2];        /* x5 */
    p = (p << 2) + c_less[3];            /* x4 */
    p = (p << 1) + p + c_less[4];        /* x3 */
    p = (p << 1) + c_less[5];            /* x2 */
    unsigned o = 0;
    for (int i = 0; i < CUBIES - 1; i++)
        o = (o << 1) + o + ori[i];
    unsigned c[2] = {0, 0};
    for (int i = 0; i < CUBIES; i++) {
        if (perm[i] < 2)
            c[perm[i]] = ((unsigned) i << 1) + (unsigned) i + ori[i];
    }
    *pp = p;
    *po = o;
    *pq = (c[0] << 4) + (c[0] << 2) + c[0] + c[1];
    return 1;
}

int rubik_solve(const char *state, char *out, size_t cap)
{
    unsigned p, o, q;
    if (!parse(state, &p, &o, &q))
        return -1;
    uint8_t path[MAX_DEPTH];
    int n = search(p, o, q, path);

    /* Each name is one or two characters, then a space or the NUL. */
    size_t need = 0;
    for (int i = 0; i < n; i++)
        need += move_text[path[i]][1] ? 3 : 2;
    if (n == 0)
        need = 1;
    if (need > cap) {
        if (cap >= 1)
            out[0] = '\0';
        return -2;
    }
    char *w = out;
    for (int i = 0; i < n; i++) {
        if (i > 0)
            *w++ = ' ';
        *w++ = move_text[path[i]][0];
        if (move_text[path[i]][1])
            *w++ = move_text[path[i]][1];
    }
    *w = '\0';
    return n;
}
