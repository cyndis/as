require 'assembler'
require 'parser'
require 'stringio'

class AS::ARMCodeGenerator
	def initialize
		@asm = AS::Assembler.new(AS::ARM)
	end

	def data(str)
		@asm.add_object AS::DataObject.new(str)
	end

	%w(r0 r1 r2 r3 r4 r5 r6 r7 r8 r9 r10 r11 r12
	   r13 r14 r15 a1 a2 a3 a4 v1 v2 v3 v4 v5 v6
	   rfp sl fp ip sp lr pc
	).each { |reg|
		define_method(reg) {
			[:reg, reg]
		}
	}

	def instruction(name, *args)
		node = AS::Parser::InstructionNode.new
		node.opcode = name.to_s
		node.args = []

		args.each { |arg|
			if (arg.is_a?(Array))
				if (arg[0] == :reg)
					node.args << AS::Parser::RegisterArgNode.new { |n|
						n.name = arg[1]
					}
				end
			elsif (arg.is_a?(Integer))
				node.args << AS::Parser::NumLiteralArgNode.new { |n|
					n.value = arg
				}
			elsif (arg.is_a?(Symbol))
				node.args << AS::Parser::LabelRefArgNode.new { |n|
					n.label = arg.to_s
				}
			else
				raise 'Invalid argument for instruction'
			end
		}

		@asm.add_object AS::ARM::Instruction.new(node)
	end

	%w(adc add and bic eor orr rsb rsc sbc sub
	   mov mvn cmn cmp teq tst
	).each { |inst|
		define_method(inst) { |*args|
			instruction inst.to_sym, *args
		}
	}

	def label(name)
		@asm.add_object AS::LabelObject.new(name.to_s)
	end

	def assemble
		io = StringIO.new
		@symbols = @asm.assemble(io)
		io.string
	end
	attr_reader :symbols
end

if (__FILE__ == $0)
	gen = AS::ARMCodeGenerator.new
	gen.label :_start
	gen.mov gen.r0, 5
	gen.data "\x1E\xFF\x2F\xE1"
	p gen.assemble
end
