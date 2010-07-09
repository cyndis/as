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
	def initialize(name)
		@name = name
		@linkage = ELF::STB_LOCAL
	end
	attr_accessor :name, :linkage

	def assemble(io, as)
		as.add_symbol self, io.tell
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
	def initialize(asm_arch)
		@asm_arch = asm_arch

		@objects = []

		@label_linkage = {}
		@label_objects = {}
		@label_callbacks = []

		@symbols = {}
	end

	def add_object(obj)
		@objects << obj
	end

	def add_symbol(symbol, addr)
		@symbols[symbol] = addr
	end

	def load_ast(ast)
		ast.children.each { |cmd|
			if (cmd.is_a?(AS::Parser::LabelNode))
				add_object label = AS::LabelObject.new(cmd.name)
				@label_objects[cmd.name] = label
			elsif (cmd.is_a?(AS::Parser::InstructionNode))
				add_object @asm_arch::Instruction.new(cmd)
			elsif (cmd.is_a?(AS::Parser::DirectiveNode))
				if (cmd.name == 'global')
					if (not @label_linkage[cmd.value])
						@label_linkage[cmd.value] = [ELF::STB_GLOBAL, cmd]
					else
						raise AS::AssemblyError.new(
							'cannot change already specified linkage of section',
							cmd
						)
					end
				elsif (cmd.name == "hexdata")
					bytes = cmd.value.strip.split(/\s+/).map { |hex|
						hex.to_i(16)
					}.pack('C*')
					add_object AS::DataObject.new(bytes)
				else
					raise AS::AssemblyError.new('unknown directive', cmd)
				end
			end
		}
	end

	def register_label_callback(label, io_pos, node, &block)
		@label_callbacks << [label, io_pos, block, node]
	end

	def assemble(io)
		@label_linkage.each_pair { |name, data|
			linkage, node = *data
			if (label = @label_objects[name])
				label.linkage = linkage
			else
				raise AS::AssemblyError.new('cannot change linkage of undefined section', node)
			end
		}

		@objects.each { |obj|
			obj.assemble io, self
		}

		@label_callbacks.each { |data|
			label, io_pos, block, node = *data
			if (label_obj = @label_objects[label])
				symbol = @symbols[label_obj]
				io.seek io_pos
				block.call io, symbol
			else
				# trying to resolve label that is not found
				# TODO add to elf relocation table so that
				#      external symbols can be used
				raise AS::AssemblyError.new('cannot resolve address of undefined symbol', node)
			end
		}

		@symbols
	end
end
