# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/PerceivedComplexity

require_relative 'ast'
require_relative 'errors'

# :nodoc:
class TypeChecker
  BUILTINS = {
    'println'  => [:func, [:string], :void,   false],
    'print'    => [:func, [:string], :void,   false],
    'readline' => [:func, [],        :string, false],
    'exit'     => [:func, [:int],    :void,   false]
  }.freeze

  ARITHMETIC_OPS = %w[+ - * /].freeze
  COMPARISON_OPS = %w[== != < <= > >=].freeze
  LOGICAL_OPS    = %w[and or].freeze

  def initialize
    @scopes       = [{}]
    @funcs        = BUILTINS.dup
    @errors       = {}
    @current_func = nil
  end

  def check(program)
    program.stmts.each { |s| hoist(s) }
    program.stmts.each { |s| check_stmt(s) }
  end

  private

  # ---- Scope ----

  def push_scope = @scopes.push({})
  def pop_scope  = @scopes.pop

  def define(name, type)
    @scopes.last[name] = type
  end

  def lookup(name)
    @scopes.reverse_each { |s| return s[name] if s.key?(name) }
    nil
  end

  def all_names
    @scopes.flat_map(&:keys) + @funcs.keys
  end

  def error(msg, line: nil, col: nil, token: nil, hint: nil)
    raise TypeCheckError.new(msg, line: line, col: col, token: token, hint: hint, phase: :type)
  end

  # ---- Fuzzy name matching (for "did you mean?" suggestions) ----

  def closest_match(target, candidates)
    best = candidates.min_by { |c| levenshtein(target.downcase, c.downcase) }
    dist = levenshtein(target.downcase, best.downcase)
    dist <= [target.length / 2, 3].max ? best : nil
  end

  def levenshtein(a, b)
    return b.length if a.empty?
    return a.length if b.empty?

    prev = (0..b.length).to_a
    a.each_char.with_index(1) do |ca, i|
      curr = [i]
      b.each_char.with_index(1) do |cb, j|
        curr << [prev[j] + 1, curr.last + 1, prev[j - 1] + (ca == cb ? 0 : 1)].min
      end
      prev = curr
    end
    prev.last
  end

  # ---- First-pass hoisting ----

  def hoist(node)
    case node
    when AST::FuncDecl
      param_types = node.params.map { |p| resolve_type(p.type) }
      @funcs[node.name] = [:func, param_types, resolve_type(node.return_type), node.failable]
    when AST::ErrorDecl
      @errors[node.name] = node.variants
    end
  end

  def resolve_type(annotation)
    return annotation if annotation.is_a?(Symbol)
    annotation
  end

  # ---- Statements ----

  def check_stmt(node)
    case node
    when AST::VarDecl   then check_var_decl(node)
    when AST::Assign    then check_assign(node)
    when AST::FuncDecl  then check_func_decl(node)
    when AST::Return    then check_return(node)
    when AST::If        then check_if(node)
    when AST::While     then check_while(node)
    when AST::ExprStmt  then check_expr(node.expr)
    when AST::Raise     then check_raise(node)
    when AST::ErrorDecl then nil # hoisted above
    else
      error("unknown statement '#{node.class}'")
    end
  end

  def check_var_decl(node)
    declared = resolve_type(node.type)
    actual   = check_expr(node.value)
    unify!(declared, actual, "variable '#{node.name}'", line: node.line)
    define(node.name, declared)
  end

  def check_assign(node)
    target_name = node.target.is_a?(AST::Ident) ? node.target.name : nil
    unless target_name
      error("invalid assignment target", line: node.target&.line)
    end

    target_type = lookup(target_name)
    unless target_type
      hint = closest_match(target_name, all_names)
      error("undefined variable '#{target_name}'",
            line: node.target.line,
            hint: hint ? "did you mean '#{hint}'?" : "declare it first: '#{target_name}: <type> = <value>'")
    end

    actual = check_expr(node.value)
    unify!(target_type, actual, "assignment to '#{target_name}'", line: node.target.line)
  end

  def check_func_decl(node)
    prev_func     = @current_func
    @current_func = @funcs[node.name]
    push_scope
    node.params.each { |p| define(p.name, resolve_type(p.type)) }
    node.body.each   { |s| check_stmt(s) }
    pop_scope
    @current_func = prev_func

    ret = resolve_type(node.return_type)
    return unless ret != :void && !body_returns?(node.body)

    error("function '#{node.name}' must return a '#{ret}' value but has no return statement",
          line: node.line,
          hint: "add 'return <value>' before 'end', or change the return type to 'void'")
  end

  def body_returns?(stmts)
    stmts.any? do |s|
      case s
      when AST::Return then true
      when AST::If     then body_returns?(s.then_body) && s.else_body && body_returns?(s.else_body)
      when AST::While  then body_returns?(s.body)
      else false
      end
    end
  end

  def check_return(node)
    unless @current_func
      error("'return' used outside of a function", line: node.line,
            hint: "move this 'return' inside a function body")
    end

    expected = @current_func[2]
    if node.value.nil?
      unify!(expected, :void, "'return'", line: node.line)
    else
      actual = check_expr(node.value)
      unify!(expected, actual, "'return'", line: node.line)
    end
  end

  def check_if(node)
    cond_type = check_expr(node.condition)
    unify!(:bool, cond_type, "'if' condition")
    push_scope; node.then_body.each { |s| check_stmt(s) }; pop_scope
    return unless node.else_body

    push_scope; node.else_body.each { |s| check_stmt(s) }; pop_scope
  end

  def check_while(node)
    cond_type = check_expr(node.condition)
    unify!(:bool, cond_type, "'while' condition")
    push_scope; node.body.each { |s| check_stmt(s) }; pop_scope
  end

  def check_raise(node)
    if @current_func && !@current_func[3]
      func_name = @current_func[0] rescue '?'
      error("'raise' cannot be used in a function that doesn't end with '!'",
            hint: "rename the function to '#{func_name}!' to mark it as failable")
    end
    check_expr(node.condition) if node.condition
  end

  # ---- Expressions ----

  def check_expr(node)
    case node
    when AST::IntLit    then :int
    when AST::FloatLit  then :float
    when AST::StringLit then :string
    when AST::BoolLit   then :bool
    when AST::Ident     then check_ident(node)
    when AST::BinaryOp  then check_binary(node)
    when AST::UnaryOp   then check_unary(node)
    when AST::Call      then check_call(node)
    when AST::Try       then check_try(node)
    else
      error("unknown expression '#{node.class}'")
    end
  end

  def check_ident(node)
    type = lookup(node.name)
    unless type
      hint = closest_match(node.name, all_names)
      error("undefined variable '#{node.name}'",
            line: node.line,
            hint: hint ? "did you mean '#{hint}'?" : "declare it first: '#{node.name}: <type> = <value>'")
    end
    type
  end

  def check_binary(node)
    left  = check_expr(node.left)
    right = check_expr(node.right)
    op    = node.op

    if ARITHMETIC_OPS.include?(op)
      unless numeric?(left) && numeric?(right)
        error("'#{op}' requires numeric operands, got '#{left}' and '#{right}'",
              hint: "both sides must be 'int' or 'float'")
      end
      left == :float || right == :float ? :float : :int
    elsif COMPARISON_OPS.include?(op)
      unless compatible?(left, right)
        error("cannot compare '#{left}' with '#{right}' using '#{op}'",
              hint: "both sides must be the same type")
      end
      :bool
    elsif LOGICAL_OPS.include?(op)
      unless left == :bool && right == :bool
        error("'#{op}' requires 'bool' operands, got '#{left}' and '#{right}'",
              hint: "use a comparison like '> 0' to convert a number to bool")
      end
      :bool
    else
      error("unknown operator '#{op}'")
    end
  end

  def check_unary(node)
    operand = check_expr(node.operand)
    case node.op
    when '-'
      unless numeric?(operand)
        error("'-' requires a numeric operand, got '#{operand}'",
              hint: "unary minus only works on 'int' and 'float'")
      end
      operand
    when 'not'
      unless operand == :bool
        error("'not' requires a 'bool' operand, got '#{operand}'",
              hint: "use a comparison like '== 0' to get a bool first")
      end
      :bool
    else
      error("unknown unary operator '#{node.op}'")
    end
  end

  def check_call(node)
    name = node.callee.name
    func = @funcs[name]

    unless func
      hint = closest_match(name, @funcs.keys)
      error("undefined function '#{name}'",
            line: node.line,
            hint: hint ? "did you mean '#{hint}'?" : "define it with: func #{name}(...) -> <type>")
    end

    if %w[println print].include?(name)
      error("'#{name}' takes exactly 1 argument", line: node.line) unless node.args.size == 1
      check_expr(node.args.first)
      return :void
    end

    _, param_types, return_type, _ = func
    if node.args.size != param_types.size
      diff = node.args.size < param_types.size ? 'missing' : 'too many'
      error("'#{name}' expects #{param_types.size} argument(s) but got #{node.args.size}",
            line: node.line,
            hint: "#{diff} #{(param_types.size - node.args.size).abs} argument(s)")
    end

    node.args.each_with_index do |arg, i|
      actual = check_expr(arg)
      unify!(param_types[i], actual, "argument #{i + 1} of '#{name}'", line: node.line)
    end

    return_type
  end

  def check_try(node)
    check_expr(node.expr)
  end

  # ---- Type helpers ----

  def numeric?(type)
    %i[int float].include?(type)
  end

  def compatible?(a, b)
    return true if a == b
    return true if a == :unknown || b == :unknown
    return true if numeric?(a) && numeric?(b)
    false
  end

  def unify!(expected, actual, context, line: nil)
    return if compatible?(expected, actual)

    hint = type_mismatch_hint(expected, actual)
    error("type mismatch in #{context}: expected '#{expected}', got '#{actual}'",
          line: line, hint: hint)
  end

  def type_mismatch_hint(expected, actual)
    case [expected, actual]
    in [:int, :float] | [:float, :int]
      "use an explicit conversion, e.g. '.to_int()' or '.to_float()'"
    in [:string, :int] | [:string, :float] | [:string, :bool]
      "convert to string with '.to_string()', or use an f-string: f'value is {x}'"
    in [:bool, :int]
      "use a comparison like '!= 0' to get a bool from a number"
    in [:void, _]
      "this expression returns a value but the function returns void"
    in [_, :void]
      "the function returns void and cannot be used as a value"
    else
      nil
    end
  end
end

# rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/PerceivedComplexity
