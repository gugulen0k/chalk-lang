# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/PerceivedComplexity

require_relative 'token_type'
require_relative 'token'

# :nodoc:
class Lexer
  attr_reader :tokens

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
    ' ' => -> {},
    "\r" => -> {},
    "\t" => -> {},
    "\n" => lambda {
      @line += 1
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
    end,
    '/' => -> { add_token(type: TokenType::SLASH) },
    '?' => -> { add_token(type: TokenType::QUESTION) },
    "'" => -> { scan_string(fstring: false) }
  }.freeze

  KEYWORDS = {
    'func' => TokenType::FUNC,
    'return' => TokenType::RETURN,
    'if' => TokenType::IF,
    'else' => TokenType::ELSE,
    'end' => TokenType::END_KW,
    'while' => TokenType::WHILE,
    'for' => TokenType::FOR,
    'in' => TokenType::IN,
    'break' => TokenType::BREAK,
    'skip' => TokenType::SKIP,
    'match' => TokenType::MATCH,
    'with' => TokenType::WITH,
    'mut' => TokenType::MUT,
    'pub' => TokenType::PUB,
    'struct' => TokenType::STRUCT,
    'enum' => TokenType::ENUM,
    'error' => TokenType::ERROR,
    'import' => TokenType::IMPORT,
    'from' => TokenType::FROM,
    'as' => TokenType::AS,
    'const' => TokenType::CONST,
    'raise' => TokenType::RAISE,
    'try' => TokenType::TRY,
    'catch' => TokenType::CATCH,
    'and' => TokenType::AND,
    'or' => TokenType::OR,
    'not' => TokenType::NOT,
    'reserve' => TokenType::RESERVE,
    'true' => TokenType::TRUE,
    'false' => TokenType::FALSE,
    'int' => TokenType::INT,
    'float' => TokenType::FLOAT,
    'string' => TokenType::STRING,
    'bool' => TokenType::BOOL,
    'void' => TokenType::VOID
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
    character = advance
    possible_token = POSSIBLE_TOKENS[character]

    if possible_token
      instance_exec(&possible_token)
    elsif alpha?(character)
      scan_identifier_or_keyword(character)
    elsif digit?(character)
      scan_number(character)
    else
      print_error(character)
    end
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

  def peek_ahead(number)
    pos = @current + number
    return nil if pos >= @source.size

    @source[pos]
  end

  def match?(character)
    return false unless character == peek

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

  def scan_identifier_or_keyword(first_char)
    # 'f' followed by "'" is an f-string, not an identifier
    if first_char == 'f' && peek == "'"
      advance # consume the opening quote
      scan_string(fstring: true)
      return
    end

    advance while alphanumeric?(peek)
    text = @source[@start...@current]
    type = KEYWORDS[text] || TokenType::IDENT
    add_token(type: type)
  end

  def scan_number(first_char)
    # Detect base prefix: 0x, 0b, 0o
    if first_char == '0'
      case peek
      when 'x', 'X'
        advance
        advance while @source[@current]&.match?(/[0-9a-fA-F_]/)
        return add_token(type: TokenType::INT_LIT, literal: @source[@start...@current].to_i(16))
      when 'b', 'B'
        advance
        advance while @source[@current]&.match?(/[01_]/)
        return add_token(type: TokenType::INT_LIT, literal: @source[@start...@current].to_i(2))
      when 'o', 'O'
        advance
        advance while @source[@current]&.match?(/[0-7_]/)
        return add_token(type: TokenType::INT_LIT, literal: @source[@start...@current].to_i(8))
      end
    end

    advance while digit?(peek) || peek == '_'

    is_float = peek == '.' && digit?(peek_ahead(1))
    if is_float
      advance # consume '.'
      advance while digit?(peek) || peek == '_'
    end

    # Scientific notation: e or E followed by optional sign and digits
    if peek&.match?(/[eE]/) && (digit?(peek_ahead(1)) || (peek_ahead(1)&.match?(/[+-]/) && digit?(peek_ahead(2))))
      advance # e/E
      advance if peek&.match?(/[+-]/)
      advance while digit?(peek)
      is_float = true
    end

    raw = @source[@start...@current].delete('_')
    if is_float
      add_token(type: TokenType::FLOAT_LIT, literal: raw.to_f)
    else
      add_token(type: TokenType::INT_LIT, literal: raw.to_i)
    end
  end

  def scan_string(fstring:)
    # Triple-quote check
    if peek == "'" && peek_ahead(1) == "'"
      advance
      advance
      scan_triple_string(fstring: fstring)
      return
    end

    str_start = @current
    loop do
      return print_error('unterminated string') if at_end? || peek == "\n"

      ch = advance
      break if ch == "'"
    end

    literal = @source[str_start...(@current - 1)]
    add_token(type: TokenType::STRING_LIT, literal: literal)
  end

  def scan_triple_string(fstring: false) # rubocop:disable Lint/UnusedMethodArgument
    str_start = @current
    loop do
      return print_error('unterminated triple-quoted string') if at_end?

      @line += 1 if peek == "\n"

      if peek == "'" && peek_ahead(1) == "'" && peek_ahead(2) == "'"
        literal = @source[str_start...@current]
        advance
        advance
        advance
        # Strip leading/trailing newlines per spec
        literal = literal.delete_prefix("\n").delete_suffix("\n")
        add_token(type: TokenType::STRING_LIT, literal: literal)
        return
      end

      advance
    end
  end

  def scan_doc_comment
    doc_start = @current

    advance until at_end? || (peek == ']' && peek_ahead(1) == '#' && peek_ahead(2) == '#')

    return print_error('unterminated doc comment') if at_end?

    advance # ]
    advance # #
    advance # #

    doc_literal = @source[doc_start...(@current - 3)]

    add_token(type: TokenType::DOC_COMMENT, literal: doc_literal)
  end

  def scan_multiline_comment
    advance until at_end? || (peek == ']' && peek_ahead(1) == '#')

    return print_error('unterminated multiline comment') if at_end?

    advance # ]
    advance # #
  end

  def scan_line_comment
    advance while peek != "\n" && !at_end?
  end
end
# rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/PerceivedComplexity
