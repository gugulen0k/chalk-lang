# frozen_string_literal: true

require_relative 'lexer'
require_relative 'parser'
require_relative 'type_checker'
require_relative 'codegen'
require_relative 'errors'

src      = ARGV[0] || './examples/test.sf'
out      = src.sub(/\.sf$/, '.ll')
raw_code = File.read(src)

def render_source_line(err, lines)
  src_line = lines[err.line - 1]
  return unless src_line

  gutter = err.line.to_s
  pad    = ' ' * gutter.length
  warn "#{pad} \e[36m|\e[0m"
  warn "#{gutter} \e[36m|\e[0m  #{src_line.rstrip}"
  warn "#{pad} \e[36m|\e[0m"
end

def render_error(err, src, raw_code)
  warn "\e[1;31merror:\e[0m \e[1m#{err.message}\e[0m"

  if err.line
    warn "  \e[36m-->\e[0m #{src}:#{err.line}"
    render_source_line(err, raw_code.lines)
  end

  warn "  \e[33m= hint:\e[0m #{err.hint}" if err.hint
  warn ''
end

begin
  lexer = Lexer.new(raw_code)
  lexer.scan_tokens

  ast = Parser.new(lexer.tokens).parse
  TypeChecker.new.check(ast)

  ir = Codegen.new.generate(ast)
  File.write(out, ir)
  puts "Written: #{out}"
rescue SheftError => e
  render_error(e, src, raw_code)
  exit 1
end
