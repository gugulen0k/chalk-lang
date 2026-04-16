# frozen_string_literal: true

module AST
  Program = Struct.new(:stmts)

  # Declarations
  VarDecl     = Struct.new(:mutable, :name, :type, :value)
  FuncDecl    = Struct.new(:pub, :name, :failable, :bool_fn, :params, :return_type, :body)
  Param       = Struct.new(:name, :type)
  ConstDecl   = Struct.new(:name, :type, :value)
  ImportDecl  = Struct.new(:path, :import_alias, :items)
  StructDecl  = Struct.new(:pub, :name, :fields, :func_defs)
  StructField = Struct.new(:mutable, :name, :type, :default)
  EnumDecl    = Struct.new(:pub, :name, :variants)
  EnumVariant = Struct.new(:name, :type)
  ErrorDecl   = Struct.new(:pub, :name, :variants)

  # Statements
  Return   = Struct.new(:value)
  If       = Struct.new(:condition, :then_body, :else_body)
  While    = Struct.new(:condition, :body)
  ForIn    = Struct.new(:var, :index_var, :iterable, :body)
  Match    = Struct.new(:value, :arms)
  MatchArm = Struct.new(:pattern, :guard, :body)
  Raise    = Struct.new(:expr, :condition)
  Break    = Struct.new(:condition)
  Skip     = Struct.new(:condition)
  Assign   = Struct.new(:target, :value)
  ExprStmt = Struct.new(:expr)

  # Match patterns
  LiteralPattern = Struct.new(:value)
  WithPattern    = Struct.new(:name)
  IdentPattern   = Struct.new(:name)
  EnumPattern    = Struct.new(:enum_name, :variant, :binding)

  # Expressions
  IntLit       = Struct.new(:value)
  FloatLit     = Struct.new(:value)
  StringLit    = Struct.new(:value)
  BoolLit      = Struct.new(:value)
  Ident        = Struct.new(:name)
  BinaryOp     = Struct.new(:op, :left, :right)
  UnaryOp      = Struct.new(:op, :operand)
  Call         = Struct.new(:callee, :args)
  MethodCall   = Struct.new(:receiver, :method_name, :args)
  FieldAccess  = Struct.new(:receiver, :field)
  IndexAccess  = Struct.new(:receiver, :index)
  Range        = Struct.new(:from, :to, :inclusive)
  ArrayLit     = Struct.new(:elements)
  ArrayReserve = Struct.new(:capacity)
  StructLit    = Struct.new(:name, :fields)
  PathExpr     = Struct.new(:parts)
  Ternary      = Struct.new(:condition, :then_expr, :else_expr)
  Try          = Struct.new(:expr)
  Catch        = Struct.new(:expr, :handler)
  CatchBlock   = Struct.new(:arms)
end
