# frozen_string_literal: true

require_relative './token_type'
require_relative './token'

# :nodoc:
class Lexer
  POSSIBLE_TOKENS = {
    '+' => -> { add_token(type: TokenType::PLUS) },
    '*' => -> { add_token(type: TokenType::STAR) },
    '%' => -> { add_token(type: TokenType::PERCENT) },
    '(' => -> { add_token(type: TokenType::LPAREN) },
    ')' => -> { add_token(type: TokenType::RPAREN) },
    '[' => -> { add_token(type: TokenType::LBRACKET) },
    ']' => -> { add_token(type: TokenType::RBRACKET) },
    '{' => -> { add_token(type: TokenType::LBRACE) },
    '}' => -> { add_token(type: TokenType::RBRACE) },
    ',' => -> { add_token(type: TokenType::COMMA) },
    ' ' => -> { nil },
    "\r" => -> { nil },
    "\t" => -> { nil },
    "\n" => lambda {
      @line += 1
      add_token(type: TokenType::NEWLINE)
    },
    '.' => lambda do
      if match?('.')
        match?('=') ? add_token(type: TokenType::DOT_DOT_EQUAL) : add_token(type: TokenType::DOT_DOT)
      else
        add_token(type: TokenType::DOT)
      end
    end,
    ':' => lambda do
      match?(':') ? add_token(type: TokenType::COLON_COLON) : add_token(type: TokenType::COLON)
    end,
    '>' => lambda do
      match?('=') ? add_token(type: TokenType::GREATER_EQUAL) : add_token(type: TokenType::GREATER)
    end,
    '<' => lambda do
      match?('=') ? add_token(type: TokenType::LESS_EQUAL) : add_token(type: TokenType::LESS)
    end,
    '=' => lambda do
      if match?('=')
        add_token(type: TokenType::EQUAL_EQUAL)
      else
        match?('>') ? add_token(type: TokenType::FAT_ARROW) : add_token(type: TokenType::EQUAL)
      end
    end,
    '!' => lambda do
      match?('=') ? add_token(type: TokenType::BANG_EQUAL) : add_token(type: TokenType::BANG)
    end,
    '-' => lambda do
      match?('>') ? add_token(type: TokenType::ARROW) : add_token(type: TokenType::MINUS)
    end
  }.freeze

  def initialize(source)
    @source = source
    @start = 0
    @current = 0
    @line = 1
    @tokens = []
  end

  def scan_tokens
    until at_end?
      @start = @current

      scan_token
    end

    eof_token = Token.new(type: TokenType::EOF, lexeme: '', literal: nil, line: @line)
    @tokens.push(eof_token)

    @tokens
  end

  private

  def scan_token
    # +  -  *  %  (  )  [  ]  {  }  ,  :
    character = advance
    possible_token = POSSIBLE_TOKENS[character]

    possible_token ? possible_token.call : print_error(character)
  end

  def add_token(type:, literal: nil)
    lexeme = @source[@start...@current]
    token  = Token.new(lexeme: lexeme, type: type, literal: literal, line: @line)

    @tokens.push(token)
  end

  def print_error(character)
    puts "[line ##{@line}] Unexpected character '#{character}'"
  end

  def advance
    char = @source[@current]
    @current += 1
    char
  end

  def peek
    return nil if at_end?

    @source[@current]
  end

  def match?(character)
    return false unless character == peek

    @current += 1
    true
  end

  def at_end?
    @current >= @source.size
  end
end
