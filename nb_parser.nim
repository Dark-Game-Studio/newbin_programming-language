# nb_parser.nim
import strutils, tables, sequtils

type
  TokenKind = enum
    tkIdent, tkInt, tkFloat, tkString, tkBool
    tkPlus, tkMinus, tkStar, tkSlash, tkPercent
    tkEq, tkNeq, tkLt, tkGt, tkLe, tkGe
    tkAssign, tkLParen, tkRParen, tkLBrace, tkRBrace
    tkLBracket, tkRBracket, tkComma, tkColon, tkSemi
    tkDot, tkArrow, tkFatArrow
    tkIf, tkElse, tkWhile, tkFor, tkIn, tkReturn
    tkFunc, tkClass, tkVar, tkVal, tkNew
    tkTry, tkCatch, tkThrow, tkFinally
    tkSearch, tkFetch, tkAsync, tkAwait
    tkEof

  Token = object
    kind: TokenKind
    value: string
    line, col: int

  ASTNodeKind = enum
    astProgram, astBlock, astFuncDef, astClassDef
    astVarDecl, astAssign, astBinaryOp, astUnaryOp
    astCall, astIf, astWhile, astFor, astReturn
    astIntLit, astFloatLit, astStrLit, astBoolLit
    astIdent, astFieldAccess, astIndexAccess
    astSearchExpr, astFetchExpr

  ASTNode = ref object
    case kind: ASTNodeKind
    of astProgram, astBlock:
      statements: seq[ASTNode]
    of astFuncDef:
      funcName: string
      params: seq[(string, string)]  # (name, type)
      returnType: string
      body: ASTNode
    of astVarDecl:
      varName: string
      varType: string
      initializer: ASTNode
    of astBinaryOp:
      operator: string
      left, right: ASTNode
    of astIntLit:
      intVal: int64
    of astFloatLit:
      floatVal: float64
    of astStrLit:
      strVal: string
    of astIdent:
      identName: string
    # ... other node types

# Lexer
proc lexer(source: string): seq[Token] =
  var tokens: seq[Token]
  var pos = 0
  var line = 1
  var col = 1
  
  while pos < source.len:
    case source[pos]
    of ' ', '\t':
      inc col
      inc pos
    of '\n', '\r':
      inc line
      col = 1
      inc pos
      if source[pos] == '\n': inc pos
    of '+': tokens.add(Token(kind: tkPlus, line: line, col: col)); inc pos; inc col
    of '-': 
      if pos+1 < source.len and source[pos+1] == '>':
        tokens.add(Token(kind: tkArrow, line: line, col: col))
        inc pos, 2; inc col, 2
      else:
        tokens.add(Token(kind: tkMinus, line: line, col: col))
        inc pos; inc col
    of '=':
      if pos+1 < source.len and source[pos+1] == '=':
        tokens.add(Token(kind: tkEq, line: line, col: col))
        inc pos, 2; inc col, 2
      else:
        tokens.add(Token(kind: tkAssign, line: line, col: col))
        inc pos; inc col
    of '"':
      # Parse string
      inc pos; inc col
      var strVal = ""
      while pos < source.len and source[pos] != '"':
        if source[pos] == '\\':
          inc pos; inc col
          case source[pos]
          of 'n': strVal.add '\n'
          of 't': strVal.add '\t'
          of '\\': strVal.add '\\'
          of '"': strVal.add '"'
          else: strVal.add source[pos]
        else:
          strVal.add source[pos]
        inc pos; inc col
      inc pos; inc col  # Skip closing quote
      tokens.add(Token(kind: tkStrLit, value: strVal, line: line, col: col))
    of '0'..'9':
      var numStr = ""
      while pos < source.len and source[pos] in {'0'..'9', '.'}:
        numStr.add source[pos]
        inc pos; inc col
      if '.' in numStr:
        tokens.add(Token(kind: tkFloat, value: numStr, line: line, col: col))
      else:
        tokens.add(Token(kind: tkInt, value: numStr, line: line, col: col))
    of 'a'..'z', 'A'..'Z', '_':
      var ident = ""
      while pos < source.len and source[pos] in {'a'..'z', 'A'..'Z', '0'..'9', '_'}:
        ident.add source[pos]
        inc pos; inc col
      
      case ident
      of "if": tokens.add(Token(kind: tkIf, line: line, col: col))
      of "else": tokens.add(Token(kind: tkElse, line: line, col: col))
      of "while": tokens.add(Token(kind: tkWhile, line: line, col: col))
      of "for": tokens.add(Token(kind: tkFor, line: line, col: col))
      of "func": tokens.add(Token(kind: tkFunc, line: line, col: col))
      of "class": tokens.add(Token(kind: tkClass, line: line, col: col))
      of "var": tokens.add(Token(kind: tkVar, line: line, col: col))
      of "return": tokens.add(Token(kind: tkReturn, line: line, col: col))
      of "search": tokens.add(Token(kind: tkSearch, line: line, col: col))
      of "fetch": tokens.add(Token(kind: tkFetch, line: line, col: col))
      of "true", "false": tokens.add(Token(kind: tkBool, value: ident, line: line, col: col))
      of "async": tokens.add(Token(kind: tkAsync, line: line, col: col))
      of "await": tokens.add(Token(kind: tkAwait, line: line, col: col))
      of "try": tokens.add(Token(kind: tkTry, line: line, col: col))
      of "catch": tokens.add(Token(kind: tkCatch, line: line, col: col))
      else: tokens.add(Token(kind: tkIdent, value: ident, line: line, col: col))
    else:
      inc pos; inc col
  
  tokens.add(Token(kind: tkEof))
  return tokens

