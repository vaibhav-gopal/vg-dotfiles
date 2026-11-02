cmake_minimum_required(VERSION 3.25)
project(hello VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON) # for clangd

# the code, as a library the program and the tests both link
add_library(greet src/greet.cpp)
target_include_directories(greet PUBLIC include)
target_compile_options(greet PRIVATE -Wall -Wextra -Wpedantic)

add_executable(hello src/main.cpp)
target_link_libraries(hello PRIVATE greet)
install(TARGETS hello)

include(CTest)
if(BUILD_TESTING)
  add_executable(greet_test tests/greet_test.cpp)
  target_link_libraries(greet_test PRIVATE greet)
  add_test(NAME greet COMMAND greet_test)
endif()
