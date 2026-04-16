# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/AbcSize

require_relative './ast'

class Codegen
  INTERP_REGEX = /\{([a-zA-Z_][a-zA-Z0-9_]*)\}/.freeze

  ARITH_INT   = { '+' => 'add',  '-' => 'sub',  '*' => 'mul',  '/' => 'sdiv', '%' => 'srem' }.freeze
  ARITH_FLOAT = { '+' => 'fadd', '-' => 'fsub', '*' => 'fmul', '/' => 'fdiv' }.freeze
  ICMP_OPS    = { '==' => 'icmp eq',  '!=' => 'icmp ne',  '<'  => 'icmp slt',
                  '<=' => 'icmp sle', '>'  => 'icmp sgt', '>=' => 'icmp sge' }.freeze
  FCMP_OPS    = { '==' => 'fcmp oeq', '!=' => 'fcmp one', '<'  => 'fcmp olt',
                  '<=' => 'fcmp ole', '>'  => 'fcmp ogt', '>=' => 'fcmp oge' }.freeze

  def initialize
    @globals    = []
    @functions  = []
    @str_count  = 0
    @func_table = {
      'println'  => { params: [:string], return_type: :void },
      'print'    => { params: [:string], return_type: :void },
      'readline' => { params: [],        return_type: :string },
      'exit'     => { params: [:int],    return_type: :void }
    }
    reset_func_state
  end

  def generate(program)
    emit_preamble
    program.stmts.each { |s| register_func(s) if s.is_a?(AST::FuncDecl) }

    toplevel = []
    program.stmts.each do |s|
      case s
      when AST::FuncDecl                                          then emit_func(s)
      when AST::StructDecl, AST::EnumDecl, AST::ErrorDecl,
           AST::ImportDecl                                        then nil
      else toplevel << s
      end
    end

    emit_main(toplevel) unless toplevel.empty?
    ([@globals.join("\n")] + @functions).join("\n")
  end

  private

  # ---------- State ----------

  def reset_func_state
    @ir           = []
    @reg          = 0
    @label_num    = 0
    @locals       = {}
    @loop_stack   = []
    @alloca_count = Hash.new(0)
  end

  def new_reg
    r = "%t#{@reg}"; @reg += 1; r
  end

  def alloca_ptr(name)
    n = @alloca_count[name]
    @alloca_count[name] += 1
    n.zero? ? "%#{name}.addr" : "%#{name}_#{n}.addr"
  end

  def new_label(pfx = 'bb')
    l = "#{pfx}#{@label_num}"; @label_num += 1; l
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
    when :int    then 'i64'
    when :float  then 'double'
    when :bool   then 'i1'
    when :string then 'i8*'
    when :void   then 'void'
    else 'i8*'
    end
  end

  def infer_type(node)
    case node
    when AST::IntLit    then :int
    when AST::FloatLit  then :float
    when AST::BoolLit   then :bool
    when AST::StringLit then :string
    when AST::Ident     then @locals[node.name]&.dig(:type) || :unknown
    when AST::BinaryOp
      l = infer_type(node.left); r = infer_type(node.right)
      %w[== != < <= > >=].include?(node.op) ? :bool : (l == :float || r == :float ? :float : l)
    when AST::UnaryOp   then node.op == 'not' ? :bool : infer_type(node.operand)
    else :unknown
    end
  end

  # ---------- Preamble & string globals ----------

  def emit_preamble
    @globals << 'declare i32 @puts(i8*)'
    @globals << 'declare i32 @printf(i8*, ...)'
    @globals << 'declare void @exit(i32)'
    @globals << ''
  end

  def alloc_str(content)
    escaped = content.each_char.map { |c|
      case c
      when "\n" then '\0A'
      when "\t" then '\09'
      when '"'  then '\22'
      when '\\' then '\5C'
      else c
      end
    }.join
    name = "str#{@str_count}"; @str_count += 1
    len  = content.length + 1
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
      params:      node.params.map(&:type),
      return_type: node.return_type
    }
  end

  def func_return_type(name)
    @func_table[name.delete_suffix('!').delete_suffix('?')]&.dig(:return_type) || :int
  end

  # ---------- Top-level emitters ----------

  def emit_func(node)
    reset_func_state
    ret_lt     = lt(node.return_type)
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
    emit(node.return_type == :void ? 'ret void' : 'unreachable') unless terminates?

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
    when AST::VarDecl, AST::ConstDecl then emit_var_decl(node)
    when AST::Assign                  then emit_assign(node)
    when AST::Return                  then emit_return(node)
    when AST::If                      then emit_if(node)
    when AST::While                   then emit_while(node)
    when AST::ForIn                   then emit_for(node)
    when AST::ExprStmt                then emit_expr(node.expr)
    when AST::Break                   then emit_break(node)
    when AST::Skip                    then emit_skip(node)
    when AST::Raise                   then emit_raise(node)
    when AST::FuncDecl                then emit_func(node)
    else nil
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
    return emit("; undefined '#{node.target.name}'") unless local

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
    cond_ref, _ = emit_expr(node.condition)
    then_lbl    = new_label('then')
    merge_lbl   = new_label('merge')
    else_lbl    = node.else_body ? new_label('else') : merge_lbl

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
    cond_ref, _ = emit_expr(node.condition)
    emit "br i1 #{cond_ref}, label %#{body_lbl}, label %#{end_lbl}"
    emit "#{body_lbl}:"

    @loop_stack.push({ cond: cond_lbl, end: end_lbl })
    node.body.each { |s| emit_stmt(s) }
    @loop_stack.pop
    emit "br label %#{cond_lbl}" unless terminates?
    emit "#{end_lbl}:"
  end

  def emit_for(node)
    unless node.iterable.is_a?(AST::Range)
      emit '; TODO: array for-in'; return
    end

    range          = node.iterable
    from_ref, _    = emit_expr(range.from)
    to_ref, _      = emit_expr(range.to)
    ptr = alloca_ptr(node.var)
    emit "#{ptr} = alloca i64"
    emit "store i64 #{from_ref}, i64* #{ptr}"
    @locals[node.var] = { ptr: ptr, type: :int }

    cond_lbl = new_label('fc')
    body_lbl = new_label('fb')
    inc_lbl  = new_label('fi')
    end_lbl  = new_label('fe')

    emit "br label %#{cond_lbl}"
    emit "#{cond_lbl}:"
    cur = new_reg
    emit "#{cur} = load i64, i64* #{ptr}"
    cmp = new_reg
    emit "#{cmp} = #{range.inclusive ? 'icmp sle' : 'icmp slt'} i64 #{cur}, #{to_ref}"
    emit "br i1 #{cmp}, label %#{body_lbl}, label %#{end_lbl}"
    emit "#{body_lbl}:"

    # skip goes to inc_lbl (not cond_lbl) so increment always runs
    @loop_stack.push({ cond: inc_lbl, end: end_lbl })
    node.body.each { |s| emit_stmt(s) }
    @loop_stack.pop

    emit "br label %#{inc_lbl}" unless terminates?
    emit "#{inc_lbl}:"
    cur2 = new_reg; inc = new_reg
    emit "#{cur2} = load i64, i64* #{ptr}"
    emit "#{inc} = add i64 #{cur2}, 1"
    emit "store i64 #{inc}, i64* #{ptr}"
    emit "br label %#{cond_lbl}"
    emit "#{end_lbl}:"
  end

  def emit_break(node)
    lp = @loop_stack.last
    return emit('; break outside loop') unless lp

    if node.condition
      ref, _ = emit_expr(node.condition)
      after  = new_label('ab')
      emit "br i1 #{ref}, label %#{lp[:end]}, label %#{after}"
      emit "#{after}:"
    else
      emit "br label %#{lp[:end]}"
      emit "#{new_label('dead')}:"
    end
  end

  def emit_skip(node)
    lp = @loop_stack.last
    return emit('; skip outside loop') unless lp

    if node.condition
      ref, _ = emit_expr(node.condition)
      after  = new_label('as')
      emit "br i1 #{ref}, label %#{lp[:cond]}, label %#{after}"
      emit "#{after}:"
    else
      emit "br label %#{lp[:cond]}"
      emit "#{new_label('dead')}:"
    end
  end

  def emit_raise(node)
    g        = alloc_str("error: raise\n")
    err_lbl  = new_label('raise')
    cont_lbl = new_label('rc')

    if node.condition
      cref, _ = emit_expr(node.condition)
      emit "br i1 #{cref}, label %#{err_lbl}, label %#{cont_lbl}"
    else
      emit "br label %#{err_lbl}"
    end

    emit "#{err_lbl}:"
    emit "call i32 @puts(i8* #{str_ptr(g)})"
    emit 'call void @exit(i32 1)'
    emit 'unreachable'
    emit "#{cont_lbl}:"
  end

  # ---------- Expressions → [ref, type] ----------

  def emit_expr(node)
    case node
    when AST::IntLit      then [node.value.to_s, :int]
    when AST::FloatLit    then [llvm_float(node.value), :float]
    when AST::BoolLit     then [node.value ? '1' : '0', :bool]
    when AST::StringLit   then emit_string_lit(node)
    when AST::Ident       then emit_load(node.name)
    when AST::BinaryOp    then emit_binary(node)
    when AST::UnaryOp     then emit_unary(node)
    when AST::Call        then emit_call(node)
    when AST::MethodCall  then emit_method_call(node)
    when AST::IndexAccess then [emit_index_access(node), :unknown]
    when AST::Ternary     then emit_ternary(node)
    when AST::Match       then emit_match(node)
    when AST::Try, AST::Catch then emit_expr(node.expr)
    when AST::Range       then ['undef', :range_int]
    when AST::PathExpr    then ['0', :int]
    when AST::FieldAccess then ['0', :unknown]
    else ['0', :int]
    end
  end

  def llvm_float(v)
    '%.17e' % v
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
        t = new_reg; emit "#{t} = sitofp i64 #{lref} to double"; lref = t
      end
      if rtype == :int
        t = new_reg; emit "#{t} = sitofp i64 #{rref} to double"; rref = t
      end
    end

    op_lt  = use_float ? 'double' : lt(ltype)
    reg    = new_reg

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
      emit "#{reg} = and i1 #{lref}, #{rref}"; [reg, :bool]
    when 'or'
      emit "#{reg} = or i1 #{lref}, #{rref}";  [reg, :bool]
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
      emit "#{reg} = xor i1 #{ref}, 1"; [reg, :bool]
    else
      [ref, type]
    end
  end

  def emit_call(node)
    base = node.callee.name.delete_suffix('!').delete_suffix('?')

    case base
    when 'println' then emit_print(node.args.first, newline: true);  ['', :void]
    when 'print'   then emit_print(node.args.first, newline: false); ['', :void]
    else
      arg_vals  = node.args.map { |a| emit_expr(a) }
      args_str  = arg_vals.map { |r, t| "#{lt(t)} #{r}" }.join(', ')
      ret_type  = func_return_type(node.callee.name)

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
        interp.each do |var|
          var_type = @locals[var]&.dig(:type) || :string
          spec = case var_type
                 when :int   then '%lld'
                 when :float then '%g'
                 when :bool  then '%d'
                 else '%s'
                 end
          fmt.sub!("{#{var}}", spec)
          vref, vtype = emit_load(var)
          if vtype == :bool
            ext = new_reg; emit "#{ext} = zext i1 #{vref} to i32"
            arg_refs << "i32 #{ext}"
          else
            arg_refs << "#{lt(vtype)} #{vref}"
          end
        end
        fmt += "\n" if newline
        ptr   = str_ptr(alloc_str(fmt))
        all   = (["i8* #{ptr}"] + arg_refs).join(', ')
        emit "call i32 (i8*, ...) @printf(#{all})"
      end
    else
      ref, type = emit_expr(arg_node)
      fmt_str, extra = case type
                       when :int   then [newline ? "%lld\n" : '%lld', "i64 #{ref}"]
                       when :float then [newline ? "%g\n"   : '%g',   "double #{ref}"]
                       when :bool
                         ext = new_reg; emit "#{ext} = zext i1 #{ref} to i32"
                         [newline ? "%d\n" : '%d', "i32 #{ext}"]
                       else
                         ptr = str_ptr(alloc_str(''))
                         newline ? emit("call i32 @puts(i8* #{ref})") : emit("call i32 @printf(i8* #{ref})")
                         return
                       end
      ptr = str_ptr(alloc_str(fmt_str))
      emit "call i32 (i8*, ...) @printf(i8* #{ptr}, #{extra})"
    end
  end

  def emit_method_call(node)
    emit "; TODO method .#{node.method_name}"
    ['0', :int]
  end

  def emit_index_access(node)
    emit '; TODO index access'
    '0'
  end

  def emit_ternary(node)
    cond_ref, _ = emit_expr(node.condition)
    res_type    = infer_type(node.then_expr)
    ptr         = "#{new_reg}.tern"
    then_lbl    = new_label('tt')
    else_lbl    = new_label('te')
    merge_lbl   = new_label('tm')

    emit "#{ptr} = alloca #{lt(res_type)}"
    emit "br i1 #{cond_ref}, label %#{then_lbl}, label %#{else_lbl}"

    emit "#{then_lbl}:"
    tr, _ = emit_expr(node.then_expr)
    emit "store #{lt(res_type)} #{tr}, #{lt(res_type)}* #{ptr}"
    emit "br label %#{merge_lbl}"

    emit "#{else_lbl}:"
    er, _ = emit_expr(node.else_expr)
    emit "store #{lt(res_type)} #{er}, #{lt(res_type)}* #{ptr}"
    emit "br label %#{merge_lbl}"

    emit "#{merge_lbl}:"
    res = new_reg
    emit "#{res} = load #{lt(res_type)}, #{lt(res_type)}* #{ptr}"
    [res, res_type]
  end

  def emit_match(node)
    subj_ref, subj_type = emit_expr(node.value)
    end_lbl = new_label('me')

    node.arms.each_with_index do |arm, idx|
      arm_lbl  = new_label('ma')
      next_lbl = idx + 1 < node.arms.size ? new_label('mn') : end_lbl
      saved    = @locals.dup

      bind_arm_vars(arm, subj_ref, subj_type, idx)
      cref = arm_condition(arm, subj_ref, subj_type)

      if cref
        emit "br i1 #{cref}, label %#{arm_lbl}, label %#{next_lbl}"
      else
        emit "br label %#{arm_lbl}"
      end

      emit "#{arm_lbl}:"
      emit_expr(arm.body)
      emit "br label %#{end_lbl}" unless terminates?

      emit "#{next_lbl}:" if idx + 1 < node.arms.size
      @locals = saved
    end

    emit "#{end_lbl}:"
    ['undef', :unknown]
  end

  def bind_arm_vars(arm, subj_ref, subj_type, idx)
    case arm.pattern
    when AST::WithPattern, AST::IdentPattern
      name = arm.pattern.name
      return if name == '_'

      ptr = alloca_ptr("#{name}_#{idx}")
      emit "#{ptr} = alloca #{lt(subj_type)}"
      emit "store #{lt(subj_type)} #{subj_ref}, #{lt(subj_type)}* #{ptr}"
      @locals[name] = { ptr: ptr, type: subj_type }
    end
  end

  def arm_condition(arm, subj_ref, subj_type)
    base = case arm.pattern
           when AST::LiteralPattern
             pr, _ = emit_expr(arm.pattern.value)
             cmp   = new_reg
             op    = subj_type == :float ? 'fcmp oeq' : 'icmp eq'
             emit "#{cmp} = #{op} #{lt(subj_type)} #{subj_ref}, #{pr}"
             cmp
           else nil
           end

    return base unless arm.guard

    gr, _ = emit_expr(arm.guard)
    return gr unless base

    combined = new_reg
    emit "#{combined} = and i1 #{base}, #{gr}"
    combined
  end

  # ---------- Helpers ----------

  def llvm_name(name)
    name.delete_suffix('!').delete_suffix('?')
  end
end

# rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/AbcSize
