#import "Basic";
#import "Math";

// This should be an import for actual apps
#load "../Jai_To_Shader.jai";

main :: () {
  print("Vertex Shader:\n%\n\n=========\n\n", testing_vertex_shader_string);
  // print("Fragment Shader:\n%\n", testing_fragment_shader_string);
}


// ==========================================================================================

VertexShader_In :: struct {
  a_pos: Vector2;
}

VertexShader_Out :: struct {
  f_pos: Vector2; @semantic_SV_POSITION
}

VertexShader_CBuffer :: struct {
  test: Vector2;
  texture: Texture2D; @register_t0
  sampler: SamplerState; @register_s0
}

testing_vertex_shader :: (in: VertexShader_In, cbuf: VertexShader_CBuffer) -> VertexShader_Out {
  out: VertexShader_Out;
  out.f_pos = in.a_pos;
  return out;
} @hlsl @vertex_shader