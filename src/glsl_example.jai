#import "Basic";
#import "Math";
Input :: #import "Input";
#import "Window_Creation";
#import "GL";

// This should be an import for actual apps
#load "../Jai_To_Shader.jai";

#load "glsl_shaders.jai";
#load "backend.jai";

main :: () {
  window := create_window(1080, 720, "FancyTiles");
  load_gl(window);

  print("Vertex Shader:\n%\n\n=========\n\n", tiles_vertex_shader_string);
  print("Fragment Shader:\n%\n", tiles_fragment_shader_string);

  vao: u32;
  buffer: u32;
  shader: u32;
  
  data := Vector2.[
    Vector2.{ -1, -1 },
    Vector2.{  1, -1 },
    Vector2.{  1,  1 },
    Vector2.{ -1, -1 },
    Vector2.{  1,  1 },
    Vector2.{ -1,  1 },
  ];

  glGenVertexArrays(1, *vao);
  glBindVertexArray(vao);
  glGenBuffers(1, *buffer);
  glBindBuffer(GL_ARRAY_BUFFER, buffer);
  glBufferData(GL_ARRAY_BUFFER, 6 * size_of(Vector2), *data, GL_STATIC_DRAW);
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, size_of(Vector2), xx 0);
  glEnableVertexAttribArray(0);

  err: s32;
  shader = glCreateProgram();
  vert_module := glCreateShader(GL_VERTEX_SHADER);
  frag_module := glCreateShader(GL_FRAGMENT_SHADER);
  vscode := tiles_vertex_shader_string;
  fscode := tiles_fragment_shader_string;
  glShaderSource(vert_module, 1, *vscode.data, xx *vscode.count);
  glShaderSource(frag_module, 1, *fscode.data, xx *fscode.count);
  glCompileShader(vert_module);
  glCompileShader(frag_module);

  glGetShaderiv(vert_module, GL_COMPILE_STATUS, *err);
  if xx err == GL_FALSE {
    print("Vertex Shader Compilation Failed:\n");
    length: u32;
    glGetShaderiv(vert_module, GL_INFO_LOG_LENGTH, xx *length);
    info: *GLchar = alloc(length * size_of(GLchar));
    glGetShaderInfoLog(vert_module, length, xx 0, info);
    info_str: string;
    info_str.data = xx info;
    info_str.count = length;
    print("%\n", info_str);
    free(info);
    exit(1);
  }
  glGetShaderiv(frag_module, GL_COMPILE_STATUS, *err);
  if xx err == GL_FALSE {
    print("Fragment Shader Compilation Failed:\n");
    length: u32;
    glGetShaderiv(frag_module, GL_INFO_LOG_LENGTH, xx *length);
    info: *GLchar = alloc(length * size_of(GLchar));
    glGetShaderInfoLog(frag_module, length, xx 0, info);
    info_str: string;
    info_str.data = xx info;
    info_str.count = length;
    print("%\n", info_str);
    free(info);
    exit(1);
  }

  glAttachShader(shader, vert_module);
  glAttachShader(shader, frag_module);
  glLinkProgram(shader);
  glGetProgramiv(shader, GL_LINK_STATUS, *err);
  if xx err == GL_FALSE {
    print("Program Linking Failed:\n");
    length: u32;
    glGetProgramiv(shader, GL_INFO_LOG_LENGTH, xx *length);
    info: *GLchar = alloc(length * size_of(GLchar));
    glGetProgramInfoLog(shader, length, xx 0, info);
    info_str: string;
    info_str.data = xx info;
    info_str.count = length;
    print("%", info_str);
    free(info);
    exit(1);
  }
  glDetachShader(shader, vert_module);
  glDetachShader(shader, frag_module);
  glDeleteShader(vert_module);
  glDeleteShader(frag_module);
  glUseProgram(shader);
  
  resolution_location := glGetUniformLocation(shader, "u_resolution");
  time_location := glGetUniformLocation(shader, "u_time");

  glUniform2f(resolution_location, 1080, 720);

  quit := false;
  start : Apollo_Time;
  end : Apollo_Time;
  dt : float64 = ---;
  time_value : float32;

  while !quit {
    dt = to_float64_seconds(end - start);
    start = current_time_consensus();
    
    time_value += xx dt;

    Input.update_window_events();
    for Input.events_this_frame {
      if it.type == {
        case .QUIT; quit = true;
      }
    }

    glClearColor(0.3, 0.2, 0.3, 1.0);
    glClear(GL_COLOR_BUFFER_BIT);
    glUniform1f(time_location, time_value);
    
    glDrawArrays(GL_TRIANGLES, 0, 6);

    swap_buffers(window);
    end = current_time_consensus();
  }

  glDeleteBuffers(1, *buffer);
  glDeleteVertexArrays(1, *vao);
  glDeleteProgram(shader);
}
