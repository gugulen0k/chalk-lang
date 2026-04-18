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

@str0 = private unnamed_addr constant [20 x i8] c"%lld + %lld = %lld\0A\00"
@str1 = private unnamed_addr constant [20 x i8] c"%lld * %lld = %lld\0A\00"
@str2 = private unnamed_addr constant [14 x i8] c"nested: %lld\0A\00"
@str3 = private unnamed_addr constant [12 x i8] c"expr: %lld\0A\00"
define i64 @add(i64 %a, i64 %b) {
entry:
  %a.addr = alloca i64
  store i64 %a, i64* %a.addr
  %b.addr = alloca i64
  store i64 %b, i64* %b.addr
  %t0 = load i64, i64* %a.addr
  %t1 = load i64, i64* %b.addr
  %t2 = add i64 %t0, %t1
  ret i64 %t2
dead0:
  unreachable
}

define i64 @multiply(i64 %a, i64 %b) {
entry:
  %a.addr = alloca i64
  store i64 %a, i64* %a.addr
  %b.addr = alloca i64
  store i64 %b, i64* %b.addr
  %t0 = load i64, i64* %a.addr
  %t1 = load i64, i64* %b.addr
  %t2 = mul i64 %t0, %t1
  ret i64 %t2
dead0:
  unreachable
}

define i32 @main() {
entry:
  %x.addr = alloca i64
  store i64 10, i64* %x.addr
  %y.addr = alloca i64
  store i64 5, i64* %y.addr
  %t0 = load i64, i64* %x.addr
  %t1 = load i64, i64* %y.addr
  %t2 = load i64, i64* %x.addr
  %t3 = load i64, i64* %y.addr
  %t4 = call i64 @add(i64 %t2, i64 %t3)
  %t5 = getelementptr inbounds [20 x i8], [20 x i8]* @str0, i32 0, i32 0
  call i32 (i8*, ...) @printf(i8* %t5, i64 %t0, i64 %t1, i64 %t4)
  %t6 = load i64, i64* %x.addr
  %t7 = load i64, i64* %y.addr
  %t8 = load i64, i64* %x.addr
  %t9 = load i64, i64* %y.addr
  %t10 = call i64 @multiply(i64 %t8, i64 %t9)
  %t11 = getelementptr inbounds [20 x i8], [20 x i8]* @str1, i32 0, i32 0
  call i32 (i8*, ...) @printf(i8* %t11, i64 %t6, i64 %t7, i64 %t10)
  %t12 = load i64, i64* %x.addr
  %t13 = load i64, i64* %y.addr
  %t14 = call i64 @add(i64 %t12, i64 %t13)
  %t15 = call i64 @multiply(i64 %t14, i64 2)
  %t16 = getelementptr inbounds [14 x i8], [14 x i8]* @str2, i32 0, i32 0
  call i32 (i8*, ...) @printf(i8* %t16, i64 %t15)
  %t17 = load i64, i64* %x.addr
  %t18 = load i64, i64* %y.addr
  %t19 = add i64 %t17, %t18
  %t20 = getelementptr inbounds [12 x i8], [12 x i8]* @str3, i32 0, i32 0
  call i32 (i8*, ...) @printf(i8* %t20, i64 %t19)
  ret i32 0
}
