# Test: arithmetic and operator precedence
a: int = 10
b: int = 3

sum: int = a + b
diff: int = a - b
prod: int = a * b

# operator precedence: should be 10 + (3 * 2) = 16, not (10 + 3) * 2 = 26
precedence: int = a + b * 2

print(sum)
print(diff)
print(prod)
print(precedence)
