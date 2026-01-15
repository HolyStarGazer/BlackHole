#include <glad/glad.h>
#include <GLFW/glfw3.h>
#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <cmath>

// Window dimensions
const unsigned int SCR_WIDTH = 1280;
const unsigned int SCR_HEIGHT = 720;

// Camera state (spherical coordinates around origin)
float camRadius = 300.0f;      // Distance from black hole
float camTheta = 1.3f;         // Polar angle (from top, ~74 degrees)
float camPhi = 0.0f;           // Azimuthal angle
float camFov = 60.0f;          // Field of view

// Camera limits
const float CAM_MIN_RADIUS = 50.0f;
const float CAM_MAX_RADIUS = 1500.0f;

// Mouse state
bool mousePressed = false;
double lastMouseX = 0.0, lastMouseY = 0.0;

// Current window size
int windowWidth = SCR_WIDTH;
int windowHeight = SCR_HEIGHT;

// Function prototypes
void framebuffer_size_callback(GLFWwindow* window, int width, int height);
void mouse_button_callback(GLFWwindow* window, int button, int action, int mods);
void cursor_position_callback(GLFWwindow* window, double xpos, double ypos);
void scroll_callback(GLFWwindow* window, double xoffset, double yoffset);
void processInput(GLFWwindow* window);
std::string loadShaderSource(const char* filepath);
unsigned int compileShader(unsigned int type, const char* source);
unsigned int createShaderProgram(const char* vertexPath, const char* fragmentPath);

int main()
{
    // Initialize GLFW
    if (!glfwInit())
    {
        std::cerr << "Failed to initialize GLFW" << std::endl;
        return -1;
    }

    // Configure GLFW
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

#ifdef __APPLE__
    glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);
