# nb_test_suite.nim
import unittest, os, streams, json, strformat

# === UNIT TESTS ===

suite "NB Binary Format":
  
  test "Header serialization":
    let header = NBFileHeader(
      magic: NB_MAGIC,
      versionMajor: 1,
      versionMinor: 0,
      flags: 0,
      timestamp: 1234567890'u64,
      entryPoint: 0x1000,
      sectionTableOffset: 0x40
    )
    
    # Serialize
    var stream = newStringStream()
    stream.write(header.magic)
    stream.write(header.versionMajor)
    stream.write(header.versionMinor)
    stream.write(header.flags)
    
    check stream.data[0..3] == @[byte 0x4E, 0x42, 0x01, 0x00]
    check stream.data[4] == 1
    check stream.data[5] == 0

  test "Opcode encoding":
    check cast[int](opNop) == 0x00
    check cast[int](opHalt) == 0xFF
    check cast[int](opWebSearch) == 0x72
    
    # Test opcode ranges
    for op in NBOpcode:
      let val = cast[int](op)
      check val >= 0x00 and val <= 0xFF

suite "Lexer":
  
  test "Basic tokens":
    let source = "var x: int = 42;"
    let tokens = lexer(source)
    
    check tokens[0].kind == tkVar
    check tokens[1].kind == tkIdent
    check tokens[1].value == "x"
    check tokens[2].kind == tkColon
    check tokens[3].kind == tkIdent
    check tokens[3].value == "int"
    check tokens[4].kind == tkAssign
    check tokens[5].kind == tkInt
    check tokens[5].value == "42"
    check tokens[6].kind == tkSemi

  test "String literals":
    let source = """var msg = "Hello, World!";"""
    let tokens = lexer(source)
    
    check tokens[4].kind == tkStrLit
    check tokens[4].value == "Hello, World!"

  test "Search keyword":
    let source = "var result = search(\"query\");"
    let tokens = lexer(source)
    
    check tokens[4].kind == tkSearch
    check tokens[6].kind == tkStrLit
    check tokens[6].value == "query"

suite "Parser":

  test "Simple assignment":
    let source = "var x: int = 42;"
    let tokens = lexer(source)
    var parser = newParser(tokens)
    let ast = parser.parseStatement()
    
    check ast.kind == astVarDecl
    check ast.varName == "x"
    check ast.varType == "int"

  test "Function definition":
    let source = """
    func add(a: int, b: int): int {
        return a + b;
    }
    """
    let tokens = lexer(source)
    var parser = newParser(tokens)
    let ast = parser.parseProgram()
    
    check ast.kind == astProgram
    check ast.statements[0].kind == astFuncDef
    check ast.statements[0].funcName == "add"
    check ast.statements[0].params.len == 2

  test "Search expression":
    let source = """search("machine learning");"""
    let tokens = lexer(source)
    var parser = newParser(tokens)
    let ast = parser.parseStatement()
    
    check ast.kind == astSearchExpr

suite "Code Generation":

  test "Push integer":
    var cg = newCodeGen()
    let ast = ASTNode(kind: astIntLit, intVal: 42)
    cg.generateExpr(ast)
    
    check cg.code[0] == byte(opPush64)
    check cg.code[1] == 42

  test "Add operation":
    var cg = newCodeGen()
    let ast = ASTNode(
      kind: astBinaryOp,
      operator: "tkPlus",
      left: ASTNode(kind: astIntLit, intVal: 10),
      right: ASTNode(kind: astIntLit, intVal: 20)
    )
    cg.generateExpr(ast)
    
    check cg.code[0] == byte(opPush64)
    check cg.code[5] == byte(opPush64)
    check cg.code[10] == byte(opAddI)

suite "VM Execution":

  test "Simple arithmetic":
    # Program: push 10, push 20, add, print
    var vm = newVM()
    vm.code = @[
      byte(opPush64), 10, 0, 0, 0, 0, 0, 0, 0,
      byte(opPush64), 20, 0, 0, 0, 0, 0, 0, 0,
      byte(opAddI),
      byte(opPrint),
      byte(opHalt)
    ]
    vm.execute()
    
    # Check output
    check vm.lastPrinted == 30

