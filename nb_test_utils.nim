# nb_test_utils.nim
import random, strformat

proc generateRandomValidProgram*(): string =
  let functions = @["main", "calculate", "process", "filter", "transform"]
  let types = @["int", "float", "string", "bool"]
  let ops = @["+", "-", "*", "/"]
  
  result = &"func {sample(functions)}() {{\n"
  
  let numVars = rand(1..5)
  for i in 0..<numVars:
    let varName = fmt"var{rand(1000)}"
    let varType = sample(types)
    let value = case varType
      of "int": $rand(0..1000)
      of "float": $rand(0.0..1.0)
      of "string": "\"test\""
      of "bool": sample(@["true", "false"])
      else: "0"
    
    result.add(&"  var {varName}: {varType} = {value};\n")
  
  result.add("  return 0;\n}")
  return result

proc generateRandomBytes*(size: int): seq[byte] =
  result = newSeq[byte](size)
  for i in 0..<size:
    result[i] = byte(rand(255))

proc generateLoopCode*(iterations: int): seq[byte] =
  # Generate bytecode for a simple loop
  result = @[
    byte(opPush64), 0, 0, 0, 0, 0, 0, 0, 0,  # counter = 0
    byte(opStoreLocal), 0,                       # store in local 0
  ]
  
  # Loop start
  result.add(byte(opLoadLocal))  # load counter
  result.add(0)
  result.add(byte(opPush64))     # push limit
  # ... add iteration limit bytes
  
  # Increment and loop
  result.add(byte(opInc))
  result.add(byte(opJmp))
  # ... add jump back bytes
  
  return result