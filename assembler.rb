module AS
	class AssemblyError < StandardError
		def initialize(message, node)
			super(message)

			@node = node
		end
		attr_reader :node
	end
end

require 'parser'
require 'arm_assembler'
require 'elfobject'

class Numeric
	def fits_u8?
		self >= 0 and self <= 255
	end
end

class AS::LabelObject
	def initialize
		@address = nil
	end
	attr_writer :address

	def address
		if (@address.nil?)
			raise 'Tried to use label object that has not been set'
		end
		@address
	end

	def assemble(io, as)
		self.address = io.tell
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

class AS::Assembler
	def initialize
		@objects = []
		@label_objects = []
		@label_callbacks = []
	end

	def add_object(obj)
		@objects << obj
	end

	def register_label_callback(label, io_pos, &block)
		@label_callbacks << [label, io_pos, block]
	end

	def assemble(io)
		@objects.each { |obj|
			obj.assemble io, self
		}

		@label_callbacks.each { |data|
			label, io_pos, block = *data
			io.seek io_pos
			block.call io, label.address
		}
	end
end

class AS::AstAssembler
	def initialize(asm_arch)
		@asm_arch = asm_arch

		@symbols = {}
		@pending_linkage = {}

		@asm = AS::Assembler.new
	end

	def load_ast(ast)
		ast.children.each { |cmd|
			if (cmd.is_a?(AS::Parser::LabelNode))
				@asm.add_object object_for_label(cmd.name)
			elsif (cmd.is_a?(AS::Parser::InstructionNode))
				@asm.add_object @asm_arch::Instruction.new(cmd, self)
			elsif (cmd.is_a?(AS::Parser::DirectiveNode))
				if (cmd.name == 'global')
					symbol = @symbols[cmd.value]
					if (symbol)
						symbol[:linkage] = ELF::STB_GLOBAL
					else
						@pending_linkage[cmd.value] = [ELF::STB_GLOBAL, cmd]
					end
				elsif (cmd.name == "hexdata")
					bytes = cmd.value.strip.split(/\s+/).map { |hex|
						hex.to_i(16)
					}.pack('C*')
					@asm.add_object AS::DataObject.new(bytes)
				else
					raise AS::AssemblyError.new('unknown directive', cmd)
				end
			end
		}
	end

	def object_for_label(name)
		if (not @symbols[name])
			@symbols[name] = {:label => AS::LabelObject.new, :linkage => ELF::STB_LOCAL, :name => name}
			if (linkage = @pending_linkage[name])
				@symbols[name][:linkage] = linkage[0]
				@pending_linkage.delete name
			end
		end
		@symbols[name][:label]
	end

	def assemble(io)
		if (not @pending_linkage.empty?)
			first = @pending_linkage.first
			raise AS::AssemblyError.new('cannot change linkage of unknown label', first[1])
		end

		@asm.assemble io
	end

	def symbols
		@symbols.values
	end
end

