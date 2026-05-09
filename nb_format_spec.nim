# nb_format_spec.nim

const
  NB_MAGIC = [byte 0x4E, 0x42, 0x01, 0x00]  # "NB\0x01\0x00"
  NB_VERSION_MAJOR = 1
  NB_VERSION_MINOR = 0
  MAX_STRING_LENGTH = 65535
  MAX_FUNCTION_PARAMS = 255

type
  # === HEADER SECTION ===
  NBFileHeader* = object
    magic*: array[4, byte]          # Magic bytes "NB\0x01\0x00"
    versionMajor*: uint8            # Major version
    versionMinor*: uint8            # Minor version
    flags*: uint16                  # File flags
    timestamp*: uint64              # Compilation timestamp
    entryPoint*: uint32             # Offset to entry point
    sectionTableOffset*: uint32     # Offset to section table

  NBFileFlags = enum
    flagDebug = 0x0001              # Contains debug info
    flagCompressed = 0x0002         # Sections are compressed
    flagEncrypted = 0x0004          # Sections are encrypted
    flagPIE = 0x0008                # Position Independent Executable

  # === SECTION TABLE ===
  NBSectionType* = enum
    secNull = 0x00
    secCode = 0x01                  # Executable code
    secData = 0x02                  # Static data
    secStrings = 0x03               # String table
    secSymbols = 0x04              # Symbol table
    secTypes = 0x05                # Type metadata
    secDebug = 0x06                # Debug information
    secImports = 0x07              # Import table
    secExports = 0x08              # Export table
    secResources = 0x09            # Resources/text/etc
    secRelocations = 0x0A          # Relocations

  NBSectionHeader* = object
    name*: array[8, char]          # Section name
    sectType*: NBSectionType
    flags*: uint32                 # Section flags
    virtualAddress*: uint64        # Virtual address in memory
    offset*: uint64                # Offset in file
    size*: uint64                  # Size in file
    virtualSize*: uint64           # Size in memory
    alignment*: uint32             # Alignment requirement

  # === CODE SECTION ===
  NBFunction* = object
    nameOffset*: uint32            # Offset in string table
    flags*: uint16                 # Function flags
    paramsCount*: uint8            # Number of parameters
    localVarsCount*: uint16        # Number of local variables
    maxStackSize*: uint16          # Maximum stack size
    codeOffset*: uint32            # Offset to bytecode
    codeSize*: uint32              # Size of bytecode
    exceptionTableOffset*: uint32  # Offset to exception handlers

  NBOpcode* = enum
    # Stack Operations (0x00-0x0F)
    opNop = 0x00
    opPush8 = 0x01
    opPush16 = 0x02
    opPush32 = 0x03
    opPush64 = 0x04
    opPushF32 = 0x05
    opPushF64 = 0x06
    opPushStr = 0x07
    opPushNull = 0x08
    opPushTrue = 0x09
    opPushFalse = 0x0A
    opPop = 0x0B
    opDup = 0x0C
    opSwap = 0x0D
    
    # Arithmetic (0x10-0x1F)
    opAddI = 0x10
    opSubI = 0x11
    opMulI = 0x12
    opDivI = 0x13
    opModI = 0x14
    opAddF = 0x15
    opSubF = 0x16
    opMulF = 0x17
    opDivF = 0x18
    opNeg = 0x19
    opInc = 0x1A
    opDec = 0x1B
    
    # Bitwise (0x20-0x2F)
    opAnd = 0x20
    opOr = 0x21
    opXor = 0x22
    opNot = 0x23
    opShl = 0x24
    opShr = 0x25
    
    # Comparison (0x30-0x3F)
    opEq = 0x30
    opNeq = 0x31
    opLt = 0x32
    opGt = 0x33
    opLe = 0x34
    opGe = 0x35
    
    # Control Flow (0x40-0x4F)
    opJmp = 0x40
    opJmpIf = 0x41
    opJmpIfNot = 0x42
    opCall = 0x43
    opRet = 0x44
    opCallNative = 0x45
    opYield = 0x46
    
    # Variables (0x50-0x5F)
    opLoadGlobal = 0x50
    opStoreGlobal = 0x51
    opLoadLocal = 0x52
    opStoreLocal = 0x53
    opLoadField = 0x54
    opStoreField = 0x55
    opLoadIndex = 0x56
    opStoreIndex = 0x57
    
    # Memory (0x60-0x6F)
    opNew = 0x60
    opNewArray = 0x61
    opNewMap = 0x62
    opDelete = 0x63
    
    # Web/Network (0x70-0x7F)
    opHttpGet = 0x70
    opHttpPost = 0x71
    opWebSearch = 0x72    # Bing search
    opFetchUrl = 0x73
    opParseJson = 0x74
    opParseXml = 0x75
    
    # Advanced (0x80-0x8F)
    opTry = 0x80
    opCatch = 0x81
    opThrow = 0x82
    opFinally = 0x83
    opTypeOf = 0x84
    opCast = 0x85
    opPrint = 0x86
    opConcat = 0x87
    
    opHalt = 0xFF

  # === DATA TYPES ===
  NBTypeKind* = enum
    tkVoid
    tkInt8
    tkInt16
    tkInt32
    tkInt64
    tkFloat32
    tkFloat64
    tkBool
    tkChar
    tkString
    tkArray
    tkMap
    tkFunction
    tkClass
    tkNull
    tkAny

  NBType* = object
    kind*: NBTypeKind
    subType*: int32       # For arrays: element type, for maps: value type
    dimensions*: uint16    # For arrays
    classNameOffset*: uint32  # For class types

  # === SYMBOL TABLE ===
  NBSymbol* = object
    nameOffset*: uint32
    symType*: NBType
    flags*: uint32
    value*: uint64        # For constants/addresses
    scope*: uint32        # Scope level

  # === EXCEPTION TABLE ===
  NBExceptionHandler* = object
    tryStart*: uint32
    tryEnd*: uint32
    handlerStart*: uint32
    exceptionType*: int32  # -1 for catch-all
    finallyBlock*: uint32  # 0 if no finally

  # === COMPLETE FILE STRUCTURE ===
  NBFile* = object
    header*: NBFileHeader
    sections*: seq[NBSectionHeader]
    functions*: TableRef[uint32, NBFunction]
    symbols*: TableRef[string, NBSymbol]
    stringTable*: seq[byte]      # Raw string data
    codeSection*: seq[byte]      # Raw bytecode
    debugInfo*: seq[byte]        # Debug data if present