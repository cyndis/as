require 'assembler'
require 'parser'
require 'stringio'

class AS::ARMCodeGenerator
	def initialize
		@asm = AS::Assembler.new
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
			elsif (arg.is_a?(GeneratorLabel))
				node.args << arg
			else
				raise 'Invalid argument for instruction'
			end
		}

		@asm.add_object AS::ARM::Instruction.new(node)
	end

	%w(adc add and bic eor orr rsb rsc sbc sub
	   mov mvn cmn cmp teq tst b bl bx swi
	).each { |inst|
		define_method(inst) { |*args|
			instruction inst.to_sym, *args
		}
		define_method(inst+'s') { |*args|
			instruction (inst+'s').to_sym, *args
		}
		%w(al eq ne cs mi hi cc pl ls vc
		   lt le ge gt vs
		).each { |cond_suffix|
			define_method(inst+cond_suffix) { |*args|
				instruction (inst+cond_suffix).to_sym, *args
			}
			define_method(inst+'s'+cond_suffix) { |*args|
				instruction (inst+'s'+cond_suffix).to_sym, *args
			}
		}
	}

	class GeneratorLabel < AS::LabelObject
		def initialize(asm)
			@asm = asm
		end
		def set!
			@asm.add_object self
		end
	end

	def label
		GeneratorLabel.new(@asm)
	end

	def assemble
		io = StringIO.new
		@asm.assemble(io)
		io.string
	end
end

if (__FILE__ == $0)
	gen = AS::ARMCodeGenerator.new

	gen.instance_eval {
		mov r0, 5
		loop_start = label
		loop_start.set!
		subs r0, r0, 1
		bne loop_start
		bx lr
	}

	require 'objectwriter'
	require 'tempfile'
	writer = AS::ObjectWriter.new(ELF::TARGET_ARM)
	writer.set_text gen.assemble

	file = Tempfile.new('arm_as_generated')

	begin
		writer.save(file.path)
	rescue => err
		puts 'as: cannot save output file: ' + err.message
		exit
	end

	system("arm-objdump -dS \"#{file.path}\"")
end
