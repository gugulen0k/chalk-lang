import argparse
import os
import subprocess
import sys

from codegen import CodeGenerator
from lexer import make_parser
from semantic import ChalkError, SemanticAnalyzer
from transformer import ChalkTransformer


def main():
    # --------------------------------------------------------
    # CLI argument parsing
    # --------------------------------------------------------
    parser_cli = argparse.ArgumentParser(
        prog="chalk",
        description="Chalk compiler — compiles .ch files to native binaries",
    )

    parser_cli.add_argument("source", help="path to the .ch source file")

    parser_cli.add_argument(
        "-o",
        "--output",
        help="name of the output binary (default: same as source without .ch)",
        default=None,
    )

    parser_cli.add_argument(
        "--emit-c", help="save the generated C code to a file", action="store_true"
    )

    args = parser_cli.parse_args()

    # --------------------------------------------------------
    # Resolve file paths
    # --------------------------------------------------------
    source_path = args.source

    if not os.path.exists(source_path):
        print(f"chalk: error: file '{source_path}' not found")
        sys.exit(1)

    if not source_path.endswith(".ch"):
        print(f"chalk: error: '{source_path}' is not a .ch file")
        sys.exit(1)

    # output binary name — default is source filename without .ch
    if args.output:
        output_path = args.output
    else:
        output_path = source_path.replace(".ch", "")

    # temp C file — we'll delete it after compilation
    c_path = source_path.replace(".ch", ".c")

    # --------------------------------------------------------
    # Chalk compilation pipeline
    # --------------------------------------------------------
    try:
        with open(source_path, "r") as f:
            source = f.read()

        chalk_parser = make_parser()
        transformer = ChalkTransformer()
        analyzer = SemanticAnalyzer()
        generator = CodeGenerator()

        raw_tree = chalk_parser.parse(source)
        ast = transformer.transform(raw_tree)
        analyzer.analyze(ast)
        c_code = generator.generate(ast)

    except ChalkError as e:
        print(f"chalk: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"chalk: parse error: {e}")
        sys.exit(1)

    # --------------------------------------------------------
    # Write C code to file
    # --------------------------------------------------------
    with open(c_path, "w") as f:
        f.write(c_code)

    if args.emit_c:
        print(f"chalk: C code written to '{c_path}'")

    # --------------------------------------------------------
    # Invoke gcc to compile C → binary
    # --------------------------------------------------------
    gcc_result = subprocess.run(
        ["gcc", c_path, "-o", output_path], capture_output=True, text=True
    )

    # clean up the C file unless --emit-c was passed
    if not args.emit_c:
        os.remove(c_path)

    if gcc_result.returncode != 0:
        print(f"chalk: gcc error:\n{gcc_result.stderr}")
        sys.exit(1)

    print(f"chalk: compiled successfully → {output_path}")


if __name__ == "__main__":
    main()
