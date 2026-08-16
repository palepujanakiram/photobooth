cmake_minimum_required(VERSION 3.10.2)
project(canon-sidecar C CXX)

set(SRC_DIR  ${PROJECT_SOURCE_DIR}/src)
# EDSDK is copied into the build context by build.sh
set(EDSDK_DIR ${PROJECT_SOURCE_DIR}/EDSDK)

# aarch64 must be checked first: CMake MATCHES "arm" also matches "aarch64".
if(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|ARM64|arm64")
  set(EDSDK_ARCH ARM64)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "arm")
  set(EDSDK_ARCH ARM32)
else()
  message(FATAL_ERROR
    "Unsupported CMAKE_SYSTEM_PROCESSOR=${CMAKE_SYSTEM_PROCESSOR}")
endif()

set(EDSDK_LIB ${EDSDK_DIR}/Library/${EDSDK_ARCH}/libEDSDK.so)
if(NOT EXISTS ${EDSDK_LIB})
  message(FATAL_ERROR "EDSDK library not found: ${EDSDK_LIB}")
endif()
message(STATUS "Linking Canon EDSDK ${EDSDK_ARCH}: ${EDSDK_LIB}")

add_compile_options(-D TARGET_OS_LINUX)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall -std=c++17 -pthread")
set(CMAKE_CXX_FLAGS_RELEASE "-O2")

add_executable(canon-sidecar
    ${SRC_DIR}/main.cpp
    ${SRC_DIR}/canon_camera.cpp
    ${SRC_DIR}/canon_camera_live.cpp
    ${SRC_DIR}/canon_camera_capture.cpp
)

set_target_properties(canon-sidecar PROPERTIES
    CXX_STANDARD          17
    CXX_STANDARD_REQUIRED YES
    BUILD_RPATH  "$ORIGIN"
    INSTALL_RPATH "$ORIGIN"
)

target_include_directories(canon-sidecar PUBLIC
    ${SRC_DIR}
    ${EDSDK_DIR}/Header
)

target_link_libraries(canon-sidecar PRIVATE
    ${EDSDK_LIB}
    pthread
)

# 64-bit atomics on armhf often need libatomic.
if(EDSDK_ARCH STREQUAL "ARM32")
  target_link_libraries(canon-sidecar PRIVATE atomic)
endif()

# glibc LD_PRELOAD helper: dup the Java USB fd when libusb opens usbfs.
add_library(usb_open_hook SHARED ${SRC_DIR}/usb_open_hook.c)
target_link_libraries(usb_open_hook PRIVATE dl)
set_target_properties(usb_open_hook PROPERTIES
    C_STANDARD 99
    POSITION_INDEPENDENT_CODE ON
    BUILD_RPATH "$ORIGIN"
    INSTALL_RPATH "$ORIGIN"
    LINK_FLAGS "-Wl,--version-script=${SRC_DIR}/usb_open_hook.map"
)
