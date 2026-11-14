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

# An exit taken before the `try` does not lead into its `finally`.

proc returnBeforeDefer(c: bool): int =
  var y: int
  if c: return 0
  defer: echo "defer ", y
  y = 1
  result = y

proc returnBeforeTry(c: bool): int =
  var y: int
  if c: return 0
  try:
    y = 4
    return y
  finally:
    echo "finally ", y

proc breakBeforeTry(): int =
  var y: int
  for i in 0 .. 2:
    if i == 5: break
    try:
      y = i + 7
      break
    finally:
      echo "finally ", y
  result = 0

proc bareReturnBeforeDefer(c: bool): int =
  result = 0
  var y: int
  if c: return
  defer: echo "defer ", y
  y = 2
  result = y

echo deferReadsResult()
echo earlyReturn(true)
echo earlyReturn(false)
echo viaReturn()
echo viaBreak()
echo returnBeforeDefer(false)
echo returnBeforeTry(false)
echo breakBeforeTry()
echo bareReturnBeforeDefer(false)
