# frozen_string_literal: true

# rubocop:disable Style/OneClassPerFile

# :nodoc:
class SheftError < StandardError
  attr_reader :line, :hint

  def initialize(msg, line: nil, hint: nil)
    super(msg)
    @line = line
    @hint = hint
  end
end

class ParseError     < SheftError; end
class TypeCheckError < SheftError; end

# rubocop:enable Style/OneClassPerFile
