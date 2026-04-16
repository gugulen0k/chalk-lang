# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/PerceivedComplexity

require_relative './ast'

class TypeError < StandardError; end

# Resolved types used throughout the checker.
# Primitive symbols: :int, :float, :string, :bool, :void
# Arrays:            [:array, inner_type]
# Functions:         [:func, param_types, return_type, failable]
# User-defined:      a String (struct/enum name)

# :nodoc:
class TypeChecker
  BUILTINS = {
    'println' => [:func, [:string], :void, false],
    'print' => [:func, [:string], :void, false],
    'readline' => [:func, [], :string, false],
    'exit' => [:func, [:int], :void, false]
  }.freeze

  def initialize
    @scopes       = [{}]
    @funcs        = BUILTINS.dup
    @structs      = {}
    @enums        = {}
    @errors       = {}
    @current_func = nil
  end

  def check(program)
    program.stmts.each { |s| hoist(s) }
    program.stmts.each { |s| check_stmt(s) } # rubocop:disable Style/CombinableLoops
  end

  private

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

  def error(msg)
    raise TypeError, msg
  end

  # ---- First-pass hoisting ----

  def hoist(node)
    case node
    when AST::FuncDecl
      param_types = node.params.map { |p| resolve_type(p.type) }
      @funcs[node.name] = [:func, param_types, resolve_type(node.return_type), node.failable]
    when AST::StructDecl
      @structs[node.name] = node.fields.each_with_object({}) do |f, h|
        h[f.name] = resolve_type(f.type)
      end
    when AST::EnumDecl
      @enums[node.name] = node.variants.map(&:name)
    when AST::ErrorDecl
      @errors[node.name] = node.variants
    when AST::ConstDecl
      define(node.name, resolve_type(node.type))
    end
  end

  # ---- Resolve AST type annotation to canonical type ----

  def resolve_type(ann)
    return ann if ann.is_a?(Symbol) # :int, :float, etc.
    return ann if ann.is_a?(Array)  # [:array, inner]

    # String = user-defined type name
    ann
  end

  # ---- Statement checking ----

  def check_stmt(node)
    case node
    when AST::VarDecl    then check_var_decl(node)
    when AST::Assign     then check_assign(node)
    when AST::FuncDecl   then check_func_decl(node)
    when AST::Return     then check_return(node)
    when AST::If         then check_if(node)
    when AST::While      then check_while(node)
    when AST::ForIn      then check_for(node)
    when AST::ExprStmt   then check_expr(node.expr)
    when AST::Raise      then check_raise(node)
    when AST::Break, AST::Skip # no type rules
    when AST::ConstDecl  then check_const(node)
    when AST::ImportDecl # skip — module resolution not implemented yet
    when AST::StructDecl then check_struct_methods(node)
    when AST::EnumDecl, AST::ErrorDecl # already hoisted
    else
      error("Unknown statement node: #{node.class}")
    end
  end

  def check_var_decl(node)
    declared = resolve_type(node.type)
    actual   = check_expr(node.value)
    unify!(declared, actual, "variable '#{node.name}'")
    define(node.name, declared)
  end

  def check_assign(node)
    target_type = lookup(node.target.name)
    error("Undefined variable '#{node.target.name}'") unless target_type

    actual = check_expr(node.value)
    unify!(target_type, actual, "assignment to '#{node.target.name}'")
  end

  def check_func_decl(node)
    prev_func     = @current_func
    @current_func = @funcs[node.name]
    push_scope
    node.params.each { |p| define(p.name, resolve_type(p.type)) }
    node.body.each   { |s| check_stmt(s) }
    pop_scope
    @current_func = prev_func
  end

  def check_return(node)
    error("'return' outside function") unless @current_func

    expected = @current_func[2] # return_type
    if node.value.nil?
      unify!(expected, :void, "'return'")
    else
      actual = check_expr(node.value)
      unify!(expected, actual, "'return'")
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

  def check_for(node)
    iter_type = check_expr(node.iterable)
    push_scope
    case iter_type
    when Array
      # [:array, elem_type]
      define(node.var, iter_type[1])
      define(node.index_var, :int) if node.index_var
    when :range_int
      define(node.var, :int)
    else
      error("'for' iterable must be an array or integer range, got #{iter_type}")
    end
    node.body.each { |s| check_stmt(s) }
    pop_scope
  end

  def check_raise(node)
    # Verify we're inside a failable function
    error("'raise' used inside non-failable function '#{@current_func}'") if @current_func && !@current_func[3]
    check_expr(node.condition) if node.condition
  end

  def check_const(node)
    declared = resolve_type(node.type)
    actual   = check_expr(node.value)
    unify!(declared, actual, "constant '#{node.name}'")
  end

  def check_struct_methods(node)
    @structs[node.name] ||= {}
    node.func_defs.each { |m| check_func_decl(m) }
  end

  # ---- Expression type inference ----

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
    when AST::MethodCall then check_method_call(node)
    when AST::FieldAccess then check_field_access(node)
    when AST::IndexAccess then check_index_access(node)
    when AST::Range     then check_range(node)
    when AST::ArrayLit  then check_array_lit(node)
    when AST::ArrayReserve then check_array_reserve(node)
    when AST::StructLit then check_struct_lit(node)
    when AST::PathExpr  then check_path_expr(node)
    when AST::Ternary   then check_ternary(node)
    when AST::Try       then check_try(node)
    when AST::Catch     then check_catch(node)
    when AST::Match     then check_match(node)
    else
      error("Unknown expression node: #{node.class}")
    end
  end

  def check_ident(node)
    type = lookup(node.name)
    error("Undefined variable '#{node.name}'") unless type

    type
  end

  ARITHMETIC_OPS = %w[+ - * / %].freeze
  COMPARISON_OPS = %w[== != < <= > >=].freeze
  LOGICAL_OPS    = %w[and or].freeze

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
    error("Undefined function '#{name}'") unless func

    # println/print accept any single printable value
    if %w[println print].include?(name)
      error("'#{name}' takes exactly 1 argument") unless node.args.size == 1
      check_expr(node.args.first)
      return :void
    end

    _, param_types, return_type, _failable = func
    check_call_args(name, param_types, node.args)
    return_type
  end

  def check_method_call(node)
    receiver = check_expr(node.receiver)
    # Basic built-in method types — expand as stdlib grows
    case receiver
    when Array
      elem_type = receiver[1]
      case node.method_name
      when 'push'  then check_call_args('push', [elem_type], node.args)
                        :void
      when 'pop'   then elem_type
      when 'len'   then :int
      when 'has'   then :bool
      when 'map', 'filter' then receiver # returns same array type (approximate)
      else error("Unknown array method '#{node.method_name}'")
      end
    when :string
      case node.method_name
      when 'len' then :int
      when 'upper', 'lower', 'trim', 'replace', 'repeat' then :string
      when 'split' then %i[array string]
      when 'empty?', 'starts_with?', 'ends_with?',
           'contains?', 'alpha?', 'digit?' then :bool
      when 'to_int!'                                      then :int
      when 'to_float!'                                    then :float
      when 'to_string'                                    then :string
      when 'index_of!'                                    then :int
      else error("Unknown string method '#{node.method_name}'")
      end
    else
      # User-defined struct method — look up in funcs table
      func = @funcs[node.method_name] || @funcs["#{receiver}.#{node.method_name}"]
      return func[2] if func

      # Unknown — return :unknown for now rather than hard-erroring on user structs
      :unknown
    end
  end

  def check_field_access(node)
    receiver = check_expr(node.receiver)
    return :unknown unless receiver.is_a?(String)

    fields = @structs[receiver]
    error("Undefined struct '#{receiver}'") unless fields

    fields[node.field] || error("Struct '#{receiver}' has no field '#{node.field}'")
  end

  def check_index_access(node)
    receiver = check_expr(node.receiver)
    index    = check_expr(node.index)
    error("Index must be int, got #{index}") unless index == :int
    case receiver
    when Array then receiver[1]
    when :string then :string
    else error("Cannot index into #{receiver}")
    end
  end

  def check_range(node)
    from = check_expr(node.from)
    to   = check_expr(node.to)
    error("Range bounds must be int, got #{from}..#{to}") \
      unless from == :int && to == :int
    :range_int
  end

  def check_array_lit(node)
    return %i[array unknown] if node.elements.empty?

    types = node.elements.map { |e| check_expr(e) }
    first = types.first
    types.each_with_index do |t, i|
      error("Array element #{i} type #{t} does not match element 0 type #{first}") unless t == first
    end
    [:array, first]
  end

  def check_array_reserve(node)
    cap = check_expr(node.capacity)
    error("Array reserve capacity must be int, got #{cap}") unless cap == :int
    %i[array unknown]
  end

  def check_struct_lit(node)
    fields = @structs[node.name]
    # Struct may be defined in another module — skip field checks if unknown
    return node.name unless fields

    node.fields.each do |fname, fval|
      expected = fields[fname]
      error("Struct '#{node.name}' has no field '#{fname}'") unless expected
      actual = check_expr(fval)
      unify!(expected, actual, "field '#{fname}' of struct '#{node.name}'")
    end
    node.name
  end

  def check_path_expr(_node)
    # e.g. MyModule::CONSTANT or ErrorSet.Variant — treat as :unknown for now
    :unknown
  end

  def check_ternary(node)
    cond = check_expr(node.condition)
    error("Ternary condition must be bool, got #{cond}") unless cond == :bool
    then_t = check_expr(node.then_expr)
    else_t = check_expr(node.else_expr)
    error("Ternary branches have different types: #{then_t} vs #{else_t}") \
      unless compatible?(then_t, else_t)
    then_t
  end

  def check_try(node)
    check_expr(node.expr)
  end

  def check_catch(node)
    check_expr(node.expr)
  end

  def check_match(node)
    subject_type = check_expr(node.value)
    arm_types = node.arms.map do |arm|
      push_scope
      case arm.pattern
      when AST::WithPattern
        define(arm.pattern.name, subject_type)
      when AST::EnumPattern
        define(arm.pattern.binding, subject_type) if arm.pattern.binding
      end
      check_expr(arm.guard) if arm.guard
      result = check_expr(arm.body)
      pop_scope
      result
    end
    # All arms must produce the same type
    first = arm_types.first
    arm_types.each_with_index do |t, i|
      next if compatible?(first, t)

      error("Match arm #{i} produces #{t}, expected #{first}")
    end
    first || :void
  end

  # ---- Helpers ----

  def check_call_args(name, param_types, args)
    error("'#{name}' expects #{param_types.size} argument(s), got #{args.size}") \
      if args.size != param_types.size
    args.each_with_index do |arg, i|
      actual = check_expr(arg)
      unify!(param_types[i], actual, "argument #{i + 1} of '#{name}'")
    end
  end

  def numeric?(type)
    %i[int float].include?(type)
  end

  def compatible?(type_a, type_b)
    return true if type_a == type_b
    return true if type_a == :unknown || type_b == :unknown
    return true if numeric?(type_a) && numeric?(type_b)
    # [:array, :unknown] is compatible with any [:array, T]
    return true if type_a.is_a?(Array) && type_b.is_a?(Array) &&
                   type_a[0] == :array && type_b[0] == :array &&
                   (type_a[1] == :unknown || type_b[1] == :unknown)

    false
  end

  def unify!(expected, actual, context)
    return if compatible?(expected, actual)

    error("Type mismatch in #{context}: expected #{expected}, got #{actual}")
  end
end

# rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/PerceivedComplexity
