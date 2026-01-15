cmake_minimum_required(VERSION 3.15)
project(BlackHoleSimulation)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Add external libraries
add_subdirectory(external/glfw)
add_subdirectory(external/glm)

# GLAD source files
set(GLAD_SOURCES
    external/glad/src/glad.c
)

# Main executable
add_executable(BlackHole
    src/main.cpp
    ${GLAD_SOURCES}
)

# Include directories
target_include_directories(BlackHole PRIVATE
    external/glfw/include
    external/glad/include
    external/glm
    external/stb
)

# Link libraries
target_link_libraries(BlackHole
    glfw
    ${CMAKE_DL_LIBS}  # For dynamic loading (required by GLAD)
)

# Platform-specific settings
if(WIN32)
    target_link_libraries(BlackHole opengl32)
elseif(APPLE)
    find_library(OPENGL_LIBRARY OpenGL)
    find_library(COCOA_LIBRARY Cocoa)
    find_library(IOKIT_LIBRARY IOKit)
    find_library(COREVIDEO_LIBRARY CoreVideo)
    target_link_libraries(BlackHole 
        ${OPENGL_LIBRARY}
        ${COCOA_LIBRARY}
        ${IOKIT_LIBRARY}
        ${COREVIDEO_LIBRARY}
    )
else()
    find_package(OpenGL REQUIRED)
    target_link_libraries(BlackHole OpenGL::GL)
endif()

# Copy shaders to build directory
file(COPY ${CMAKE_SOURCE_DIR}/shaders DESTINATION ${CMAKE_BINARY_DIR})