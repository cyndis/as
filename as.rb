require_relative 'parser'
require_relative 'assembler'
require_relative 'objectwriter'
require 'optparse'
require 'ostruct'

module AS
end

class AS::CommandLine
  def initialize
    options = OpenStruct.new
    options.output_file = "a.out"
    options.target = :arm

    opts = OptionParser.new do |opts|
      opts.banner = "Usage: as [options] <input file>"

      opts.separator ""
      opts.separator "Options:"

      opts.on("-t", "--target TARGET",
              "Specify target architecture (arm [default], ttk91)") { |o|
        options.target = o.to_sym
        if (not [:arm, :ttk91].include?(options.target))
          puts opts
          exit
        end
      }

      opts.on("-o", "--output FILENAME",
              "Specify output filename for object file") { |o|
        options.output_file = o
      }

      opts.on("-s", "--show-ast",
              "Show parse tree") { |o|
        options.show_ast = true
      }

      opts.on_tail("-h", "--help", "Show this message") {
        puts opts
        exit
      }
    end

    opts.parse!(ARGV)

    options.input_file = ARGV.shift
    if (not options.input_file)
      puts opts
      exit
    end

    @options = options
  end
  attr_reader :options

  def run
    begin
      if (options.input_file == '-')
        code = $stdin.read
      else
        code = File.read(options.input_file)
      end
    rescue => err
      puts 'as: could not read input file: ' + err.message
      exit 2
    end

    begin
      ast = AS::Parser.parse(code)
    rescue AS::ParseError => err
      puts 'as: parse error on line %d, column %d' % [err.line+1, err.column+1]
      line = code.split("\n")[err.line]
      puts line.gsub(/\s/, ' ')
      puts ' ' * (err.column-1) + '^'
      puts '  ' + err.message
      exit 3
    end

    if (options.show_ast)
      require 'pp'
      pp ast
      exit 0
    end
    
    case options.target
    when :arm
      require_relative 'arm_assembler.rb'
      as_module = AS::ARM
      as_target = ELF::TARGET_ARM
    when :ttk91
      require_relative 'ttk91_assembler.rb'
      as_module = AS::TTK91
      as_target = ELF::TARGET_TTK91
    end

    asm = AS::AstAssembler.new(as_module)
    begin
      asm.load_ast ast
      data = StringIO.new
      asm.assemble(data)
      symbols = asm.symbols
    rescue AS::AssemblyError => err
      if (err.node)
        puts 'as: assembly error on line %d, column %d' % [
          err.node.line+1, err.node.column+1]
        line = code.split("\n")[err.node.line]
        puts line.gsub(/\s/, ' ')
        puts ' ' * (err.node.column-1) + '^'
        puts '  ' + err.message
      else
        puts 'as: ' + err.message
      end
      exit 4
    end

    writer = AS::ObjectWriter.new(as_target)
    writer.set_text data.string

    reloc_name_ref = {}

    symbols.each { |symbol|
      label = symbol[:label]
      if (label.extern?)
        reloc_name_ref[label] = symbol[:name]
        writer.add_reloc_symbol symbol[:name]
      else
        writer.add_symbol symbol[:name], symbol[:label].address, symbol[:linkage]
      end
    }

    asm.relocations.each { |reloc|
      writer.add_reloc reloc.position, reloc_name_ref[reloc.label], reloc.type
    }

    begin
      writer.save(options.output_file)
    rescue => err
      puts 'as: cannot save output file: ' + err.message
    end
  end
end

if (__FILE__ == $0)
  AS::CommandLine.new.run
end
