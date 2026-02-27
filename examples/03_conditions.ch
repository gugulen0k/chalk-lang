# Test: if / else branches
x: int = 10
y: int = 20

if x > y
  print("x is bigger")
else
  print("y is bigger")
end

# Test: nested if
if x > 0
  if y > 0
    print("both positive")
  else
    print("y is not positive")
  end
else
  print("x is not positive")
end
