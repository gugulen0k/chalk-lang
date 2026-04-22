# frozen_string_literal: true

require_relative 'lexer'
require_relative 'parser'
require_relative 'type_checker'
require_relative 'codegen'
require_relative 'errors'

# ─────────────────────────────────────────────────────────────
#  Diagnostic renderer
#  Produces output like:
#
#  error[type]: expected 'int', got 'string'
#    --> src/main.sf:12:9
#     |
#  12 |   x: int = 'hello'
#     |            ^^^^^^^ type mismatch here
#     |
#     = hint: change the value to an integer, e.g. 42
# ─────────────────────────────────────────────────────────────
module Diagnostic
  # ANSI helpers
  RED    = "\e[1;31m"
  YELLOW = "\e[1;33m"
  CYAN   = "\e[36m"
  BOLD   = "\e[1m"
  DIM    = "\e[2m"
  RESET  = "\e[0m"

  PHASE_LABEL = {
    lex: 'lex',
    parse: 'parse',
    type: 'type',
    unknown: 'error'
  }.freeze

  def self.render(err, filepath, source)
    lines = source.lines

    phase = PHASE_LABEL[err.phase] || 'error'
    warn "#{RED}error[#{phase}]#{RESET}#{BOLD}: #{err.message}#{RESET}"

    if err.line
      col_info = err.col ? ":#{err.col}" : ''
      warn "  #{CYAN}-->#{RESET} #{filepath}:#{err.line}#{col_info}"

      render_snippet(lines, err)
    end

    warn "  #{YELLOW}= hint:#{RESET} #{err.hint}" if err.hint

    warn ''
  end

  def self.render_snippet(lines, err)
    line_num  = err.line
    src_line  = lines[line_num - 1]
    return unless src_line

    gutter    = line_num.to_s
    pad       = ' ' * gutter.length

    warn "#{pad} #{CYAN}|#{RESET}"
    warn "#{CYAN}#{gutter}#{RESET} #{CYAN}|#{RESET}  #{src_line.rstrip}"

    # Draw the ^^^ underline if we have column + token info
    if err.col
      token_len = err.token&.length || 1
      prefix    = ' ' * (err.col - 1) # spaces before the caret
      carets    = "#{RED}#{'~' * token_len}#{RESET}"
      warn "#{pad} #{CYAN}|#{RESET}  #{prefix}#{carets}"
    else
      warn "#{pad} #{CYAN}|#{RESET}"
    end
  end
  private_class_method :render_snippet
end

# ─────────────────────────────────────────────────────────────
#  Entry point
# ─────────────────────────────────────────────────────────────
src  = ARGV[0] || './examples/hello.sf'
out  = src.sub(/\.sf$/, '.ll')
code = File.read(src)

begin
  lexer = Lexer.new(code)
  lexer.scan_tokens

  ast = Parser.new(lexer.tokens).parse
  TypeChecker.new.check(ast)

  ir = Codegen.new.generate(ast)
  File.write(out, ir)
  puts "[32m\u2714[0m compiled \e[1m#{src}\e[0m  \e[2m→ #{out}\e[0m"
rescue SheftError => e
  Diagnostic.render(e, src, code)
  exit 1
end
