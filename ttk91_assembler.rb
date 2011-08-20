module AS::TTK91
  R_TTK91_ABS16 = 0x00
  
  def self.write_resolved_relocation(io, addr, type)
    case type
    when R_TTK91_ABS16
      io.seek 2, IO::SEEK_CUR
      io.write_uint16 addr
    else
      raise 'unknown relocation type'
    end
  end
end

module AS::TTK91::InstructionTools
  def reg_ref(arg)
    if (not arg.is_a?(AS::Parser::RegisterArgNode))
      raise AS::AssemblyError.new('argument must be a register', arg)
    end

    ref =
    {'r0' => 0, 'r1' => 1, 'r2' => 2, 'r3' => 3, 'r4' => 4,
     'r5' => 5, 'r6' => 6, 'r7' => 7}[arg.name.downcase]

    if (not ref)
      raise AS::AssemblyError.new('unknown register %s' % arg.name.downcase, arg)
    end

    ref
  end
end

class AS::TTK91::Instruction
  include AS::TTK91::InstructionTools

  def initialize(node, ast_asm = nil)
    @node = node
    @ast_asm = ast_asm
    @opcode = node.opcode.downcase.to_sym
    @args = node.args
  end
  attr_reader :opcode, :args
  
  OPCODES = {
    :nop => 0x00, :store => 0x01, :load => 0x02, :in => 0x03, :out => 0x04,
    :add => 0x11, :sub => 0x12, :mul => 0x13, :div => 0x14, :mod => 0x15,
    :and => 0x16, :or => 0x17, :xor => 0x18, :shl => 0x19, :shr => 0x1a,
    :not => 0x1b, :shra => 0x1c, :comp => 0x1f, :jump => 0x20, :jneg => 0x21,
    :jzer => 0x22, :jpos => 0x23, :jnneg => 0x24, :jnzer => 0x25, :jnpos =>0x26,
    :jles => 0x27, :jequ => 0x28, :jgre => 0x29, :jnles => 0x2a, :jnequ => 0x2b,
    :jngre => 0x2c, :call => 0x32, :exit => 0x32, :push => 0x33, :pop => 0x34,
    :pushr => 0x35, :popr => 0x36, :svc => 0x70
  }
  
  RelocHandler = AS::TTK91.method(:write_resolved_relocation)
  
  def check_size(lit)
    if (lit.value > 0xFFFF)
      raise AS::AssemblyError.new(AS::ERRSTR_NUMERIC_LITERAL_TOO_LARGE, lit)
    end
  end
  
  M_IMMEDIATE = 0
  M_DIRECT = 1
  M_INDIRECT = 2
  
  def parse_second_operand(node, io, as)
    m = M_IMMEDIATE
    if (node.is_a?(AS::Parser::NumLiteralArgNode))
      check_size node
      addr = node.value
      ri = 0
    elsif (node.is_a?(AS::Parser::ReferenceArgNode))
      arg1 = node.argument
      m = M_DIRECT
      if (arg1.is_a?(AS::Parser::NumLiteralArgNode))
        check_size arg1
        addr = arg1.value
        ri = 0
      elsif (arg1.is_a?(AS::Parser::ReferenceArgNode))
        arg2 = arg1.argument
        m = M_INDIRECT
        if (arg2.is_a?(AS::Parser::NumLiteralArgNode))
          check_size arg2
          addr = arg2.value
          ri = 0
        elsif (arg2.is_a?(AS::Parser::RegisterArgNode))
          addr = 0
          ri = reg_ref(arg2)
        elsif (arg2.is_a?(AS::Parser::MathNode))
          ri = reg_ref(arg2.left)
          if (not arg2.right.is_a?(AS::Parser::NumLiteralArgNode))
            raise AS::AssemblyError.new('argument must be a numeric literal',
                                        arg2.right)
          end
          check_size arg2.right
          addr = arg2.right.value
        elsif (arg.is_a?(AS::LabelObject) or arg.is_a?(AS::Parser::LabelRefArgNode))
          ri = 0
          addr = 0
          arg = @ast_asm.object_for_label(arg.label, self) if 
            arg.is_a?(AS::Parser::LabelRefArgNode)
          as.add_relocation(io.tell, arg, AS::TTK91::R_TTK91_ABS16, RelocHandler)
        else
          raise AS::AssemblyError.new(AS::ERRSTR_INVALID_ARG, arg2)
        end
      elsif (arg1.is_a?(AS::Parser::MathNode))
        ri = reg_ref(arg1.left)
        if (not arg1.right.is_a?(AS::Parser::NumLiteralArgNode))
          raise AS::AssemblyError.new('argument must be a numeric literal',
                                      arg1.right)
        end
        check_size arg1.right
        addr = arg1.right.value
      elsif (arg1.is_a?(AS::Parser::RegisterArgNode))
        ri = reg_ref(arg1)
        addr = 0
      elsif (arg.is_a?(AS::LabelObject) or arg.is_a?(AS::Parser::LabelRefArgNode))
        ri = 0
        addr = 0
        arg = @ast_asm.object_for_label(arg.label, self) if 
          arg.is_a?(AS::Parser::LabelRefArgNode)
        as.add_relocation(io.tell, arg, AS::TTK91::R_TTK91_ABS16, RelocHandler)
      else
        raise AS::AssemblyError.new(AS::ERRSTR_INVALID_ARG, arg1)
      end
    elsif (node.is_a?(AS::Parser::MathNode))
      ri = reg_ref(node.left)
      if (not node.right.is_a?(AS::Parser::NumLiteralArgNode))
        raise AS::AssemblyError.new('argument must be a numeric literal',
                                    node.right)
      end
      check_size node.right
      addr = node.right.value
    elsif (node.is_a?(AS::Parser::RegisterArgNode))
      ri = reg_ref(node)
      addr = 0
    elsif (arg.is_a?(AS::LabelObject) or arg.is_a?(AS::Parser::LabelRefArgNode))
      ri = 0
      addr = 0
      arg = @ast_asm.object_for_label(arg.label, self) if 
        arg.is_a?(AS::Parser::LabelRefArgNode)
      as.add_relocation(io.tell, arg, AS::TTK91::R_TTK91_ABS16, RelocHandler)
    else
      raise AS::AssemblyError.new(AS::ERRSTR_INVALID_ARG, node)
    end
    
    return [m, ri, addr]
  end
  
  def assemble(io, as)
    case opcode
      # Rj,M,Ri,ADDR
    when :load, :in, :out, :add, :sub, :mul, :div, :mod, :and, :or, :xor,
         :shl, :shr, :shra, :comp, :push, :store, :jneg, :jzer, :jpos, :jnneg,
         :jnzer, :jnpos, :call, :svc
      rj = reg_ref(args[0])
      m, ri, addr = parse_second_operand(args[1], io, as)
    
      if (opcode == :store and m == M_IMMEDIATE)
        raise AS::AssemblyError.new('argument must not be immediate', args[1])
      end
      
      p [opcode, args]
      p [addr, ri, m, rj, OPCODES[opcode]]
      
      io.write_uint32 addr | (ri << 16) | (m << 16+3) | (rj << 16+3+2) |
                  (OPCODES[opcode] << 16+3+2+3)
    
    when :pop, :exit
      rj = reg_ref(args[0])
      ri = reg_ref(args[1])
      io.write_uint32 (ri << 16) | (rj << 16+3+2) |
                      (OPCODES[:push] << 16+3+2+3)
    when :pushr, :popr, :not
      rj = reg_ref(args[0])
      io.write_uint32 (rj << 16+3+2) | (OPCODES[opcode] << 16+3+2+3)
    when :nop
      io.write_uint32 (OPCODES[:nop] << 16+3+2+3)
    when :jump, :jles, :jequ, :jgre, :jnles, :jnequ, :jngre
      m, ri, addr = parse_second_operand(args[0], io, as)
      
      io.write_uint32 addr | (ri << 16) | (m << 16+3) |
                      (OPCODES[opcode] << 16+3+2+3)
    end
  end
end
