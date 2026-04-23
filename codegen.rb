# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/PerceivedComplexity, Naming/MethodParameterName

require_relative 'ast'
require_relative 'lexer'
require_relative 'parser'

# :nodoc:
class Codegen
  INTERP_REGEX = /\{([^}]+)\}/.freeze

  ARITH_INT   = { '+' => 'add',  '-' => 'sub',  '*' => 'mul',  '/' => 'sdiv', '%' => 'srem'  }.freeze
  ARITH_FLOAT = { '+' => 'fadd', '-' => 'fsub', '*' => 'fmul', '/' => 'fdiv', '%' => 'frem'  }.freeze
  ICMP_OPS    = { '==' => 'icmp eq',  '!=' => 'icmp ne',  '<'  => 'icmp slt',
                  '<=' => 'icmp sle', '>'  => 'icmp sgt', '>=' => 'icmp sge' }.freeze
  FCMP_OPS    = { '==' => 'fcmp oeq', '!=' => 'fcmp one', '<'  => 'fcmp olt',
                  '<=' => 'fcmp ole', '>'  => 'fcmp ogt', '>=' => 'fcmp oge' }.freeze

  def initialize
    @globals       = []
    @functions     = []
    @str_count     = 0
    @error_codes   = {}
    @error_counter = 1
    @func_table    = {
      'println' => { params: [:string], return_type: :void },
      'print' => { params: [:string], return_type: :void },
      'readline' => { params: [], return_type: :string },
      'exit' => { params: [:int], return_type: :void }
    }
    reset_func_state
  end

  def generate(program)
    # First pass: collect error codes and function signatures
    program.stmts.each do |s|
      case s
      when AST::FuncDecl then register_func(s)
      when AST::ErrorDecl
        s.variants.each do |v|
          @error_codes["#{s.name}.#{v}"] = @error_counter
          @error_counter += 1
        end
      end
    end

    emit_preamble

    toplevel = []
    program.stmts.each do |s|
      case s
      when AST::FuncDecl  then emit_func(s)
      when AST::ErrorDecl then nil
      else toplevel << s
      end
    end

    emit_main(toplevel) unless toplevel.empty?
    ([@globals.join("\n")] + @functions).join("\n")
  end

  private

  # ---------- State ----------

  def reset_func_state
    @ir               = []
    @reg              = 0
    @label_num        = 0
    @locals           = {}
    @alloca_count     = Hash.new(0)
    @current_ret_type = :void
  end

  def new_reg
    r = "%t#{@reg}"
    @reg += 1
    r
  end

  def alloca_ptr(name)
    n = @alloca_count[name]
    @alloca_count[name] += 1
    n.zero? ? "%#{name}.addr" : "%#{name}_#{n}.addr"
  end

  def new_label(pfx = 'bb')
    l = "#{pfx}#{@label_num}"
    @label_num += 1
    l
  end

  def emit(line)
    s = line.strip
    @ir << (s.empty? || s.end_with?(':') ? line : "  #{s}")
  end

  def terminates?
    @ir.reverse_each do |line|
      s = line.strip
      next if s.empty?
      return false if s.end_with?(':')

      return s.start_with?('ret ') || s.start_with?('br ') || s == 'unreachable'
    end
    false
  end

  # ---------- Types ----------

  def lt(t)
    case t
    when :int         then 'i64'
    when :float       then 'double'
    when :bool        then 'i1'
    when :void        then 'void'
    else                   'i8*'
    end
  end

  # ---------- Preamble & string globals ----------

  def emit_preamble
    @globals << 'declare i32 @puts(i8*)'
    @globals << 'declare i32 @printf(i8*, ...)'
    @globals << 'declare void @exit(i32)'
    @globals << ''
    @globals << '@__sheft_err_code = global i64 0'
    @globals << ''
  end

  def alloc_str(content)
    escaped = content.each_char.map do |c|
      case c
      when "\n" then '\0A'
      when "\t" then '\09'
      when '"'  then '\22'
      when '\\' then '\5C'
      else c
      end
    end.join
    name = "str#{@str_count}"
    @str_count += 1
    len = content.length + 1
    @globals << "@#{name} = private unnamed_addr constant [#{len} x i8] c\"#{escaped}\\00\""
    { name: name, len: len }
  end

  def str_ptr(g)
    r = new_reg
    emit "#{r} = getelementptr inbounds [#{g[:len]} x i8], [#{g[:len]} x i8]* @#{g[:name]}, i32 0, i32 0"
    r
  end

  # ---------- Function registration ----------

  def register_func(node)
    @func_table[node.name] = {
      params: node.params.map(&:type),
      return_type: node.return_type
    }
  end

  def func_return_type(name)
    @func_table[name.delete_suffix('!').delete_suffix('?')]&.dig(:return_type) || :int
  end

  # ---------- Top-level emitters ----------

  def emit_func(node)
    reset_func_state
    @current_ret_type = node.return_type
    is_main    = node.pub && node.name == 'main' && node.return_type == :void && node.params.empty?
    ret_lt     = is_main ? 'i32' : lt(node.return_type)
    params_str = node.params.map { |p| "#{lt(p.type)} %#{p.name}" }.join(', ')

    @ir << "define #{ret_lt} @#{llvm_name(node.name)}(#{params_str}) {"
    @ir << 'entry:'

    node.params.each do |p|
      ptr = alloca_ptr(p.name)
      emit "#{ptr} = alloca #{lt(p.type)}"
      emit "store #{lt(p.type)} %#{p.name}, #{lt(p.type)}* #{ptr}"
      @locals[p.name] = { ptr: ptr, type: p.type }
    end

    node.body.each { |s| emit_stmt(s) }
    unless terminates?
      emit(if is_main
             'ret i32 0'
           else
             (node.return_type == :void ? 'ret void' : 'unreachable')
           end)
    end

    @ir << '}'
    @ir << ''
    @functions << @ir.join("\n")
  end

  def emit_main(stmts)
    reset_func_state
    @ir << 'define i32 @main() {'
    @ir << 'entry:'
    stmts.each { |s| emit_stmt(s) }
    emit 'ret i32 0' unless terminates?
    @ir << '}'
    @ir << ''
    @functions << @ir.join("\n")
  end

  # ---------- Statements ----------

  def emit_stmt(node)
    case node
    when AST::VarDecl  then emit_var_decl(node)
    when AST::Assign   then emit_assign(node)
    when AST::Return   then emit_return(node)
    when AST::If       then emit_if(node)
    when AST::While    then emit_while(node)
    when AST::ExprStmt then emit_expr(node.expr)
    when AST::Raise    then emit_raise(node)
    when AST::FuncDecl then emit_func(node)
    end
  end

  def emit_var_decl(node)
    ref, type = emit_expr(node.value)
    ptr = alloca_ptr(node.name)
    emit "#{ptr} = alloca #{lt(type)}"
    emit "store #{lt(type)} #{ref}, #{lt(type)}* #{ptr}"
    @locals[node.name] = { ptr: ptr, type: type }
  end

  def emit_assign(node)
    local = @locals[node.target.name]
    raise "Codegen: assignment to undefined local '#{node.target.name}'" unless local

    ref, type = emit_expr(node.value)
    emit "store #{lt(type)} #{ref}, #{lt(type)}* #{local[:ptr]}"
  end

  def emit_return(node)
    if node.value.nil?
      emit 'ret void'
    else
      ref, type = emit_expr(node.value)
      emit "ret #{lt(type)} #{ref}"
    end
    emit "#{new_label('dead')}:"
  end

  def emit_if(node)
    cond_ref, = emit_expr(node.condition)
    then_lbl  = new_label('then')
    merge_lbl = new_label('merge')
    else_lbl  = node.else_body ? new_label('else') : merge_lbl

    emit "br i1 #{cond_ref}, label %#{then_lbl}, label %#{else_lbl}"
    emit "#{then_lbl}:"
    node.then_body.each { |s| emit_stmt(s) }
    emit "br label %#{merge_lbl}" unless terminates?

    if node.else_body
      emit "#{else_lbl}:"
      node.else_body.each { |s| emit_stmt(s) }
      emit "br label %#{merge_lbl}" unless terminates?
    end

    emit "#{merge_lbl}:"
  end

  def emit_while(node)
    cond_lbl = new_label('wc')
    body_lbl = new_label('wb')
    end_lbl  = new_label('we')

    emit "br label %#{cond_lbl}"
    emit "#{cond_lbl}:"
    cond_ref, = emit_expr(node.condition)
    emit "br i1 #{cond_ref}, label %#{body_lbl}, label %#{end_lbl}"
    emit "#{body_lbl}:"
    node.body.each { |s| emit_stmt(s) }
    emit "br label %#{cond_lbl}" unless terminates?
    emit "#{end_lbl}:"
  end

  def emit_raise(node)
    code      = resolve_error_code(node.expr)
    raise_lbl = new_label('raise')
    cont_lbl  = new_label('rc')

    if node.condition
      cref, = emit_expr(node.condition)
      emit "br i1 #{cref}, label %#{raise_lbl}, label %#{cont_lbl}"
    else
      emit "br label %#{raise_lbl}"
    end

    emit "#{raise_lbl}:"
    emit "store i64 #{code}, i64* @__sheft_err_code"
    emit_zero_return
    emit "#{cont_lbl}:"
  end

  def emit_zero_return
    case @current_ret_type
    when :void   then emit 'ret void'
    when :float  then emit 'ret double 0.0'
    when :bool   then emit 'ret i1 0'
    when :string then emit 'ret i8* null'
    else              emit 'ret i64 0'
    end
    emit "#{new_label('dead')}:"
    emit 'unreachable'
  end

  def resolve_error_code(expr)
    # Error variants are referenced as bare identifiers with dot notation:
    # e.g. MathError.DivByZero parses as Ident("MathError") in a field-access
    # position. For v0.1 we resolve by matching "Name.Variant" from the expr.
    key = case expr
          when AST::Ident then expr.name # bare raise — no matching error code
          end
    @error_codes[key] || 1
  end

  # ---------- Expressions → [ref, type] ----------

  def emit_expr(node)
    case node
    when AST::IntLit    then [node.value.to_s, :int]
    when AST::FloatLit  then [llvm_float(node.value), :float]
    when AST::BoolLit   then [node.value ? '1' : '0', :bool]
    when AST::StringLit then emit_string_lit(node)
    when AST::Ident     then emit_load(node.name)
    when AST::BinaryOp  then emit_binary(node)
    when AST::UnaryOp   then emit_unary(node)
    when AST::Call      then emit_call(node)
    when AST::Try       then emit_try(node)
    else raise "Codegen: unhandled expression node #{node.class}"
    end
  end

  def llvm_float(val)
    format('%.17e', val)
  end

  def emit_load(name)
    local = @locals[name]
    return ["0 ; undef #{name}", :int] unless local

    r = new_reg
    emit "#{r} = load #{lt(local[:type])}, #{lt(local[:type])}* #{local[:ptr]}"
    [r, local[:type]]
  end

  def emit_string_lit(node)
    g = alloc_str(node.value)
    [str_ptr(g), :string]
  end

  def emit_binary(node)
    lref, ltype = emit_expr(node.left)
    rref, rtype = emit_expr(node.right)
    op          = node.op

    use_float = ltype == :float || rtype == :float

    if use_float
      if ltype == :int
        t = new_reg
        emit "#{t} = sitofp i64 #{lref} to double"
        lref = t
      end
      if rtype == :int
        t = new_reg
        emit "#{t} = sitofp i64 #{rref} to double"
        rref = t
      end
    end

    op_lt = use_float ? 'double' : lt(ltype)
    reg   = new_reg

    case op
    when '+', '-', '*', '/', '%'
      instr = use_float ? ARITH_FLOAT[op] : ARITH_INT[op]
      emit "#{reg} = #{instr} #{op_lt} #{lref}, #{rref}"
      [reg, use_float ? :float : ltype]
    when '==', '!=', '<', '<=', '>', '>='
      instr = use_float ? FCMP_OPS[op] : ICMP_OPS[op]
      emit "#{reg} = #{instr} #{op_lt} #{lref}, #{rref}"
      [reg, :bool]
    when 'and'
      emit "#{reg} = and i1 #{lref}, #{rref}"
      [reg, :bool]
    when 'or'
      emit "#{reg} = or i1 #{lref}, #{rref}"
      [reg, :bool]
    else
      ['0', :int]
    end
  end

  def emit_unary(node)
    ref, type = emit_expr(node.operand)
    reg = new_reg
    case node.op
    when '-'
      type == :float ? emit("#{reg} = fneg double #{ref}") : emit("#{reg} = sub i64 0, #{ref}")
      [reg, type]
    when 'not'
      emit "#{reg} = xor i1 #{ref}, 1"
      [reg, :bool]
    else
      [ref, type]
    end
  end

  def emit_call(node)
    base = node.callee.name.delete_suffix('!').delete_suffix('?')

    case base
    when 'println' then emit_print(node.args.first, newline: true)
                        ['', :void]
    when 'print'   then emit_print(node.args.first, newline: false)
                        ['', :void]
    else
      arg_vals = node.args.map { |a| emit_expr(a) }
      args_str = arg_vals.map { |r, t| "#{lt(t)} #{r}" }.join(', ')
      ret_type = func_return_type(node.callee.name)

      if ret_type == :void
        emit "call void @#{llvm_name(node.callee.name)}(#{args_str})"
        ['', :void]
      else
        r = new_reg
        emit "#{r} = call #{lt(ret_type)} @#{llvm_name(node.callee.name)}(#{args_str})"
        [r, ret_type]
      end
    end
  end

  def emit_print(arg_node, newline:)
    return emit('; print: no arg') unless arg_node

    if arg_node.is_a?(AST::StringLit)
      content = arg_node.value
      interp  = content.scan(INTERP_REGEX).flatten

      if interp.empty?
        ptr = str_ptr(alloc_str(content))
        newline ? emit("call i32 @puts(i8* #{ptr})") : emit("call i32 @printf(i8* #{ptr})")
      else
        fmt      = content.dup
        arg_refs = []
        interp.each do |expr_str|
          expr_node   = parse_interp_expr(expr_str)
          vref, vtype = emit_expr(expr_node)
          spec = case vtype
                 when :int   then '%lld'
                 when :float then '%g'
                 when :bool  then '%d'
                 else '%s'
                 end
          fmt.sub!("{#{expr_str}}", spec)
          if vtype == :bool
            ext = new_reg
            emit "#{ext} = zext i1 #{vref} to i32"
            arg_refs << "i32 #{ext}"
          else
            arg_refs << "#{lt(vtype)} #{vref}"
          end
        end
        fmt += "\n" if newline
        ptr = str_ptr(alloc_str(fmt))
        all = (["i8* #{ptr}"] + arg_refs).join(', ')
        emit "call i32 (i8*, ...) @printf(#{all})"
      end
    else
      ref, type = emit_expr(arg_node)
      fmt_str, extra = case type
                       when :int   then [newline ? "%lld\n" : '%lld', "i64 #{ref}"]
                       when :float then [newline ? "%g\n"   : '%g',   "double #{ref}"]
                       when :bool
                         ext = new_reg
                         emit "#{ext} = zext i1 #{ref} to i32"
                         [newline ? "%d\n" : '%d', "i32 #{ext}"]
                       else
                         newline ? emit("call i32 @puts(i8* #{ref})") : emit("call i32 @printf(i8* #{ref})")
                         return
                       end
      ptr = str_ptr(alloc_str(fmt_str))
      emit "call i32 (i8*, ...) @printf(i8* #{ptr}, #{extra})"
    end
  end

  # try — propagate: if __sheft_err_code != 0, return zero-value immediately
  def emit_try(node)
    ref, type = emit_expr(node.expr)
    err_val   = new_reg
    emit "#{err_val} = load i64, i64* @__sheft_err_code"
    has_err = new_reg
    emit "#{has_err} = icmp ne i64 #{err_val}, 0"
    prop_lbl = new_label('prop')
    cont_lbl = new_label('tc')
    emit "br i1 #{has_err}, label %#{prop_lbl}, label %#{cont_lbl}"
    emit "#{prop_lbl}:"
    emit_zero_return
    emit "#{cont_lbl}:"
    [ref, type]
  end

  def parse_interp_expr(expr_str)
    lexer = Lexer.new(expr_str)
    lexer.scan_tokens
    Parser.new(lexer.tokens).send(:parse_expr)
  end

  # ---------- Helpers ----------

  def llvm_name(name)
    name.delete_suffix('!').delete_suffix('?')
  end
end

# rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/PerceivedComplexity, Naming/MethodParameterName
