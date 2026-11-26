# An enum subrange satisfies the `enum` type class, at the cost of a
# subrange match; `is` answers the same.
import std/syncio
import deps/msubrangeconstraint

type
  H = enum
    h0, h1, h2
  RH = range[h0..h1]
  Holey = enum
    ha = 1, hb = 5, hc = 9

proc g[T: enum](x: T): int = ord(x)

var x: RH = h1
echo g(x), " ", $x
echo x
for v in RH(h0)..RH(h1): echo v
var ho: range[ha..hb] = hb
echo g(ho), " ", ho
echo RH is enum

proc k[T](x: T): string =
  when T is enum: "enum" else: "other"
echo k(x)

# the subrange reaches `enum` only through a conversion match, so the
# imported `[T]` still wins over the local candidate
proc p[T: enum](x: T): string = "local enum"
echo p(x)

# a constraint the subrange satisfies as it is still costs nothing
proc q[T: enum](x: T): string = "enum"
proc q[T: range](x: T): string = "range"
echo q(x)
