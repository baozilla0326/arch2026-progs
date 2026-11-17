# rubik_solve_asm: optimal 2x2x2 cube solver, hand-written RV32I.
#
# int rubik_solve_asm(const char *state, char *out, size_t cap)
#                                   a0 = state, a1 = out, a2 = cap; result in a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions, no heap, no recursion. Tests: tests/trubik.c.
#
# The search is the one of rubik.c: iterative deepening A* over the
# coordinates p (permutation, 0..5039), o (orientation, 0..728) and q (places
# and twists of cubies 0 and 1, 0..440), pruned by h = max(D, G). The tables
# (rubik_tables.S) are laid out so that a lookup is an add and a load: the
# move tables hold byte offsets (2p, 4q), and the pattern databases are
# transposed so that rubik_asm_info[q] gives the start of the row that o, or
# p, indexes. Both bounds are tested one at a time, D first, and G is only
# loaded for a child that D does not prune.
#
# Search frame on the stack, 8 bytes per level, level d at sp + 8 + 8d:
#   +0 half 2p   +2 half o   +4 half 4q   of the cube after d moves
#   +6 byte face +7 byte turn of the move being tried from it
# The record at sp + 0 is a sentinel whose face (3) matches no face.
#
# Register use in the search:
#   s0 rubik_asm_rows       s6  bound               a3 child 2p
#   s1 rubik_asm_dist       s7  face being tried    a4 child o
#   s2 rubik_asm_info       s8  record of level d   a5 child 4q
#   s3 perm row of s7       s9  face of level d-1   a6 rubik_asm_perm_dist
#   s4 ori row of s7        s10 turn, 0..2          a7 the constant 3
#   s5 pair row of s7       s11 bound - d - 1: the largest h a child may have
#   a1, a2 keep out and cap for the output.

    .equ    CUBIES, 7
    .equ    ASCII_1, 49                 # the character "1"
    .equ    REC, 8                      # bytes per search level
    .equ    FRAME, 160                  # 13 records, 12 saved registers

    .section .rodata
faces:
    .byte   82, 66, 68                  # R, B, D
suffix:
    .byte   0, 50, 39                   # quarter turn "", half turn "2", "'"

    .text

# Load the row addresses of face s7 into s3, s4, s5 (s0 + 12 * s7).
.macro  rows
    slli    t0, s7, 2
    slli    t1, s7, 3
    add     t0, t0, t1
    add     t0, t0, s0
    lw      s3, 0(t0)
    lw      s4, 4(t0)
    lw      s5, 8(t0)
.endm

    .globl  rubik_solve_asm
    .type   rubik_solve_asm, @function
    .align  2
rubik_solve_asm:
    # ---- Validate. Cubies '1'..'7' without repeats, t0 the seen set. ----
    mv      t2, a0
    addi    t3, a0, CUBIES
    li      t0, 0
    li      t4, CUBIES
    li      t6, 1
.Lperm:
    lbu     t5, 0(t2)
    addi    t5, t5, -ASCII_1
    bgeu    t5, t4, .Linvalid           # also catches the NUL of a short string
    sll     t1, t6, t5
    and     a3, t0, t1
    bnez    a3, .Linvalid
    or      t0, t0, t1
    addi    t2, t2, 1
    bne     t2, t3, .Lperm
    # Orientations '1'..'3', t0 their sum.
    addi    t3, a0, 2 * CUBIES
    li      t0, 0
    li      t4, 3
.Lori:
    lbu     t5, 0(t2)
    addi    t5, t5, -ASCII_1
    bgeu    t5, t4, .Linvalid
    add     t0, t0, t5
    addi    t2, t2, 1
    bne     t2, t3, .Lori
    lbu     t5, 0(t2)
    bnez    t5, .Linvalid               # exactly 14 characters
.Lmod3:
    bltu    t0, t4, .Lmod3_done
    addi    t0, t0, -3
    j       .Lmod3
.Lmod3_done:
    bnez    t0, .Linvalid

    # ---- p: Lehmer rank, p = p * (7 - i) + #{j > i : s[j] < s[i]}. ----
    # The multiply by k = 7..2 is k additions. a3 = p.
    li      a3, 0
    mv      t2, a0
    addi    t3, a0, CUBIES
    li      t4, CUBIES
