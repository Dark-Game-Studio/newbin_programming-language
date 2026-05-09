# nb_codegen.nim
import tables, strformat

type
  CodeGen = object
    functions: seq[NBFunction]
    code: seq[byte]
    stringTable: seq[byte]
    stringOffsets: Table[string, uint32]
    globalSymbols: Table[string, NBSymbol]
    labelPatches: seq[(uint32, string)]  # (code position, label name)
    labels: Table[string, uint32]
    scopeStack: seq[Table[string, (uint32, NBType)]]  # Variable tracking

proc newCodeGen(): CodeGen =
  result = CodeGen()
  result.scopeStack.add(initTable[string, (uint32, NBType)]())

proc emit(cg: var CodeGen, byte: byte) =
  cg.code.add(byte)

proc emitU16(cg: var CodeGen, val: uint16) =
  cg.code.add(byte(val and 0xFF))
  cg.code.add(byte((val shr 8) and 0xFF))

proc emitU32(cg: var CodeGen, val: uint32) =
  cg.code.add(byte(val and 0xFF))
  cg.code.add(byte((val shr 8) and 0xFF))
  cg.code.add(byte((val shr 16) and 0xFF))
  cg.code.add(byte((val shr 24) and 0xFF))

proc emitU64(cg: var CodeGen, val: uint64) =
  cg.emitU32(uint32(val and 0xFFFFFFFF))
  cg.emitU32(uint32((val shr 32) and 0xFFFFFFFF))

proc addString(cg: var CodeGen, str: string): uint32 =
  if str in cg.stringOffsets:
    return cg.stringOffsets[str]
  
  let offset = uint32(cg.stringTable.len)
  cg.stringOffsets[str] = offset
  
  # Length-prefixed string
  cg.stringTable.add(byte(str.len and 0xFF))
  cg.stringTable.add(byte((str.len shr 8) and 0xFF))
  for c in str:
    cg.stringTable.add(byte(c))
  
  return offset

proc addLabel(cg: var CodeGen, name: string) =
  cg.labels[name] = uint32(cg.code.len)

proc patchLabel(cg: var CodeGen, pos: uint32, label: string) =
  cg.labelPatches.add((pos, label))

proc enterScope(cg: var CodeGen) =
  cg.scopeStack.add(initTable[string, (uint32, NBType)]())

proc leaveScope(cg: var CodeGen) =
  discard cg.scopeStack.pop()

proc addLocalVar(cg: var CodeGen, name: string, varType: NBType): uint32 =
  let slot = uint32(cg.scopeStack[^1].len)
  cg.scopeStack[^1][name] = (slot, varType)
  return slot

proc findVar(cg: var CodeGen, name: string): (uint32, NBType) =
  for i in countdown(cg.scopeStack.len - 1, 0):
    if name in cg.scopeStack[i]:
      return cg.scopeStack[i][name]
  raise newException(ValueError, "Undefined variable: " & name)

