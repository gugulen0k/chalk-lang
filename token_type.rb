# frozen_string_literal: true

module TokenType
  # --- Literals -----------------------------------------------
  INT_LIT    = :INT_LIT    # 42
  FLOAT_LIT  = :FLOAT_LIT  # 3.14
  STRING_LIT = :STRING_LIT # 'hello'
  TRUE       = :TRUE
  FALSE      = :FALSE

  # --- Identifier ---------------------------------------------
  IDENT = :IDENT

  # --- Keywords -----------------------------------------------
  FUNC   = :FUNC
  RETURN = :RETURN
  IF     = :IF
  ELSE   = :ELSE
  END_KW = :END_KW
  WHILE  = :WHILE
  MUT    = :MUT
  PUB    = :PUB
  ERROR  = :ERROR
  RAISE  = :RAISE
  TRY    = :TRY
  AND    = :AND
  OR     = :OR
  NOT    = :NOT

  # --- Built-in types -----------------------------------------
  INT    = :INT
  FLOAT  = :FLOAT
  STRING = :STRING
  BOOL   = :BOOL
  VOID   = :VOID

  # --- Arithmetic operators -----------------------------------
  PLUS  = :PLUS   # +
  MINUS = :MINUS  # -
  STAR  = :STAR   # *
  SLASH = :SLASH  # /

  # --- Comparison operators -----------------------------------
  EQUAL_EQUAL   = :EQUAL_EQUAL   # ==
  BANG_EQUAL    = :BANG_EQUAL    # !=
  LESS          = :LESS          # <
  LESS_EQUAL    = :LESS_EQUAL    # <=
  GREATER       = :GREATER       # >
  GREATER_EQUAL = :GREATER_EQUAL # >=

  # --- Assignment ---------------------------------------------
  EQUAL = :EQUAL # =

  # --- Punctuation --------------------------------------------
  LPAREN = :LPAREN # (
  RPAREN = :RPAREN # )
  COMMA  = :COMMA  # ,
  COLON  = :COLON  # :
  DOT    = :DOT    # .
  ARROW  = :ARROW  # ->

  # --- Special ------------------------------------------------
  DOC_COMMENT = :DOC_COMMENT
  NEWLINE     = :NEWLINE
  EOF         = :EOF
end
