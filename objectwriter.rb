require 'elfobject'

module AS; end

class AS::ObjectWriter
	def initialize(target)
		@object = ELF::ObjectFile.new(target)

		sym_strtab = ELF::StringTableSection.new(".strtab")
		@object.add_section sym_strtab
		@symbol_table = ELF::SymbolTableSection.new(".symtab", sym_strtab)
		@object.add_section @symbol_table

		@text = ELF::TextSection.new(".text")
		@object.add_section @text
	end

	def set_text(text)
		@text.text = text
	end

	def add_symbol(name, offset, linkage = ELF::STB_GLOBAL)
		@symbol_table.add_func_symbol name, offset, @text, linkage
	end

	def save(filename)
		File.open(filename, 'wb') { |fp|
			write fp
		}
	end

	def write(io)
		@object.write io
	end
end
