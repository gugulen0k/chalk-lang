from lexer import make_parser
from semantic import ChalkError, SemanticAnalyzer
from transformer import ChalkTransformer


def main():
    parser = make_parser()
    transformer = ChalkTransformer()
    analyzer = SemanticAnalyzer()

    with open("examples/main.ch", "r") as f:
        source = f.read()

    try:
        raw_tree = parser.parse(source)
        ast = transformer.transform(raw_tree)
        analyzer.analyze(ast)

    except ChalkError as e:
        print(f"Error: \n{e}")
    except Exception as e:
        print(f"Parse error: {e}")


if __name__ == "__main__":
    main()
