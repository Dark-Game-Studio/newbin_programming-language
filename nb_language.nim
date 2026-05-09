# nb_language.nim
import strutils, streams, os

type
  NBHeader = object
    magic: array[4, char]  # "NB01" magic bytes
    version: uint16
    flags: uint32

  NBOpcode = enum
    opNop = 0x00
    opPush = 0x01
    opPop = 0x02
    opAdd = 0x03
    opSub = 0x04
    opSearch = 0x05  # Bing search integration
    opPrint = 0x06
    opHalt = 0xFF

  NBInstruction = object
    opcode: NBOpcode
    operand: uint32

  NBProgram = object
    header: NBHeader
    instructions: seq[NBInstruction]
    dataSection: seq[byte]

proc readNBFile(filename: string): NBProgram =
  var strm = newFileStream(filename, fmRead)
  if strm.isNil:
    raise newException(IOError, "Cannot open file")
  
  # Read magic bytes
  var magic: array[4, char]
  discard strm.readData(addr magic[0], 4)
  
  if magic != ['N', 'B', '0', '1']:
    raise newException(ValueError, "Invalid NB file")
  
  # Read version and flags
  result.header.version = strm.readUint16()
  result.header.flags = strm.readUint32()
  
  # Read instruction count
  let instCount = strm.readUint32()
  
  # Read instructions
  result.instructions = newSeq[NBInstruction](instCount)
  for i in 0..<instCount:
    result.instructions[i].opcode = cast[NBOpcode](strm.readUint8())
    result.instructions[i].operand = strm.readUint32()
  
  strm.close()

proc interpret(program: NBProgram) =
  var
    stack: seq[int32]
    pc = 0
  
  while pc < program.instructions.len:
    let inst = program.instructions[pc]
    
    case inst.opcode:
    of opPush:
      stack.add(cast[int32](inst.operand))
    of opAdd:
      if stack.len >= 2:
        let b = stack.pop()
        let a = stack.pop()
        stack.add(a + b)
    of opPrint:
      if stack.len > 0:
        echo stack.pop()
    of opSearch:
      # Placeholder for Bing search integration
      echo "Search: ", inst.operand
    of opHalt:
      break
    else:
      echo "Unknown opcode: ", inst.opcode
    
    inc pc

# Main execution
when isMainModule:
  let program = readNBFile("example.nb")
  interpret(program)