#endif

    // Create window
    GLFWwindow* window = glfwCreateWindow(SCR_WIDTH, SCR_HEIGHT, "Black Hole Simulation - TON 618", NULL, NULL);
    if (window == NULL)
    {
        std::cerr << "Failed to create GLFW window" << std::endl;
        glfwTerminate();
        return -1;
    }
    glfwMakeContextCurrent(window);

    // Set callbacks
    glfwSetFramebufferSizeCallback(window, framebuffer_size_callback);
    glfwSetMouseButtonCallback(window, mouse_button_callback);
    glfwSetCursorPosCallback(window, cursor_position_callback);
    glfwSetScrollCallback(window, scroll_callback);

    // Load OpenGL function pointers with GLAD
    if (!gladLoadGLLoader((GLADloadproc)glfwGetProcAddress))
    {
        std::cerr << "Failed to initialize GLAD" << std::endl;
        return -1;
    }

    std::cout << "OpenGL Version: " << glGetString(GL_VERSION) << std::endl;

    // Build and compile shaders
    unsigned int shaderProgram = createShaderProgram("shaders/vertex.glsl", "shaders/fragment.glsl");
    if (shaderProgram == 0)
    {
        glfwTerminate();
        return -1;
    }

    // Set up fullscreen quad vertices
    float quadVertices[] = {
        // positions      // texture coords
        -1.0f,  1.0f,  0.0f,  0.0f, 1.0f,
        -1.0f, -1.0f,  0.0f,  0.0f, 0.0f,
         1.0f, -1.0f,  0.0f,  1.0f, 0.0f,
         1.0f,  1.0f,  0.0f,  1.0f, 1.0f
    };

    unsigned int indices[] = {
        0, 1, 2,
        0, 2, 3
    };

    // Create VAO, VBO, EBO
    unsigned int VAO, VBO, EBO;
    glGenVertexArrays(1, &VAO);
    glGenBuffers(1, &VBO);
    glGenBuffers(1, &EBO);

    glBindVertexArray(VAO);

    glBindBuffer(GL_ARRAY_BUFFER, VBO);
    glBufferData(GL_ARRAY_BUFFER, sizeof(quadVertices), quadVertices, GL_STATIC_DRAW);

    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, EBO);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(indices), indices, GL_STATIC_DRAW);

    // Position attribute
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 5 * sizeof(float), (void*)0);
    glEnableVertexAttribArray(0);

    // Texture coord attribute
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 5 * sizeof(float), (void*)(3 * sizeof(float)));
    glEnableVertexAttribArray(1);

    // Get uniform locations
    int resolutionLoc = glGetUniformLocation(shaderProgram, "resolution");
    int timeLoc = glGetUniformLocation(shaderProgram, "time");
    int camPosLoc = glGetUniformLocation(shaderProgram, "cameraPos");
    int camTargetLoc = glGetUniformLocation(shaderProgram, "cameraTarget");
    int camFovLoc = glGetUniformLocation(shaderProgram, "cameraFov");

    std::cout << "\n=== Black Hole Simulation Controls ===" << std::endl;
    std::cout << "Mouse drag  - Orbit camera around black hole" << std::endl;
    std::cout << "Scroll      - Zoom in/out" << std::endl;
    std::cout << "ESC         - Exit" << std::endl;
    std::cout << "\nRendering TON 618 black hole..." << std::endl;

    // Render loop
    while (!glfwWindowShouldClose(window))
    {
        // Input
        processInput(window);

        // Render
        glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);

        // Use shader program
        glUseProgram(shaderProgram);

        // Calculate camera position from spherical coordinates
        float camX = camRadius * sinf(camTheta) * cosf(camPhi);
        float camY = camRadius * cosf(camTheta);
        float camZ = camRadius * sinf(camTheta) * sinf(camPhi);

        // Update uniforms
        float time = (float)glfwGetTime();
        glUniform2f(resolutionLoc, (float)windowWidth, (float)windowHeight);
        glUniform1f(timeLoc, time);
        glUniform3f(camPosLoc, camX, camY, camZ);
        glUniform3f(camTargetLoc, 0.0f, 0.0f, 0.0f);  // Always look at origin (black hole)
        glUniform1f(camFovLoc, camFov);

        // Draw fullscreen quad
        glBindVertexArray(VAO);
        glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, 0);

        // Swap buffers and poll events
        glfwSwapBuffers(window);
        glfwPollEvents();
    }

    // Cleanup
    glDeleteVertexArrays(1, &VAO);
    glDeleteBuffers(1, &VBO);
    glDeleteBuffers(1, &EBO);
    glDeleteProgram(shaderProgram);

    glfwTerminate();
    return 0;
}

void framebuffer_size_callback(GLFWwindow* window, int width, int height)
{
    windowWidth = width;
    windowHeight = height;
    glViewport(0, 0, width, height);
}

void mouse_button_callback(GLFWwindow* window, int button, int action, int mods)
{
    if (button == GLFW_MOUSE_BUTTON_LEFT)
    {
        if (action == GLFW_PRESS)
        {
            mousePressed = true;
            glfwGetCursorPos(window, &lastMouseX, &lastMouseY);
        }
        else if (action == GLFW_RELEASE)
        {
            mousePressed = false;
        }
    }
}

void cursor_position_callback(GLFWwindow* window, double xpos, double ypos)
{
    if (mousePressed)
    {
        double dx = xpos - lastMouseX;
        double dy = ypos - lastMouseY;

        // Update camera angles
        camPhi -= (float)dx * 0.005f;
        camTheta += (float)dy * 0.005f;

        // Clamp theta to avoid flipping
        if (camTheta < 0.1f) camTheta = 0.1f;
        if (camTheta > 3.04f) camTheta = 3.04f;  // ~174 degrees

        lastMouseX = xpos;
        lastMouseY = ypos;
    }
}

