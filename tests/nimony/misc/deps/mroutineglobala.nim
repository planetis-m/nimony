when defined(nimony):
  {.feature: "assumeSync".}

proc fromA*(): int =
  var counter {.global.}: int
  inc counter
  counter

template counted*(start: int): int =
  var cached {.global.} = start
  inc cached
  cached

proc a1*(): int = counted(0)

# The instance `shared[int]` is one routine, whichever module instantiates it:
# its global is one location and its initializer runs once.
var sharedInits* = 0
proc sharedStart(): int =
  inc sharedInits
  result = 100

proc shared*[T](x: T): int =
  var n {.global.} = sharedStart()
  inc n
  result = n

iterator sharedItems*[T](x: T): int {.sideEffect.} =
  var total {.global.}: int
  inc total
  yield total

# Types with hooks, with no zero default, and without an initializer.
type Box = ref object
  n: int

proc sharedKinds*[T](x: T): string =
  var s {.global.} = "a"
  var b {.global.} = Box(n: 100)
  var r {.global.}: range[1..9] = 7
  var q {.global.}: seq[int]
  s.add "b"
  inc b.n
  q.add 0
  result = s & " " & $b.n & " " & $int(r) & " " & $q.len
