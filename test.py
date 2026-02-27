import os

from lexer import make_parser
from transformer import ChalkTransformer


def main():
    parser = make_parser()
    transformer = ChalkTransformer()

    examples = sorted(os.listdir("examples"))

    for filename in examples:
        if not filename.endswith(".ch"):
            continue

        print(f"\n{'=' * 50}")
        print(f"  {filename}")
        print(f"{'=' * 50}")

        with open(f"examples/{filename}", "r") as f:
            source = f.read()

        try:
            raw_tree = parser.parse(source)
            ast = transformer.transform(raw_tree)

            for node in ast.statements:
                print(node)

        except Exception as e:
            print(f"  ERROR: {e}")


if __name__ == "__main__":
    main()
