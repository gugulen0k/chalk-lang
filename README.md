# Sheft

Sheft is a statically typed compiled language with clean, minimal syntax. Compiles to LLVM IR and then to a native binary. Source files use `.sf` extension. Blocks end with `end`, no semicolons.

---

## Usage

```bash
./sheftc run hello.sf        # compile and run
./sheftc hello.sf -o hello   # compile to binary
./hello
```

---

## Types

| Type     | Description              |
|----------|--------------------------|
| `int`    | 64-bit signed integer    |
| `float`  | 64-bit floating point    |
| `string` | immutable string         |
| `bool`   | `true` or `false`        |
| `void`   | function return only     |

---

## Variables

Immutable by default. `mut` enables reassignment.

```
x: int = 10        # immutable
mut y: int = 5     # mutable

y = 20             # ok
x = 99             # error: cannot assign to immutable variable
```

---

## Literals

```
42          # int
3.14        # float
'hello'     # string (single quotes only — double quotes are a compile error)
true        # bool
false       # bool
```

String escape sequences: `\n`, `\t`, `\r`, `\0`, `\\`, `\'`

---

## Comments

```
# single line comment
x: int = 10   # inline comment

#[
  multiline comment
]#

##[ doc comment — required on pub items ]##
```

---

## Operators

**Arithmetic:** `+`, `-`, `*`, `/`, `%`

**Comparison:** `==`, `!=`, `<`, `>`, `<=`, `>=`

**Logical:** `and`, `or`, `not`

Arithmetic promotes `int` to `float` automatically when one operand is `float`. Standard precedence: `*` `/` `%` bind tighter than `+` `-`.

---

## Control Flow

### If / Else

```
if x > 10
  println('big')
else
  println('small')
end
```

`else` is optional.

### While

```
mut i: int = 0
while i < 5
  println(f'{i}')
  i = i + 1
end
```

---

## Functions

```
func add(a: int, b: int) -> int
  return a + b
end

func greet(name: string) -> void
  println(f'Hello, {name}!')
end

result: int = add(3, 7)
greet('world')
```

- `pub func` — public function
- `func name!()` — failable function; callers must `try` or handle the error
- `func name?()` — must return `bool`

---

## Print

```
print('no newline')
println('with newline')
println(42)
println(3.14)
println(f'x = {x}, sum = {x + y}')
```

`f'...'` strings support arbitrary expression interpolation with `{expr}`.

---

## Error Handling

Declare an error set:

```
error MathError ( DivisionByZero, Overflow )
```

Raise inside a failable function (`!`):

```
func div!(a: int, b: int) -> int
  raise MathError.DivisionByZero if b == 0
  return a / b
end
```

Propagate with `try` (only valid inside a `!` function):

```
func safe_div!(a: int, b: int) -> int
  result: int = try div!(a, b)
  return result
end
```

If `try` detects an error, the function returns a zero value immediately and the error code propagates to the caller.

---

## Full Example

```
error MathError ( DivisionByZero )

func div!(a: int, b: int) -> int
  raise MathError.DivisionByZero if b == 0
  return a / b
end

func factorial(n: int) -> int
  if n <= 1
    return 1
  end
  return n * factorial(n - 1)
end

pub func main() -> void
  result: int = try div!(10, 2)
  println(f'10 / 2 = {result}')

  mut i: int = 1
  while i <= 5
    println(f'{i}! = {factorial(i)}')
    i = i + 1
  end
end
```