# Parser
type Parser = object
  tokens: seq[Token]
  pos: int

proc newParser(tokens: seq[Token]): Parser =
  Parser(tokens: tokens, pos: 0)

proc peek(p: Parser): Token = p.tokens[p.pos]
proc advance(p: var Parser): Token =
  result = p.tokens[p.pos]
  inc p.pos

proc expect(p: var Parser, kind: TokenKind): Token =
  let token = p.peek
  if token.kind != kind:
    raise newException(ValueError, "Expected " & $kind & " but got " & $token.kind)
  return p.advance

# Expression parsing with precedence climbing
proc parseExpr(p: var Parser, minPrec: int = 0): ASTNode

proc getPrecedence(kind: TokenKind): int =
  case kind
  of tkAssign: 1
  of tkEq, tkNeq, tkLt, tkGt, tkLe, tkGe: 4
  of tkPlus, tkMinus: 5
  of tkStar, tkSlash, tkPercent: 6
  else: 0

proc parsePrimary(p: var Parser): ASTNode =
  let token = p.peek
  case token.kind
  of tkInt:
    discard p.advance
    return ASTNode(kind: astIntLit, intVal: parseInt(token.value))
  of tkFloat:
    discard p.advance
    return ASTNode(kind: astFloatLit, floatVal: parseFloat(token.value))
  of tkString:
    discard p.advance
    return ASTNode(kind: astStrLit, strVal: token.value)
  of tkBool:
    discard p.advance
    return ASTNode(kind: astBoolLit, intVal: if token.value == "true": 1 else: 0)
  of tkIdent:
    discard p.advance
    var node = ASTNode(kind: astIdent, identName: token.value)
    
    # Field access: obj.field
    while p.peek.kind == tkDot:
      discard p.advance
      let field = p.expect(tkIdent)
      node = ASTNode(kind: astFieldAccess)
      # ... build field access node
    
    # Index access: arr[index]
    while p.peek.kind == tkLBracket:
      discard p.advance
      let index = p.parseExpr()
      discard p.expect(tkRBracket)
      node = ASTNode(kind: astIndexAccess)
      # ... build index access node
    
    # Function call
    while p.peek.kind == tkLParen:
      discard p.advance
      var args: seq[ASTNode]
      if p.peek.kind != tkRParen:
        args.add p.parseExpr()
        while p.peek.kind == tkComma:
          discard p.advance
          args.add p.parseExpr()
      discard p.expect(tkRParen)
      node = ASTNode(kind: astCall, identName: token.value, statements: args)
    
    return node
  of tkLParen:
    discard p.advance
    let expr = p.parseExpr()
    discard p.expect(tkRParen)
    return expr
  of tkSearch:
    discard p.advance
    discard p.expect(tkLParen)
    let query = p.parseExpr()
    discard p.expect(tkRParen)
    return ASTNode(kind: astSearchExpr, strVal: "")
  else:
    raise newException(ValueError, "Unexpected token: " & $token.kind)

