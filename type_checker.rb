# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/PerceivedComplexity

require_relative 'ast'
require_relative 'errors'

# Resolved types used throughout the checker.
# Primitive symbols: :int, :float, :string, :bool, :void
# Functions:         [:func, param_types, return_type, failable]

# :nodoc:
class TypeChecker
  BUILTINS = {
    'println' => [:func, [:string], :void, false],
    'print' => [:func, [:string], :void, false],
    'readline' => [:func, [], :string, false],
    'exit' => [:func, [:int], :void, false]
  }.freeze

  ARITHMETIC_OPS = %w[+ - * / %].freeze
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
    check_entry_point(program.stmts)
    program.stmts.each { |s| check_stmt(s) } # rubocop:disable Style/CombinableLoops
  end

  private

  # ---- Entry point validation ----

  def check_entry_point(stmts)
    has_pub_main = stmts.any? { |s| s.is_a?(AST::FuncDecl) && s.pub && s.name == 'main' }
    has_toplevel = stmts.any? { |s| !s.is_a?(AST::FuncDecl) && !s.is_a?(AST::ErrorDecl) }
    return unless has_pub_main && has_toplevel

    error("program has both 'pub func main()' and top-level statements — use one or the other",
          hint: "remove top-level statements and put them inside 'pub func main()', or remove 'pub func main()'")
  end

  # ---- Scope helpers ----

  def push_scope
    @scopes.push({})
  end

  def pop_scope
    @scopes.pop
  end

  def define(name, type)
    @scopes.last[name] = type
  end

  def lookup(name)
    @scopes.reverse_each { |s| return s[name] if s.key?(name) }
    nil
  end

  def error(msg, line: nil, hint: nil)
    raise TypeCheckError.new(msg, line: line, hint: hint)
  end

  def closest_match(target, candidates)
    best = candidates.min_by { |c| levenshtein(target.downcase, c.downcase) }
    dist = levenshtein(target.downcase, best.downcase)
    dist <= [target.length / 2, 3].max ? best : nil
  end

  def levenshtein(str_a, str_b)
    return str_b.length if str_a.empty?
    return str_a.length if str_b.empty?

    prev = (0..str_b.length).to_a
    str_a.each_char.with_index(1) do |ca, i|
      curr = [i]
      str_b.each_char.with_index(1) do |cb, j|
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

  # ---- Resolve AST type annotation to canonical type ----

  def resolve_type(annotation)
    annotation
  end

  # ---- Statement checking ----

  def check_stmt(node)
    case node
    when AST::VarDecl  then check_var_decl(node)
    when AST::Assign   then check_assign(node)
    when AST::FuncDecl then check_func_decl(node)
    when AST::Return   then check_return(node)
    when AST::If       then check_if(node)
    when AST::While    then check_while(node)
    when AST::ExprStmt then check_expr(node.expr)
    when AST::Raise    then check_raise(node)
    when AST::ErrorDecl # already hoisted
    else
      error("Unknown statement node: #{node.class}")
    end
  end

  def check_var_decl(node)
    declared = resolve_type(node.type)
    actual   = check_expr(node.value)
    unify!(declared, actual, "variable '#{node.name}'", line: node.line)
    define(node.name, declared)
  end

  def check_assign(node)
    error("Invalid assignment target #{node.target.class}") unless node.target.is_a?(AST::Ident)

    target_type = lookup(node.target.name)
    unless target_type
      hint = closest_match(node.target.name, all_names)
      error("Undefined variable '#{node.target.name}'",
            line: node.target.line,
            hint: hint ? "did you mean '#{hint}'?" : "declare it first with '#{node.target.name}: <type> = <value>'")
    end
    actual = check_expr(node.value)
    unify!(target_type, actual, "assignment to '#{node.target.name}'", line: node.target.line)
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

    error("Function '#{node.name}' declared to return '#{ret}' but has no return statement",
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
      error("'return' outside function", line: node.line,
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
    push_scope
    node.then_body.each { |s| check_stmt(s) }
    pop_scope
    return unless node.else_body

    push_scope
    node.else_body.each { |s| check_stmt(s) }
    pop_scope
  end

  def check_while(node)
    cond_type = check_expr(node.condition)
    unify!(:bool, cond_type, "'while' condition")
    push_scope
    node.body.each { |s| check_stmt(s) }
    pop_scope
  end

  def check_raise(node)
    # Verify we're inside a failable function
    if @current_func && !@current_func[3]
      error("'raise' used inside non-failable function '#{@funcs.key(@current_func)}'")
    end
    check_expr(node.condition) if node.condition
  end

  # ---- Expression type inference ----

  def check_expr(node)
    case node
    when AST::IntLit    then :int
    when AST::FloatLit  then :float
    when AST::StringLit then :string
    when AST::BoolLit   then :bool
    when AST::Ident    then check_ident(node)
    when AST::BinaryOp then check_binary(node)
    when AST::UnaryOp  then check_unary(node)
    when AST::Call     then check_call(node)
    when AST::Try      then check_try(node)
    else
      error("Unknown expression node: #{node.class}")
    end
  end

  def check_ident(node)
    type = lookup(node.name)
    unless type
      hint = closest_match(node.name, all_names)
      error("Undefined variable '#{node.name}'",
            line: node.line,
            hint: hint ? "did you mean '#{hint}'?" : nil)
    end
    type
  end

  def check_binary(node)
    left  = check_expr(node.left)
    right = check_expr(node.right)

    if ARITHMETIC_OPS.include?(node.op)
      error("Arithmetic '#{node.op}' requires numeric operands, got #{left} and #{right}") \
        unless numeric?(left) && numeric?(right)
      # int op int => int, anything with float => float
      left == :float || right == :float ? :float : :int
    elsif COMPARISON_OPS.include?(node.op)
      error("Cannot compare #{left} with #{right} using '#{node.op}'") \
        unless compatible?(left, right)
      :bool
    elsif LOGICAL_OPS.include?(node.op)
      error("'#{node.op}' requires bool operands, got #{left} and #{right}") \
        unless left == :bool && right == :bool
      :bool
    else
      error("Unknown binary operator '#{node.op}'")
    end
  end

  def check_unary(node)
    operand = check_expr(node.operand)
    case node.op
    when '-'
      error("Unary '-' requires numeric operand, got #{operand}") unless numeric?(operand)
      operand
    when 'not'
      error("'not' requires bool operand, got #{operand}") unless operand == :bool
      :bool
    else
      error("Unknown unary operator '#{node.op}'")
    end
  end

  def check_call(node)
    name = node.callee.name
    func = @funcs[name]
    unless func
      hint = closest_match(name, @funcs.keys)
      error("Undefined function '#{name}'",
            line: node.line,
            hint: hint ? "did you mean '#{hint}'?" : "define it with 'func #{name}(...) -> <type>'")
    end

    if %w[println print].include?(name)
      error("'#{name}' takes exactly 1 argument", line: node.line) unless node.args.size == 1
      check_expr(node.args.first)
      return :void
    end

    _, param_types, return_type, _failable = func
    check_call_args(name, param_types, node.args, line: node.line)
    return_type
  end

  def check_try(node)
    check_expr(node.expr)
  end

  # ---- Helpers ----

  def check_call_args(name, param_types, args, line: nil)
    if args.size != param_types.size
      error("'#{name}' expects #{param_types.size} argument(s), got #{args.size}",
            line: line,
            hint: missing_or_extra_args_hint(name, param_types.size, args.size))
    end
    args.each_with_index do |arg, i|
      actual = check_expr(arg)
      unify!(param_types[i], actual, "argument #{i + 1} of '#{name}'", line: line)
    end
  end

  def missing_or_extra_args_hint(_name, expected, got)
    diff = (expected - got).abs
    got < expected ? "missing #{diff} argument(s)" : "remove #{diff} argument(s)"
  end

  def numeric?(type)
    %i[int float].include?(type)
  end

  def compatible?(type_a, type_b)
    return true if type_a == type_b
    return true if numeric?(type_a) && numeric?(type_b)

    false
  end

  def unify!(expected, actual, context, line: nil)
    return if compatible?(expected, actual)

    hint = type_mismatch_hint(expected, actual)
    error("Type mismatch in #{context}: expected '#{expected}', got '#{actual}'",
          line: line, hint: hint)
  end

  def type_mismatch_hint(expected, actual)
    case [expected, actual]
    in [:int, :float] | [:float, :int]
      "use an explicit conversion: '.to_int()' or '.to_float()'"
    in [:string, :int] | [:string, :float] | [:string, :bool]
      "use '.to_string()' to convert to string"
    in [:bool, :int]
      "comparison returns bool, not int — use '== 0' for zero-check"
    in [:void, _]
      "this expression returns a value but none was expected — remove the 'return' value"
    in [_, :void]
      'function returns void — it cannot be used as a value'
    else
      nil
    end
  end

  def all_names
    scope_names = @scopes.flat_map(&:keys)
    scope_names + @funcs.keys
  end
end

# rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/PerceivedComplexity