void scroll_callback(GLFWwindow* window, double xoffset, double yoffset)
{
    // Zoom in/out
    camRadius -= (float)yoffset * 20.0f;

    // Clamp radius
    if (camRadius < CAM_MIN_RADIUS) camRadius = CAM_MIN_RADIUS;
    if (camRadius > CAM_MAX_RADIUS) camRadius = CAM_MAX_RADIUS;
}

void processInput(GLFWwindow* window)
{
    if (glfwGetKey(window, GLFW_KEY_ESCAPE) == GLFW_PRESS)
        glfwSetWindowShouldClose(window, true);

    // Keyboard zoom controls
    if (glfwGetKey(window, GLFW_KEY_W) == GLFW_PRESS || glfwGetKey(window, GLFW_KEY_UP) == GLFW_PRESS)
    {
        camRadius -= 2.0f;
        if (camRadius < CAM_MIN_RADIUS) camRadius = CAM_MIN_RADIUS;
    }
    if (glfwGetKey(window, GLFW_KEY_S) == GLFW_PRESS || glfwGetKey(window, GLFW_KEY_DOWN) == GLFW_PRESS)
    {
        camRadius += 2.0f;
        if (camRadius > CAM_MAX_RADIUS) camRadius = CAM_MAX_RADIUS;
    }

    // Keyboard rotation controls
    if (glfwGetKey(window, GLFW_KEY_A) == GLFW_PRESS || glfwGetKey(window, GLFW_KEY_LEFT) == GLFW_PRESS)
    {
        camPhi += 0.02f;
    }
    if (glfwGetKey(window, GLFW_KEY_D) == GLFW_PRESS || glfwGetKey(window, GLFW_KEY_RIGHT) == GLFW_PRESS)
    {
        camPhi -= 0.02f;
    }
}

std::string loadShaderSource(const char* filepath)
{
    std::ifstream file(filepath);
    if (!file.is_open())
    {
        std::cerr << "Failed to open shader file: " << filepath << std::endl;
        return "";
    }

    std::stringstream buffer;
    buffer << file.rdbuf();
    return buffer.str();
}

unsigned int compileShader(unsigned int type, const char* source)
{
    unsigned int shader = glCreateShader(type);
    glShaderSource(shader, 1, &source, NULL);
    glCompileShader(shader);

    // Check for compilation errors
    int success;
    char infoLog[512];
    glGetShaderiv(shader, GL_COMPILE_STATUS, &success);
    if (!success)
    {
        glGetShaderInfoLog(shader, 512, NULL, infoLog);
        std::cerr << "Shader compilation failed:\n" << infoLog << std::endl;
        return 0;
    }

    return shader;
}

unsigned int createShaderProgram(const char* vertexPath, const char* fragmentPath)
{
    // Load shader sources
    std::string vertexSource = loadShaderSource(vertexPath);
    std::string fragmentSource = loadShaderSource(fragmentPath);

    if (vertexSource.empty() || fragmentSource.empty())
    {
        return 0;
    }

    // Compile shaders
    unsigned int vertexShader = compileShader(GL_VERTEX_SHADER, vertexSource.c_str());
    unsigned int fragmentShader = compileShader(GL_FRAGMENT_SHADER, fragmentSource.c_str());

    if (vertexShader == 0 || fragmentShader == 0)
    {
        return 0;
    }

    // Link shaders into program
    unsigned int shaderProgram = glCreateProgram();
    glAttachShader(shaderProgram, vertexShader);
    glAttachShader(shaderProgram, fragmentShader);
    glLinkProgram(shaderProgram);

    // Check for linking errors
    int success;
    char infoLog[512];
    glGetProgramiv(shaderProgram, GL_LINK_STATUS, &success);
    if (!success)
    {
        glGetProgramInfoLog(shaderProgram, 512, NULL, infoLog);
        std::cerr << "Shader program linking failed:\n" << infoLog << std::endl;
        return 0;
    }

    // Delete shaders (they're linked into program now)
    glDeleteShader(vertexShader);
    glDeleteShader(fragmentShader);

    return shaderProgram;
}
