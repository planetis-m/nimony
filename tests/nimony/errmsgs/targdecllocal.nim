## A declaration inside a call argument is local to that argument, for every
## kind of call: a later use is undeclared (it used to be a "could not find
## symbol" internal error where the callee dropped the argument).

import std / syncio

proc f(x: int): int = x
template t(v: untyped): untyped = v
type E = enum A, B
var arr = [10, 20, 30]

discard compiles((let a1 = 1; a1))
discard a1
discard (let a2 = 1; a2) is int
discard a2
discard astToStr((let a3 = 1; a3))
discard a3
type T = typeof((let a4 = 1; a4))
discard a4
discard arr[(let a5 = 1; a5)]
discard a5
discard $(let a6 = B; a6)
discard a6
discard f((let a8 = 1; a8))
discard a8
discard f(f((let a9 = 1; a9)))
discard a9
discard static(f((let a11 = 1; a11)))
discard a11
