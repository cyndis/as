require_relative 'streamreader'

module ELF
  ET_NONE = 0
  ET_REL = 1
  ET_EXEC = 2
  ET_DYN = 3
  ET_CORE = 4

  EM_NONE = 0
  EM_M32 = 1
  EM_SPARC = 2
  EM_386 = 3
  EM_68K = 4
  EM_88K = 5
  EM_860 = 7
  EM_MIPS = 8
  EM_ARM = 40
  
  # Custom
  EM_TTK91 = 50000

  EV_NONE = 0
  EV_CURRENT = 1

  ELFCLASSNONE = 0
  ELFCLASS32 = 1
  ELFCLASS64 = 2

  ELFDATANONE = 0
  ELFDATA2LSB = 1
  ELFDATA2MSB = 2

  SHT_NULL = 0
  SHT_PROGBITS = 1
  SHT_SYMTAB = 2
  SHT_STRTAB = 3
  SHT_RELA = 4
  SHT_HASH = 5
  SHT_DYNAMIC = 6
  SHT_NOTE = 7
  SHT_NOBITS = 8
  SHT_REL = 9
  SHT_SHLIB = 10
  SHT_DYNSYM = 11

  SHF_WRITE = 0x1
  SHF_ALLOC = 0x2
  SHF_EXECINSTR = 0x4

  STB_LOCAL = 0
  STB_GLOBAL = 1
  STB_WEAK = 2

  ABI_SYSTEMV = 0
  ABI_ARM = 0x61

  ARM_INFLOOP = "\x08\xf0\x4f\xe2"

  TARGET_ARM = [ELFCLASS32, ELFDATA2LSB, ABI_ARM, EM_ARM]
  TARGET_X86 = [ELFCLASS32, ELFDATA2LSB, ABI_SYSTEMV, EM_386]
  TARGET_TTK91 = [ELFCLASS32, ELFDATA2LSB, ABI_SYSTEMV, EM_TTK91]
end

class ELF::Section
  def initialize(name)
    @name = name
  end
  attr_accessor :name, :index

  def type
    raise 'Reimplement #type'
  end
  def flags
    0
  end
  def addr
    0
  end
  def link
    0
  end
  def info
    0
  end
  def alignment
    1
  end
  def ent_size
    0
  end
end

class ELF::StringTableSection < ELF::Section
  def initialize(*args)
    super

    @string_data = "\x00"
    @indices = {"" => 0}
  end

  def add_string(str)
    return if @indices[str]

    @indices[str] = @string_data.length
    @string_data << str << "\x00"
  end

  def index_for(str)
    @indices[str]
  end

  def write(io)
    io << @string_data
  end

  def type
    ELF::SHT_STRTAB
  end
end

class ELF::NullSection < ELF::Section
  def initialize
    super('')
  end

  def write(io)
  end

  def type
    ELF::SHT_NULL
  end

  def alignment
    0
  end
end

class ELF::TextSection < ELF::Section
  attr_accessor :text

  def write(io)
    io << text
  end

  def type
    ELF::SHT_PROGBITS
  end

  def flags
    ELF::SHF_ALLOC | ELF::SHF_EXECINSTR
  end
  
  def alignment
    4
  end
end

class ELF::SymbolTableSection < ELF::Section
  def initialize(name, strtab)
    super(name)

    @strtab = strtab

    @symbols = []
  end

  def add_func_symbol(name, value, text_section, linkage)
    @strtab.add_string name
    arr = [name, value, text_section, linkage]
    if (linkage == ELF::STB_LOCAL)
      @symbols.unshift arr
    else
      @symbols.push arr
    end
  end

  def index_for_name(name)
    @symbols.each_with_index { |sym, idx|
      if (sym[0] == name)
        return idx
      end
    }
    nil
  end

  def type
    ELF::SHT_SYMTAB
  end

  def ent_size
    16
  end

  def link
    @strtab.index
  end

  def info
    i = -1
    @symbols.each_with_index { |sym, idx|
      if (sym[4] == ELF::STB_LOCAL)
        i = idx
      end
    }
    i + 1
  end

  def write(io)
    # write undefined symbol
    io.write_uint32 0
    io.write_uint32 0
    io.write_uint32 0
    io.write_uint8 ELF::STB_LOCAL << 4
    io.write_uint8 0
    io.write_uint16 0

    # write other symbols
    @symbols.each { |sym|
      io.write_uint32 @strtab.index_for(sym[0])
      io.write_uint32 sym[1]
      io.write_uint32 0
      io.write_uint8((sym[3] << 4) + 0)
      io.write_uint8 0
      if (sym[2])
        io.write_uint16 sym[2].index
      else
        # undefined symbol
        io.write_uint16 0
      end
    }
  end
