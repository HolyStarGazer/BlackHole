/*
 * BLACK HOLE SIMULATION - Main Application
 * 
 * This application renders a real-time visualization of gravitational lensing
 * around a Schwarzschild black hole using ray tracing through curved spacetime.
 * 
 * Controls:
 * - Left Mouse + Drag: Orbit camera around black hole
 * - Scroll Wheel: Zoom in/out
 * - R: Reset camera to default position
 * - ESC: Exit
 */

#include <glad/glad.h>
#include <GLFW/glfw3.h>
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/constants.hpp>
#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <cmath>

// ============================================================================
// CONFIGURATION
// ============================================================================

// Window settings
const unsigned int SCR_WIDTH = 1280;
const unsigned int SCR_HEIGHT = 720;

// Camera settings
// We use spherical coordinates for orbiting: (radius, theta, phi)
// theta = polar angle from Y axis (0 = top, PI = bottom)
// phi = azimuthal angle in XZ plane
struct Camera {
    float radius = 50.0f;           // Start further back to see TON 618's scale
    float theta = glm::half_pi<float>() * 0.8f;  // Slightly above equator
    float phi = 0.3f;               // Slight angle
    float fov = 60.0f;
    
    // Orbit limits
    float minRadius = 10.0f;
    float maxRadius = 800.0f;
    float minTheta = 0.1f;
    float maxTheta = glm::pi<float>() - 0.1f;
    
    // Mouse state
    bool isDragging = false;
    double lastMouseX = 0.0;
    double lastMouseY = 0.0;
    float sensitivity = 0.005f;
    
    /*
     * Convert spherical coordinates to Cartesian position
     * 
     * x = r * sin(theta) * cos(phi)
     * y = r * cos(theta)
     * z = r * sin(theta) * sin(phi)
     */
    glm::vec3 getPosition() const {
        return glm::vec3(
            radius * sin(theta) * cos(phi),
            radius * cos(theta),
            radius * sin(theta) * sin(phi)
        );
    }
    
    // Camera always looks at the black hole (origin)
    glm::vec3 getTarget() const {
        return glm::vec3(0.0f, 0.0f, 0.0f);
    }
    
    void reset() {
        radius = 25.0f;
        theta = glm::half_pi<float>();
        phi = 0.0f;
    }
};

// Global camera instance
Camera camera;

// ============================================================================
// CALLBACK FUNCTIONS
// ============================================================================

/*
 * Handle window resize
 * Updates the OpenGL viewport to match new window dimensions
 */
void framebuffer_size_callback(GLFWwindow* window, int width, int height)
{
    glViewport(0, 0, width, height);
}

/*
 * Handle mouse button events
 * Left click starts camera orbit, release stops it
 */
void mouse_button_callback(GLFWwindow* window, int button, int action, int mods)
{
    if (button == GLFW_MOUSE_BUTTON_LEFT) {
        if (action == GLFW_PRESS) {
            camera.isDragging = true;
            glfwGetCursorPos(window, &camera.lastMouseX, &camera.lastMouseY);
        } else if (action == GLFW_RELEASE) {
            camera.isDragging = false;
        }
    }
}

/*
 * Handle mouse movement
 * When dragging, orbit the camera around the black hole
 * 
 * Horizontal movement (dx) changes phi (azimuthal angle)
 * Vertical movement (dy) changes theta (polar angle)
 */
void cursor_position_callback(GLFWwindow* window, double xpos, double ypos)
{
    if (camera.isDragging) {
        double dx = xpos - camera.lastMouseX;
        double dy = ypos - camera.lastMouseY;
        
        // Update angles
        // Negative dx because dragging right should rotate camera left (counterclockwise)
        camera.phi -= static_cast<float>(dx) * camera.sensitivity;
        camera.theta += static_cast<float>(dy) * camera.sensitivity;
        
        // Clamp theta to prevent flipping
        camera.theta = glm::clamp(camera.theta, camera.minTheta, camera.maxTheta);
        
        // Keep phi in [-PI, PI]
        if (camera.phi > glm::pi<float>()) camera.phi -= glm::two_pi<float>();
        if (camera.phi < -glm::pi<float>()) camera.phi += glm::two_pi<float>();
        
        camera.lastMouseX = xpos;
        camera.lastMouseY = ypos;
    }
}

