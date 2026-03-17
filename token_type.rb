# frozen_string_literal: true

module TokenType
  # --- Literals -----------------------------------------------
  INT_LIT    = :INT_LIT    # 42, 0xFF, 0b1010
  FLOAT_LIT  = :FLOAT_LIT  # 3.14, 1.5e10
  STRING_LIT = :STRING_LIT # 'hello'  (all string forms collapse to this)
  TRUE       = :TRUE
  FALSE      = :FALSE
  NIL        = :NIL

  # --- Identifier ---------------------------------------------
  IDENT = :IDENT # variable names, function names, type names

  # --- Keywords -----------------------------------------------
  FUNC    = :FUNC
  RETURN  = :RETURN
  IF      = :IF
  ELSE    = :ELSE
  END_KW  = :END_KW
  WHILE   = :WHILE
  FOR     = :FOR
  IN      = :IN
  BREAK   = :BREAK
  SKIP    = :SKIP
  MATCH   = :MATCH
  WITH    = :WITH # match guard: 'n with name if condition'
  MUT     = :MUT
  PUB     = :PUB
  STRUCT  = :STRUCT
  ENUM    = :ENUM
  ERROR   = :ERROR
  IMPORT  = :IMPORT
  FROM    = :FROM
  AS      = :AS
  CONST   = :CONST
  RAISE   = :RAISE
  TRY     = :TRY
  CATCH   = :CATCH
  AND     = :AND
  OR      = :OR
  NOT     = :NOT
  RESERVE = :RESERVE # 'reserve' keyword for array pre-allocation

  # --- Built-in types (appear in type annotations) ------------
  INT    = :INT    # the word 'int' in 'x: int = 5'
  FLOAT  = :FLOAT  # the word 'float'
  STRING = :STRING # the word 'string'
  BOOL   = :BOOL   # the word 'bool'
  VOID   = :VOID   # the word 'void'

  # --- Arithmetic operators -----------------------------------
  PLUS    = :PLUS    # +
  MINUS   = :MINUS   # -
  STAR    = :STAR    # *
  SLASH   = :SLASH   # /
  PERCENT = :PERCENT # %

  # --- Comparison operators -----------------------------------
  EQUAL_EQUAL   = :EQUAL_EQUAL    # ==
  BANG_EQUAL    = :BANG_EQUAL     # !=
  LESS          = :LESS           #
  LESS_EQUAL    = :LESS_EQUAL     # <=
  GREATER       = :GREATER        # >
  GREATER_EQUAL = :GREATER_EQUAL  # >=

  # --- Assignment ---------------------------------------------
  EQUAL = :EQUAL # =

  # --- Delimiters & punctuation -------------------------------
  LPAREN      = :LPAREN      # (
  RPAREN      = :RPAREN      # )
  LBRACKET    = :LBRACKET    # [
  RBRACKET    = :RBRACKET    # ]
  LBRACE      = :LBRACE      # {
  RBRACE      = :RBRACE      # }
  COMMA       = :COMMA       # ,
  COLON       = :COLON       # :
  COLON_COLON = :COLON_COLON # :: path separator in imports
  DOT         = :DOT         # .
  ARROW       = :ARROW       # ->
  FAT_ARROW   = :FAT_ARROW   # =>

  # --- Range operators ----------------------------------------
  DOT_DOT       = :DOT_DOT       # ..   exclusive range
  DOT_DOT_EQUAL = :DOT_DOT_EQUAL # ..=  inclusive range

  # --- Suffix characters --------------------------------------
  BANG     = :BANG     # ! (failable function suffix)
  QUESTION = :QUESTION # ? (bool function suffix / nullable type)

  # --- Special ------------------------------------------------
  NEWLINE = :NEWLINE
  EOF     = :EOF
end
