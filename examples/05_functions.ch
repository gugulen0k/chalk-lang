# Test: function definition and calls
func add(a: int, b: int) -> bool
  return a + b
end

func multiply(a: int, b: int) -> int
  return a * b
end

result1: int = add(3, 7)
result2: int = multiply(4, 5)

print(result1)
print(result2)

# Test: function call inside expression
result3: int = add(result1, result2)
print(result3)
