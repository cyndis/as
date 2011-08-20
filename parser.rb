require_relative 'str_scanner'

module AS
  class ParseError < StandardError
    def initialize(message, s)
      super(message)

      @line = s.line
      @column = s.column
    end
    attr_reader :line, :column
  end
end

class AS::Parser
  def initialize(str)
    scanner = AS::Scanner.new(str)

    @ast = parse_toplevel scanner
  end
  attr_reader :ast

  def self.parse(str)
    new(str).ast
  end

  class Node
    def initialize(s = nil)
      if (s)
        @line = s.prev_line
        @column = s.prev_column
      else
        @line = 0
        @column = 0
      end

      yield self if block_given?
    end
    attr_reader :line, :column
  end

  class ToplevelNode < Node
    attr_accessor :children
  end
  def parse_toplevel(s)
    node = ToplevelNode.new(s)
    node.children = []
    while (not s.eos?)
      node.children << parse(s)
    end
    node
  end

  def parse(s)
    s.scan /\s*/
    node = nil
    %w(comment directive label instruction).each { |em|
      if (node = send('parse_'+em, s))
        break
      end
    }
    raise AS::ParseError.new('could not parse element', s) unless node
    s.scan /\s*/
    node
  end

  class CommentNode < Node; end
  def parse_comment(s)
    if (s.scan(/;.*?$/))
      CommentNode.new(s)
    end
  end

  class DirectiveNode < Node
    attr_accessor :name, :value
  end
  def parse_directive(s)
    if (m = s.scan(/\.(\w+)(?:(?!$)\s+(.+)\s*?$)?/))
      DirectiveNode.new(s) { |n|
        n.name = m[0]
        n.value = m[1]
      }
    end
  end

  class LabelNode < Node
    attr_accessor :name
  end
  def parse_label(s)
    if (m = s.scan(/(\/*\w+):/))
      LabelNode.new(s) { |n|
        n.name = m[0]
      }
    end
  end

  class InstructionNode < Node
    attr_accessor :opcode, :args
  end
  def parse_instruction(s)
    if (m = s.scan(/(\w+)/))
      node = InstructionNode.new(s) { |n|
        n.opcode = m[0]
        n.args = []
      }
      if (not s.scan(/\s*($|;)/))
        loop {
          arg = parse_arg(s)
          node.args << arg
          break if not s.scan(/\s*,/)
        }
      end
      node
    end
  end

  class ArgNode < Node
  end
  def parse_arg(s)
    s.scan /\s*/
    node = nil
    %w(reference register register_list num_literal label_ref).each { |em|
      if (node = send('parse_'+em, s))
        break
      end
    }
    raise AS::ParseError.new('expected argument but none found', s) unless node
    
    if (node2 = parse_arg_op(s))
      node2.argument = node
      node = node2
    end

    s.scan /\s*/
    node
  end
  
  def parse_arg_op(s)
    s.scan /\s*/
    node = nil
    %w(shift math).each do |em|
      if (node = send('parse_'+em, s))
        break
      end
    end
    s.scan /\s*/
    node
  end

  class ShiftNode < Node
    attr_accessor :type, :value, :argument
  end
  def parse_shift(s)
    if (m = s.scan(/(lsl|lsr|asr|ror|rrx)\s+/i))
      op = m[0].downcase
      if (op == 'rrx' or arg = parse_arg(s))
        ShiftNode.new(s) { |n|
          n.type = m[0].downcase
          n.value = arg
        }
      else
        nil
      end
    end
  end
  
  class MathNode < Node
    attr_accessor :left, :right, :op
    alias_method :argument, :left
    alias_method :argument=, :left=
  end
  def parse_math(s)
    if (m = s.scan_str(/[\+\-]/))
      if (arg1 = parse_arg(s))
        MathNode.new(s) do |n|
          n.right = arg1
          n.op = m
        end
      else
        raise AS::ParseError.new('expected right side for arithmetic op', s)
      end
    end
  end

  REGISTER_REGEXP = Regexp.union(*%w(r0 r1 r2 r3 r4 r5 r6 r7 r8 r9 r10 r11 r12
     r13 r14 r15 a1 a2 a3 a4 v1 v2 v3 v4 v5 v6
     rfp sl fp ip sp lr pc
  ))
  class RegisterArgNode < ArgNode
    attr_accessor :name
  end
  def parse_register(s)
    if (m = s.scan_str(REGISTER_REGEXP))
      RegisterArgNode.new(s) { |n|
        n.name = m
      }
    end
  end
  
  class RegisterListArgNode < ArgNode
    attr_accessor :registers
  end
  def parse_register_list(s)
    if (m = s.scan(/\{/))
      node = RegisterListArgNode.new(s) do |n|
        n.registers = []
      end
      loop do
        s.scan /\s*/
        reg = parse_register(s)
        if (not reg)
          return nil
        end
        s.scan /\s*,?/
        
        node.registers << reg
        
        if (s.scan(/\}/))
          break
        end
      end
      node
    end
  end

  class NumLiteralArgNode < ArgNode
    attr_accessor :value
  end
  class NumEquivAddrArgNode < NumLiteralArgNode
  end
  def parse_num_literal(s)
    if (m = s.scan(/(=?)#(-?(?:0x)?[0-9A-Fa-f]+)/))
      (m[0] == '=' ? NumEquivAddrArgNode : NumLiteralArgNode).new(s) { |n|
        n.value = Integer(m[1])
      }
    end
  end

  class LabelRefArgNode < ArgNode
    attr_accessor :label, :label_object
  end
  class LabelEquivAddrArgNode < LabelRefArgNode
  end
  def parse_label_ref(s)
    if (m = s.scan(/(=?)(\/*\w+)/))
      (m[0] == '=' ? LabelEquivAddrArgNode : LabelRefArgNode).new(s) { |n|
        n.label = m[1]
      }
    end
  end
  
  class ReferenceArgNode < ArgNode
    attr_accessor :argument
  end
  def parse_reference(s)
    if (m = s.scan(/\[/))
      arg = parse_arg(s)
      if (arg and s.scan(/\]/))
        ReferenceArgNode.new(s) do |n|
          n.argument = arg
        end
      end
    end
  end
end

if (__FILE__ == $0)
  p AS::Parser.parse ARGV[0]
end