/*
 * Handle scroll wheel
 * Zoom in/out by changing camera radius
 * 
 * Uses exponential scaling for natural-feeling zoom:
 * small scroll near = small movement, small scroll far = large movement
 */
void scroll_callback(GLFWwindow* window, double xoffset, double yoffset)
{
    // Exponential zoom for natural feel
    float zoomFactor = 1.0f - static_cast<float>(yoffset) * 0.1f;
    camera.radius *= zoomFactor;
    
    // Clamp to valid range
    camera.radius = glm::clamp(camera.radius, camera.minRadius, camera.maxRadius);
}

/*
 * Process keyboard input
 * ESC: Close window
 * R: Reset camera
 */
void processInput(GLFWwindow* window)
{
    if (glfwGetKey(window, GLFW_KEY_ESCAPE) == GLFW_PRESS)
        glfwSetWindowShouldClose(window, true);
    
    // Reset camera with R key (with simple debounce)
    static bool rKeyWasPressed = false;
    if (glfwGetKey(window, GLFW_KEY_R) == GLFW_PRESS) {
        if (!rKeyWasPressed) {
            camera.reset();
            std::cout << "Camera reset" << std::endl;
        }
        rKeyWasPressed = true;
    } else {
        rKeyWasPressed = false;
    }
}

// ============================================================================
// SHADER LOADING
// ============================================================================

/*
 * Load shader source code from file
 * Returns empty string on failure
 */
std::string loadShaderSource(const char* filepath)
{
    std::ifstream file(filepath);
    if (!file.is_open()) {
        std::cerr << "Failed to open shader file: " << filepath << std::endl;
        return "";
    }

    std::stringstream buffer;
    buffer << file.rdbuf();
    return buffer.str();
}

/*
 * Compile a single shader
 * 
 * type: GL_VERTEX_SHADER or GL_FRAGMENT_SHADER
 * source: GLSL source code as string
 * 
 * Returns shader ID, or 0 on failure
 */
unsigned int compileShader(unsigned int type, const char* source)
{
    unsigned int shader = glCreateShader(type);
    glShaderSource(shader, 1, &source, NULL);
    glCompileShader(shader);

    // Check for compilation errors
    int success;
    char infoLog[512];
    glGetShaderiv(shader, GL_COMPILE_STATUS, &success);
    if (!success) {
        glGetShaderInfoLog(shader, 512, NULL, infoLog);
        std::cerr << "Shader compilation failed:\n" << infoLog << std::endl;
        return 0;
    }

    return shader;
}

/*
 * Create a complete shader program from vertex and fragment shaders
 * 
 * The pipeline is:
 * 1. Load source files
 * 2. Compile vertex shader
 * 3. Compile fragment shader
 * 4. Link into program
 * 5. Delete individual shaders (they're now part of program)
 * 
 * Returns program ID, or 0 on failure
 */
unsigned int createShaderProgram(const char* vertexPath, const char* fragmentPath)
{
    // Load source
    std::string vertexSource = loadShaderSource(vertexPath);
    std::string fragmentSource = loadShaderSource(fragmentPath);

    if (vertexSource.empty() || fragmentSource.empty()) {
        return 0;
    }

    // Compile shaders
    unsigned int vertexShader = compileShader(GL_VERTEX_SHADER, vertexSource.c_str());
    unsigned int fragmentShader = compileShader(GL_FRAGMENT_SHADER, fragmentSource.c_str());

    if (vertexShader == 0 || fragmentShader == 0) {
        return 0;
    }

    // Link program
    unsigned int shaderProgram = glCreateProgram();
    glAttachShader(shaderProgram, vertexShader);
    glAttachShader(shaderProgram, fragmentShader);
    glLinkProgram(shaderProgram);

    // Check for linking errors
    int success;
    char infoLog[512];
    glGetProgramiv(shaderProgram, GL_LINK_STATUS, &success);
    if (!success) {
        glGetProgramInfoLog(shaderProgram, 512, NULL, infoLog);
        std::cerr << "Shader program linking failed:\n" << infoLog << std::endl;
        return 0;
    }

    // Cleanup - shaders are now linked into program
    glDeleteShader(vertexShader);
    glDeleteShader(fragmentShader);

    return shaderProgram;
}

