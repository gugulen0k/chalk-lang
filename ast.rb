# frozen_string_literal: true

module AST
  Program = Struct.new(:stmts)

  # Declarations
  VarDecl   = Struct.new(:mutable, :name, :type, :value, :line)
  FuncDecl  = Struct.new(:pub, :name, :failable, :bool_fn, :params, :return_type, :body, :line)
  Param     = Struct.new(:name, :type)
  ErrorDecl = Struct.new(:pub, :name, :variants)

  # Statements
  Return   = Struct.new(:value, :line)
  If       = Struct.new(:condition, :then_body, :else_body)
  While    = Struct.new(:condition, :body)
  Raise    = Struct.new(:expr, :condition)
  Assign   = Struct.new(:target, :value)
  ExprStmt = Struct.new(:expr)

  # Expressions
  IntLit    = Struct.new(:value)
  FloatLit  = Struct.new(:value)
  StringLit = Struct.new(:value)
  BoolLit   = Struct.new(:value)
  Ident     = Struct.new(:name, :line)
  BinaryOp  = Struct.new(:op, :left, :right)
  UnaryOp   = Struct.new(:op, :operand)
  Call      = Struct.new(:callee, :args, :line)
  Try       = Struct.new(:expr)
end
