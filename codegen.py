from ast_nodes import (
    Assign,
    BinOp,
    Bool,
    ExprStmt,
    FuncCall,
    FuncDef,
    IfStmt,
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


def chalk_type_to_c(type_: str) -> str:
    mapping = {
        "int": "int",
        "float": "float",
        "string": "char*",
        "bool": "int",
        "void": "void",
    }
    return mapping[type_]


class CodeGenerator:
    def __init__(self):
        self.indent_level = 0  # tracks how deep we are in blocks
        self.output = []  # list of generated lines
        self._var_types: dict[str, str] = {}
        self._func_return_types: dict[str, str] = {}

    def _indent(self) -> str:
        return "    " * self.indent_level  # 4 spaces per level

    def _emit(self, line: str):
        self.output.append(self._indent() + line)

    def generate(self, program: Program) -> str:
        self._emit("#include <stdio.h>")
        self._emit("#include <string.h>")
        self._emit("")

        # Function definitions go at file scope (valid C).
        for stmt in program.statements:
            if isinstance(stmt, FuncDef):
                self._gen_stmt(stmt)

        # Everything else (declarations, prints, calls) must be inside
        # a function in C, so we wrap them in a generated main().
        non_func = [s for s in program.statements if not isinstance(s, FuncDef)]
        if non_func:
            self._emit("int main() {")
            self.indent_level += 1
            for stmt in non_func:
                self._gen_stmt(stmt)
            self._emit("return 0;")
            self.indent_level -= 1
            self._emit("}")

        return "\n".join(self.output)

    def _gen_expr(self, node) -> str:
        match node:
            case Number(value=v):
                return str(v)

            case String(value=v):
                return f'"{v}"'  # wrap in C double quotes

            case Bool(value=v):
                return "1" if v else "0"  # true→1, false→0

            case Var(name=n):
                return n  # just the variable name

            case UnaryOp(op="-", operand=operand):
                return f"-{self._gen_expr(operand)}"

            case BinOp(left=left, op=op, right=right):
                l = self._gen_expr(left)
                r = self._gen_expr(right)
                return f"({l} {op} {r})"  # wrap in parens for safety

            case FuncCall(name=name, args=args):
                args_str = ", ".join(self._gen_expr(a) for a in args)
                return f"{name}({args_str})"

    def _gen_stmt(self, node):
        match node:
            case VarDecl(name=name, type=type_, value=value, mutable=mutable):
                self._var_types[name] = type_
                c_type = chalk_type_to_c(type_)
                c_value = self._gen_expr(value)
                if mutable:
                    self._emit(f"{c_type} {name} = {c_value};")
                else:
                    self._emit(f"const {c_type} {name} = {c_value};")

            case Assign(name=name, value=value):
                c_value = self._gen_expr(value)
                self._emit(f"{name} = {c_value};")

            case PrintStmt(values=values):
                self._gen_print(values)

            case ReturnStmt(value=value):
                if value is None:
                    self._emit("return;")
                else:
                    self._emit(f"return {self._gen_expr(value)};")

            case ExprStmt(value=value):
                self._emit(f"{self._gen_expr(value)};")

            case IfStmt(condition=cond, then_body=then_body, else_body=else_body):
                self._emit(f"if ({self._gen_expr(cond)}) {{")
                self.indent_level += 1
                for stmt in then_body:
                    self._gen_stmt(stmt)
                self.indent_level -= 1
                if else_body:
                    self._emit("} else {")
                    self.indent_level += 1
                    for stmt in else_body:
                        self._gen_stmt(stmt)
                    self.indent_level -= 1
                self._emit("}")

            case WhileStmt(condition=cond, body=body):
                self._emit(f"while ({self._gen_expr(cond)}) {{")
                self.indent_level += 1
                for stmt in body:
                    self._gen_stmt(stmt)
                self.indent_level -= 1
                self._emit("}")

            case FuncDef(name=name, params=params, return_type=return_type, body=body):
                self._func_return_types[name] = return_type

                for param_name, param_type in params:
                    self._var_types[param_name] = param_type

                c_return = chalk_type_to_c(return_type)
                c_params = ", ".join(f"{chalk_type_to_c(t)} {n}" for n, t in params)

                self._emit(f"{c_return} {name}({c_params}) {{")
                self.indent_level += 1

                for stmt in body:
                    self._gen_stmt(stmt)

                self.indent_level -= 1
                self._emit("}")
                self._emit("")  # blank line after function

    def _expr_type(self, node) -> str | None:
        match node:
            case Number(value=v):
                return "float" if isinstance(v, float) else "int"
            case String():
                return "string"
            case Bool():
                return "bool"
            case Var(name=name):
                return self._var_types.get(name)
            case UnaryOp(operand=operand):
                return self._expr_type(operand)
            case BinOp(op=op, left=left):
                if op in ("==", "!=", "<", ">", "<=", ">="):
                    return "bool"
                return self._expr_type(left)
            case FuncCall(name=name):
                return self._func_return_types.get(name)
        return None

    def _fmt(self, type_: str | None) -> str:
        """Return the printf format specifier for a single value."""
        match type_:
            case "string":
                return "%s"
            case "float":
                return "%f"
            case "bool":
                return "%d"
            case "int":
                return "%d"
            case _:
                return "%d"

    def _gen_print(self, values):
        fmt = "".join(self._fmt(self._expr_type(v)) for v in values) + "\\n"
        args = ", ".join(self._gen_expr(v) for v in values)
        self._emit(f'printf("{fmt}", {args});')
