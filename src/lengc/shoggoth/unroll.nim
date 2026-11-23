#
#           NIFC Scalar Loop Unrolling (nifcore)
#        (c) Copyright 2026 Andreas Rumpf
#
#    See the file "license.txt", included in this
#    distribution, for details about the copyright.

## Scalar loop unrolling over `countedloops` (see `UNROLL_DESIGN.md`).

import std / [tables, sets, assertions, strutils]
import ".." / ".." / "lib" / [nifcoreparse, nifcdecl, lengaa]
import ".." / ".." / "models" / tags
import ".." / nifmodules
import patchsets, countedloops, cse, intrinsiceffects

const
  MaxFullTrip = 8
  MaxUnrollTokens = 200      ## matches `inliner.InlineHintBound`
  LoopCtrlTokens = 13        ## step + back-edge control overhead

type
  UnrollStats* = object
    full*, by2*, by4*: int
  Unroller = object
    orig: ptr TokenBuf
    ps: Patchset
    synth: seq[TokenBuf]
    resolver: SummaryResolver
    m: ptr MainModule
    procAddrTaken: HashSet[SymId]
    optSize: bool
    volRegs, counter, growthLeft: int
    stats: ptr UnrollStats
  BodyScan = object
    defs, written, used: HashSet[SymId]
    hasPtrStore, ok: bool
  LoopInfo = object
    bodyTokens, liveOuter, bits: int
    ok, hasStart, hasStop, isUnsigned: bool
    startVal, stopVal, constTrip, tMin, tMax: int64
  Plan = object
    ok, full, useLimVar, exactDiv: bool
    factor: int

template tid(x: untyped): TagId = TagId(ord(x))
template tree(b: var TokenBuf; tag: TagId; body: untyped) =
  b.openTag tag; body; b.closeTag()

proc freshName(u: var Unroller; role = ""): string =
  inc u.counter
  if role.len > 0: "`unr." & role & "." & $u.counter else: "`unr." & $u.counter

proc spanTokens(orig: ptr TokenBuf; n: Cursor): int =
  let a = cursorToPosition(orig[], n); var e = n; skip e
  cursorToPosition(orig[], e) - a

proc constIntExpr(n: Cursor; v: var int64): bool =
  ## Literal, wrapper, or signed literal `add`/`sub` (`indvars` `(sub (i W) 0 N)`).
  result = false
  if cursorIsNil(n): return
  case n.kind
  of IntLit: v = intVal(n); result = true
  of UIntLit:
    if uintVal(n) <= uint64(high(int64)): v = int64(uintVal(n)); result = true
  of TagLit:
    let ek = n.exprKind; var c = n.childCursor
    if ek in {SufC, ParC}: result = constIntExpr(c, v)
    elif ek == ConvC: skip c; result = constIntExpr(c, v)
    elif ek in {AddC, SubC} and c.kind == TagLit and c.typeKind == IT:
      skip c; var a, b: int64 = 0
      if c.hasMore and constIntExpr(c, a):
        skip c
        if c.hasMore and constIntExpr(c, b):
          skip c
          if not c.hasMore and abs(a) < (1'i64 shl 60) and abs(b) < (1'i64 shl 60):
            v = if ek == AddC: a + b else: a - b
            result = true
  else: discard

proc typeBounds(typ: Cursor; a: var LoopInfo): bool =
  result = false
  if typ.kind == TagLit and typ.typeKind in {IT, UT} and typ.childCursor.kind == IntLit:
    a.bits = int(intVal(typ.childCursor)); a.isUnsigned = typ.typeKind == UT
    if a.bits in [32, 64, -1]:
      a.tMax = if a.bits == 64: high(int64) elif a.isUnsigned: 4294967295'i64 else: 2147483647'i64
      a.tMin = if a.isUnsigned: 0 else: -a.tMax - 1
      result = true

proc collectAddrTaken(n: Cursor; acc: var HashSet[SymId]) =
  if n.kind != TagLit: return
  if n.exprKind in AddrKinds:
    let r = lvalueRoot(n.childCursor)
    if r != SymId(0): acc.incl r
  var it = n; it.loopInto: (collectAddrTaken(it, acc); skip it)

