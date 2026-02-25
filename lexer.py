from lark import Lark


def make_parser():
    with open("grammar.lark", "r") as f:
        grammar = f.read()

    return Lark(
        grammar,
        parser="earley",
        propagate_positions=True,  # tracks line numbers for error messages
    )
