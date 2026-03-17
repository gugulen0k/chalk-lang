# frozen_string_literal: true

# :nodoc:
class Token
  attr_reader :lexeme, :line, :literal, :type

  def initialize(lexeme:, literal:, type:, line:)
    @lexeme  = lexeme
    @literal = literal
    @type    = type
    @line    = line
  end
end
