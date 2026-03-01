# Test: everything together — a small real program

func max(a: int, b: int) -> int
  if a > b
    return a
  else
    return b
  end
end

func factorial(n: int) -> int
  mut result: int = 1
  mut i: int = 1
  while i <= n
    result = result * i
    i = i + 1
  end
  return result
end

print("max: ", max(12, 7))
print("factorial: ", factorial(5))
