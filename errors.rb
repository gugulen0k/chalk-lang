# frozen_string_literal: true

# Base error for all compiler-produced diagnostics.
# Every error carries:
#   message  — what went wrong (plain English, no jargon)
#   line     — 1-based source line number
#   col      — 1-based column of the token that triggered the error (optional)
#   token    — the offending lexeme, used to draw the ^^^ underline (optional)
#   hint     — a short actionable suggestion shown below the source snippet
#   phase    — which compiler phase raised this (:lex, :parse, :type)
class SheftError < StandardError
  attr_reader :line, :col, :token, :hint, :phase

  def initialize(msg, line: nil, col: nil, token: nil, hint: nil, phase: :unknown)
    super(msg)
    @line  = line
    @col   = col
    @token = token
    @hint  = hint
    @phase = phase
  end
end

class LexError       < SheftError; end
class ParseError     < SheftError; end
class TypeCheckError < SheftError; end
