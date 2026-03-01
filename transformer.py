from lark import Token, Transformer

from ast_nodes import (
    Assign,
    BinOp,
    Bool,
    ExprStmt,
    FuncCall,
    FuncDef,
    IfStmt,
    Node,
    Number,
    PrintStmt,
    Program,
    ReturnStmt,
    String,
    UnaryOp,
    Var,
    VarDecl,
    WhileStmt,
)


class ChalkTransformer(Transformer):
    MUTABLE_KEYWORD = "mut"

    # --------------------------------------------------------
    # PROGRAM ROOT
    # --------------------------------------------------------
    def start(self, statements):
        return Program(statements=list(statements))

    # --------------------------------------------------------
    # LITERALS
    # --------------------------------------------------------
    def number(self, args):
        raw = str(args[0])
        # use the source token to decide: '2.0' is float, '2' is int
        value = float(raw) if "." in raw else int(raw)
        return Number(value=value, line=self._line(args))

    def string(self, args):
        raw = str(args[0])

        return String(value=raw[1:-1], line=self._line(args))

    def true(self, args):
        return Bool(value=True)

    def false(self, args):
        return Bool(value=False)

    # --------------------------------------------------------
    # VARIABLE REFERENCE
    # --------------------------------------------------------
    def var(self, args):
        return Var(name=str(args[0]), line=self._line(args))

    # --------------------------------------------------------
    # EXPRESSIONS
    # --------------------------------------------------------
    def negate(self, args):
        return UnaryOp(op="-", operand=args[0], line=self._line(args))

    def addition(self, args):
        return self._binop(args)

    def multiplication(self, args):
        return self._binop(args)

    def comparison(self, args):
        return self._binop(args)

    def _binop(self, args):
        # args = [left, op, right, op, right, ...]
        # we fold left to right: ((a + b) + c)
        result = args[0]

        i = 1

        while i < len(args):
            op = str(args[i])
            right = args[i + 1]
            result = BinOp(left=result, op=op, right=right, line=self._line(args))
            i += 2

        return result

    def func_call(self, args):
        name = str(args[0])
        call_args = [a for a in args[1:] if not isinstance(a, Token)]

        return FuncCall(name=name, args=call_args, line=self._line(args))

    # --------------------------------------------------------
    # STATEMENTS
    # --------------------------------------------------------
    def var_decl(self, args):
        # check if first token is 'mut'
        if isinstance(args[0], Token) and args[0] == self.MUTABLE_KEYWORD:
            mutable, name, type_, value = True, str(args[1]), str(args[2]), args[3]
        else:
            mutable, name, type_, value = (
                False,
                str(args[0]),
                str(args[1]),
                args[2],
            )

        return VarDecl(
            name=name, type=type_, value=value, mutable=mutable, line=self._line(args)
        )

    def assign(self, args):
        return Assign(name=str(args[0]), value=args[1], line=self._line(args))

    def else_clause(self, args):
        return [s for s in args if isinstance(s, Node)]

    def if_stmt(self, args):
        condition = args[0]
        rest = args[1:]

        # else_clause() returns a plain list, so it's the only list in args.
        # All then-branch statements are Node instances.
        if rest and isinstance(rest[-1], list):
            else_body = rest[-1]
            then_body = [s for s in rest[:-1] if isinstance(s, Node)]
        else:
            then_body = [s for s in rest if isinstance(s, Node)]
            else_body = []

        return IfStmt(
            condition=condition,
            then_body=then_body,
            else_body=else_body,
            line=self._line(args),
        )

    def while_stmt(self, args):
        condition = args[0]

        body = [s for s in args[1:] if isinstance(s, Node)]

        return WhileStmt(condition=condition, body=body, line=self._line(args))

    def func_def(self, args):
        name = str(args[0])
        # params() returns a list, so args[1] is either that list or the return type string
        params = args[1] if isinstance(args[1], list) else []
        return_type = str(args[2]) if isinstance(args[1], list) else str(args[1])
        body = [s for s in args if isinstance(s, Node)]

        return FuncDef(
            name=name,
            params=params,
            return_type=return_type,
            body=body,
            line=self._line(args),
        )

    def params(self, args):
        return [a for a in args if not isinstance(a, Token)]

    def param(self, args):
        return (str(args[0]), str(args[1]))  # ("name", "type")

    def return_stmt(self, args):
        value = args[0] if args and isinstance(args[0], Node) else None
        return ReturnStmt(value=value, line=self._line(args))

    def print_stmt(self, args):
        values = [a for a in args if isinstance(a, Node)]
        return PrintStmt(values=values, line=self._line(args))

    def expr_stmt(self, args):
        return ExprStmt(value=args[0], line=self._line(args))

    def _line(self, args):
        for a in args:
            if isinstance(a, Token):
                return a.line
            if isinstance(a, Node) and a.line is not None:
                return a.line
        return None