.Lrank:
    mv      t5, t4
    li      t6, 0
.Lrank_mul:
    add     t6, t6, a3
    addi    t5, t5, -1
    bnez    t5, .Lrank_mul
    mv      a3, t6
    lbu     t0, 0(t2)
    addi    t1, t2, 1
.Lrank_count:
    lbu     t5, 0(t1)
    sltu    t5, t5, t0
    add     a3, a3, t5
    addi    t1, t1, 1
    bne     t1, t3, .Lrank_count
    addi    t2, t2, 1
    addi    t4, t4, -1
    li      t5, 1
    bne     t4, t5, .Lrank

    # ---- o: the first six orientations in base 3. a4 = o. ----
    li      a4, 0
    addi    t2, a0, CUBIES
    addi    t3, a0, 2 * CUBIES - 1
.Lori_rank:
    lbu     t5, 0(t2)
    addi    t5, t5, -ASCII_1
    slli    t6, a4, 1
    add     a4, a4, t6
    add     a4, a4, t5
    addi    t2, t2, 1
    bne     t2, t3, .Lori_rank

    # ---- q = c0 * 21 + c1, where ck = 3 * place + twist of cubie k. ----
    li      t0, 0                       # 3 * place
    mv      t2, a0
    addi    t3, a0, CUBIES
    li      t4, ASCII_1
    li      t6, ASCII_1 + 1
.Lpair:
    lbu     t5, 0(t2)
    lbu     t1, CUBIES(t2)
    addi    t1, t1, -ASCII_1
    add     t1, t1, t0
    bne     t5, t4, 1f
    mv      a6, t1                      # c0
1:
    bne     t5, t6, 2f
    mv      a7, t1                      # c1
2:
    addi    t0, t0, 3
    addi    t2, t2, 1
    bne     t2, t3, .Lpair
    slli    t0, a6, 4
    slli    t1, a6, 2
    add     a5, t0, t1
    add     a5, a5, a6
    add     a5, a5, a7

    # Byte offsets: 2p and 4q.
    slli    a3, a3, 1
    slli    a5, a5, 2

    # ---- Search. ----
    addi    sp, sp, -FRAME
    sw      s0, 104(sp)
    sw      s1, 108(sp)
    sw      s2, 112(sp)
    sw      s3, 116(sp)
    sw      s4, 120(sp)
    sw      s5, 124(sp)
    sw      s6, 128(sp)
    sw      s7, 132(sp)
    sw      s8, 136(sp)
    sw      s9, 140(sp)
    sw      s10, 144(sp)
    sw      s11, 148(sp)
    la      s0, rubik_asm_rows
    la      s1, rubik_asm_dist
    la      s2, rubik_asm_info
    la      a6, rubik_asm_perm_dist
    li      a7, 3
    sb      a7, 6(sp)                   # sentinel face
    sh      a3, REC+0(sp)
    sh      a4, REC+2(sp)
    sh      a5, REC+4(sp)

    # h of the start: D in t2, G in t3.
    add     t1, s2, a5
    lhu     t0, 0(t1)
    add     t0, t0, a4
    add     t0, t0, s1
    lbu     t2, 0(t0)
    lhu     t0, 2(t1)
    srli    t5, a3, 1
    add     t0, t0, t5
    add     t0, t0, a6
    lbu     t3, 0(t0)
    li      a0, 0
    or      t0, t2, t3
    beqz    t0, .Loutput                # solved already
    mv      s6, t2
    bgeu    t2, t3, .Lbound
    mv      s6, t3

.Lbound:
    addi    s8, sp, REC
    addi    s11, s6, -1
    li      s9, 3
    li      s7, -1

    # Try the next face from level d, never the face of the previous move.
.Lnext_face:
    addi    s7, s7, 1
    bne     s7, s9, 1f
    addi    s7, s7, 1
1:
    bgeu    s7, a7, .Lbacktrack
    sb      s7, 6(s8)
    rows
    lhu     a3, 0(s8)
    lhu     a4, 2(s8)
    lhu     a5, 4(s8)
    li      s10, 0

    # One more quarter turn of face s7: the child after turn s10 + 1.
