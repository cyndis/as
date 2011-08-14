module AS
  class AssemblyError < StandardError
    def initialize(message, node)
      super(message)

      @node = node
    end
    attr_reader :node
  end
end

require_relative 'parser'
require_relative 'arm_assembler'
require_relative 'elfobject'

class Numeric
  def fits_u8?
    self >= 0 and self <= 255
  end
end

class AS::LabelObject
  def initialize
    @address = nil
    @extern = false
  end
  attr_writer :address

  def address
    return 0 if extern?

    if (@address.nil?)
      raise 'Tried to use label object that has not been set'
    end
    @address
  end

  def assemble(io, as)
    self.address = io.tell
  end

  def extern?
    @extern
  end

  def extern!
    @extern = true
  end
end

class AS::DataObject
  def initialize(data)
    @data = data
  end

  def assemble(io, as)
    io << @data
  end
end

class AS::Relocation
  def initialize(pos, label, type, handler)
    @position = pos
    @label = label
    @type = type
    @handler = handler
  end
  attr_reader :position, :label, :type, :handler
end

class AS::Assembler
  def initialize
    @objects = []
    @label_objects = []
    @label_callbacks = []
    @relocations = []
  end
  attr_reader :relocations, :objects

  def add_object(obj)
    @objects << obj
  end

  def add_relocation(*args)
    @relocations << AS::Relocation.new(*args)
  end

  def register_label_callback(label, io_pos, &block)
    @label_callbacks << [label, io_pos, block]
  end

  def assemble(io)
    @objects.each do |obj|
      obj.assemble io, self
    end

    @relocations.delete_if do |reloc|
      io.seek reloc.position
      if (reloc.label.extern?)
        reloc.handler.call(io, io.tell, reloc.type)
      else
        reloc.handler.call(io, reloc.label.address, reloc.type)
      end
      not reloc.label.extern?
    end
  end
end

class AS::AstAssembler
  def initialize(asm_arch)
    @asm_arch = asm_arch

    @symbols = {}
    @inst_label_context = {}

    @asm = AS::Assembler.new
  end
  
  def assembler
    @asm
  end

  def load_ast(ast)
    label_breadcrumb = []
    ast.children.each do |cmd|
      if (cmd.is_a?(AS::Parser::LabelNode))
        m = /^\/+/.match(cmd.name)
        count = m ? m[0].length : 0
        label_breadcrumb = label_breadcrumb[0,count]
        label_breadcrumb << cmd.name[count..-1]
        @asm.add_object object_for_label(label_breadcrumb.join('/'))
      elsif (cmd.is_a?(AS::Parser::InstructionNode))
        inst = @asm_arch::Instruction.new(cmd, self)
        @asm.add_object inst
        @inst_label_context[inst] = label_breadcrumb
      elsif (cmd.is_a?(AS::Parser::DirectiveNode))
        if (cmd.name == 'global')
          symbol_for_label(cmd.value)[:linkage] = ELF::STB_GLOBAL
        elsif (cmd.name == 'extern')
          object_for_label(cmd.value).extern!
        elsif (cmd.name == 'hexdata')
          bytes = cmd.value.strip.split(/\s+/).map do |hex|
            hex.to_i(16)
          end.pack('C*')
          @asm.add_object AS::DataObject.new(bytes)
        elsif (cmd.name == "asciz")
          str = eval(cmd.value) + "\x00"
          @asm.add_object AS::DataObject.new(str)
        elsif (defined?(AS::ARM) and cmd.name == 'addrtable')
          @asm.add_object AS::ARM::AddrTableObject.new
        else
          raise AS::AssemblyError.new('unknown directive', cmd)
        end
      end
    end
  end

  # instruction is user for label context
  def symbol_for_label(name, instruction=nil)
    if (instruction)
      context = @inst_label_context[instruction]
      m = /^(\/*)(.+)/.match(name)
      breadcrumb = context[0,m[1].length]
      breadcrumb << m[2]
      p breadcrumb
      qual_name = breadcrumb.join('/')
    else
      qual_name = name
    end
    
    if (not @symbols[qual_name])
      @symbols[name] = {:label => AS::LabelObject.new, :linkage => ELF::STB_LOCAL, :name => qual_name}
    end
    @symbols[qual_name]
  end

  def object_for_label(name, instruction=nil)
    symbol_for_label(name, instruction)[:label]
  end

  def assemble(io)
    @asm.assemble io
  end

  def symbols
    @symbols.values
  end

  def relocations
    @asm.relocations
  end
end

