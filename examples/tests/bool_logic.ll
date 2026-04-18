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

@str0 = private unnamed_addr constant [4 x i8] c"%d\0A\00"
@str1 = private unnamed_addr constant [4 x i8] c"%d\0A\00"
@str2 = private unnamed_addr constant [4 x i8] c"%d\0A\00"
@str3 = private unnamed_addr constant [4 x i8] c"%d\0A\00"
@str4 = private unnamed_addr constant [4 x i8] c"%d\0A\00"
@str5 = private unnamed_addr constant [4 x i8] c"%d\0A\00"
@str6 = private unnamed_addr constant [4 x i8] c"%d\0A\00"
define i1 @is_even(i64 %n) {
entry:
  %n.addr = alloca i64
  store i64 %n, i64* %n.addr
  %t0 = load i64, i64* %n.addr
  %t1 = srem i64 %t0, 2
  %t2 = icmp eq i64 %t1, 0
  ret i1 %t2
dead0:
  unreachable
}

define i1 @in_range(i64 %n, i64 %lo, i64 %hi) {
entry:
  %n.addr = alloca i64
  store i64 %n, i64* %n.addr
  %lo.addr = alloca i64
  store i64 %lo, i64* %lo.addr
  %hi.addr = alloca i64
  store i64 %hi, i64* %hi.addr
  %t0 = load i64, i64* %n.addr
  %t1 = load i64, i64* %lo.addr
  %t2 = icmp sge i64 %t0, %t1
  %t3 = load i64, i64* %n.addr
  %t4 = load i64, i64* %hi.addr
  %t5 = icmp sle i64 %t3, %t4
  %t6 = and i1 %t2, %t5
  ret i1 %t6
dead0:
  unreachable
}

define i32 @main() {
entry:
  %t0 = call i1 @is_even(i64 4)
  %t1 = zext i1 %t0 to i32
  %t2 = getelementptr inbounds [4 x i8], [4 x i8]* @str0, i32 0, i32 0
  call i32 (i8*, ...) @printf(i8* %t2, i32 %t1)
  %t3 = call i1 @is_even(i64 7)
  %t4 = zext i1 %t3 to i32
  %t5 = getelementptr inbounds [4 x i8], [4 x i8]* @str1, i32 0, i32 0
  call i32 (i8*, ...) @printf(i8* %t5, i32 %t4)
  %t6 = call i1 @in_range(i64 5, i64 1, i64 10)
  %t7 = zext i1 %t6 to i32
  %t8 = getelementptr inbounds [4 x i8], [4 x i8]* @str2, i32 0, i32 0
  call i32 (i8*, ...) @printf(i8* %t8, i32 %t7)
  %t9 = call i1 @in_range(i64 15, i64 1, i64 10)
  %t10 = zext i1 %t9 to i32
  %t11 = getelementptr inbounds [4 x i8], [4 x i8]* @str3, i32 0, i32 0
  call i32 (i8*, ...) @printf(i8* %t11, i32 %t10)
  %a.addr = alloca i1
  store i1 1, i1* %a.addr
  %b.addr = alloca i1
  store i1 0, i1* %b.addr
  %t12 = load i1, i1* %a.addr
  %t13 = load i1, i1* %b.addr
  %t14 = and i1 %t12, %t13
  %t15 = zext i1 %t14 to i32
  %t16 = getelementptr inbounds [4 x i8], [4 x i8]* @str4, i32 0, i32 0
  call i32 (i8*, ...) @printf(i8* %t16, i32 %t15)
  %t17 = load i1, i1* %a.addr
  %t18 = load i1, i1* %b.addr
  %t19 = or i1 %t17, %t18
  %t20 = zext i1 %t19 to i32
  %t21 = getelementptr inbounds [4 x i8], [4 x i8]* @str5, i32 0, i32 0
  call i32 (i8*, ...) @printf(i8* %t21, i32 %t20)
  %t22 = load i1, i1* %a.addr
  %t23 = xor i1 %t22, 1
  %t24 = zext i1 %t23 to i32
  %t25 = getelementptr inbounds [4 x i8], [4 x i8]* @str6, i32 0, i32 0
  call i32 (i8*, ...) @printf(i8* %t25, i32 %t24)
  ret i32 0
}
