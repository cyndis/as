module AS; end

if (not defined? RUBY_ENGINE or not RUBY_ENGINE == 'rbx')
	class Regexp
		def match_start(str, idx)
			Regexp.compile('\A(?:'+source+')').match(str[idx..-1])
		end
	end
end

class AS::Scanner
	def initialize(str)
		@string = str
		@pos = 0
		@line = 0
		@column = 0
	end
	attr_accessor :string, :pos, :line, :column, :prev_line, :prev_column

	def rest
		string[pos..-1]
	end

	def advance_str(str)
		self.prev_line = line
		self.prev_column = column
		self.pos += str.length
		self.line += str.count("\n")
		if (str.include?("\n"))
			self.column = str.length - str.rindex("\n")
		else
			self.column += str.length
		end
	end

	def scan(regexp)
		if (match = regexp.match_start(rest, 0))
			advance_str match.to_s
			match.captures
		else
			nil
		end
	end

	def scan_str(regexp)
		if (match = regexp.match_start(rest, 0))
			advance_str match.to_s
			match.to_s
		else
			nil
		end
	end

	def lookahead(regexp)
		if (match = regexp.match_start(rest, 0))
			true
		else
			false
		end
	end

	def eos?
		pos == string.length
	end
end
