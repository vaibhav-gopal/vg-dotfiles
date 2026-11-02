// The greeting, as a library the program and its tests share.
#pragma once

#include <string>
#include <string_view>

// The greeting for `name`.
std::string greeting(std::string_view name);
