# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/PerceivedComplexity

require_relative 'token_type'
require_relative 'token'
require_relative 'errors'

# :nodoc:
class Lexer
  attr_reader :tokens

  POSSIBLE_TOKENS = {
    '+' => -> { add_token(type: TokenType::PLUS) },
    '*' => -> { add_token(type: TokenType::STAR) },
    '(' => -> { add_token(type: TokenType::LPAREN) },
    ')' => -> { add_token(type: TokenType::RPAREN) },
    ',' => -> { add_token(type: TokenType::COMMA) },
    ' ' => -> {},
    "\r" => -> {},
    "\t" => -> {},
    "\n" => lambda {
      @line += 1
      @line_start = @current
      add_token(type: TokenType::NEWLINE)
    },
    '#' => lambda do
      if match?('#')
        match?('[') ? scan_doc_comment : scan_line_comment
      elsif match?('[')
        scan_multiline_comment
      else
        scan_line_comment
      end
    end,
    '.' => -> { add_token(type: TokenType::DOT) },
    ':' => -> { add_token(type: TokenType::COLON) },
    '>' => lambda do
      match?('=') ? add_token(type: TokenType::GREATER_EQUAL) : add_token(type: TokenType::GREATER)
    end,
    '<' => lambda do
      match?('=') ? add_token(type: TokenType::LESS_EQUAL) : add_token(type: TokenType::LESS)
    end,
    '=' => lambda do
      match?('=') ? add_token(type: TokenType::EQUAL_EQUAL) : add_token(type: TokenType::EQUAL)
    end,
    # ! is only valid as != — standalone ! is not valid Sheft syntax
    '!' => lambda do
      if match?('=')
        add_token(type: TokenType::BANG_EQUAL)
      else
        lex_error("unexpected character '!'", hint: "did you mean '!='? standalone '!' is not valid in Sheft")
      end
    end,
    '-' => lambda do
      match?('>') ? add_token(type: TokenType::ARROW) : add_token(type: TokenType::MINUS)
    end,
    '/' => -> { add_token(type: TokenType::SLASH) },
    # ' opens a string literal — double quotes are a compile error in Sheft
    "'" => -> { scan_string },
    '"' => lambda do
      lex_error('strings use single quotes in Sheft', hint: "replace \" with '")
    end
  }.freeze

  KEYWORDS = {
    'func' => TokenType::FUNC,
    'return' => TokenType::RETURN,
    'if' => TokenType::IF,
    'else' => TokenType::ELSE,
    'end' => TokenType::END_KW,
    'while' => TokenType::WHILE,
    'mut' => TokenType::MUT,
    'pub' => TokenType::PUB,
    'error' => TokenType::ERROR,
    'raise' => TokenType::RAISE,
    'try' => TokenType::TRY,
    'and' => TokenType::AND,
    'or' => TokenType::OR,
    'not' => TokenType::NOT,
    'true' => TokenType::TRUE,
    'false' => TokenType::FALSE,
    'int' => TokenType::INT,
    'float' => TokenType::FLOAT,
    'string' => TokenType::STRING,
    'bool' => TokenType::BOOL,
    'void' => TokenType::VOID
  }.freeze

  def initialize(source)
    @source     = source
    @start      = 0
    @current    = 0
    @line       = 1
    @line_start = 0 # tracks the index where the current line began
    @tokens     = []
  end

  def scan_tokens
    until at_end?
      @start = @current
      scan_token
    end

    @tokens.push(Token.new(type: TokenType::EOF, lexeme: '', literal: nil, line: @line))
    @tokens
  end

  private

  def scan_token
    character = advance
    handler   = POSSIBLE_TOKENS[character]

    if handler
      instance_exec(&handler)
    elsif alpha?(character)
      scan_identifier_or_keyword
    elsif digit?(character)
      scan_number
    else
      lex_error("unexpected character '#{character}'")
    end
  end

  def add_token(type:, literal: nil)
    lexeme = @source[@start...@current]
    col    = @start - @line_start + 1
    @tokens.push(Token.new(type: type, lexeme: lexeme, literal: literal, line: @line, col: col))
  end

  # Raises a LexError with source location attached.
  def lex_error(msg, hint: nil)
    col = @start - @line_start + 1
    raise LexError.new(msg, line: @line, col: col, hint: hint)
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

  def peek_ahead(number)
    pos = @current + number
    return nil if pos >= @source.size

    @source[pos]
  end

  def match?(expected)
    return false if at_end?
    return false if @source[@current] != expected

    @current += 1
    true
  end

  def at_end?
    @current >= @source.size
  end

  def alpha?(char)
    char&.match?(/[a-zA-Z_]/)
  end

  def digit?(char)
    char&.match?(/[0-9]/)
  end

  def alphanumeric?(char)
    alpha?(char) || digit?(char)
  end

  # Scans an identifier or keyword.
  # Identifiers in Sheft may end with a single ! or ? suffix:
  #   empty?   tokenize!
  # The suffix is consumed as part of the lexeme — no standalone BANG/QUESTION tokens.
  def scan_identifier_or_keyword
    advance while alphanumeric?(peek)
    match?('!') || match?('?')

    text = @source[@start...@current]
    type = KEYWORDS[text] || TokenType::IDENT
    add_token(type: type)
  end

  def scan_number
    advance while digit?(peek)

    if peek == '.' && digit?(peek_ahead(1))
      advance
      advance while digit?(peek)
      add_token(type: TokenType::FLOAT_LIT, literal: @source[@start...@current].to_f)
    else
      add_token(type: TokenType::INT_LIT, literal: @source[@start...@current].to_i)
    end
  end

  # Single-quoted string literal. Double quotes raise a LexError.
  def scan_string
    while peek != "'" && !at_end?
      if peek == "\n"
        @line += 1
        @line_start = @current + 1
      end
      advance
    end

    lex_error('unterminated string literal', hint: "add a closing ' to end the string") if at_end?

    advance # closing '
    value = @source[(@start + 1)...(@current - 1)]
    add_token(type: TokenType::STRING_LIT, literal: value)
  end

  def scan_line_comment
    advance while peek != "\n" && !at_end?
  end

  def scan_multiline_comment
    depth = 1
    until at_end?
      if peek == '#' && peek_ahead(1) == '['
        advance
        advance
        depth += 1
      elsif peek == ']' && peek_ahead(1) == '#'
        advance
        advance
        depth -= 1
        break if depth.zero?
      else
        if peek == "\n"
          @line += 1
          @line_start = @current + 1
        end
        advance
      end
    end
  end

  def scan_doc_comment
    content = +''
    until at_end?
      if peek == ']' && peek_ahead(1) == '#' && peek_ahead(2) == '#'
        advance
        advance
        advance
        break
      end
      content << advance
    end
    add_token(type: TokenType::DOC_COMMENT, literal: content.strip)
  end
end

# rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/PerceivedComplexity
