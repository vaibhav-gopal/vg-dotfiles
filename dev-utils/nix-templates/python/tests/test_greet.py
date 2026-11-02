from hello import greeting


def test_greets_by_name():
    assert greeting("nix") == "Hello, nix!"
