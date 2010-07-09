module AS::ARM
end

module AS::ARM::InstructionTools
	def reg_ref(arg)
		if (not arg.is_a?(AS::Parser::RegisterArgNode))
			raise 'Must be a register'
		end

		ref =
		{'r0' => 0, 'r1' => 1, 'r2' => 2, 'r3' => 3, 'r4' => 4, 'r5' => 5,
		 'r6' => 6, 'r7' => 7, 'r8' => 8, 'r9' => 9, 'r10' => 10, 'r11' => 11,
		 'r12' => 12, 'r13' => 13, 'r14' => 14, 'r15' => 15, 'a1' => 0, 'a2' => 1,
		 'a3' => 2, 'a4' => 3, 'v1' => 4, 'v2' => 5, 'v3' => 6, 'v4' => 7, 'v5' => 8,
		 'v6' => 9, 'rfp' => 9, 'sl' => 10, 'fp' => 11, 'ip' => 12, 'sp' => 13,
		 'lr' => 14, 'pc' => 15}[arg.name.downcase]

		if (not ref)
			raise AS::AssemblyError.new('unknown register %s' % arg.name.downcase, arg)
		end

		ref
	end
end

class AS::ARM::Instruction
	include AS::ARM::InstructionTools

	COND_POSTFIXES = Regexp.union(%w(eq ne cs cc mi pl vs vc hi ls ge lt gt le al)).source
	def initialize(node)
		@node = node
		opcode = node.opcode
		args = node.args

		opcode = opcode.downcase
		@cond = :al
		if (opcode =~ /(#{COND_POSTFIXES})$/)
			@cond = $1.to_sym
			opcode = opcode[0..-3]
		end
		if (opcode =~ /s$/)
			@s = true
			opcode = opcode[0..-2]
		else
			@s = false
		end
		@opcode = opcode.downcase.to_sym
		@args = args
	end
	attr_reader :opcode, :args

	OPC_DATA_PROCESSING = 0b00
	# These are used differently in the
	# instruction encoders
	OPCODES = {
		:adc => 0b0101, :add => 0b0100,
		:and => 0b0000, :bic => 0b1110,
		:eor => 0b0001, :orr => 0b1100,
		:rsb => 0b0011, :rsc => 0b0111,
		:sbc => 0b0110, :sub => 0b0010,

		# for these Rn is sbz (should be zero)
		:mov => 0b1101,
		:mvn => 0b1111,
		# for these Rd is sbz and S=1
		:cmn => 0b1011,
		:cmp => 0b1010,
		:teq => 0b1001,
		:tst => 0b1000,

		:b => 0b1010,
		:bl => 0b1011,
		:bx => 0b00010010
	}
	COND_BITS = {
		:al => 0b1110, :eq => 0b0000,
		:ne => 0b0001, :cs => 0b0010,
		:mi => 0b0100, :hi => 0b1000,
		:cc => 0b0011, :pl => 0b0101,
		:ls => 0b1001, :vc => 0b0111,
		:lt => 0b1011, :le => 0b1101,
		:ge => 0b1010, :gt => 0b1100,
		:vs => 0b0110
	}
	def assemble(io, as)
		s = @s ? 1 : 0
		case opcode
		when :adc, :add, :and, :bic, :eor, :orr, :rsb, :rsc, :sbc, :sub
			a = BuilderA.make(OPC_DATA_PROCESSING, OPCODES[opcode], s)
			a.cond = COND_BITS[@cond]
			a.rd = reg_ref(args[0])
			a.rn = reg_ref(args[1])
			a.build_operand args[2]
			a.write io
		when :cmn, :cmp, :teq, :tst
			a = BuilderA.make(OPC_DATA_PROCESSING, OPCODES[opcode], 1)
			a.cond = COND_BITS[@cond]
			a.rn = reg_ref(args[0])
			a.rd = 0
			a.build_operand args[1]
			a.write io
		when :mov, :mvn
			a = BuilderA.make(OPC_DATA_PROCESSING, OPCODES[opcode], s)
			a.cond = COND_BITS[@cond]
			a.rn = 0
			a.rd = reg_ref(args[0])
			a.build_operand args[1]
			a.write io
		when :b, :bl
			arg = args[0]
			if (arg.is_a?(AS::Parser::NumLiteralArgNode))
				jmp_val = arg.value >> 2
				packed = [jmp_val].pack('l')
				# signed 32-bit, condense to 24-bit
				# TODO add check that the value fits into 24 bits
				io << packed[0,3]
			elsif (arg.is_a?(AS::Parser::LabelRefArgNode))
				as.register_label_callback(arg.label, io.tell) { |io, reloc_pos|
					# subtract 8 because of pipeline
					diff = reloc_pos - io.tell - 8
					packed = [diff >> 2].pack('l')
					# TODO see prev. todo
					io << packed[0,3]
				}
				io << "\x00\x00\x00"
			end
			io.write_uint8 OPCODES[opcode] | (COND_BITS[@cond] << 4)
		when :bx
			rm = reg_ref(args[0])
			io.write_uint32 rm | (0b1111111111110001 << 4) | (OPCODES[:bx] << 16+4) |
			                (COND_BITS[@cond] << 16+4+8)
		else
			raise AS::AssemblyError.new("unknown instruction #{opcode}", @node)
		end
	end

	# Builder for addressing mode 1
	class BuilderA
		include AS::ARM::InstructionTools

		def initialize
			@cond = 0b1110
			@inst_class = 0
			@i = 0
			@opcode = 0
			@s = 0
			@rn = 0
			@rd = 0
			@operand = 0
		end
		attr_accessor :cond, :inst_class, :i, :opcode, :s,
		              :rn, :rd, :operand

		def self.make(inst_class, opcode, s)
			a = new
			a.inst_class = inst_class
			a.opcode = opcode
			a.s = s
			a
		end

		def build_operand(arg)
			if (arg.is_a?(AS::Parser::NumLiteralArgNode))
				if (arg.value.fits_u8?)
					# no shifting needed
					@operand = arg.value
					@i = 1
				else
					raise AS::AssemblyError.new('cannot fit numeric literal argument in operand', arg)
				end
			elsif (arg.is_a?(AS::Parser::RegisterArgNode))
				@operand = reg_ref(arg)
				@i = 0
			else
				raise AS::AssemblyError.new('invalid operand argument', arg)
			end
		end

		def write(io)
			val = operand | (rd << 12) | (rn << 12+4) |
			      (s << 12+4+4) | (opcode << 12+4+4+1) |
			      (i << 12+4+4+1+4) | (inst_class << 12+4+4+1+4+1) |
			      (cond << 12+4+4+1+4+1+2)
			io.write_uint32 val
		end
	end
end