proc parseExpr(p: var Parser, minPrec: int = 0): ASTNode =
  var left = p.parsePrimary()
  
  while true:
    let token = p.peek
    let prec = getPrecedence(token.kind)
    if prec < minPrec:
      break
    
    discard p.advance
    let right = p.parseExpr(prec + 1)
    left = ASTNode(kind: astBinaryOp, operator: $token.kind, left: left, right: right)
  
  return left

# Parse statements
proc parseStatement(p: var Parser): ASTNode =
  let token = p.peek
  case token.kind
  of tkVar:
    discard p.advance
    let name = p.expect(tkIdent)
    var varType = "auto"
    if p.peek.kind == tkColon:
      discard p.advance
      varType = p.expect(tkIdent).value
    discard p.expect(tkAssign)
    let init = p.parseExpr()
    discard p.expect(tkSemi)
    return ASTNode(kind: astVarDecl, varName: name.value, varType: varType, initializer: init)
  of tkReturn:
    discard p.advance
    let expr = if p.peek.kind != tkSemi: p.parseExpr() else: nil
    discard p.expect(tkSemi)
    return ASTNode(kind: astReturn, intVal: 0)  # Store expr
  of tkIf:
    discard p.advance
    discard p.expect(tkLParen)
    let condition = p.parseExpr()
    discard p.expect(tkRParen)
    let thenBranch = p.parseBlock()
    var elseBranch: ASTNode = nil
    if p.peek.kind == tkElse:
      discard p.advance
      elseBranch = p.parseBlock()
    return ASTNode(kind: astIf, left: condition, right: thenBranch)
  else:
    let expr = p.parseExpr()
    discard p.expect(tkSemi)
    return expr

proc parseBlock(p: var Parser): ASTNode =
  discard p.expect(tkLBrace)
  var stmts: seq[ASTNode]
  while p.peek.kind != tkRBrace and p.peek.kind != tkEof:
    stmts.add p.parseStatement()
  discard p.expect(tkRBrace)
  return ASTNode(kind: astBlock, statements: stmts)

proc parseProgram(p: var Parser): ASTNode =
  var stmts: seq[ASTNode]
  while p.peek.kind != tkEof:
    if p.peek.kind == tkFunc:
      discard p.advance
      let name = p.expect(tkIdent).value
      discard p.expect(tkLParen)
      var params: seq[(string, string)]
      if p.peek.kind != tkRParen:
        let paramName = p.expect(tkIdent).value
        discard p.expect(tkColon)
        let paramType = p.expect(tkIdent).value
        params.add((paramName, paramType))
        while p.peek.kind == tkComma:
          discard p.advance
          let paramName = p.expect(tkIdent).value
          discard p.expect(tkColon)
          let paramType = p.expect(tkIdent).value
          params.add((paramName, paramType))
      discard p.expect(tkRParen)
      var returnType = "void"
      if p.peek.kind == tkColon:
        discard p.advance
        returnType = p.expect(tkIdent).value
      let body = p.parseBlock()
      stmts.add ASTNode(kind: astFuncDef, funcName: name, params: params, 
                        returnType: returnType, body: body)
    else:
      stmts.add p.parseStatement()
  
  return ASTNode(kind: astProgram, statements: stmts)

proc parse*(source: string): ASTNode =
  let tokens = lexer(source)
  var parser = newParser(tokens)
  return parser.parseProgram()