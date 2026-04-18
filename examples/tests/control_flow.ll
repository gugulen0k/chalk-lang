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

@str0 = private unnamed_addr constant [18 x i8] c"sum 1..10 = %lld\0A\00"
@str1 = private unnamed_addr constant [32 x i8] c"first power of 2 >= 32 is %lld\0A\00"
@str2 = private unnamed_addr constant [2 x i8] c"A\00"
@str3 = private unnamed_addr constant [2 x i8] c"B\00"
@str4 = private unnamed_addr constant [2 x i8] c"C\00"
define i32 @main() {
entry:
  %total.addr = alloca i64
  store i64 0, i64* %total.addr
  %i.addr = alloca i64
  store i64 1, i64* %i.addr
  br label %fc0
fc0:
  %t0 = load i64, i64* %i.addr
  %t1 = icmp sle i64 %t0, 10
  br i1 %t1, label %fb1, label %fe3
fb1:
  %t2 = load i64, i64* %total.addr
  %t3 = load i64, i64* %i.addr
  %t4 = add i64 %t2, %t3
  store i64 %t4, i64* %total.addr
  br label %fi2
fi2:
  %t5 = load i64, i64* %i.addr
  %t6 = add i64 %t5, 1
  store i64 %t6, i64* %i.addr
  br label %fc0
fe3:
  %t7 = load i64, i64* %total.addr
  %t8 = getelementptr inbounds [18 x i8], [18 x i8]* @str0, i32 0, i32 0
  call i32 (i8*, ...) @printf(i8* %t8, i64 %t7)
  %x.addr = alloca i64
  store i64 1, i64* %x.addr
  br label %wc4
wc4:
  %t9 = load i64, i64* %x.addr
  %t10 = icmp slt i64 %t9, 32
  br i1 %t10, label %wb5, label %we6
wb5:
  %t11 = load i64, i64* %x.addr
  %t12 = mul i64 %t11, 2
  store i64 %t12, i64* %x.addr
  br label %wc4
we6:
  %t13 = load i64, i64* %x.addr
  %t14 = getelementptr inbounds [32 x i8], [32 x i8]* @str1, i32 0, i32 0
  call i32 (i8*, ...) @printf(i8* %t14, i64 %t13)
  %score.addr = alloca i64
  store i64 75, i64* %score.addr
  %t15 = load i64, i64* %score.addr
  %t16 = icmp sge i64 %t15, 90
  br i1 %t16, label %then7, label %else9
then7:
  %t17 = getelementptr inbounds [2 x i8], [2 x i8]* @str2, i32 0, i32 0
  call i32 @puts(i8* %t17)
  br label %merge8
else9:
  %t18 = load i64, i64* %score.addr
  %t19 = icmp sge i64 %t18, 75
  br i1 %t19, label %then10, label %else12
then10:
  %t20 = getelementptr inbounds [2 x i8], [2 x i8]* @str3, i32 0, i32 0
  call i32 @puts(i8* %t20)
  br label %merge11
else12:
  %t21 = getelementptr inbounds [2 x i8], [2 x i8]* @str4, i32 0, i32 0
  call i32 @puts(i8* %t21)
  br label %merge11
merge11:
  br label %merge8
merge8:
  ret i32 0
}
