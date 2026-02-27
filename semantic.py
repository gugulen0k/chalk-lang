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


class ChalkError(Exception):
    """All semantic errors in Chalk raise this."""

    pass


class Symbol:
    """Represents a variable in the symbol table."""

    def __init__(self, name: str, type_: str, mutable: bool):
        self.name = name
        self.type_ = type_
        self.mutable = mutable


class FuncSymbol:
    """Represents a function in the symbol table."""

    def __init__(self, name: str, params: list, return_type: str):
        self.name = name
        self.params = params  # [("a", "int"), ("b", "int")]
        self.return_type = return_type


class Scope:
    """A single level of scope — one dictionary of symbols."""

    def __init__(self):
        self.symbols: dict[str, Symbol | FuncSymbol] = {}

    def define(self, name: str, symbol):
        self.symbols[name] = symbol

    def lookup(self, name: str):
        return self.symbols.get(name, None)


class SemanticAnalyzer:
    def __init__(self):
        # stack of scopes — index 0 is global, last is current
        self.scopes: list[Scope] = [Scope()]
        self.current_func: FuncSymbol | None = None

    # --------------------------------------------------------
    # SCOPE HELPERS
    # --------------------------------------------------------
    def _push_scope(self):
        self.scopes.append(Scope())

    def _pop_scope(self):
        self.scopes.pop()

    def _define(self, name: str, symbol):
        """Define a symbol in the current (innermost) scope."""
        self.scopes[-1].define(name, symbol)

    def _lookup(self, name: str):
        """Look up a symbol — search from innermost to outermost scope."""
        for scope in reversed(self.scopes):
            sym = scope.lookup(name)
            if sym is not None:
                return sym
        return None

    def _error(self, msg: str, line=None):
        prefix = f"[line #{line}]: " if line else ""
        raise ChalkError(f"* {prefix}{msg}")

    # --------------------------------------------------------
    # ENTRY POINT
    # --------------------------------------------------------
    def analyze(self, program: Program):
        for stmt in program.statements:
            self._check_stmt(stmt)

    # --------------------------------------------------------
    # STATEMENTS
    # --------------------------------------------------------
    def _check_stmt(self, node: Node):
        if isinstance(node, VarDecl):
            self._check_var_decl(node)
        elif isinstance(node, Assign):
            self._check_assign(node)
        elif isinstance(node, IfStmt):
            self._check_if(node)
        elif isinstance(node, WhileStmt):
            self._check_while(node)
        elif isinstance(node, FuncDef):
            self._check_func_def(node)
        elif isinstance(node, ReturnStmt):
            self._check_return(node)
        elif isinstance(node, PrintStmt):
            self._check_expr(node.value)
        elif isinstance(node, ExprStmt):
            self._check_expr(node.value)

    def _check_var_decl(self, node: VarDecl):
        # check the value expression is valid
        value_type = self._check_expr(node.value)

        # check type compatibility
        if value_type and value_type != node.type:
            self._error(
                f"type mismatch: '{node.name}' is '{node.type}' but got '{value_type}'",
                node.line,
            )

        # register in current scope
        self._define(node.name, Symbol(node.name, node.type, node.mutable))

    def _check_assign(self, node: Assign):
        sym = self._lookup(node.name)

        # variable must exist
        if sym is None:
            self._error(f"undefined variable '{node.name}'", node.line)

        # variable must be mutable
        if isinstance(sym, Symbol) and not sym.mutable:
            self._error(
                f"cannot assign to immutable variable '{node.name}'\n"
                f"hint: declare it as 'mut {node.name}: {sym.type_} = ...'",
                node.line,
            )

        # check the value expression is valid
        value_type = self._check_expr(node.value)

        # check type compatibility
        if value_type and value_type != sym.type_:
            self._error(
                f"type mismatch in assignment to '{node.name}': "
                f"expected '{sym.type_}', got '{value_type}'",
                node.line,
            )

    def _check_if(self, node: IfStmt):
        self._check_expr(node.condition)

        self._push_scope()
        for stmt in node.then_body:
            self._check_stmt(stmt)
        self._pop_scope()

        self._push_scope()
        for stmt in node.else_body:
            self._check_stmt(stmt)
        self._pop_scope()

    def _check_while(self, node: WhileStmt):
        self._check_expr(node.condition)

        self._push_scope()
        for stmt in node.body:
            self._check_stmt(stmt)
        self._pop_scope()

    def _check_func_def(self, node: FuncDef):
        # register the function in current scope FIRST
        # (allows recursive calls)
        func_sym = FuncSymbol(node.name, node.params, node.return_type)
        self._define(node.name, func_sym)

        # new scope for function body
        self._push_scope()
        prev_func = self.current_func
        self.current_func = func_sym

        # register params as variables inside the function
        for param_name, param_type in node.params:
            self._define(param_name, Symbol(param_name, param_type, mutable=False))

        for stmt in node.body:
            self._check_stmt(stmt)

        self.current_func = prev_func
        self._pop_scope()

    def _check_return(self, node: ReturnStmt):
        # return must be inside a function
        if self.current_func is None:
            self._error("'return' used outside of a function", node.line)

        return_type = self._check_expr(node.value)

        if return_type and return_type != self.current_func.return_type:
            self._error(
                f"return type mismatch in '{self.current_func.name}': "
                f"expected '{self.current_func.return_type}', got '{return_type}'",
                node.line,
            )

    # --------------------------------------------------------
    # EXPRESSIONS
    # Returns the type of the expression as a string,
    # or None if it can't be determined
    # --------------------------------------------------------
    def _check_expr(self, node: Node) -> str | None:
        if isinstance(node, Number):
            return "float" if isinstance(node.value, float) else "int"

        if isinstance(node, String):
            return "string"

        if isinstance(node, Bool):
            return "bool"

        if isinstance(node, Var):
            sym = self._lookup(node.name)
            if sym is None:
                self._error(f"undefined variable '{node.name}'", node.line)
            return sym.type_

        if isinstance(node, UnaryOp):
            operand_type = self._check_expr(node.operand)
            if operand_type not in ("int", "float"):
                self._error(
                    f"unary '-' requires int or float, got '{operand_type}'", node.line
                )
            return operand_type

        if isinstance(node, BinOp):
            return self._check_binop(node)

        if isinstance(node, FuncCall):
            return self._check_func_call(node)

        return None

    def _check_binop(self, node: BinOp) -> str | None:
        left_type = self._check_expr(node.left)
        right_type = self._check_expr(node.right)

        # comparison operators always return bool
        if node.op in ("==", "!=", "<", ">", "<=", ">="):
            if left_type != right_type:
                self._error(
                    f"cannot compare '{left_type}' and '{right_type}'", node.line
                )
            return "bool"

        # arithmetic operators
        if node.op in ("+", "-", "*", "/"):
            if left_type != right_type:
                self._error(
                    f"type mismatch: cannot apply '{node.op}' "
                    f"to '{left_type}' and '{right_type}'",
                    node.line,
                )
            return left_type

        return None

    def _check_func_call(self, node: FuncCall) -> str | None:
        sym = self._lookup(node.name)

        if sym is None:
            self._error(f"undefined function '{node.name}'", node.line)

        if not isinstance(sym, FuncSymbol):
            self._error(f"'{node.name}' is a variable, not a function", node.line)

        # check argument count
        if len(node.args) != len(sym.params):
            self._error(
                f"'{node.name}' expects {len(sym.params)} argument(s), "
                f"got {len(node.args)}",
                node.line,
            )

        # check argument types
        for i, (arg, (param_name, param_type)) in enumerate(zip(node.args, sym.params)):
            arg_type = self._check_expr(arg)
            if arg_type and arg_type != param_type:
                self._error(
                    f"argument {i + 1} of '{node.name}': "
                    f"expected '{param_type}', got '{arg_type}'",
                    node.line,
                )

        return sym.return_type
