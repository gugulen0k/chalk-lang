# frozen_string_literal: true

require_relative './lexer'
require_relative './parser'
require_relative './type_checker'
require_relative './codegen'

src  = ARGV[0] || './examples/test.sf'
out  = src.sub(/\.sf$/, '.ll')

raw_code = File.read(src)

lexer = Lexer.new(raw_code)
lexer.scan_tokens

ast = Parser.new(lexer.tokens).parse

TypeChecker.new.check(ast)

ir = Codegen.new.generate(ast)
File.write(out, ir)
puts "Written: #{out}"
