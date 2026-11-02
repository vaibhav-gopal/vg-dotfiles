// greeting()'s tests, run by CTest (exit code 0 passes).
#include <iostream>

#include "greet.hpp"

int main() {
    const auto got = greeting("nix");
    if (got != "Hello, nix!") {
        std::cerr << "greeting(\"nix\") = \"" << got << "\", expected \"Hello, nix!\"\n";
        return 1;
    }
    return 0;
}
