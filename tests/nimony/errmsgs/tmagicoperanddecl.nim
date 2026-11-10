## A declaration in the operand of a magic that is checked again after
## overload resolution is declared once, by that check, and stays local to
## the operand: the operand is not emitted, so a later use is undeclared
## (it used to be a "could not find symbol" internal error).

import std / syncio

echo compiles((let a = 1; a))
echo a
echo((let b = 1; b) is int)
echo b
echo astToStr((let c = 1; c))
echo c