proc scanBody(u: var Unroller; n: Cursor; sc: var BodyScan) =
  if not sc.ok: return
  case n.kind
  of Symbol: sc.used.incl n.symId
  of SymbolDef: sc.defs.incl n.symId
  of TagLit:
    let sk = n.stmtKind; let ek = n.exprKind
    if sk in {LoopS, WhileS, BreakS, TryS, OnerrS, EmitS, ProcS, TypeS,
              GvarS, TvarS, MflagS, VflagS, JtrueS}: sc.ok = false; return
    if sk in {LabS, JmpS}: return
    if sk == CallS or ek == CallC:
      let c = n.childCursor; var fs = FunctionSummary()
      if not (c.kind == Symbol and resolveCallee(u.resolver, c.symId, fs) and fs.noReturn):
        sc.ok = false; return
    if (sk == InstrS or ek == InstrC) and not (u.m != nil and instrIsPure(u.m[], n)):
      sc.ok = false; return
    if sk in {VarS, ConstS}:
      var d = n.childCursor; skip d
      if d.hasMore and d.kind == TagLit:
        var p = d; p.loopInto:
          if p.kind == TagLit and p.pragmaKind in {StaticP, ExportcP, ImportcP}: sc.ok = false
          skip p
    elif sk == AsgnS:
      let r = lvalueRoot(n.childCursor)
      if r != SymId(0): sc.written.incl r else: sc.hasPtrStore = true
    let f = fieldSlot(n); var i = 0; var it = n
    it.loopInto:
      if sc.ok and i != f: scanBody(u, it, sc)
      inc i; skip it
  else: discard

proc isHoistedVar(s: Cursor): bool =
  if s.kind == TagLit and s.stmtKind == VarS and s.childCursor.kind == SymbolDef:
    let nm = symName(s.childCursor)
    result = nm.startsWith("`iv.") or nm.startsWith("`cse.")
  else: result = false

proc isVecRem(sibs: seq[Cursor]; idx: int): bool =
  var j = idx - 1
  while j >= 0 and sibs[j].kind == TagLit:
    let s = sibs[j]; let c = s.childCursor
    if s.stmtKind == IfS and c.substructureKind == ElifU:
      return c.childCursor.kind == Symbol and symName(c.childCursor).startsWith("vec.ok.")
    if isHoistedVar(s): dec j else: return false
  false

proc findStartExpr(sibs: seq[Cursor]; idx: int; ivSym: SymId; itePrev: Cursor): Cursor =
  result = default(Cursor); var j = idx - 1
  while j >= 0:
    result = startValue(sibs[j], ivSym)
    if not cursorIsNil(result): return
    if isHoistedVar(sibs[j]): dec j else: return
  if j < 0: result = startValue(itePrev, ivSym)

