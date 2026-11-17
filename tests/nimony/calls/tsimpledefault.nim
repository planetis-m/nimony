
import std / [syncio]

proc myecho(x: int = 4) =
  echo x

myecho()

# a default that calls a proc literal: the call site checks the typed
# `(expr (stmts (proc ...)) anonproc)` callee again
proc addLit(a: int; w = (proc (): int = 3)()): int = a + w
echo addLit(1)

# A default may read a toplevel let/var declared before the routine; it is
# evaluated at each call.
let greeting = "hello"
var count = 1

proc greet(name: string; word = greeting): string = word & ", " & name
proc counted(n: int = count): int = n

echo greet("you")
echo counted()
count = 2
echo counted()

# A field name in a default is not a lookup of the let/var of that name.
type O = object
  greeting: int

proc fieldDefault(w = O(greeting: 3)): int = w.greeting
when fieldDefault() == 3:
  echo "field ok"
