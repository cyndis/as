Assembler in Ruby
=================

Supported assembly languages:

- ARM, quite incompletely
- TTK91/Titokone, with non-standard (better!) syntax

Outputs ELF object files, with relocation support.

ARM
---

Constant table support exists but isn't very good. Some addressing modes
are not supported or only partially supported.

Supported (pseudo)instructions:

- adc, add, and, bic, eor, orr, rsb, rsc, sbc, sub, cmn, cmp, teq, tst,
  mov, mvn, strb, str, ldrb, ldr, push, pop, b, bl, bx, swi
- Conditional versions of above

TTK91/Titokone
--------------

Everything should be supported. This has not really been tested, though,
as the official TTK91 emulator doesn't read ELF binaries.
