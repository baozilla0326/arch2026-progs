# BFloat16 narrowing, multiply and square root, hand-written RV32I.
#
# uint16_t bf16_from_f32_asm(uint32_t f32bits)   a0 -> a0
# uint16_t bf16_mul_asm(uint16_t a, uint16_t b)   a0, a1 -> a0
# uint16_t bf16_sqrt_asm(uint16_t a)              a0 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tbf16.c. The uint16_t arguments arrive
# zero-extended, as the calling convention requires.

    .equ    BIAS, 127
    .equ    NAN, 0x7FC0
    .equ    INF, 0x7F80

    .text

# from_f32: Inf and NaN keep their top half; everything else adds 0x7FFF
# plus the lowest kept bit (round to nearest, ties to even).
    .globl  bf16_from_f32_asm
    .type   bf16_from_f32_asm, @function
    .align  2
bf16_from_f32_asm:
    lui     t1, 0x7F800             # exponent field mask
    and     t0, a0, t1
    beq     t0, t1, 1f
    srli    t0, a0, 16
    andi    t0, t0, 1
    add     a0, a0, t0
    lui     t1, 0x8
    addi    t1, t1, -1              # 0x7FFF
    add     a0, a0, t1
1:
    srli    a0, a0, 16
    ret
    .size   bf16_from_f32_asm, .-bf16_from_f32_asm

# mul: special values first (a, then b), then normalize, multiply the two
# 8-bit significands with an unrolled shift-and-add and truncate.
    .globl  bf16_mul_asm
    .type   bf16_mul_asm, @function
    .align  2
bf16_mul_asm:
    xor     t6, a0, a1
    srli    t6, t6, 15
    slli    t6, t6, 15              # product sign
    srli    t0, a0, 7
    andi    t0, t0, 0xFF            # exponent of a
    srli    t1, a1, 7
    andi    t1, t1, 0xFF            # exponent of b
    andi    t2, a0, 0x7F            # fraction of a
    andi    t3, a1, 0x7F            # fraction of b
    li      t4, 0xFF
    beq     t0, t4, .Lm_a_special
    beq     t1, t4, .Lm_b_special
    slli    t5, a0, 17              # a is +-0 when its low 15 bits are 0
    beqz    t5, .Lm_zero
    slli    t5, a1, 17
    beqz    t5, .Lm_zero

    # leading one: set it for normals, shift it up for denormals
    bnez    t0, 1f
    li      t0, 1
2:
    slli    t2, t2, 1
    addi    t0, t0, -1
    andi    t5, t2, 0x80
    beqz    t5, 2b
    j       3f
1:
    ori     t2, t2, 0x80
3:
    bnez    t1, 1f
    li      t1, 1
2:
    slli    t3, t3, 1
    addi    t1, t1, -1
    andi    t5, t3, 0x80
    beqz    t5, 2b
    j       3f
1:
    ori     t3, t3, 0x80
3:
    # a2 = t2 * t3 (8 x 8 bits); bit 7 of t3 is always set
    li      a2, 0
    .irp    bit, 0, 1, 2, 3, 4, 5, 6
    andi    t5, t3, 1 << \bit
    beqz    t5, 4f
    add     a2, a2, t2
4:
    slli    t2, t2, 1
    .endr
    add     a2, a2, t2

    add     t0, t0, t1
    addi    t0, t0, -BIAS           # result exponent
    # keep 7 fraction bits: shift by 8 when the product reached bit 15
    srli    t5, a2, 15
    add     t0, t0, t5
    addi    t5, t5, 7
    srl     a2, a2, t5
    andi    a2, a2, 0x7F

    bge     t0, t4, .Lm_inf
    bgtz    t0, 5f
    li      t5, -6                  # denormal result, or zero below 2^-6
    blt     t0, t5, .Lm_zero
    li      t5, 1
    sub     t5, t5, t0
    srl     a2, a2, t5
    li      t0, 0
5:
    slli    t0, t0, 7
    or      a0, t6, t0
    or      a0, a0, a2
    ret

.Lm_a_special:
    bnez    t2, .Lm_ret             # NaN a is returned unchanged
    slli    t5, a1, 17
    beqz    t5, .Lm_nan             # Inf times zero
    j       .Lm_inf
.Lm_b_special:
    mv      a0, a1
    bnez    t3, .Lm_ret             # NaN b is returned unchanged
    or      t5, t0, t2              # a is finite here; zero when both are 0
    beqz    t5, .Lm_nan             # zero times Inf
.Lm_inf:
    li      a0, INF
    or      a0, a0, t6
    ret
.Lm_nan:
    li      a0, NAN
    ret
.Lm_zero:
    mv      a0, t6
.Lm_ret:
    ret
    .size   bf16_mul_asm, .-bf16_mul_asm

# sqrt: the contract result is the largest r with (r * r) / 128 <= m, that
# is r = isqrt(128 * m + 127). For a normal input m is in [128, 511], so r
# is in [128, 255] and the result is always a normal number: no Inf or zero
# check is needed. The integer square root is found digit by digit, two
# bits of the radicand per step, with no multiply.
    .globl  bf16_sqrt_asm
    .type   bf16_sqrt_asm, @function
    .align  2
bf16_sqrt_asm:
    srli    t0, a0, 7
    andi    t0, t0, 0xFF            # exponent
    andi    t1, a0, 0x7F            # fraction
    li      t3, 0xFF
    beq     t0, t3, .Ls_special
    slli    t2, a0, 17
    beqz    t2, .Ls_zero            # either zero gives +0
    srli    t2, a0, 15
    bnez    t2, .Ls_nan             # negative nonzero
    beqz    t0, .Ls_zero            # denormals give +0

    # e = exponent - 127 is odd exactly when the exponent is even
    andi    t2, t0, 1
    xori    t2, t2, 1               # 1 when e is odd
    ori     t1, t1, 0x80            # m with its leading one
    sll     t1, t1, t2              # odd e: double m
    addi    t0, t0, -BIAS
    sub     t0, t0, t2
    srai    t0, t0, 1
    addi    t0, t0, BIAS            # new exponent

    # n = 128 * m + 127 is in [16511, 65535]; the first digit always fits
    slli    t1, t1, 7
    ori     t1, t1, 127
    lui     t2, 0x4                 # bit = 1 << 14
    sub     t1, t1, t2
    mv      t3, t2                  # res = bit
    srli    t2, t2, 2
1:
    add     t4, t3, t2              # res + bit
    srli    t3, t3, 1
    bltu    t1, t4, 2f
    sub     t1, t1, t4
    add     t3, t3, t2
2:
    srli    t2, t2, 2
    bnez    t2, 1b

    andi    t3, t3, 0x7F
    slli    t0, t0, 7
    or      a0, t0, t3
    ret

.Ls_special:
    bnez    t1, .Ls_ret             # NaN is returned unchanged
    srli    t2, a0, 15
    beqz    t2, .Ls_ret             # +Inf is returned unchanged
.Ls_nan:
    li      a0, NAN
    ret
.Ls_zero:
    li      a0, 0
.Ls_ret:
    ret
    .size   bf16_sqrt_asm, .-bf16_sqrt_asm
