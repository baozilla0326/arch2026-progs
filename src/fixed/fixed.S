# Arithmetic from logic and Q11.20 multiply, hand-written RV32I.
#
# uint32_t op1_asm(uint32_t a, uint32_t b, int *n)   a0, a1, a2 -> a0
# uint32_t op2_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# uint32_t op3_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# int32_t  q_mul_asm(int32_t a, int32_t b)           a0, a1 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tfixed.c.

    .equ    Q, 20

    .text

# op1: bitwise adder. Each pass: carry = (a & b) << 1, a = a ^ b, b = carry.
    .globl  op1_asm
    .type   op1_asm, @function
    .align  2
op1_asm:
    li      t0, 0                   # pass count
    beqz    a1, 2f
1:
    and     t1, a0, a1
    xor     a0, a0, a1
    slli    a1, t1, 1
    addi    t0, t0, 1
    bnez    a1, 1b
2:
    sw      t0, 0(a2)
    ret
    .size   op1_asm, .-op1_asm

# op2: a - b modulo 2^32.
    .globl  op2_asm
    .type   op2_asm, @function
    .align  2
op2_asm:
    sub     a0, a0, a1
    ret
    .size   op2_asm, .-op2_asm

# op3: floor((a + b) / 2) = (a & b) + ((a ^ b) >> 1), no overflow.
    .globl  op3_asm
    .type   op3_asm, @function
    .align  2
op3_asm:
    xor     t0, a0, a1
    and     a0, a0, a1
    srli    t0, t0, 1
    add     a0, a0, t0
    ret
    .size   op3_asm, .-op3_asm

# q_mul: Q11.20 product, rounded half up, low 32 bits kept.
#
# One shift-and-add loop forms the unsigned 64-bit product t3:t2 of a and b:
# the multiplicand t5:t4 doubles each step and is added when the low bit of
# the multiplier t6 is set. The loop stops as soon as no multiplier bit is
# left. A leaf routine: no __mulsi3 call, no stack frame.
    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2
q_mul_asm:
    li      t2, 0                   # product, low word
    li      t3, 0                   # product, high word
    mv      t4, a0                  # multiplicand, low word
    li      t5, 0                   # multiplicand, high word
    mv      t6, a1                  # multiplier
    beqz    t6, .Lsigned
.Lmul:
    andi    t0, t6, 1
    beqz    t0, .Lshift
    add     t2, t2, t4              # product += multiplicand (64 bits)
    sltu    t0, t2, t4              # carry out of the low word
    add     t3, t3, t5
    add     t3, t3, t0
.Lshift:
    srli    t0, t4, 31              # multiplicand <<= 1 (64 bits)
    slli    t5, t5, 1
    or      t5, t5, t0
    slli    t4, t4, 1
    srli    t6, t6, 1
    bnez    t6, .Lmul

.Lsigned:
    # A negative operand x stands for x - 2^32: subtract the other operand
    # from the high word.
    bgez    a0, 1f
    sub     t3, t3, a1
1:
    bgez    a1, 2f
    sub     t3, t3, a0
2:
    # Add half a unit (2^19), then keep bits 20..51 of the 64-bit sum.
    lui     t0, 0x80                # 1 << (Q - 1)
    add     t0, t2, t0
    sltu    t1, t0, t2              # carry into the high word
    add     t3, t3, t1
    srli    t0, t0, Q
    slli    t3, t3, 32 - Q
    or      a0, t0, t3
    ret
    .size   q_mul_asm, .-q_mul_asm
