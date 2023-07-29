write_hlsl_vertex_shader :: (ctx: *Shader_Write_Context, node: *Code_Procedure_Body) -> string {
  return "";
}

write_hlsl_fragment_shader :: (ctx: *Shader_Write_Context, node: *Code_Procedure_Body) -> string {
  return "";
}

print_hlsl_procedure_call :: (ctx: *Shader_Write_Context, node: *String_Builder, pc: *Code_Procedure_Call) {
}

print_hlsl_function :: (ctx: *Shader_Write_Context, sb: *String_Builder, called_fn: *Code_Procedure_Header) {
}

write_hlsl_shader_code :: (ctx: *Shader_Write_Context, node: *Code_Procedure_Body) -> string {
  return "";
}
