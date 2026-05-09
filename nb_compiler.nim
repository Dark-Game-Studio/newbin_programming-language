# nb_compiler.nim
import streams, os

type
  NBBuilder = object
    program: NBProgram

proc newNBFile(): NBBuilder =
  result.program.header.magic = ['N', 'B', '0', '1']
  result.program.header.version = 1
  result.program.instructions = @[]

proc addInstruction(builder: var NBBuilder, opcode: NBOpcode, operand: uint32 = 0) =
  builder.program.instructions.add(NBInstruction(opcode: opcode, operand: operand))

proc saveToFile(builder: NBBuilder, filename: string) =
  var strm = newFileStream(filename, fmWrite)
  
  # Write magic bytes
  strm.write('N')
  strm.write('B')
  strm.write('0')
  strm.write('1')
  
  # Write header
  strm.write(builder.program.header.version)
  strm.write(builder.program.header.flags)
  
  # Write instructions count
  strm.write(cast[uint32](builder.program.instructions.len))
  
  # Write instructions
  for inst in builder.program.instructions:
    strm.write(cast[uint8](inst.opcode))
    strm.write(inst.operand)
  
  strm.close()

# Example usage
var builder = newNBFile()
builder.addInstruction(opPush, 42)
builder.addInstruction(opPush, 58)
builder.addInstruction(opAdd)
builder.addInstruction(opPrint)
builder.addInstruction(opHalt)
builder.saveToFile("example.nb")