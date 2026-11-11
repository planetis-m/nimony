import std/syncio
import mconstvec as vm

# A `const` of a type with a `ptr UncheckedArray` field is serialized
# through the `len` and `[]` of the module that declares the type, even
# when the evaluated code calls a `len` of the user's for the same type.

proc len(x: Vec[int]): int = 1

proc mk(): Vec[int] =
  result = mkv()
  discard len(result)

const
  a = mkv()
  b = mk()
  rows = [mkv(), mkv()]
  sq = @[mkv()]

echo vm.len(a), " ", a[0], a[1], a[2]
echo vm.len(b), " ", b[0], b[1], b[2]
echo vm.len(rows[1]), " ", rows[1][2], " ", sq[0][1]
