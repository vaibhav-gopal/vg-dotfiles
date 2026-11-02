#include "greet.hpp"

std::string greeting(std::string_view name) {
    return "Hello, " + std::string(name) + "!";
}
