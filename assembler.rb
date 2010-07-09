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

class Numeric
	def fits_u8?
		self >= 0 and self <= 255
	end
end

class AS::Section
	def initialize(name, contents)
		@name = name
		@contents = contents
		@linkage = ELF::STB_LOCAL
	end
	attr_accessor :name, :contents, :linkage

	def assemble(io, as)
		contents.each { |cont|
			cont.assemble io, as
		}
	end
end

class AS::Assembler
	def initialize(asm_arch)
		@asm_arch = asm_arch

		@sections = []
		new_section "as_toplevel"

		@section_linkage = {}
	end

	def new_section(name)
		sec = AS::Section.new(name, [])
		@sections << @current_section = sec
	end

	def load_ast(ast)
		ast.children.each { |cmd|
			if (cmd.is_a?(AS::Parser::LabelNode))
				new_section cmd.name
			elsif (cmd.is_a?(AS::Parser::InstructionNode))
				@current_section.contents << @asm_arch::Instruction.new(cmd)
			elsif (cmd.is_a?(AS::Parser::DirectiveNode))
				if (cmd.name == 'global')
					if (not @section_linkage[cmd.value])
						@section_linkage[cmd.value] = [ELF::STB_GLOBAL, cmd]
					else
						raise AS::AssemblyError.new(
							'cannot change already specified linkage of section',
							cmd
						)
					end
				else
					raise AS::AssemblyError.new('unknown directive', cmd)
				end
			end
		}
	end

	def assemble(io)
		@section_linkage.each_pair { |name, data|
			linkage, node = *data
			if (sec = @sections.find { |sec| sec.name == name })
				sec.linkage = linkage
			else
				raise AS::AssemblyError.new('cannot change linkage of undefined section', node)
			end
		}

		addr_table = {}
		@sections.each { |section|
			addr_table[section] = io.tell unless section.name == "as_toplevel"
			section.assemble io, self
		}
		addr_table
	end
end
