set(INCLUDE_RUST "local" CACHE STRING "Use rust regex crate. disabled/other.")
if(NOT ${INCLUDE_RUST} MATCHES "disabled")
    add_definitions(-DINCLUDE_RUST)
    add_subdirectory(rust)
endif()

# configure files
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/version.h.in ${CMAKE_CURRENT_SOURCE_DIR}/version.h)

set(REGEX_SOURCES
    main.c
    memory_tracker.cpp
)

if(NOT ${INCLUDE_RUST} MATCHES "disabled")
    set(REGEX_SOURCES ${REGEX_SOURCES} rust.c)
    set(REGEX_RUSTLIB rregex)
endif()

# arsh regex engine adapter. The adapter itself (arsh.cpp / arsh.cmake) is maintained outside this
# repository and copied into src/ by its build script, so the default is "disabled".
set(INCLUDE_ARSH "disabled" CACHE STRING "Use the arsh regex engine. local/disabled.")
if(NOT ${INCLUDE_ARSH} MATCHES "disabled")
    add_definitions(-DINCLUDE_ARSH)
    set(REGEX_SOURCES ${REGEX_SOURCES} arsh.cpp)
    set(REGEX_ENGINES ${REGEX_ENGINES} arsh_regex_engine)
    include(${CMAKE_CURRENT_SOURCE_DIR}/arsh.cmake)
endif()

# SRELL regex engine adapter (see srell.cmake/srell.cpp).
set(INCLUDE_SRELL "disabled" CACHE STRING "Use SRELL regex engine. local/disabled.")
if(NOT ${INCLUDE_SRELL} MATCHES "disabled")
    add_definitions(-DINCLUDE_SRELL)
    set(REGEX_SOURCES ${REGEX_SOURCES} srell.cpp)
    include(${CMAKE_CURRENT_SOURCE_DIR}/srell.cmake)
endif()

# QuickJS regexp engine adapter (see quickjs.cmake/quickjs.c).
set(INCLUDE_QUICKJS "disabled" CACHE STRING "Use QuickJS regexp engine. local/disabled.")
if(NOT ${INCLUDE_QUICKJS} MATCHES "disabled")
    add_definitions(-DINCLUDE_QUICKJS)
    set(REGEX_SOURCES ${REGEX_SOURCES} quickjs.c)
    include(${CMAKE_CURRENT_SOURCE_DIR}/quickjs.cmake)
endif()

# Hermes regex engine adapter (see hermes.cmake/hermes.cpp).
# Default is "disabled" because it needs an external Hermes build tree.
set(INCLUDE_HERMES "disabled" CACHE STRING "Use Hermes regex engine. local/disabled.")
if(NOT ${INCLUDE_HERMES} MATCHES "disabled")
    add_definitions(-DINCLUDE_HERMES)
    set(REGEX_SOURCES ${REGEX_SOURCES} hermes.cpp)
    include(${CMAKE_CURRENT_SOURCE_DIR}/hermes.cmake)
endif()

# Node.js regexp engine adapter (see nodejs.cmake/nodejs.cpp).
# Default is "disabled" because it runs the installed `node` executable out of process.
set(INCLUDE_NODEJS "disabled" CACHE STRING "Use the Node.js regexp engine. local/disabled.")
if(NOT ${INCLUDE_NODEJS} MATCHES "disabled")
    add_definitions(-DINCLUDE_NODEJS)
    set(REGEX_SOURCES ${REGEX_SOURCES} nodejs.cpp)
    include(${CMAKE_CURRENT_SOURCE_DIR}/nodejs.cmake)
endif()

# PCRE2 adapter (see pcre2.cmake/pcre2.c). It links a locally built PCRE2 (with JIT support)
# and registers the interpreted and JIT engines.
set(INCLUDE_PCRE2 "disabled" CACHE STRING "Use PCRE2. local/disabled.")
if(NOT ${INCLUDE_PCRE2} MATCHES "disabled")
    add_definitions(-DINCLUDE_PCRE2)
    set(REGEX_SOURCES ${REGEX_SOURCES} pcre2.c)
    include(${CMAKE_CURRENT_SOURCE_DIR}/pcre2.cmake)
