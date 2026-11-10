## The operand of `static` is checked once: a declaration in it is not
## reported as a redeclaration. (A statement-list expression is not folded
## at compile time yet, so the program is still refused.)

import std / syncio

echo static((let a = 1; a + 1))