end

class ELF::RelocationTableSection < ELF::Section
  def initialize(name, symtab, text_section)
    super(name)

    @symtab = symtab
    @text_section = text_section

    @relocs = []
  end

  def add_reloc(offset, name, type)
    @relocs << [offset, name, type]
  end

  def type
    ELF::SHT_REL
  end

  def ent_size
    8
  end

  def link
    @symtab.index
  end

  def info
    @text_section.index
  end

  def write(io)
    @relocs.each { |reloc|
      name_idx = @symtab.index_for_name(reloc[1])
      io.write_uint32 reloc[0]
      # +1 because entry number 0 is und
      io.write_uint32 reloc[2] | ((name_idx+1) << 8)
    }
  end
end

class ELF::ObjectFile
  include ELF

  def initialize(target)
    @target = target

    @sections = []
    add_section NullSection.new
  end

  def add_section(section)
    @sections << section
    section.index = @sections.length - 1
  end

  def write(io)
    io << "\x7fELF"
    io.write_uint8 @target[0]
    io.write_uint8 @target[1]
    io.write_uint8 EV_CURRENT
    io.write_uint8 @target[2]
    io << "\x00" * 8 # pad

    io.write_uint16 ET_REL
    io.write_uint16 @target[3]
    io.write_uint32 EV_CURRENT
    io.write_uint32 0 # entry point
    io.write_uint32 0 # no program header table
    sh_offset_pos = io.tell
    io.write_uint32 0 # section header table offset
    io.write_uint32 0 # no flags
    io.write_uint16 52 # header length
    io.write_uint16 0 # program header length
    io.write_uint16 0 # program header count
    io.write_uint16 40 # section header length

    shstrtab = StringTableSection.new(".shstrtab")
    @sections << shstrtab
    @sections.each { |section|
      shstrtab.add_string section.name
    }

    io.write_uint16 @sections.length # section header count

    io.write_uint16 @sections.length-1 # section name string table index

    # write sections

    section_data = []
    @sections.each { |section|
      offset = io.tell
      section.write(io)
      size = io.tell - offset
      section_data << {:section => section, :offset => offset,
                       :size => size}
    }

    # write section headers

    sh_offset = io.tell

    section_data.each { |data|
      section, offset, size = data[:section], data[:offset], data[:size]
      # write header first
      io.write_uint32 shstrtab.index_for(section.name)
      io.write_uint32 section.type
      io.write_uint32 section.flags
      io.write_uint32 section.addr
      if (section.type == SHT_NOBITS)
        raise 'SHT_NOBITS not handled yet'
      elsif (section.type == SHT_NULL)
        io.write_uint32 0
        io.write_uint32 0
      else
        io.write_uint32 offset
        io.write_uint32 size
      end
      io.write_uint32 section.link
      io.write_uint32 section.info
      io.write_uint32 section.alignment
      io.write_uint32 section.ent_size
    }

    io.seek sh_offset_pos
    io.write_uint32 sh_offset
  end
end

if (__FILE__ == $0)
  obj = ELF::ObjectFile.new

  sym_strtab = ELF::StringTableSection.new(".strtab")
  obj.add_section sym_strtab
  symtab = ELF::SymbolTableSection.new(".symtab", sym_strtab)
  obj.add_section symtab

  text_section = ELF::TextSection.new(".text")
  obj.add_section text_section

  symtab.add_func_symbol "_start", 0, text_section, ELF::STB_GLOBAL

  fp = File.open("test.o", "wb")
  obj.write fp

  fp.close
end
