"""A starter package: prints a greeting. Rename it in pyproject.toml, src/ and flake.nix."""


def greeting(name: str) -> str:
    """The greeting for `name`."""
    return f"Hello, {name}!"


def main() -> None:
    print(greeting("world"))
