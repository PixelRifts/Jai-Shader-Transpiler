#import "Basic";
#import "Math";
#import "Process";
#import "File";

// This should be an import for actual apps
#load "../Jai_To_Glsl.jai";

main :: () {
  print("%\n", my_jai_vertex_shader_string);
  print("==========\n\n");
  print("%\n", my_jai_fragment_shader_string);
}

list: [..]int;

//~ Vertex Shader

VertexShader_Uniforms :: struct {
  projection : Matrix4;
}

VertexShader_In :: struct {
  pos : Vector2;
  a_color : Vector4;
}

VertexShader_Out :: struct {
  gl_Position : Vector4;
  
  color : Vector4;
}



c :: () {

}

b :: () {
  
}

a :: (one: int, two: float, three: float64) {
  b();
}

my_jai_vertex_shader :: (using in : VertexShader_In, using un : VertexShader_Uniforms)
                             -> VertexShader_Out {
  using out: VertexShader_Out;
  
  a(1, 2, 3);
  
  return out;
} @vertex_shader



//~ Fragment Shader

FragmentShader_Uniforms :: struct {}

FragmentShader_Out :: struct {
  out_color : Vector4;
}

my_jai_fragment_shader :: (using in : VertexShader_Out, using un : FragmentShader_Uniforms) -> FragmentShader_Out {
  using out: FragmentShader_Out;
  
  out_color = color;
  
  return out;
} @fragment_shader
