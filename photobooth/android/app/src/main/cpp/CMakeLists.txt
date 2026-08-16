cmake_minimum_required(VERSION 3.18.1)
project(canon_sidecar_spawn)

add_library(canon_sidecar_spawn SHARED canon_sidecar_spawn.cpp)
find_library(log-lib log)
target_link_libraries(canon_sidecar_spawn ${log-lib})
