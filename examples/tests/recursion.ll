declare i32 @puts(i8*)
declare i32 @printf(i8*, ...)
declare void @exit(i32)
declare i8* @malloc(i64)
declare i8* @realloc(i8*, i64)
declare void @free(i8*)

%SheftArr_int   = type { i64*, i64, i64 }
%SheftArr_float = type { double*, i64, i64 }
%SheftArr_str   = type { i8**, i64, i64 }
%SheftArr_bool  = type { i1*, i64, i64 }

@str0 = private unnamed_addr constant [11 x i8] c"5! = %lld\0A\00"
@str1 = private unnamed_addr constant [12 x i8] c"10! = %lld\0A\00"
@str2 = private unnamed_addr constant [16 x i8] c"fib(10) = %lld\0A\00"
define i64 @factorial(i64 %n) {
entry:
  %n.addr = alloca i64
  store i64 %n, i64* %n.addr
  %t0 = load i64, i64* %n.addr
  %t1 = icmp sle i64 %t0, 1
  br i1 %t1, label %then0, label %merge1
then0:
  ret i64 1
dead2:
  br label %merge1
merge1:
  %t2 = load i64, i64* %n.addr
  %t3 = load i64, i64* %n.addr
  %t4 = sub i64 %t3, 1
  %t5 = call i64 @factorial(i64 %t4)
  %t6 = mul i64 %t2, %t5
  ret i64 %t6
dead3:
  unreachable
}

define i64 @fib(i64 %n) {
entry:
  %n.addr = alloca i64
  store i64 %n, i64* %n.addr
  %t0 = load i64, i64* %n.addr
  %t1 = icmp sle i64 %t0, 1
  br i1 %t1, label %then0, label %merge1
then0:
  %t2 = load i64, i64* %n.addr
  ret i64 %t2
dead2:
  br label %merge1
merge1:
  %t3 = load i64, i64* %n.addr
  %t4 = sub i64 %t3, 1
  %t5 = call i64 @fib(i64 %t4)
  %t6 = load i64, i64* %n.addr
  %t7 = sub i64 %t6, 2
  %t8 = call i64 @fib(i64 %t7)
  %t9 = add i64 %t5, %t8
  ret i64 %t9
dead3:
  unreachable
}

define i32 @main() {
entry:
  %t0 = call i64 @factorial(i64 5)
  %t1 = getelementptr inbounds [11 x i8], [11 x i8]* @str0, i32 0, i32 0
  call i32 (i8*, ...) @printf(i8* %t1, i64 %t0)
  %t2 = call i64 @factorial(i64 10)
  %t3 = getelementptr inbounds [12 x i8], [12 x i8]* @str1, i32 0, i32 0
  call i32 (i8*, ...) @printf(i8* %t3, i64 %t2)
  %t4 = call i64 @fib(i64 10)
  %t5 = getelementptr inbounds [16 x i8], [16 x i8]* @str2, i32 0, i32 0
  call i32 (i8*, ...) @printf(i8* %t5, i64 %t4)
  ret i32 0
}
