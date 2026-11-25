# In a checked generic body a value of type `T: C`, where `C` is an object
# type or a `ref`/`ptr` to one, is used as a `C`: passed to a `C` parameter,
# dereferenced and its fields accessed. A generic overload still wins.

import std/syncio

type
  Base = ref object of RootObj
    x: int
  Sub = ref object of Base
  OBase = object of RootObj
    x: int
  OSub = object of OBase
    y: int

method build(b: Base) {.base.} = echo "base"
method build(s: Sub) = echo "sub"
proc plain(b: Base) = echo "plain ", b.x

proc built[T: Base](v: T): T =
  v.plain()
  v.build()
  v.x = v.x + 1
  result = v

discard built(Base(x: 1))
echo built(Sub(x: 2)).x

proc oplain(o: OBase) = echo "oplain ", o.x
proc obuilt[T: OBase](v: T): int =
  oplain(v)
  result = v.x

echo obuilt(OSub(x: 3, y: 4))

proc ptrx[T: ptr OBase](v: T): int = v[].x
proc ptry[T: ptr OBase](v: T): int =
  v.x = v.x * 10
  result = v.x

var o = OSub(x: 5)
echo ptrx(addr o)
echo ptry(addr o)

# a generic candidate ranks above the constraint's own type
proc show[U](u: U) = echo "generic"
proc show(b: Base) = echo "Base"
proc callShow[T: Base](v: T) = show(v)
callShow(Sub())
