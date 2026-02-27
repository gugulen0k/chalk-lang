# Chalk

Chalk is a statically typed, interpreted language with a clean and minimal syntax.
It uses `end` to close blocks instead of braces, and enforces explicit mutability.

---

## Types

| Type     | Example          |
|----------|------------------|
| `int`    | `42`             |
| `float`  | `3.14`           |
| `string` | `"hello"`        |
| `bool`   | `true`, `false`  |

---

## Variables

Variables are **immutable by default**. Use `mut` to allow reassignment.

```
x: int = 10        # immutable
mut y: int = 5     # mutable

y = 20             # ok
x = 99             # error: cannot assign to immutable variable
```

---

## Comments

```
# This is a comment
x: int = 10  # inline comment
```

---

## Operators

**Arithmetic:** `+`, `-`, `*`, `/`

**Comparison:** `==`, `!=`, `<`, `>`, `<=`, `>=`

**Unary:** `-` (negation)

Operator precedence follows standard math rules — `*` and `/` bind tighter than `+` and `-`.

```
x: int = 2 + 3 * 4   # 14, not 20
```

---

## Control Flow

### If / Else

```
if x > 10
  print("big")
else
  print("small")
end
```

The `else` branch is optional.

### While

```
mut i: int = 0
while i < 5
  print(i)
  i = i + 1
end
```

---

## Functions

Functions are declared with `func`, take typed parameters, and require an explicit return type.

```
func add(a: int, b: int) -> int
  return a + b
end

result: int = add(3, 7)
```

---

## Print

`print` is a built-in statement for outputting a value.

```
print("hello")
print(42)
print(x + y)
```

---

## Line Continuation

Long expressions can be split across lines with a backslash:

```
x: int = 1 + 2 \
         + 3 + 4
```

---

## Full Example

```
# Compute and print triangle numbers
func triangle(n: int) -> int
  return n * (n + 1) / 2
end

mut i: int = 1
while i <= 5
  print(triangle(i))
  i = i + 1
end
```
