# frozen_string_literal: true

# :nodoc:
class Token
  attr_reader :lexeme, :line, :literal, :type

  def initialize(args)
    @lexeme  = args[:lexeme]
    @literal = args[:literal]
    @type    = args[:type]
    @line    = args[:line]
  end
end
