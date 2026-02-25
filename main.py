from lexer import make_parser
from transformer import ChalkTransformer


def main():
    parser = make_parser()
    transformer = ChalkTransformer()

    with open("examples/hello.ch", "r") as f:
        source = f.read()

    try:
        raw_tree = parser.parse(source)
        ast = transformer.transform(raw_tree)

        for node in ast.statements:
            print(node)

    except Exception as e:
        print(f"Parse error: {e}")


if __name__ == "__main__":
    main()