.Lturn:
    add     t0, s3, a3
    lhu     a3, 0(t0)                   # 2p
    slli    t0, a4, 1
    add     t0, t0, s4
    lhu     a4, 0(t0)                   # o
    add     t0, s5, a5
    lw      a5, 0(t0)                   # 4q
    add     t1, s2, a5                  # &info[q]
    lhu     t0, 0(t1)
    add     t0, t0, a4
    add     t0, t0, s1
    lbu     t2, 0(t0)                   # D
    bltu    s11, t2, .Lnext_turn
    lhu     t0, 2(t1)
    srli    t5, a3, 1
    add     t0, t0, t5
    add     t0, t0, a6
    lbu     t3, 0(t0)                   # G
    bltu    s11, t3, .Lnext_turn
    or      t0, t2, t3
    beqz    t0, .Lsolved
    # Descend: the child becomes level d + 1.
    sb      s10, 7(s8)
    sh      a3, REC+0(s8)
    sh      a4, REC+2(s8)
    sh      a5, REC+4(s8)
    addi    s8, s8, REC
    addi    s11, s11, -1
    mv      s9, s7
    li      s7, -1
    j       .Lnext_face

.Lnext_turn:
    addi    s10, s10, 1
    bne     s10, a7, .Lturn
    j       .Lnext_face

    # Every face of level d is done: resume level d - 1 after its last turn.
.Lbacktrack:
    addi    t0, sp, REC
    beq     s8, t0, .Lnext_bound
    addi    s8, s8, -REC
    addi    s11, s11, 1
    lbu     s7, 6(s8)
    lbu     s10, 7(s8)
    lbu     s9, 6-REC(s8)
    rows
    lhu     a3, REC+0(s8)
    lhu     a4, REC+2(s8)
    lhu     a5, REC+4(s8)
    j       .Lnext_turn

.Lnext_bound:
    addi    s6, s6, 1
    j       .Lbound

.Lsolved:
    sb      s10, 7(s8)
    addi    t0, sp, REC
    sub     a0, s8, t0
    srli    a0, a0, 3
    addi    a0, a0, 1                   # moves = d + 1

    # ---- Output: a0 moves, recorded in levels 0 .. a0 - 1. ----
.Loutput:
    # Bytes needed: a name of one or two characters plus a space or the NUL
    # per move, and the NUL alone for no move.
    li      t0, 1
    beqz    a0, 2f
    li      t0, 0
    addi    t2, sp, REC
    slli    t3, a0, 3
    add     t3, t3, t2
1:
    lbu     t1, 7(t2)
    sltu    t1, zero, t1
    add     t0, t0, t1
    addi    t0, t0, 2
    addi    t2, t2, REC
    bne     t2, t3, 1b
2:
    bgeu    a2, t0, .Lwrite
    beqz    a2, 3f
    sb      zero, 0(a1)
3:
    li      a0, -2
    j       .Lreturn

.Lwrite:
    la      t4, faces
    la      t5, suffix
    mv      t6, a1
    addi    t2, sp, REC
    slli    t3, a0, 3
    add     t3, t3, t2
    beqz    a0, .Lterminate
    li      a3, 32
    j       5f
4:
    sb      a3, 0(t6)
    addi    t6, t6, 1
5:
    lbu     t0, 6(t2)
    add     t0, t0, t4
    lbu     t0, 0(t0)
    sb      t0, 0(t6)
    addi    t6, t6, 1
    lbu     t1, 7(t2)
    beqz    t1, 6f
    add     t1, t1, t5
    lbu     t1, 0(t1)
    sb      t1, 0(t6)
    addi    t6, t6, 1
6:
    addi    t2, t2, REC
    bne     t2, t3, 4b
.Lterminate:
    sb      zero, 0(t6)

.Lreturn:
    lw      s0, 104(sp)
    lw      s1, 108(sp)
    lw      s2, 112(sp)
    lw      s3, 116(sp)
    lw      s4, 120(sp)
    lw      s5, 124(sp)
    lw      s6, 128(sp)
    lw      s7, 132(sp)
    lw      s8, 136(sp)
    lw      s9, 140(sp)
    lw      s10, 144(sp)
    lw      s11, 148(sp)
    addi    sp, sp, FRAME
    ret

.Linvalid:
    li      a0, -1
    ret
    .size   rubik_solve_asm, .-rubik_solve_asm
