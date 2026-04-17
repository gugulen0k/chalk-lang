# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/PerceivedComplexity, Metrics/BlockLength

require_relative 'ast'
require_relative 'token_type'
require_relative 'errors'

# :nodoc:
class Parser
  COMPARISON_OPS = [
    TokenType::EQUAL_EQUAL, TokenType::BANG_EQUAL,
    TokenType::LESS, TokenType::LESS_EQUAL,
    TokenType::GREATER, TokenType::GREATER_EQUAL
  ].freeze

  def initialize(tokens)
    @tokens = tokens
    @pos    = 0
  end

  def parse
    stmts = []
    skip_newlines
    stmts << parse_statement until at_end?
    AST::Program.new(stmts)
  end

  private

  def current
    @tokens[@pos]
  end

  def peek_type(offset = 0)
    @tokens[@pos + offset]&.type
  end

  def advance
    tok = @tokens[@pos]
    @pos += 1
    tok
  end

  def check(type) # rubocop:disable Naming/PredicateMethod
    current&.type == type
  end

  def expect(type, msg = nil)
    return advance if check(type)

    parse_error(msg || "Expected #{type}, got #{current&.type} '#{current&.lexeme}' at line #{current&.line}")
  end

  def skip_newlines
    advance while check(TokenType::NEWLINE) || check(TokenType::DOC_COMMENT)
  end

  def at_end?
    current&.type == TokenType::EOF
  end

  def parse_error(msg, line: current&.line, hint: nil)
    raise ParseError.new(msg, line: line, hint: hint)
  end

  def expect_newline_or_eof
    if check(TokenType::NEWLINE) || at_end?
      skip_newlines
    else
      parse_error("Expected newline, got #{current&.type} '#{current&.lexeme}' at line #{current&.line}")
    end
  end

  # Read IDENT and optional ! or ? suffix into one name string
  def scan_name
    name = expect(TokenType::IDENT).lexeme
    if check(TokenType::BANG)
      advance
      "#{name}!"
    elsif check(TokenType::QUESTION)
      advance
      "#{name}?"
    else
      name
    end
  end

  # ---------- Statements ----------

  def parse_statement
    skip_newlines
    case current&.type
    when TokenType::MUT, TokenType::IDENT then parse_var_assign_or_expr
    when TokenType::FUNC                  then parse_func_decl
    when TokenType::PUB                   then parse_pub
    when TokenType::RETURN                then parse_return
    when TokenType::IF                    then parse_if
    when TokenType::WHILE                 then parse_while
    when TokenType::FOR                   then parse_for
    when TokenType::MATCH                 then parse_match_stmt
    when TokenType::IMPORT                then parse_import
    when TokenType::CONST                 then parse_const
    when TokenType::RAISE                 then parse_raise
    when TokenType::BREAK                 then parse_break
    when TokenType::SKIP                  then parse_skip
    when TokenType::STRUCT                then parse_struct
    when TokenType::ENUM                  then parse_enum
    when TokenType::ERROR                 then parse_error_decl
    else
      expr = parse_expr
      expect_newline_or_eof
      AST::ExprStmt.new(expr)
    end
  end

  def parse_var_assign_or_expr
    mutable = false
    if check(TokenType::MUT)
      advance
      mutable = true
    end

    if check(TokenType::IDENT) && peek_type(1) == TokenType::COLON
      parse_var_decl(mutable)
    elsif !mutable && check(TokenType::IDENT) && peek_type(1) == TokenType::EQUAL
      ident_tok = advance
      advance # =
      value = parse_expr
      expect_newline_or_eof
      AST::Assign.new(AST::Ident.new(ident_tok.lexeme, ident_tok.line), value)
    else
      expr = parse_expr
      expect_newline_or_eof
      AST::ExprStmt.new(expr)
    end
  end

  def parse_var_decl(mutable)
    name_tok = expect(TokenType::IDENT)
    expect(TokenType::COLON)
    type = parse_type
    expect(TokenType::EQUAL)
    value = parse_expr
    expect_newline_or_eof
    AST::VarDecl.new(mutable, name_tok.lexeme, type, value, name_tok.line)
  end

  def parse_type
    case current&.type
    when TokenType::INT      then advance
                                  :int
    when TokenType::FLOAT    then advance
                                  :float
    when TokenType::STRING   then advance
                                  :string
    when TokenType::BOOL     then advance
                                  :bool
    when TokenType::VOID     then advance
                                  :void
    when TokenType::IDENT    then advance.lexeme
    when TokenType::LBRACKET
      advance
      inner = parse_type
      expect(TokenType::RBRACKET)
      [:array, inner]
    else
      parse_error("Expected type at line #{current&.line}, got #{current&.type}")
    end
  end

  def parse_func_decl(pub: false)
    func_line = current.line
    expect(TokenType::FUNC)
    name        = scan_name
    failable    = name.end_with?('!')
    bool_fn     = name.end_with?('?')
    expect(TokenType::LPAREN)
    params = parse_params
    expect(TokenType::RPAREN)
    expect(TokenType::ARROW)
    return_type = parse_type
    expect_newline_or_eof
    body = parse_block
    expect(TokenType::END_KW)
    expect_newline_or_eof
    AST::FuncDecl.new(pub, name, failable, bool_fn, params, return_type, body, func_line)
  end

  def parse_params
    params = []
    return params if check(TokenType::RPAREN)

    loop do
      pname = expect(TokenType::IDENT).lexeme
      expect(TokenType::COLON)
      ptype = parse_type
      params << AST::Param.new(pname, ptype)
      break unless check(TokenType::COMMA)

      advance
    end
    params
  end

  def parse_block
    stmts = []
    skip_newlines
    until check(TokenType::END_KW) || check(TokenType::ELSE) || at_end?
      stmts << parse_statement
      skip_newlines
    end
    stmts
  end

  def parse_return
    line = current.line
    expect(TokenType::RETURN)
    value = check(TokenType::NEWLINE) || at_end? ? nil : parse_expr
    expect_newline_or_eof
    AST::Return.new(value, line)
  end

  def parse_if
    expect(TokenType::IF)
    condition = parse_expr
    expect_newline_or_eof
    then_body = parse_block
    else_body = nil
    if check(TokenType::ELSE)
      advance
      expect_newline_or_eof
      else_body = parse_block
    end
    expect(TokenType::END_KW)
    expect_newline_or_eof
    AST::If.new(condition, then_body, else_body)
  end

  def parse_while
    expect(TokenType::WHILE)
    condition = parse_expr
    expect_newline_or_eof
    body = parse_block
    expect(TokenType::END_KW)
    expect_newline_or_eof
    AST::While.new(condition, body)
  end

  def parse_for
    expect(TokenType::FOR)
    first = expect(TokenType::IDENT).lexeme
    var, index_var = if check(TokenType::COMMA)
                       advance
                       [expect(TokenType::IDENT).lexeme, first]
                     else
                       [first, nil]
                     end
    expect(TokenType::IN)
    iterable = parse_expr
    expect_newline_or_eof
    body = parse_block
    expect(TokenType::END_KW)
    expect_newline_or_eof
    AST::ForIn.new(var, index_var, iterable, body)
  end

  def parse_match_stmt
    node = parse_match_expr
    expect_newline_or_eof
    AST::ExprStmt.new(node)
  end

  def parse_match_expr
    expect(TokenType::MATCH)
    value = parse_expr
    expect_newline_or_eof
    arms = parse_match_arms
    expect(TokenType::END_KW)
    AST::Match.new(value, arms)
  end

  def parse_match_arms
    arms = []
    skip_newlines
    until check(TokenType::END_KW) || at_end?
      arms << parse_match_arm
      skip_newlines
    end
    arms
  end

  def parse_match_arm
    pattern = nil
    guard   = nil

    if check(TokenType::WITH)
      advance
      name    = expect(TokenType::IDENT).lexeme
      pattern = AST::WithPattern.new(name)
      if check(TokenType::IF)
        advance
        guard = parse_expr
      end
    elsif check(TokenType::IDENT) && peek_type(1) == TokenType::DOT
      enum_name = advance.lexeme
      advance # DOT
      variant = expect(TokenType::IDENT).lexeme
      binding = nil
      if check(TokenType::LPAREN)
        advance
        binding = expect(TokenType::IDENT).lexeme
        expect(TokenType::RPAREN)
        if check(TokenType::IF)
          advance
          guard = parse_expr
        end
      end
      pattern = AST::EnumPattern.new(enum_name, variant, binding)
    elsif check(TokenType::IDENT)
      pattern = AST::IdentPattern.new(advance.lexeme)
    else
      pattern = AST::LiteralPattern.new(parse_primary)
    end

    expect(TokenType::FAT_ARROW)
    body = parse_expr
    expect_newline_or_eof
    AST::MatchArm.new(pattern, guard, body)
  end

  def parse_import
    expect(TokenType::IMPORT)
    path = [expect(TokenType::IDENT).lexeme]
    while check(TokenType::COLON_COLON)
      advance
      if check(TokenType::LBRACE)
        advance
        items = []
        loop do
          items << scan_name
          break unless check(TokenType::COMMA)

          advance
        end
        expect(TokenType::RBRACE)
        expect_newline_or_eof
        return AST::ImportDecl.new(path, nil, items)
      end
      path << expect(TokenType::IDENT).lexeme
    end
    import_alias = nil
    if check(TokenType::AS)
      advance
      import_alias = expect(TokenType::IDENT).lexeme
    end
    expect_newline_or_eof
    AST::ImportDecl.new(path, import_alias, nil)
  end

  def parse_const
    expect(TokenType::CONST)
    name = expect(TokenType::IDENT).lexeme
    expect(TokenType::COLON)
    type = parse_type
    expect(TokenType::EQUAL)
    value = parse_expr
    expect_newline_or_eof
    AST::ConstDecl.new(name, type, value)
  end

  def parse_raise
    expect(TokenType::RAISE)
    expr      = parse_expr
    condition = if check(TokenType::IF)
                  (advance
                   parse_expr)
                end
    expect_newline_or_eof
    AST::Raise.new(expr, condition)
  end

  def parse_break
    expect(TokenType::BREAK)
    condition = if check(TokenType::IF)
                  (advance
                   parse_expr)
                end
    expect_newline_or_eof
    AST::Break.new(condition)
  end

  def parse_skip
    expect(TokenType::SKIP)
    condition = if check(TokenType::IF)
                  (advance
                   parse_expr)
                end
    expect_newline_or_eof
    AST::Skip.new(condition)
  end

  def parse_pub
    advance # pub
    case current&.type
    when TokenType::FUNC   then parse_func_decl(pub: true)
    when TokenType::STRUCT then parse_struct(pub: true)
    when TokenType::ENUM   then parse_enum(pub: true)
    when TokenType::ERROR  then parse_error_decl(pub: true)
    else parse_error("Expected declaration after 'pub' at line #{current&.line}")
    end
  end

  def parse_struct(pub: false)
    expect(TokenType::STRUCT)
    name = expect(TokenType::IDENT).lexeme
    expect_newline_or_eof
    fields    = []
    func_defs = []
    skip_newlines
    until check(TokenType::END_KW) || at_end?
      if check(TokenType::FUNC) || (check(TokenType::PUB) && peek_type(1) == TokenType::FUNC)
        pub_method = check(TokenType::PUB) && advance
        func_defs << parse_func_decl(pub: !pub_method.nil?)
      else
        mutable = false
        if check(TokenType::MUT)
          advance
          mutable = true
        end
        fname = expect(TokenType::IDENT).lexeme
        expect(TokenType::COLON)
        ftype   = parse_type
        default = if check(TokenType::EQUAL)
                    (advance
                     parse_expr)
                  end
        expect_newline_or_eof
        fields << AST::StructField.new(mutable, fname, ftype, default)
      end
      skip_newlines
    end
    expect(TokenType::END_KW)
    expect_newline_or_eof
    AST::StructDecl.new(pub, name, fields, func_defs)
  end

  def parse_enum(pub: false)
    expect(TokenType::ENUM)
    name     = expect(TokenType::IDENT).lexeme
    variants = []
    if check(TokenType::LPAREN)
      advance
      loop do
        variants << AST::EnumVariant.new(expect(TokenType::IDENT).lexeme, nil)
        break unless check(TokenType::COMMA)

        advance
      end
      expect(TokenType::RPAREN)
    else
      expect_newline_or_eof
      skip_newlines
      until check(TokenType::END_KW) || at_end?
        vname = expect(TokenType::IDENT).lexeme
        vtype = if check(TokenType::COLON)
                  (advance
                   parse_type)
                end
        expect_newline_or_eof
        variants << AST::EnumVariant.new(vname, vtype)
        skip_newlines
      end
      expect(TokenType::END_KW)
    end
    expect_newline_or_eof
    AST::EnumDecl.new(pub, name, variants)
  end

  def parse_error_decl(pub: false)
    expect(TokenType::ERROR)
    name     = expect(TokenType::IDENT).lexeme
    variants = []
    if check(TokenType::LPAREN)
      advance
      loop do
        variants << expect(TokenType::IDENT).lexeme
        break unless check(TokenType::COMMA)

        advance
      end
      expect(TokenType::RPAREN)
    else
      expect_newline_or_eof
      skip_newlines
      until check(TokenType::END_KW) || at_end?
        variants << expect(TokenType::IDENT).lexeme
        expect_newline_or_eof
        skip_newlines
      end
      expect(TokenType::END_KW)
    end
    expect_newline_or_eof
    AST::ErrorDecl.new(pub, name, variants)
  end

  # ---------- Expressions ----------

  def parse_expr
    parse_ternary
  end

  def parse_ternary
    expr = parse_or
    return expr unless check(TokenType::QUESTION)

    advance
    then_expr = parse_expr
    expect(TokenType::COLON)
    else_expr = parse_expr
    AST::Ternary.new(expr, then_expr, else_expr)
  end

  def parse_or
    left = parse_and
    while check(TokenType::OR)
      op    = advance.lexeme
      right = parse_and
      left  = AST::BinaryOp.new(op, left, right)
    end
    left
  end

  def parse_and
    left = parse_not
    while check(TokenType::AND)
      op    = advance.lexeme
      right = parse_not
      left  = AST::BinaryOp.new(op, left, right)
    end
    left
  end

  def parse_not
    return AST::UnaryOp.new(advance.lexeme, parse_not) if check(TokenType::NOT)

    parse_comparison
  end

  def parse_comparison
    left = parse_addition
    while COMPARISON_OPS.include?(current&.type)
      op    = advance.lexeme
      right = parse_addition
      left  = AST::BinaryOp.new(op, left, right)
    end
    left
  end

  def parse_addition
    left = parse_multiplication
    while check(TokenType::PLUS) || check(TokenType::MINUS)
      op    = advance.lexeme
      right = parse_multiplication
      left  = AST::BinaryOp.new(op, left, right)
    end
    left
  end

  def parse_multiplication
    left = parse_unary
    while check(TokenType::STAR) || check(TokenType::SLASH) || check(TokenType::PERCENT)
      op    = advance.lexeme
      right = parse_unary
      left  = AST::BinaryOp.new(op, left, right)
    end
    left
  end

  def parse_unary
    return AST::UnaryOp.new(advance.lexeme, parse_unary) if check(TokenType::MINUS)
    return AST::Try.new(parse_unary) if check(TokenType::TRY)

    parse_postfix
  end

  def parse_postfix
    expr = parse_primary

    loop do
      if check(TokenType::DOT)
        advance
        name = scan_name
        if check(TokenType::LPAREN)
          advance
          args = parse_args
          expect(TokenType::RPAREN)
          expr = AST::MethodCall.new(expr, name, args)
        else
          expr = AST::FieldAccess.new(expr, name)
        end
      elsif check(TokenType::LBRACKET)
        advance
        index = parse_expr
        expect(TokenType::RBRACKET)
        expr = AST::IndexAccess.new(expr, index)
      elsif check(TokenType::COLON_COLON)
        advance
        part = expect(TokenType::IDENT).lexeme
        parts = if expr.is_a?(AST::PathExpr)
                  expr.parts + [part]
                else
                  [expr.is_a?(AST::Ident) ? expr.name : expr, part]
                end
        expr = AST::PathExpr.new(parts)
      else
        break
      end
    end

    if check(TokenType::DOT_DOT)
      advance
      return AST::Range.new(expr, parse_addition, false)
    elsif check(TokenType::DOT_DOT_EQUAL)
      advance
      return AST::Range.new(expr, parse_addition, true)
    end

    if check(TokenType::CATCH)
      advance
      return AST::Catch.new(expr, parse_expr) unless check(TokenType::NEWLINE)

      expect_newline_or_eof
      arms = parse_match_arms
      expect(TokenType::END_KW)
      return AST::Catch.new(expr, AST::CatchBlock.new(arms))

    end

    expr
  end

  def parse_primary
    case current&.type
    when TokenType::INT_LIT    then AST::IntLit.new(advance.literal)
    when TokenType::FLOAT_LIT  then AST::FloatLit.new(advance.literal)
    when TokenType::STRING_LIT then AST::StringLit.new(advance.literal)
    when TokenType::TRUE       then advance
                                    AST::BoolLit.new(true)
    when TokenType::FALSE      then advance
                                    AST::BoolLit.new(false)
    when TokenType::LPAREN
      advance
      expr = parse_expr
      expect(TokenType::RPAREN)
      expr
    when TokenType::LBRACKET
      advance
      if check(TokenType::RESERVE)
        advance
        cap = parse_expr
        expect(TokenType::RBRACKET)
        AST::ArrayReserve.new(cap)
      elsif check(TokenType::RBRACKET)
        advance
        AST::ArrayLit.new([])
      else
        elems = [parse_expr]
        while check(TokenType::COMMA)
          advance
          elems << parse_expr
        end
        expect(TokenType::RBRACKET)
        AST::ArrayLit.new(elems)
      end
    when TokenType::IDENT
      ident_tok = advance
      name      = ident_tok.lexeme
      line      = ident_tok.line
      if check(TokenType::BANG)
        advance
        name += '!'
      elsif check(TokenType::QUESTION)
        advance
        name += '?'
      end
      if check(TokenType::LPAREN)
        advance
        args = parse_args
        expect(TokenType::RPAREN)
        AST::Call.new(AST::Ident.new(name, line), args, line)
      elsif check(TokenType::LBRACE)
        advance
        fields = []
        until check(TokenType::RBRACE)
          fname = expect(TokenType::IDENT).lexeme
          expect(TokenType::COLON)
          fval = parse_expr
          fields << [fname, fval]
          advance if check(TokenType::COMMA)
        end
        expect(TokenType::RBRACE)
        AST::StructLit.new(name, fields)
      else
        AST::Ident.new(name, line)
      end
    when TokenType::MATCH
      parse_match_expr
    else
      parse_error("Unexpected token #{current&.type} '#{current&.lexeme}' at line #{current&.line}")
    end
  end

  def parse_args
    args = []
    return args if check(TokenType::RPAREN)

    args << parse_expr
    while check(TokenType::COMMA)
      advance
      args << parse_expr
    end
    args
  end
end

# rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/PerceivedComplexity, Metrics/BlockLength
