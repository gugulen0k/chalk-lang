from dataclasses import dataclass, field
from typing import Optional


# ============================================================
# BASE CLASS
# Every AST node inherits from this.
# 'line' tracks where in the source file this node came from
# — useful for error messages later.
# ============================================================
@dataclass(kw_only=True)
class Node:
    line: Optional[int] = field(default=None, repr=False)


# ============================================================
# LITERALS — raw values in the source code
# ============================================================
@dataclass
class Number(Node):
    value: float


@dataclass
class String(Node):
    value: str


@dataclass
class Bool(Node):
    value: bool


# ============================================================
# VARIABLE REFERENCE
# When you write 'x' in an expression — this is it
# ============================================================
@dataclass
class Var(Node):
    name: str


# ============================================================
# BINARY OPERATION
# Covers: +, -, *, /, ==, !=, <, >, <=, >=
#
# Example: a + b
#   BinOp(left=Var("a"), op="+", right=Var("b"))
# ============================================================
@dataclass
class BinOp(Node):
    left: Node
    op: str
    right: Node


# ============================================================
# UNARY OPERATION
# Currently just negation: -x
#
# Example: -5
#   UnaryOp(op="-", operand=Number(5))
# ============================================================
@dataclass
class UnaryOp(Node):
    op: str
    operand: Node


# ============================================================
# FUNCTION CALL
#
# Example: add(1, 2)
#   FuncCall(name="add", args=[Number(1), Number(2)])
# ============================================================
@dataclass
class FuncCall(Node):
    name: str
    args: list[Node]


# ============================================================
# STATEMENTS
# ============================================================
@dataclass
class VarDecl(Node):
    name: str
    type: str
    value: Node
    mutable: bool  # True if declared with 'mut'


@dataclass
class Assign(Node):
    name: str
    value: Node


@dataclass
class IfStmt(Node):
    condition: str
    then_body: list[Node]
    else_body: list[Node]  # empty list if no else branch


@dataclass
class WhileStmt(Node):
    condition: str
    body: list[Node]


@dataclass
class FuncDef(Node):
    name: str
    params: list[tuple[str, str]]
    return_type: str
    body: list[Node]


@dataclass
class ReturnStmt(Node):
    value: Optional[Node]  # None when parsed as bare 'return'; always a semantic error


@dataclass
class PrintStmt(Node):
    values: list[Node]  # one or more expressions printed as a single line


@dataclass
class ExprStmt(Node):
    value: Node


# ============================================================
# PROGRAM ROOT
# The top-level node — holds all statements
# ============================================================
@dataclass
class Program(Node):
    statements: list[Node]