// ============================================================================
// MAIN FUNCTION
// ============================================================================

int main()
{
    // ========================================
    // Initialize GLFW
    // ========================================
    
    if (!glfwInit()) {
        std::cerr << "Failed to initialize GLFW" << std::endl;
        return -1;
    }

    // Request OpenGL 4.3 Core Profile
    // Core Profile = modern OpenGL without deprecated features
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

#ifdef __APPLE__
    // macOS requires forward compatibility
    glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);
#endif

    // ========================================
    // Create window
    // ========================================
    
    GLFWwindow* window = glfwCreateWindow(SCR_WIDTH, SCR_HEIGHT, 
        "TON 618 - Supermassive Black Hole Visualization", NULL, NULL);
    
    if (window == NULL) {
        std::cerr << "Failed to create GLFW window" << std::endl;
        glfwTerminate();
        return -1;
    }
    
    glfwMakeContextCurrent(window);
    
    // Register callbacks
    glfwSetFramebufferSizeCallback(window, framebuffer_size_callback);
    glfwSetMouseButtonCallback(window, mouse_button_callback);
    glfwSetCursorPosCallback(window, cursor_position_callback);
    glfwSetScrollCallback(window, scroll_callback);

    // ========================================
    // Initialize GLAD
    // ========================================
    
    // GLAD loads OpenGL function pointers at runtime
    // This is necessary because OpenGL is a specification, and the actual
    // function addresses depend on the graphics driver
    if (!gladLoadGLLoader((GLADloadproc)glfwGetProcAddress)) {
        std::cerr << "Failed to initialize GLAD" << std::endl;
        return -1;
    }

    std::cout << "OpenGL Version: " << glGetString(GL_VERSION) << std::endl;
    std::cout << "GLSL Version: " << glGetString(GL_SHADING_LANGUAGE_VERSION) << std::endl;
    std::cout << "Renderer: " << glGetString(GL_RENDERER) << std::endl;

    // ========================================
    // Build shader program
    // ========================================
    
    unsigned int shaderProgram = createShaderProgram(
        "shaders/vertex.glsl", 
        "shaders/fragment.glsl"
    );
    
    if (shaderProgram == 0) {
        glfwTerminate();
        return -1;
    }

    // ========================================
    // Create fullscreen quad
    // ========================================
    
    /*
     * We render a fullscreen quad and do all the actual rendering in the
     * fragment shader. This is a common technique for:
     * - Ray tracing/marching
     * - Post-processing effects
     * - Shadertoy-style demos
     * 
     * The quad covers the entire screen from (-1,-1) to (1,1) in NDC
     * (Normalized Device Coordinates)
     */
    float quadVertices[] = {
        // positions        // texture coords (not used but kept for flexibility)
        -1.0f,  1.0f, 0.0f,   0.0f, 1.0f,   // top-left
        -1.0f, -1.0f, 0.0f,   0.0f, 0.0f,   // bottom-left
         1.0f, -1.0f, 0.0f,   1.0f, 0.0f,   // bottom-right
         1.0f,  1.0f, 0.0f,   1.0f, 1.0f    // top-right
    };

    unsigned int indices[] = {
        0, 1, 2,  // First triangle
        0, 2, 3   // Second triangle
    };

    // Create Vertex Array Object (VAO)
    // VAO stores the vertex attribute configuration
    unsigned int VAO, VBO, EBO;
    glGenVertexArrays(1, &VAO);
    glGenBuffers(1, &VBO);
    glGenBuffers(1, &EBO);

    glBindVertexArray(VAO);

    // Upload vertex data to VBO
    glBindBuffer(GL_ARRAY_BUFFER, VBO);
    glBufferData(GL_ARRAY_BUFFER, sizeof(quadVertices), quadVertices, GL_STATIC_DRAW);

    // Upload index data to EBO
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, EBO);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(indices), indices, GL_STATIC_DRAW);

    // Configure vertex attributes
    // Attribute 0: position (vec3)
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 5 * sizeof(float), (void*)0);
    glEnableVertexAttribArray(0);

    // Attribute 1: texture coord (vec2)
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 5 * sizeof(float), (void*)(3 * sizeof(float)));
    glEnableVertexAttribArray(1);

    // ========================================
    // Get uniform locations
    // ========================================
    
    /*
     * Uniforms are shader variables that stay constant for an entire draw call
     * We query their locations once, then use those locations to update values
     */
    GLint resolutionLoc = glGetUniformLocation(shaderProgram, "resolution");
    GLint timeLoc = glGetUniformLocation(shaderProgram, "time");
    GLint cameraPosLoc = glGetUniformLocation(shaderProgram, "cameraPos");
    GLint cameraTargetLoc = glGetUniformLocation(shaderProgram, "cameraTarget");
    GLint cameraFovLoc = glGetUniformLocation(shaderProgram, "cameraFov");

    // Check if uniforms were found
    if (cameraPosLoc == -1) std::cerr << "Warning: cameraPos uniform not found" << std::endl;
    if (cameraTargetLoc == -1) std::cerr << "Warning: cameraTarget uniform not found" << std::endl;
    if (cameraFovLoc == -1) std::cerr << "Warning: cameraFov uniform not found" << std::endl;

    // ========================================
    // Print controls
    // ========================================
    
    std::cout << "\n========================================" << std::endl;
    std::cout << "TON 618 VISUALIZATION" << std::endl;
    std::cout << "One of the largest known black holes" << std::endl;
    std::cout << "========================================" << std::endl;
    std::cout << "\nTON 618 Facts:" << std::endl;
    std::cout << "  Mass: ~66 billion solar masses" << std::endl;
    std::cout << "  Event horizon: ~1,300 AU (43x Neptune's orbit)" << std::endl;
    std::cout << "  Location: 10.4 billion light-years away" << std::endl;
    std::cout << "\nControls:" << std::endl;
    std::cout << "  Left Mouse + Drag : Orbit camera" << std::endl;
    std::cout << "  Scroll Wheel      : Zoom in/out" << std::endl;
    std::cout << "  R                 : Reset camera" << std::endl;
    std::cout << "  ESC               : Exit" << std::endl;
    std::cout << "\nRendering..." << std::endl;

    // ========================================
    // Main render loop
    // ========================================
    
    while (!glfwWindowShouldClose(window))
    {
        // Process input
        processInput(window);

        // Get current window size
        int width, height;
        glfwGetFramebufferSize(window, &width, &height);

        // Clear screen
        glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);

        // Activate shader
        glUseProgram(shaderProgram);

        // Update uniforms
        float time = static_cast<float>(glfwGetTime());
        glm::vec3 camPos = camera.getPosition();
        glm::vec3 camTarget = camera.getTarget();

        glUniform2f(resolutionLoc, static_cast<float>(width), static_cast<float>(height));
        glUniform1f(timeLoc, time);
        glUniform3f(cameraPosLoc, camPos.x, camPos.y, camPos.z);
        glUniform3f(cameraTargetLoc, camTarget.x, camTarget.y, camTarget.z);
        glUniform1f(cameraFovLoc, camera.fov);

        // Draw fullscreen quad
        glBindVertexArray(VAO);
        glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, 0);

        // Swap buffers and poll events
        glfwSwapBuffers(window);
        glfwPollEvents();
    }

    // ========================================
    // Cleanup
    // ========================================
    
    glDeleteVertexArrays(1, &VAO);
    glDeleteBuffers(1, &VBO);
    glDeleteBuffers(1, &EBO);
    glDeleteProgram(shaderProgram);

    glfwTerminate();
    return 0;
}