proc generateExpr(cg: var CodeGen, node: ASTNode) =
  case node.kind
  of astIntLit:
    cg.emit(byte(opPush64))
    cg.emitU64(cast[uint64](node.intVal))
  
  of astStrLit:
    let strOffset = cg.addString(node.strVal)
    cg.emit(byte(opPushStr))
    cg.emitU32(strOffset)
  
  of astBoolLit:
    if node.intVal == 1:
      cg.emit(byte(opPushTrue))
    else:
      cg.emit(byte(opPushFalse))
  
  of astIdent:
    let (slot, varType) = cg.findVar(node.identName)
    cg.emit(byte(opLoadLocal))
    cg.emit(byte(slot))
  
  of astBinaryOp:
    cg.generateExpr(node.left)
    cg.generateExpr(node.right)
    
    case node.operator
    of "tkPlus": cg.emit(byte(opAddI))
    of "tkMinus": cg.emit(byte(opSubI))
    of "tkStar": cg.emit(byte(opMulI))
    of "tkSlash": cg.emit(byte(opDivI))
    of "tkEq": cg.emit(byte(opEq))
    of "tkNeq": cg.emit(byte(opNeq))
    of "tkLt": cg.emit(byte(opLt))
    of "tkGt": cg.emit(byte(opGt))
    else: raise newException(ValueError, "Unknown operator: " & node.operator)
  
  of astCall:
    # Push arguments in reverse order
    for i in countdown(node.statements.len - 1, 0):
      cg.generateExpr(node.statements[i])
    
    # Emit call instruction
    cg.emit(byte(opCall))
    let funcNameOffset = cg.addString(node.identName)
    cg.emitU32(funcNameOffset)
    cg.emit(byte(node.statements.len))
  
  of astSearchExpr:
    cg.emit(byte(opWebSearch))
    # Query is already on stack from previous expression
  
  else:
    raise newException(ValueError, "Cannot generate code for: " & $node.kind)

proc generateStatement(cg: var CodeGen, node: ASTNode) =
  case node.kind
  of astVarDecl:
    let initType = NBType(kind: tkInt64)  # TODO: Type inference
    let slot = cg.addLocalVar(node.varName, initType)
    if node.initializer != nil:
      cg.generateExpr(node.initializer)
      cg.emit(byte(opStoreLocal))
      cg.emit(byte(slot))
  
  of astBlock:
    cg.enterScope()
    for stmt in node.statements:
      cg.generateStatement(stmt)
    cg.leaveScope()
  
  of astIf:
    cg.generateExpr(node.left)  # Condition
    cg.emit(byte(opJmpIfNot))
    let elseLabel = fmt"else_{cg.labels.len}"
    cg.patchLabel(uint32(cg.code.len - 4), elseLabel)
    cg.emitU32(0)  # Placeholder
    
    cg.generateStatement(node.right)  # True branch
    
    let endLabel = fmt"endif_{cg.labels.len}"
    cg.emit(byte(opJmp))
    cg.patchLabel(uint32(cg.code.len - 4), endLabel)
    cg.emitU32(0)  # Placeholder
    
    cg.addLabel(elseLabel)
    # Generate else branch if exists
    
    cg.addLabel(endLabel)
  
  of astReturn:
    if node.intVal != 0:  # Has return value
      cg.generateExpr(node.statements[0])  # TODO: Fix AST structure
    cg.emit(byte(opRet))
  
  of astFuncDef:
    let funcStart = uint32(cg.code.len)
    let nameOffset = cg.addString(node.funcName)
    
    # Function prologue
    cg.enterScope()
    for i, (paramName, _) in node.params:
      cg.addLocalVar(paramName, NBType(kind: tkAny))  # Params start at slot 0
    
    # Generate function body
    cg.generateStatement(node.body)
    cg.leaveScope()
    
    # Add function metadata
    cg.functions.add(NBFunction(
      nameOffset: nameOffset,
      flags: 0,
      paramsCount: uint8(node.params.len),
      localVarsCount: 0,  # Calculated later
      maxStackSize: 0,     # Calculated later
      codeOffset: funcStart,
      codeSize: uint32(cg.code.len) - funcStart,
      exceptionTableOffset: 0
    ))
  
  else:
    cg.generateExpr(node)

proc generate*(node: ASTNode): CodeGen =
  result = newCodeGen()
  result.generateStatement(node)
  
  # Patch all labels
  for (pos, label) in result.labelPatches:
    if label in result.labels:
      let targetAddr = result.labels[label]
      # Patch the 4-byte address at position pos
      result.code[pos] = byte(targetAddr and 0xFF)
      result.code[pos+1] = byte((targetAddr shr 8) and 0xFF)
      result.code[pos+2] = byte((targetAddr shr 16) and 0xFF)
      result.code[pos+3] = byte((targetAddr shr 24) and 0xFF)