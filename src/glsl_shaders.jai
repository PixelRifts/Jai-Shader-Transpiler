// https://www.shadertoy.com/view/mdBSRt

//~ Vertex Shader

VertexShader_Uniforms :: struct {}
VertexShader_In :: struct {
  a_pos : Vector2;
}
VertexShader_Out :: struct {
  gl_Position: Vector4; @inbuilt
  gl_FragCoord: Vector4; @inbuilt
}

tiles_vertex_shader :: (using in : VertexShader_In, using un : VertexShader_Uniforms)
                             -> VertexShader_Out {
  using out: VertexShader_Out;
  
  gl_Position = Vector4.{ a_pos.x, a_pos.y, 0.0, 1.0 };
  
  return out;
} @glsl @vertex_shader


//~ Fragment Shader

FragmentShader_Uniforms :: struct {
  u_resolution : Vector2;
  u_time       : float;
}
FragmentShader_Out :: struct {
  out_color : Vector4;
}

tiles_fragment_shader :: (using in : VertexShader_Out, using un : FragmentShader_Uniforms) -> FragmentShader_Out {
  using out: FragmentShader_Out;

  aspect_ratio := u_resolution.y / u_resolution.x;
  uv := Vector2.{ gl_FragCoord.x, gl_FragCoord.y } / u_resolution.x;
  uv -= Vector2.{ 0.5, 0.5 * aspect_ratio };
  rot := radians(-30.0 -u_time); // radians(45.0*sin(iTime));
  rotation_matrix := Matrix2.{cos(rot), -sin(rot), sin(rot), cos(rot)};
 	uv = rotation_matrix * uv;
  scaled_uv := 20.0 * uv;
  tile := fract(scaled_uv);
  tile_dist := min(min(tile.x, 1.0-tile.x), min(tile.y, 1.0-tile.y));
  square_dist := length(floor(scaled_uv));
  edge := sin(u_time-square_dist*20.);
  edge = mod(edge * edge, edge / edge);
  value := mix(tile_dist, 1.0-tile_dist, step(1.0, edge));
  edge = pow(abs(1.0-edge), 2.2) * 0.5;
  value = smoothstep(edge-0.05, edge, 0.95*value);
  value += square_dist*.1;
  value *= 0.8 - 0.2;
  out_color = Vector4.{ pow(value, 2.0), pow(value, 1.5), pow(value, 1.2), 1.0 };

  return out;
} @glsl @fragment_shader
