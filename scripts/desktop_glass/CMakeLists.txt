cmake_minimum_required(VERSION 3.16)
project(DesktopCapture LANGUAGES C CXX)
set(CMAKE_AUTOMOC ON)
find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick)
find_package(PkgConfig REQUIRED)
pkg_check_modules(WAYLAND REQUIRED IMPORTED_TARGET wayland-client)
find_program(WAYLAND_SCANNER wayland-scanner REQUIRED)
foreach(proto workspace workspace-capture source copy foreign)
    add_custom_command(OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/${proto}.h ${CMAKE_CURRENT_BINARY_DIR}/${proto}.c
        COMMAND ${WAYLAND_SCANNER} client-header ${CMAKE_CURRENT_SOURCE_DIR}/${proto}.xml ${CMAKE_CURRENT_BINARY_DIR}/${proto}.h
        COMMAND ${WAYLAND_SCANNER} private-code ${CMAKE_CURRENT_SOURCE_DIR}/${proto}.xml ${CMAKE_CURRENT_BINARY_DIR}/${proto}.c
        DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/${proto}.xml VERBATIM)
    list(APPEND PROTOCOL_SOURCES ${CMAKE_CURRENT_BINARY_DIR}/${proto}.c ${CMAKE_CURRENT_BINARY_DIR}/${proto}.h)
endforeach()
add_library(desktopcapture MODULE capture.cpp ${PROTOCOL_SOURCES})
target_include_directories(desktopcapture PRIVATE ${CMAKE_CURRENT_BINARY_DIR})
target_compile_features(desktopcapture PRIVATE cxx_std_17)
target_link_libraries(desktopcapture PRIVATE Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick PkgConfig::WAYLAND)
