// A starter program: prints a greeting. Rename the project in CMakeLists.txt and flake.nix.
#include <iostream>

#include "greet.hpp"

int main() {
    std::cout << greeting("world") << '\n';
    return 0;
}
