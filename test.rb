#!/usr/bin/env ruby
# frozen_string_literal: true

require 'English'

# rubocop:disable Metrics/MethodLength, Metrics/AbcSize

PASS  = "\e[32mPASS\e[0m"
FAIL  = "\e[31mFAIL\e[0m"
RED   = "\e[31m"
RESET = "\e[0m"

@pass = 0
@fail = 0

def compile(sf_file)
  ll_file = sf_file.sub(/\.sf$/, '.ll')
  result  = `ruby main.rb #{sf_file} 2>&1`
  [ll_file, $CHILD_STATUS.success?, result]
end

def build_and_run(ll_file)
  obj = '/tmp/sheft_test.o'
  bin = '/tmp/sheft_test'
  `llc -filetype=obj #{ll_file} -o #{obj} 2>&1`
  return nil unless $CHILD_STATUS.success?

  `gcc -no-pie #{obj} -o #{bin} 2>&1`
  return nil unless $CHILD_STATUS.success?

  output = `#{bin} 2>&1`
  $CHILD_STATUS.success? ? output.chomp : nil
end

def test_ok(label, sf_file, expected_output)
  ll_file, ok, err = compile(sf_file)
  unless ok
    puts "#{FAIL} #{label}"
    puts "  #{RED}compile error:#{RESET} #{err.lines.first&.chomp}"
    @fail += 1
    return
  end

  actual = build_and_run(ll_file)
  if actual.nil?
    puts "#{FAIL} #{label}"
    puts "  #{RED}link/run failed#{RESET}"
    @fail += 1
  elsif actual == expected_output
    puts "#{PASS} #{label}"
    @pass += 1
  else
    puts "#{FAIL} #{label}"
    puts "  #{RED}expected:#{RESET} #{expected_output.inspect}"
    puts "  #{RED}actual:  #{RESET} #{actual.inspect}"
    @fail += 1
  end
end

def test_err(label, sf_file, expected_in_stderr)
  _ll, ok, output = compile(sf_file)
  if ok
    puts "#{FAIL} #{label}"
    puts "  #{RED}expected compile error but succeeded#{RESET}"
    @fail += 1
  elsif output.include?(expected_in_stderr)
    puts "#{PASS} #{label}"
    @pass += 1
  else
    puts "#{FAIL} #{label}"
    puts "  #{RED}expected stderr to contain:#{RESET} #{expected_in_stderr.inspect}"
    puts "  #{RED}actual stderr:#{RESET} #{output.lines.first&.chomp}"
    @fail += 1
  end
end

DIR = 'examples/tests'

puts "\n\e[1m=== Happy path ===\e[0m\n\n"

test_ok 'f-string: variable + function call + nested + expr',
        "#{DIR}/fstring.sf",
        "10 + 5 = 15\n10 * 5 = 50\nnested: 30\nexpr: 15"

test_ok 'control flow: for loop, while loop, if/else',
        "#{DIR}/control_flow.sf",
        "sum 1..10 = 55\nfirst power of 2 >= 32 is 32\nB"

test_ok 'recursion: factorial and fibonacci',
        "#{DIR}/recursion.sf",
        "5! = 120\n10! = 3628800\nfib(10) = 55"

test_ok 'bool logic: bool functions, and/or/not',
        "#{DIR}/bool_logic.sf",
        "1\n0\n1\n0\n0\n1\n0"

test_ok 'fizzbuzz (1..20)',
        'examples/fizzbuzz.sf',
        "1\n2\nFizz\n4\nBuzz\nFizz\n7\n8\nFizz\nBuzz\n11\nFizz\n13\n14\nFizzBuzz\n16\n17\nFizz\n19\nBuzz"

test_ok 'hello world',
        'examples/hello.sf',
        'Hello, world!'

puts "\n\e[1m=== Error diagnostics ===\e[0m\n\n"

test_err 'undefined variable → did you mean?',
         "#{DIR}/err_undef_var.sf",
         "did you mean 'name'?"

test_err 'undefined function → did you mean?',
         "#{DIR}/err_undef_func.sf",
         "did you mean 'greet'?"

test_err 'missing return in non-void function',
         "#{DIR}/err_missing_return.sf",
         'has no return statement'

test_err 'type mismatch: int ← string',
         "#{DIR}/err_type_mismatch.sf",
         "expected 'int', got 'string'"

test_err 'wrong argument count',
         "#{DIR}/err_wrong_args.sf",
         'expects 2 argument(s), got 3'

puts "\n#{'─' * 40}"
fail_str = @fail.positive? ? "#{RED}#{@fail} failed#{RESET}" : "#{@fail} failed"
puts "  #{@pass + @fail} tests: \e[32m#{@pass} passed\e[0m, #{fail_str}"
puts

exit @fail.positive? ? 1 : 0