endif()

if(NOT ${INCLUDE_HYPERSCAN} MATCHES "disabled")
    add_definitions(-DINCLUDE_HYPERSCAN)
    set(REGEX_SOURCES ${REGEX_SOURCES} hyperscan.c)
    set(REGEX_ENGINES ${REGEX_ENGINES} hs)
endif()

if(NOT ${INCLUDE_ONIGURUMA} MATCHES "disabled")
    add_definitions(-DINCLUDE_ONIGURUMA)
    set(REGEX_SOURCES ${REGEX_SOURCES} onig.c)
    set(REGEX_ENGINES ${REGEX_ENGINES} onig)
endif()

if(NOT ${INCLUDE_TRE} MATCHES "disabled")
    add_definitions(-DINCLUDE_TRE)
    set(REGEX_SOURCES ${REGEX_SOURCES} tre.c)
    set(REGEX_ENGINES ${REGEX_ENGINES} tre)
endif()

if(NOT ${INCLUDE_CTRE} MATCHES "disabled")
    add_definitions(-DINCLUDE_CTRE)
    set(REGEX_SOURCES ${REGEX_SOURCES} ctre.cpp)
    #set(REGEX_ENGINES ${REGEX_ENGINES} ctre)
endif()

if(NOT ${INCLUDE_RE2} MATCHES "disabled")
    add_definitions(-DINCLUDE_RE2)
    set(REGEX_SOURCES ${REGEX_SOURCES} re2.cpp)
    # Note: RE2 is linked via CMake target, not added to REGEX_ENGINES
endif()

if(NOT ${INCLUDE_CPPSTD} MATCHES "disabled")
    add_definitions(-DINCLUDE_CPPSTD)
    set(REGEX_SOURCES ${REGEX_SOURCES} cppstd.cpp)
endif()

if(NOT ${INCLUDE_BOOST} MATCHES "disabled")
    add_definitions(-DINCLUDE_BOOST)
    set(REGEX_SOURCES ${REGEX_SOURCES} boost.cpp)
    include(${CMAKE_CURRENT_SOURCE_DIR}/boost.cmake)
endif()

if(NOT ${INCLUDE_YARA} MATCHES "disabled")
    add_definitions(-DINCLUDE_YARA)
    set(REGEX_SOURCES ${REGEX_SOURCES} yara.c)
    set(REGEX_ENGINES ${REGEX_ENGINES} yara jansson)
endif()

include_directories(
    ${PROJECT_SOURCE_DIR}/vendor/local/include
    ${CMAKE_CURRENT_SOURCE_DIR}/rust/include
)

link_directories(${PROJECT_SOURCE_DIR}/vendor/local/lib)

if(CMAKE_BUILD_TYPE MATCHES "^Release")
    link_directories(${PROJECT_BINARY_DIR}/rregex/release)
else()
    link_directories(${PROJECT_BINARY_DIR}/rregex/debug)
endif()

add_executable(regex_perf ${REGEX_SOURCES})

if(TARGET librregex)
    add_dependencies(regex_perf librregex)
endif()

# Use CMake to find and link dependencies properly
set(EXTRA_LIBRARIES "")
if(NOT ${INCLUDE_RE2} MATCHES "disabled")
    # Set the prefix path so CMake can find our locally built packages
    list(APPEND CMAKE_PREFIX_PATH "${PROJECT_SOURCE_DIR}/vendor/local")
    find_package(re2 REQUIRED)
    set(EXTRA_LIBRARIES re2::re2)
endif()

target_link_libraries(regex_perf ${REGEX_RUSTLIB} ${REGEX_ENGINES} ${EXTRA_LIBRARIES} pthread dl)
