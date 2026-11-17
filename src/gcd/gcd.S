# gcd_u32_asm: binary GCD, hand-written RV32I.
#
# uint32_t gcd_u32_asm(uint32_t a, uint32_t b)   a in a0, b in a1, result in a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tgcd.c.
#
# Same identities as gcd.c. After the shared factors of two are counted in t1,
# a is made odd once and stays odd, so the main loop only strips twos from b,
# keeps the smaller value in a and subtracts it from the larger one. The
# difference of two odd values is even, so its first shift needs no test.
# Every loop tests at the bottom to save one jump per iteration.

    .text

    .globl  gcd_u32_asm
    .type   gcd_u32_asm, @function
    .align  2
gcd_u32_asm:
    beqz    a0, .Lret_b             # gcd(0, b) = b
    beqz    a1, .Lret_a             # gcd(a, 0) = a

    # k = number of shared factors of two = trailing zeros of (a | b)
    or      t0, a0, a1
    li      t1, 0
    andi    t2, t0, 1
    bnez    t2, .Lk_done
.Lk_loop:
    srli    t0, t0, 1
    addi    t1, t1, 1
    andi    t2, t0, 1
    beqz    t2, .Lk_loop
.Lk_done:
    srl     a0, a0, t1
    srl     a1, a1, t1

    # make a odd; it stays odd from here on
    andi    t2, a0, 1
    bnez    t2, .Lb_entry
.La_loop:
    srli    a0, a0, 1
    andi    t2, a0, 1
    beqz    t2, .La_loop

.Lb_entry:
    # a is odd; b may still be even
    andi    t2, a1, 1
    bnez    t2, .Lloop
.Lstrip:
    srli    a1, a1, 1
    andi    t2, a1, 1
    beqz    t2, .Lstrip
.Lloop:
    # both odd: a = min(a, b), d = |b - a|
    sub     t2, a1, a0
    bgeu    a1, a0, .Ldiff
    mv      a0, a1
    neg     t2, t2
.Ldiff:
    beqz    t2, .Ldone
    # odd minus odd is even and nonzero, so one shift needs no test
    srli    a1, t2, 1
    andi    t2, a1, 1
    bnez    t2, .Lloop
    j       .Lstrip

.Ldone:
    sll     a0, a0, t1              # put the shared factors of two back
.Lret_a:
    ret
.Lret_b:
    mv      a0, a1
    ret
    .size   gcd_u32_asm, .-gcd_u32_asm
