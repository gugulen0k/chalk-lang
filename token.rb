# frozen_string_literal: true

# :nodoc:
class Token
  attr_reader :type, :lexeme, :literal, :line, :col

  def initialize(type:, lexeme:, literal:, line:, col: nil)
    @type    = type
    @lexeme  = lexeme
    @literal = literal
    @line    = line
    @col     = col
  end

  def to_s
    @lexeme
  end
end