# === INTEGRATION TESTS ===

suite "End-to-End Tests":

  test "Compile and run simple program":
    let source = """
    func main() {
        var x = 10;
        var y = 20;
        var sum = x + y;
        print(sum);
    }
    """
    
    let ast = parse(source)
    let codeGen = generate(ast)
    let binary = writeNBFile(codeGen, "test_output.nb")
    
    let vm = newVM()
    vm.loadFromFile("test_output.nb")
    vm.execute()
    
    check vm.output == "30\n"

  test "Web search integration (mock)":
    let source = """
    func main() {
        var result = search("test query");
        print(result.title);
    }
    """
    
    # Mock search client
    var mockClient = newSearchClient("mock-key")
    mockClient.endpoint = "http://localhost:9999/mock-search"
    
    # ... test with mocked HTTP server

# === PERFORMANCE TESTS ===

suite "Performance":

  test "Large file parsing":
    var source = ""
    for i in 0..<10000:
      source.add(&"func func{i}() {{ var x{i} = {i}; }}\n")
    
    let startTime = cpuTime()
    let ast = parse(source)
    let parseTime = cpuTime() - startTime
    
    echo &"Parsed 10000 functions in {parseTime:.3f} seconds"
    check parseTime < 1.0  # Should parse quickly

  test "VM execution speed":
    # Generate loop that runs 1 million operations
    var vm = newVM()
    vm.code = generateLoopCode(1_000_000)
    
    let startTime = cpuTime()
    vm.execute()
    let execTime = cpuTime() - startTime
    
    echo &"Executed 1M ops in {execTime:.3f} seconds"
    check execTime < 2.0  # Should execute quickly

# === FUZZ TESTING ===

suite "Fuzz Tests":

  test "Random valid programs":
    for i in 0..<100:
      let program = generateRandomValidProgram()
      try:
        let ast = parse(program)
        let codeGen = generate(ast)
        let binary = writeNBFile(codeGen)
        
        var vm = newVM()
        vm.load(binary)
        vm.execute()
      except:
        echo &"Failed on program {i}: {program}"
        raise

  test "Malformed binary files":
    for i in 0..<1000:
      let randomBytes = generateRandomBytes(rand(16..1024))
      
      try:
        var vm = newVM()
        vm.load(randomBytes)
        vm.execute()
        
        # VM should handle gracefully
        check not vm.crashed
      except CatchableError:
        # Expected for truly malformed input
        discard

# === WEB SEARCH TESTS ===

suite "Search Integration":

  test "Search API request formation":
    let client = newSearchClient("test-key")
    let query = "nim programming"
    let request = buildSearchRequest(client, query)
    
    check request.headers["Ocp-Apim-Subscription-Key"] == "test-key"
    check request.url.contains("nim%20programming")

  test "Search result parsing":
    let mockResponse = """
    {
      "webPages": {
        "value": [
          {
            "name": "Nim Programming Language",
            "url": "https://nim-lang.org",
            "snippet": "Nim is a statically typed compiled systems programming language."
          }
        ]
      }
    }
    """
    
    let results = parseSearchResults(parseJson(mockResponse))
    
    check results.len == 1
    check results[0].title == "Nim Programming Language"
    check results[0].url == "https://nim-lang.org"

  test "Rate limiting":
    var client = newSearchClient("test-key")
    client.rateLimiter.minDelay = 0.1
    
    var times: seq[float]
    for i in 0..<5:
      let startTime = epochTime()
      discard waitFor client.searchWeb("test query")
      times.add(epochTime() - startTime)
    
    # Check that requests were spaced out
    for i in 1..<times.len:
      check times[i] - times[i-1] >= 0.09

# === RUN ALL TESTS ===

when isMainModule:
  # Run specific test suites
  runUnitTests()
  
  # Generate test coverage report
  generateCoverageReport()
  
  # Run benchmarks
  runBenchmarks()