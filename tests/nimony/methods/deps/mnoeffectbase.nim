type Shape* = ref object of RootObj
method area*(s: Shape): int {.base, noSideEffect.} = 0

type Box*[T] = ref object of RootObj
  x*: T
method size*[T](b: Box[T]): int {.base, noSideEffect.} = 0