proc computeConstTrip(kind: LoopKind; a: var LoopInfo) =
  a.constTrip = -1
  if not (a.hasStart and a.hasStop) or (a.isUnsigned and (a.startVal < 0 or a.stopVal < 0)): return
  let sv = a.startVal; let ev = a.stopVal
  let up = cast[uint64](ev) - cast[uint64](sv); let dn = cast[uint64](sv) - cast[uint64](ev)
  case kind
  of CountUpExclusive:
    if sv >= ev: a.constTrip = 0 elif up <= uint64(high(int64)): a.constTrip = int64(up)
  of CountUp:
    if sv > ev: a.constTrip = 0
    elif ev < a.tMax and up < uint64(high(int64)): a.constTrip = int64(up + 1'u64)
  of CountDown:
    if ev > sv: a.constTrip = 0
    elif ev > a.tMin and dn < uint64(high(int64)): a.constTrip = int64(dn + 1'u64)
  of CountUpUntil:
    if sv == ev: a.constTrip = 0 elif sv < ev and up <= uint64(high(int64)): a.constTrip = int64(up)
  of NoLoop: discard

proc analyzeLoop(u: var Unroller; d: DetectedLoop; startCur, iteGuard: Cursor;
                 hasGuard, allHoisted: bool; stmts: seq[Cursor]): LoopInfo =
  result = LoopInfo(constTrip: -1)
  if stmts.len == 0 or not d.isUnitStep or not u.orig[].pool.symIsLocal(d.counterSym) or
     d.counterSym in u.procAddrTaken or not typeBounds(d.typ, result): return
  result.hasStart = constIntExpr(startCur, result.startVal)
  result.hasStop = constIntExpr(d.stop, result.stopVal)
  computeConstTrip(d.kind, result)
  if not hasGuard and result.constTrip == 0: return
  let hoistedGuard = allHoisted and not cursorIsNil(iteGuard) and
    ((d.kind == CountUpExclusive and result.hasStop and result.stopVal == 0 and
      symName(d.counter).startsWith("`iv.j.")) or
     sameTest(iteGuard, d.cond, d.counterSym, startCur))
  if not (hasGuard or result.constTrip >= 1 or hoistedGuard): return
  var sc = BodyScan(ok: true)
  for s in stmts: result.bodyTokens += spanTokens(u.orig, s); scanBody(u, s, sc)
  let stopOk = result.hasStop or
    (d.stop.kind == Symbol and d.stop.symId notin sc.defs and d.stop.symId notin sc.written and
     (not sc.hasPtrStore or (u.orig[].pool.symIsLocal(d.stop.symId) and
                             d.stop.symId notin u.procAddrTaken)))
  if not sc.ok or not stopOk: return
  sc.used.incl d.counterSym
  if d.stop.kind == Symbol: sc.used.incl d.stop.symId
  for s in sc.used:
    if s notin sc.defs and u.orig[].pool.symIsLocal(s): inc result.liveOuter
  result.ok = true

proc choosePlan(u: Unroller; d: DetectedLoop; a: LoopInfo): Plan =
  result = Plan()
  if a.constTrip >= 0 and a.constTrip <= MaxFullTrip:
    let exp = int(a.constTrip) * a.bodyTokens
    let cap = if u.optSize: a.bodyTokens + LoopCtrlTokens else: MaxUnrollTokens
    if a.constTrip <= 1 or (exp <= cap and exp - a.bodyTokens <= u.growthLeft):
      return Plan(ok: true, full: true)
  if u.optSize or d.kind == CountUpUntil: return
  for k in [4, 2]:
    if not result.ok and (a.constTrip < 0 or a.constTrip >= int64(k)):
      let ex = a.constTrip >= int64(k) and a.constTrip mod int64(k) == 0
      let copies = if ex: k else: k + 1
      if copies * a.bodyTokens <= MaxUnrollTokens and (copies - 1) * a.bodyTokens <= u.growthLeft:
        let km1 = int64(k - 1); var ok = ex; var lv = false
        if not ok and a.hasStop:
          ok = case d.kind
            of CountUpExclusive: a.stopVal >= a.tMin + km1
            of CountUp: a.stopVal >= a.tMin + km1 and a.stopVal < a.tMax
            of CountDown: a.stopVal <= a.tMax - km1 and a.stopVal > a.tMin
            else: false
        elif not ok and a.liveOuter + 1 <= u.volRegs: ok = true; lv = true
        elif not ok and d.kind == CountUpExclusive and k == 4: ok = true
        if ok: result = Plan(ok: true, factor: k, useLimVar: lv, exactDiv: ex)

proc collectDefs(n: Cursor; u: var Unroller; ren: var Table[SymId, string]) =
  if n.kind == SymbolDef:
    if not ren.hasKey(n.symId): ren[n.symId] = u.freshName()
  elif n.kind == TagLit:
    var it = n; it.loopInto: (collectDefs(it, u, ren); skip it)

proc emitIntVal(b: var TokenBuf; isUnsigned: bool; v: int64) =
  if isUnsigned: b.addUIntLit cast[uint64](v) else: b.addIntLit v

proc emitCopy(b: var TokenBuf; n: Cursor; ren: Table[SymId, string];
              d: DetectedLoop; a: LoopInfo; substIv: bool; ivVal: int64) =
  case n.kind
  of TagLit:
    let li = rawLineInfo(n); b.openTag n.cursorTagId
    if li.isValid: b.appendLineInfo li
    let f = fieldSlot(n); var i = 0; var it = n
    it.loopInto:
      if i == f: b.addSubtree it else: emitCopy(b, it, ren, d, a, substIv, ivVal)
      inc i; skip it
    b.closeTag()
  of Symbol:
    if substIv and n.symId == d.counterSym: emitIntVal(b, a.isUnsigned, ivVal)
    elif ren.hasKey(n.symId): b.addSymUse ren.getOrDefault(n.symId)
    else: b.addSubtree n
  of SymbolDef:
    if ren.hasKey(n.symId): b.addSymDef ren.getOrDefault(n.symId) else: b.addSubtree n
  else: b.addSubtree n

proc emitScoped(u: var Unroller; b: var TokenBuf; stmts: seq[Cursor];
                d: DetectedLoop; a: LoopInfo; freshen, substIv: bool; ivVal: int64) =
  var ren = initTable[SymId, string]()
  if freshen:
    for s in stmts: collectDefs(s, u, ren)
  b.tree tid(ScopeTagId):
    b.tree tid(StmtsTagId):
      for s in stmts: emitCopy(b, s, ren, d, a, substIv, ivVal)

proc emitDistCond(b: var TokenBuf; d: DetectedLoop; a: LoopInfo; thresh: int64) =
  b.tree tid(LeTagId):
    b.addUIntLit uint64(thresh)
    b.tree tid(SubTagId):
      b.tree tid(UTagId): b.addIntLit int64(a.bits)
      for op in (if d.kind == CountDown: [d.counter, d.stop] else: [d.stop, d.counter]):
        if a.isUnsigned: b.addSubtree op
        else:
          b.tree tid(CastTagId):
            b.tree tid(UTagId): b.addIntLit int64(a.bits)
            b.addSubtree op

proc emitLimCmp(b: var TokenBuf; d: DetectedLoop; a: LoopInfo; limSym: string; limLit: int64) =
  b.tree(if d.kind == CountUpExclusive: tid(LtTagId) else: tid(LeTagId)):
    if d.kind != CountDown: b.addSymUse d.counterSym
    if limSym.len > 0: b.addSymUse limSym else: emitIntVal(b, a.isUnsigned, limLit)
    if d.kind == CountDown: b.addSymUse d.counterSym

proc emitFull(u: var Unroller; d: DetectedLoop; a: LoopInfo; stmts: seq[Cursor]): TokenBuf =
  result = createTokenBuf(64, u.orig[].pool, u.orig[].tags)
  let dir = if d.kind == CountDown: -1'i64 else: 1'i64
  result.tree tid(StmtsTagId):
    for k in 0 ..< int(a.constTrip):
      let v = a.startVal + int64(k) * dir
      emitScoped(u, result, stmts, d, a, k > 0, true, v)
      result.tree tid(AsgnTagId):
        result.addSymUse d.counterSym; emitIntVal(result, a.isUnsigned, v + dir)

proc emitMainLoop(u: var Unroller; b: var TokenBuf; d: DetectedLoop; a: LoopInfo;
                  stmts: seq[Cursor]; p: Plan; limName: string; litLim, thresh: int64) =
  b.tree tid(LoopTagId):
    b.tree tid(StmtsTagId):
      for k in 0 ..< p.factor:
        emitScoped(u, b, stmts, d, a, not p.exactDiv or k > 0, false, 0); b.addSubtree d.update
      b.tree tid(ContinueTagId):
        if p.exactDiv: b.addSubtree d.cond
        elif a.hasStop: emitLimCmp(b, d, a, "", litLim)
        elif p.useLimVar: emitLimCmp(b, d, a, limName, 0)
        else: emitDistCond(b, d, a, thresh)

proc emitPartial(u: var Unroller; d: DetectedLoop; a: LoopInfo; stmts: seq[Cursor];
                 hasGuard: bool; p: Plan): TokenBuf =
  result = createTokenBuf(128, u.orig[].pool, u.orig[].tags)
  let km1 = int64(p.factor - 1)
  let litLim = if d.kind == CountDown: a.stopVal + km1 else: a.stopVal - km1
  let thresh = if d.kind in {CountUp, CountDown}: km1 else: int64(p.factor)
  if hasGuard: result.openTag tid(IteTagId); result.addSubtree d.guard.childCursor
  result.tree tid(StmtsTagId):
    if p.exactDiv: emitMainLoop(u, result, d, a, stmts, p, "", litLim, thresh)
    else:
      result.tree tid(IteTagId):
        if a.hasStop: emitLimCmp(result, d, a, "", litLim) else: emitDistCond(result, d, a, thresh)
        result.tree tid(StmtsTagId):
          result.tree tid(ScopeTagId):
            var limName = ""
            if p.useLimVar:
              limName = u.freshName("lim")
              result.tree tid(VarTagId):
                result.addSymDef limName; result.addDotToken(); result.addSubtree d.typ
                result.tree(if d.kind == CountDown: tid(AddTagId) else: tid(SubTagId)):
                  result.addSubtree d.typ; result.addSubtree d.stop; emitIntVal(result, a.isUnsigned, km1)
            emitMainLoop(u, result, d, a, stmts, p, limName, litLim, thresh)
        result.addDotToken()
      result.tree tid(IteTagId):
        result.addSubtree d.cond
        result.tree tid(StmtsTagId): result.addSubtree d.loop
        result.addDotToken()
  if hasGuard: result.addDotToken(); result.closeTag()

proc walkList(u: var Unroller; listNode, iteGuard, itePrev: Cursor) =
  var sibs: seq[Cursor] = @[]; var it = listNode
  it.loopInto: (sibs.add it; skip it)
  var allHoisted = true
  for i in 0 ..< sibs.len:
    let s = sibs[i]
    if s.kind == TagLit:
      var d = DetectedLoop(kind: NoLoop); var startCur = default(Cursor)
      var hasGuard = false; var target = s
      if s.stmtKind == IteS:
        d = detectGuardedLoop(s, if i > 0: sibs[i - 1] else: default(Cursor))
        if d.kind != NoLoop:
          hasGuard = true
          startCur = if cursorIsNil(d.start): findStartExpr(sibs, i, d.counterSym, default(Cursor)) else: d.start
      elif s.stmtKind in {StmtsS, ScopeS, LoopS}:
        var inner = s
        while inner.kind == TagLit and inner.stmtKind in {StmtsS, ScopeS}:
          var c = inner.childCursor
          if not c.hasMore: inner = default(Cursor); break
          inner = c; skip c
          if c.hasMore: inner = default(Cursor); break
        if not cursorIsNil(inner) and inner.stmtKind == LoopS:
          d = detectLoop(inner)
          if d.kind != NoLoop:
            target = inner; startCur = findStartExpr(sibs, i, d.counterSym, if allHoisted: itePrev else: default(Cursor))
      var applied = d.kind != NoLoop and isVecRem(sibs, i)
      if d.kind != NoLoop and not applied:
        let stmts = bodyStmts(d)
        let info = analyzeLoop(u, d, startCur, iteGuard, hasGuard, allHoisted, stmts)
        let p = if info.ok: choosePlan(u, d, info) else: Plan()
        if p.ok:
          var nb = if p.full: emitFull(u, d, info, stmts) else: emitPartial(u, d, info, stmts, hasGuard, p)
          u.growthLeft -= (if p.full: max(0, (int(info.constTrip) - 1) * info.bodyTokens)
                           else: (if p.exactDiv: p.factor - 1 else: p.factor) * info.bodyTokens)
          if u.stats != nil:
            if p.full: inc u.stats[].full elif p.factor == 4: inc u.stats[].by4 else: inc u.stats[].by2
          u.synth.add ensureMove(nb)
          u.ps.addSubst(cursorToPosition(u.orig[], target), cursorAt(u.synth[^1], 0))
          applied = true
      if not applied:
        if s.stmtKind == IteS:
          var cond, thenArm, elseArm = default(Cursor)
          if twoWayParts(s, cond, thenArm, elseArm):
            let prev = if i > 0: sibs[i - 1] else: default(Cursor)
            if thenArm.kind == TagLit:
              walkList(u, thenArm, if not hasArm(elseArm): cond else: default(Cursor), prev)
            if hasArm(elseArm) and elseArm.kind == TagLit: walkList(u, elseArm, default(Cursor), default(Cursor))
        elif s.stmtKind notin {ProcS, TypeS}:
          let pass = allHoisted and s.stmtKind in {StmtsS, ScopeS}
          walkList(u, s, if pass: iteGuard else: default(Cursor), if pass: itePrev else: default(Cursor))
    if not isHoistedVar(s): allHoisted = false

proc runUnroll*(buf: var TokenBuf; summaries: ptr FunctionSummaryTable;
                m: ptr MainModule; optSize: bool; volatileLocalRegs: int;
                minted: var int; stats: ptr UnrollStats = nil): bool {.discardable.} =
  ## Unroll eligible counted loops in one proc body. Returns whether `buf` changed.
  result = false
  let root = beginRead(buf)
  if root.kind != TagLit: return
  var u = Unroller(
    orig: addr buf, ps: initPatchset(addr buf), synth: @[],
    resolver: initSummaryResolver(summaries, m), m: m,
    procAddrTaken: initHashSet[SymId](), optSize: optSize,
    volRegs: (if volatileLocalRegs > 0: volatileLocalRegs else: 4),
    counter: minted, growthLeft: max(400, spanTokens(addr buf, root) div 2), stats: stats)
  collectAddrTaken(root, u.procAddrTaken)
  walkList(u, root, default(Cursor), default(Cursor))
  minted = u.counter
  if not u.ps.isEmpty:
    var newBuf = u.ps.apply(); buf = ensureMove(newBuf); result = true

when isMainModule:
  proc parse(src: string; pool: Pool = nil): TokenBuf =
    if pool == nil: parseFromBuffer(src, "M", 100, sharedTags = createLengTagPool())
    else: parseFromBuffer(src, "M", 100, sharedPool = pool, sharedTags = createLengTagPool())

  proc flat(s: string): string =
    result = ""
    var prevSpace = false
    for ch in s:
      if ch in {' ', '\n', '\r', '\t'}:
        if not prevSpace and result.len > 0 and result[^1] != '(':
          result.add ' '
          prevSpace = true
      else:
        if prevSpace and ch == ')': result.setLen result.len - 1
        result.add ch
        prevSpace = false

  proc unrolled(src: string; optSize = false; volRegs = 4;
                summaries: ptr FunctionSummaryTable = nil;
                pool: Pool = nil; st: ptr UnrollStats = nil): (string, bool) =
    var b = parse(src, pool)
    var minted = 0
    let changed = runUnroll(b, summaries, nil, optSize, volRegs, minted, st)
    (flat(toString(b, includeLineInfo = false)), changed)

  block full_unroll_small_const:
    var st = UnrollStats()
    let (got, ch) = unrolled(
      "(stmts (var :i.0 . (i 64) 0) " &
      "(stmts (loop (stmts (asgn sum.0 (add (i 64) sum.0 (at a.0 i.0))) " &
      "(asgn i.0 (add (i 64) i.0 1)) (continue (lt i.0 4))))))", st = addr st)
    doAssert ch and st.full == 1, got
    doAssert "(loop" notin got, got
    doAssert "(at a.0 0)" in got and "(at a.0 3)" in got, got
    doAssert "(asgn i.0 4)" in got, got

  block full_unroll_zero_one_and_until:
    let (g0, ch0) = unrolled(
      "(stmts (var :i.0 . (i 64) 0) (ite (lt 0 0) (stmts (loop (stmts " &
      "(asgn x.0 (add (i 64) x.0 i.0)) (asgn i.0 (add (i 64) i.0 1)) " &
      "(continue (lt i.0 0))))) .))")
    doAssert ch0 and "(loop" notin g0 and "(asgn x.0" notin g0, g0
    let (g1, ch1) = unrolled(
      "(stmts (var :i.0 . (i 64) 0) (ite (lt 0 1) (stmts (loop (stmts " &
      "(asgn x.0 (add (i 64) x.0 i.0)) (asgn i.0 (add (i 64) i.0 1)) " &
      "(continue (lt i.0 1))))) .))", optSize = true)
    doAssert ch1 and "(loop" notin g1 and "(add (i 64)x.0 0)" in g1, g1
    let (gu, chu) = unrolled(
      "(stmts (var :i.0 . (i 64) 0) (ite (not (eq 0 3)) (stmts (loop (stmts " &
      "(asgn x.0 (add (i 64) x.0 i.0)) (asgn i.0 (add (i 64) i.0 1)) " &
      "(continue (not (eq i.0 3)))))) .))")
    doAssert chu and "(loop" notin gu and "(asgn i.0 3)" in gu, gu
    let (_, chDynU) = unrolled(
      "(stmts (var :i.0 . (i 64) 0) (ite (not (eq 0 n.0)) (stmts (loop (stmts " &
      "(asgn x.0 (add (i 64) x.0 i.0)) (asgn i.0 (add (i 64) i.0 1)) " &
      "(continue (not (eq i.0 n.0)))))) .))", volRegs = 12)
    doAssert not chDynU, "dynamic CountUpUntil must not be partially unrolled"

  block full_unroll_early_exit_keeps_iv:
    let (got, ch) = unrolled(
      "(stmts (var :i.0 . (i 64) 0) (stmts (loop (stmts " &
      "(ite (eq (at a.0 i.0) k.0) (stmts (jmp exit.0)) .) " &
      "(asgn i.0 (add (i 64) i.0 1)) (continue (lt i.0 3))))) (lab :exit.0))")
    doAssert ch and "(loop" notin got, got
    doAssert "(asgn i.0 1)" in got and "(asgn i.0 2)" in got and "(asgn i.0 3)" in got, got

  block exact_div_c2z_no_remainder:
    var st = UnrollStats()
    let (got, ch) = unrolled(
      "(stmts (var :`iv.j.1 . (i 64) (sub (i 64) 0 32)) " &
      "(loop (stmts (asgn (pat q.0 `iv.j.1) (bitor (u 8) (pat p.0 `iv.j.1) (pat r.0 `iv.j.1))) " &
      "(asgn `iv.j.1 (add (i 64) `iv.j.1 1)) (continue (lt `iv.j.1 0)))))", st = addr st)
    doAssert ch and st.by4 == 1, got
    doAssert got.count("(loop") == 1, "exact-divisible loop must emit no remainder: " & got
    doAssert got.count("(bitor") == 4, got

  block dynamic_c2z_literal_limit_no_var:
    var st = UnrollStats()
    let (got, ch) = unrolled(
      "(stmts (ite (lt 0 n.0) (stmts " &
      "(var :`iv.j.1 . (i 64) (sub (i 64) 0 n.0)) " &
      "(loop (stmts (asgn s.0 (add (i 64) s.0 (pat q.0 `iv.j.1))) " &
      "(asgn `iv.j.1 (add (i 64) `iv.j.1 1)) (continue (lt `iv.j.1 0))))) .))", st = addr st)
    doAssert ch and st.by4 == 1, got
    doAssert got.count("(loop") == 2, got
    doAssert "(lt `iv.j.1 -3)" in got and "`unr.lim." notin got, got

  block licm_cse_hoisted_inside_ite:
    var st = UnrollStats()
    let (got, ch) = unrolled(
      "(stmts (var :i.0 . (i 64) 0) (ite (lt 0 n.0) (stmts " &
      "(var :`cse.1 . (i 64) (dot r.0 t.0 0)) " &
      "(loop (stmts (asgn s.0 (add (i 64) s.0 (add (i 64) `cse.1 i.0))) " &
      "(asgn i.0 (add (i 64) i.0 1)) (continue (lt i.0 n.0))))) .))",
      volRegs = 12, st = addr st)
    doAssert ch and st.by4 == 1 and got.count("(loop") == 2, got
    let (_, chUnrel) = unrolled(
      "(stmts (var :i.0 . (i 64) 0) (ite (lt a.0 b.0) (stmts " &
      "(var :`cse.1 . (i 64) (dot r.0 t.0 0)) " &
      "(loop (stmts (asgn s.0 (add (i 64) s.0 `cse.1)) " &
      "(asgn i.0 (add (i 64) i.0 1)) (continue (lt i.0 n.0))))) .))", volRegs = 12)
    doAssert not chUnrel, "unrelated ite guard must not authorize bare loop"

  block count_up_and_count_down_partial:
    var st1 = UnrollStats()
    let (gup, ch1) = unrolled(
      "(stmts (var :i.0 . (i 64) 0) (ite (le i.0 n.0) (stmts (loop (stmts " &
      "(asgn s.0 (add (i 64) s.0 i.0)) (asgn i.0 (add (i 64) i.0 1)) " &
      "(continue (le i.0 n.0))))) .))", volRegs = 12, st = addr st1)
    doAssert ch1 and st1.by4 == 1 and "(le 3u (sub (u 64)" in gup and "(le i.0 `unr.lim." in gup, gup
    var st2 = UnrollStats()
    let (gdn, ch2) = unrolled(
      "(stmts (var :i.0 . (i 64) n.0) (ite (le 0 i.0) (stmts (loop (stmts " &
      "(asgn s.0 (add (i 64) s.0 i.0)) (asgn i.0 (sub (i 64) i.0 1)) " &
      "(continue (le 0 i.0))))) .))", st = addr st2)
    doAssert ch2 and st2.by4 == 1 and "(le 3 i.0)" in gdn and "`unr.lim." notin gdn, gdn

  block factor_two_medium_body:
    var st = UnrollStats()
    let stmt = "(asgn s.0 (add (i 64) s.0 (add (i 64) (at a.0 i.0) (at b.0 i.0)))) "
    let (got, ch) = unrolled(
      "(stmts (var :i.0 . (i 64) 0) (ite (lt i.0 n.0) (stmts (loop (stmts " &
      stmt & stmt & stmt & "(asgn i.0 (add (i 64) i.0 1)) (continue (lt i.0 n.0))))) .))",
      volRegs = 12, st = addr st)
    doAssert ch and st.by2 == 1 and got.count("(loop") == 2, got

  block dynamic_stop_reg_pressure_gate:
    let src =
      "(stmts (var :i.0 . (i 64) 0) (ite (lt i.0 n.0) (stmts (loop (stmts " &
      "(asgn s.0 (add (i 64) s.0 (at a.0 i.0))) " &
      "(asgn i.0 (add (i 64) i.0 1)) (continue (lt i.0 n.0))))) .))"
    let (gx64, ch1) = unrolled(src, volRegs = 4)
    doAssert ch1 and "`unr.lim." notin gx64 and "(sub (u 64)" in gx64, gx64
    let (ga64, ch2) = unrolled(src, volRegs = 12)
    doAssert ch2 and "`unr.lim." in ga64, ga64

  block freshen_locals_and_preserve_field_names:
    let (got, ch) = unrolled(
      "(stmts (var :i.0 . (i 64) 0) (ite (lt i.0 n.0) (stmts (loop (stmts " &
      "(var :b.0 . (i 64) (add (i 64) (dot o.0 b.0 0) i.0)) " &
      "(asgn s.0 (add (i 64) s.0 b.0)) " &
      "(asgn i.0 (add (i 64) i.0 1)) (continue (lt i.0 n.0))))) .))", volRegs = 12)
    doAssert ch, got
    doAssert got.count("(dot o.0 b.0 0)") == 5, "field name must survive freshening: " & got
    doAssert got.count(":b.0") == 1, "only remainder keeps original local name: " & got

  block skips_vectorizer_remainder:
    let src =
      "(stmts (var :vec.ok.1 . (bool) (false)) " &
      "(if (elif vec.ok.1 (stmts (asgn i.0 n.0)))) " &
      "(ite (lt i.0 n.0) (stmts (loop (stmts (asgn s.0 (add (i 64) s.0 i.0)) " &
      "(asgn i.0 (add (i 64) i.0 1)) (continue (lt i.0 n.0))))) .))"
    doAssert not unrolled(src)[1], "must not unroll vectorizer remainder"

  block calls_and_noreturn_guards:
    var modBuf = parse("(stmts (proc :panic.0.M . . (pragmas (attr \"noreturn\")) .) " &
                       "(proc :work.0.M . . . .))")
    var summaries = collectFunctionSummaries(modBuf)
    let withWork =
      "(stmts (var :i.0 . (i 64) 0) (ite (lt i.0 n.0) (stmts (loop (stmts " &
      "(call work.0.M i.0) (asgn i.0 (add (i 64) i.0 1)) (continue (lt i.0 n.0))))) .))"
    doAssert not unrolled(withWork, summaries = addr summaries, pool = modBuf.pool)[1]
    let withPanic =
      "(stmts (var :i.0 . (i 64) 0) (ite (lt i.0 n.0) (stmts (loop (stmts " &
      "(ite (not (lt i.0 m.0)) (stmts (call panic.0.M)) .) " &
      "(asgn s.0 (add (i 64) s.0 i.0)) " &
      "(asgn i.0 (add (i 64) i.0 1)) (continue (lt i.0 n.0))))) .))"
    doAssert unrolled(withPanic, volRegs = 12, summaries = addr summaries, pool = modBuf.pool)[1]

  block opt_size_skips_growth:
    let dynLoop =
      "(stmts (var :i.0 . (i 64) 0) (ite (lt i.0 n.0) (stmts (loop (stmts " &
      "(asgn s.0 (add (i 64) s.0 i.0)) (asgn i.0 (add (i 64) i.0 1)) " &
      "(continue (lt i.0 n.0))))) .))"
    doAssert not unrolled(dynLoop, optSize = true)[1]

  block rejects_break_and_static_and_addr_taken:
    let withBreak =
      "(stmts (var :i.0 . (i 64) 0) (ite (lt i.0 n.0) (stmts (loop (stmts " &
      "(ite (eq i.0 5) (stmts (break)) .) (asgn i.0 (add (i 64) i.0 1)) " &
      "(continue (lt i.0 n.0))))) .))"
    doAssert not unrolled(withBreak)[1]
    let withStatic =
      "(stmts (var :i.0 . (i 64) 0) (ite (lt i.0 n.0) (stmts (loop (stmts " &
      "(var :st.0 (pragmas (static)) (i 64) 0) (asgn i.0 (add (i 64) i.0 1)) " &
      "(continue (lt i.0 n.0))))) .))"
    doAssert not unrolled(withStatic)[1]
    let withAddrIv =
      "(stmts (var :i.0 . (i 64) 0) (var :p.0 . (ptr (i 64)) (addr i.0)) " &
      "(ite (lt i.0 n.0) (stmts (loop (stmts (asgn s.0 (add (i 64) s.0 i.0)) " &
      "(asgn i.0 (add (i 64) i.0 1)) (continue (lt i.0 n.0))))) .))"
    doAssert not unrolled(withAddrIv)[1]

  echo "unroll.nim: all self-tests passed"
