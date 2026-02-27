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
        val = float(args[0])
        # store as int if it's a whole number
        return Number(
            value=int(val) if val.is_integer() else val, line=self._line(args)
        )

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
        call_args = list(args[1:])

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

    def if_stmt(self, args):
        condition = args[0]

        # find where else starts by looking for non-Node items
        # everything after condition is statements — split by position
        rest = args[1:]

        # lark puts all then+else statements flat in args
        # we split them by finding "else" marker — but since
        # we don't emit a token for else, we use the grammar structure:
        # if_stmt has condition + then_stmts + (optionally) else_stmts
        # lark groups them, so we slice from grammar shape
        # simplest approach: all args after condition are then_body,
        # unless the grammar gives us two groups (handled below)
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
        # params is a list of tuples, return type is a string
        # find where params end and return type begins
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
        return list(args)

    def param(self, args):
        return (str(args[0]), str(args[1]))  # ("name", "type")

    def return_stmt(self, args):
        return ReturnStmt(value=args[0], line=self._line(args))

    def print_stmt(self, args):
        return PrintStmt(value=args[0], line=self._line(args))

    def expr_stmt(self, args):
        return ExprStmt(value=args[0], line=self._line(args))

    def _line(self, args):
        for a in args:
            if isinstance(a, Token):
                return a.line
            if isinstance(a, Node) and a.line is not None:
                return a.line
        return None
