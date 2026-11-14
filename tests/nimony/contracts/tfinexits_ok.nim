# A `finally` (and so a `defer`) runs on every way out of its `try`, a
# `return` or a `break` included: what is initialized on each of those ways is
# initialized in it.

import std/syncio

proc deferReadsResult(): int =
  defer: echo "defer ", result
  result = 3

proc earlyReturn(c: bool): int =
  defer: echo "defer ", result
  if c: return 5
  result = 6

proc viaReturn(): int =
  var y: int
  try:
    y = 4
    return y
  finally:
    echo "finally ", y

proc viaBreak(): int =
  var y: int
  for i in 0 .. 2:
    try:
      y = i + 7
      break
    finally:
      echo "finally ", y
  result = 0

echo deferReadsResult()
echo earlyReturn(true)
echo earlyReturn(false)
echo viaReturn()
echo viaBreak()
