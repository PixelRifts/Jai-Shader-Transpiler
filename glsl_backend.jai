
GLSL_VERSION :: "#version 330 core\n";

// Short explanation...
// Every function is dumped to a separate string, which the Shader_Write_Context holds a list of
// The functions are appended onto the functions list, and then the for loop runs to push onto
// the main builder

write_glsl_vertex_shader :: (ctx: *Shader_Write_Context, node: *Code_Procedure_Body) -> string {
  if node.header.returns.count != 1
    compiler_report("GLSL Backend: Jai Vertex Shader must return a structure with at least a Vector4 gl_Position field");
  if node.header.arguments.count != 2
    compiler_report("GLSL Backend: Jai Vertex Shader must get two structures as arguments (Vertex Input and Uniforms)");
  if node.header.parameter_usings.count != 2
    compiler_report("GLSL Backend: The struct arguments to a Jai Vertex Shader must be marked 'using'");

  // main function string builder
  main_sb: String_Builder;
  append(*main_sb, "void main() {\n");
  print_glsl_stmt(ctx, *main_sb, node.block, is_main=true);
  append(*main_sb, "}\n");
  array_add(*ctx.functions, .{ prototype=node.header, name="main", code=builder_to_string(*main_sb) });
  
  if ctx.waiting_functions.count return "";

  return write_glsl_shader_code(ctx, node);
}

write_glsl_fragment_shader :: (ctx: *Shader_Write_Context, node: *Code_Procedure_Body) -> string {
  if node.header.returns.count != 1
    compiler_report("GLSL Backend: Jai Fragment Shader must return a structure with at least one Vector4");
  if node.header.arguments.count != 2
    compiler_report("GLSL Backend: Jai Fragment Shader must get two structures as arguments (Vertex output and Uniforms)");
  if node.header.parameter_usings.count != 2
    compiler_report("GLSL Backend: The struct arguments to a Jai Fragment Shader must be marked 'using'");

  // main function string builder
  main_sb: String_Builder;
  append(*main_sb, "void main() {\n");
  print_glsl_stmt(ctx, *main_sb, node.block, is_main=true);
  append(*main_sb, "}\n");
  array_add(*ctx.functions, .{ prototype=node.header, name="main", code=builder_to_string(*main_sb) });

  if ctx.waiting_functions.count return "";

  return write_glsl_shader_code(ctx, node);
}

write_glsl_shader_code :: (ctx: *Shader_Write_Context, node: *Code_Procedure_Body) -> string {
  sb: String_Builder;
  append(*sb, tprint("%_string", node.header.name));
  append(*sb, " :: #string END\n");
  append(*sb, GLSL_VERSION);
  print_glsl_in_vars(*sb, node.header, output_layout=false);
  print_glsl_uniforms(*sb, node.header);
  print_glsl_out_vars(*sb, node.header);
  // Output prototypes for "late binding"
  for ctx.functions {
    if it.name != "main" print_glsl_prototype(*sb, it.prototype);
  }
  append(*sb, "\n");
  // Output code
  for ctx.functions {
    append(*sb, it.code);
    append(*sb, "\n");
  }
  append(*sb, "\nEND");

  return builder_to_string(*sb);
}


// In, Out, Uniforms, and Prototypes

print_glsl_in_vars :: (sb : *String_Builder, node : *Code_Procedure_Header, output_layout := true) {
  struct_type_generic := node.arguments[0].type_inst.result;
  if struct_type_generic.type != .STRUCT
    compiler_report(tprint("Glsl Backend: Shader Input is not a struct, but is a %\n", struct_type_generic.type));
  struct_type := cast(*Type_Info_Struct) struct_type_generic;
  
  for struct_type.members {
    if begins_with(it.name, "gl_") continue;
    
    if output_layout
      append(sb, tprint("layout (location=%) in ", it_index));
    else
      append(sb, "in ");
      
    print_glsl_member_with_typename(sb, *it);
    append(sb, ";\n");
  }
  append(sb, "\n");
}

print_glsl_out_vars :: (sb : *String_Builder, node : *Code_Procedure_Header) {
  struct_type_generic := node.returns[0].type_inst.result;
  if struct_type_generic.type != .STRUCT
    compiler_report("Glsl Backend: Shader Output is not a struct\n");
  struct_type := cast(*Type_Info_Struct) struct_type_generic;
  
  for struct_type.members {
    if begins_with(it.name, "gl_") continue;
    
    append(sb, "out ");
    print_glsl_member_with_typename(sb, *it);
    append(sb, ";\n");
  }
  append(sb, "\n");
}

print_glsl_uniforms :: (sb : *String_Builder, node : *Code_Procedure_Header) {
  struct_type_generic := node.arguments[1].type_inst.result;
  if struct_type_generic.type != .STRUCT
    compiler_report("Glsl Backend: Shader Input is not a struct\n");
  struct_type := cast(*Type_Info_Struct) struct_type_generic;
  
  for struct_type.members {
    append(sb, "uniform ");
    print_glsl_member_with_typename(sb, *it);
    append(sb, ";\n");
  }
  append(sb, "\n");
}

print_glsl_prototype :: (sb: *String_Builder, header: *Code_Procedure_Header) {
  if header.returns.count != 0 {
    ret := header.returns[0];
    if ret.type_inst
      print_glsl_type(sb, ret.type_inst.result);
    else
      print_glsl_type(sb, ret.expression.type);
  } else {
    append(sb, "void");
  }
  
  append(sb, tprint(" %(", header.name));
  for header.arguments {
    if it.type_inst
      print_glsl_type(sb, it.type_inst.result);
    else
      print_glsl_type(sb, it.expression.type);
    
    append(sb, " ");
    append(sb, it.name);
    
    if it_index != header.arguments.count-1 append(sb, ", ");
  }
  append(sb, ");\n");
}

print_glsl_member_with_typename :: (sb : *String_Builder, thing : *Type_Info_Struct_Member) {
  print_glsl_type(sb, thing.type);
  append(sb, " ");
  append(sb, thing.name);
}

print_glsl_type :: (sb : *String_Builder, type: *Type_Info) {
  if type.type == {
    case .INTEGER; {
      inttype := cast(*Type_Info_Integer) type;
      append(sb, ifx inttype.signed then "int" else "uint");
    }
    case .FLOAT; append(sb, ifx type.runtime_size == 64 then "double" else "float");
    case .BOOL; append(sb, "bool");
    case .STRUCT; {
      structtype := cast(*Type_Info_Struct) type;
      append(sb, jai_to_glsl_type_name(structtype.name));
    }
    case .VOID; append(sb, "void");
    
    case; compiler_report(tprint("The type '%' is currently unsupported in Jai Shaders\n", type.type));
  }
}


add_indents :: (sb : *String_Builder, indent : s64) #expand {
  for i: 0..indent*4 append(sb, " ");
}

// The big boy, statement converter
print_glsl_stmt :: (using ctx: *Shader_Write_Context, sb: *String_Builder,
                         node: *Code_Block, is_main := false, indent := 1) {
  for node.statements {
    if it.kind == {
      case .DECLARATION; {
        add_indents(sb, indent);
        
        op := cast(*Code_Declaration) it;
        
        if op.type_inst
          print_glsl_type(sb, op.type_inst.result);
        else
          print_glsl_type(sb, op.expression.type);
        
        append(sb, " ");
        append(sb, op.name);
        if op.expression {
          append(sb, " = ");
          print_glsl_expr(ctx, sb, op.expression);
        }
        append(sb, ";\n");
      }
      
      case .BINARY_OPERATOR; {
        add_indents(sb, indent);
        op := cast(*Code_Binary_Operator) it;
        
        print_glsl_expr(ctx, sb, op.left);
        append(sb, operator_string(op.operator_type));
        print_glsl_expr(ctx, sb, op.right);
        append(sb, ";\n");
      }
      
      case .IF; {
        add_indents(sb, indent);
        
        op := cast(*Code_If) it;
        
        if op.is_switch_statement {
          // GLSL switches only allow Integers for some reason, so we'll transpile other
          // things as a simple if-else chain
          if op.condition.type.type == .INTEGER {
            append(sb, "switch (");
            print_glsl_expr(ctx, sb, op.condition);
            append(sb, ") {\n");
            print_glsl_stmt(ctx, sb, op.then_block, indent=indent+1);
            add_indents(sb, indent);
            append(sb, "}\n");
          } else {
            curr := 0;
            default_case: *Code_Case;
            while curr < op.then_block.statements.count {
              curr_case := cast(*Code_Case) op.then_block.statements[curr];
              
              if curr_case.condition == null {
                default_case = curr_case;
                curr += 1;
                continue;
              }
              append(sb, "if (");
              print_glsl_expr(ctx, sb, op.condition);
              append(sb, " == ");
              print_glsl_expr(ctx, sb, curr_case.condition);
              append(sb, ") {\n");
              print_glsl_stmt(ctx, sb, curr_case.then_block, indent=indent+1);
              add_indents(sb, indent);
              
              if (curr == op.then_block.statements.count-1) && (default_case == null)
                append(sb, "}\n");
              else append(sb, "} else ");
              
              curr += 1;
            }
            if default_case {
              append(sb, "{\n");
              print_glsl_stmt(ctx, sb, default_case.then_block, indent=indent+1);
              add_indents(sb, indent);
              append(sb, "}\n");
            }
          }
        } else {
          append(sb, "if (");
          print_glsl_expr(ctx, sb, op.condition);
          append(sb, ") {\n");
          print_glsl_stmt(ctx, sb, op.then_block, indent=indent+1);
          add_indents(sb, indent);
          append(sb, "}\n");
          if op.else_block {
            append(sb, " else {\n");
            print_glsl_stmt(ctx, sb, op.else_block, indent=indent+1);
            add_indents(sb, indent);
            append(sb, "}\n");
          }
        }
      }
      
      case .CASE; {
        add_indents(sb, indent);
        op := cast(*Code_Case) it;
        
        if op.condition {
          append(sb, "case ");
          print_glsl_expr(ctx, sb, op.condition);
          append(sb, ": {\n");
        } else {
          append(sb, "default: {\n");
        }
        print_glsl_stmt(ctx, sb, op.then_block, indent=indent+1);
        add_indents(sb, indent);
        append(sb, ifx op.marked_as_fallthrough then "}" else "} break;\n");
      }
      
      case .WHILE; {
        add_indents(sb, indent);
        op := cast(*Code_While) it;
        append(sb, "while (");
        print_glsl_expr(ctx, sb, op.condition);
        append(sb, ") {\n");
        print_glsl_stmt(ctx, sb, op.block, indent=indent+1);
        add_indents(sb, indent);
        append(sb, "}\n");
      }
      
      case .FOR; {
        add_indents(sb, indent);
        op := cast(*Code_For) it;
        if op.macro_expansion_procedure_call || !op.iteration_expression_right
          compiler_report("Can't use special iterators in Jai Shaders");
        if op.for_flags & .POINTER
          compiler_report("Iteration by Pointers is disallowed in Jai Shaders");
        
        append(sb, "for (int ");
        append(sb, op.ident_decl.name);
        append(sb, " = ");
        print_glsl_expr(ctx, sb, op.iteration_expression);
        append(sb, "; ");
        append(sb, op.ident_decl.name);
        append(sb, ifx op.for_flags & .REVERSE then " > " else " < ");
        print_glsl_expr(ctx, sb, op.iteration_expression_right);
        append(sb, "; ");
        append(sb, op.ident_decl.name);
        append(sb, ifx op.for_flags & .REVERSE then " -= 1) {\n" else " += 1) {\n");
        print_glsl_stmt(ctx, sb, op.block, indent=indent+1);
        add_indents(sb, indent);
        append(sb, "}\n");
      }
      
      case .RETURN; {
        if is_main continue;
        add_indents(sb, indent);
        op := cast(*Code_Return) it;
        append(sb, "return ");
        if op.arguments_sorted.count == 0 {
          append(sb, ";\n");
        } else if op.arguments_sorted.count == 1 {
          print_glsl_expr(ctx, sb, op.arguments_sorted[0]);
          append(sb, ";\n");
        } else
          compiler_report("Multiple Return Arguments Disallowed in Jai Shaders");
      }
      
      case .PROCEDURE_CALL; {
        add_indents(sb, indent);
        handle_procedure_call(ctx, sb, xx it);
        append(sb, ";\n");
      }
      
      // Ignore the using statements in the shader
      case .USING; continue;
      
      case; {
        compiler_report(tprint("The statement of type '%' is not supported in Jai Shaders", it.kind));
      }
    }
  }
}

// Expressions. All expressions are "supported".
// Most of them are not converted to GLSL currently however.
// Will have to add specific things for many of these
// We can't simply print_expression in many of them because a struct literal could be a subexpression
// which has to be converted correctly
print_glsl_expr :: (using ctx: *Shader_Write_Context, sb : *String_Builder, node : *Code_Node) {
  if node.kind == {

    case .LITERAL; {
      lit := cast(*Code_Literal) node;
      if lit.value_type == .STRUCT {
        name := cast(*Code_Ident) lit.struct_literal_info.type_expression.type_valued_expression;
        append(sb, jai_to_glsl_type_name(name.name));
        
        append(sb, "(");
        for lit.struct_literal_info.arguments {
          if it_index != 0 append(sb, ", ");
          print_glsl_expr(ctx, sb, it);
        }
        append(sb, ")");
        
        return;
      } else PP.print_expression(sb, node);
    }

    case .UNARY_OPERATOR; {
      un := cast(*Code_Unary_Operator) node;
      append(sb, operator_string(un.operator_type));
      print_glsl_expr(ctx, sb, un.subexpression);
    }

    case .BINARY_OPERATOR; {
      bn := cast(*Code_Binary_Operator) node;
      print_glsl_expr(ctx, sb, bn.left);
      append(sb, operator_string(bn.operator_type));
      print_glsl_expr(ctx, sb, bn.right);
    }
    
    case .PROCEDURE_CALL; {
      handle_procedure_call(ctx, sb, xx node);
    }
    
    case; PP.print_expression(sb, node);
  }
}

print_glsl_procedure_call :: (ctx: *Shader_Write_Context, sb: *String_Builder, pc: *Code_Procedure_Call) {
  PP.print_expression(sb, pc.procedure_expression);
  append(sb, "(");
  for pc.arguments_sorted {
    print_glsl_expr(ctx, sb, it);
    if it_index != pc.arguments_sorted.count-1 append(sb, ", ");
  }
  append(sb, ")");
}


print_glsl_function :: (ctx: *Shader_Write_Context, sb: *String_Builder, fn: Code_Procedure_Header) {
  if fn.returns.count != 0 {
    ret := fn.returns[0];
    if ret.type_inst
      print_glsl_type(sb, ret.type_inst.result);
    else
      print_glsl_type(sb, ret.expression.type);
  } else {
    append(sb, "void");
  }
  
  append(sb, tprint(" %(", fn.name));
  for fn.arguments {
    if it.type_inst
      print_glsl_type(sb, it.type_inst.result);
    else
      print_glsl_type(sb, it.expression.type);
    
    append(sb, " ");
    append(sb, it.name);
    
    if it_index != fn.arguments.count-1 append(sb, ", ");
  }
  append(sb, ") {\n");
  print_glsl_stmt(ctx, sb, fn.body_or_null.block);
  append(sb, "}\n");
}

// This is some hardcoding, and is incomplete.
// More types need to be added here
jai_to_glsl_type_name :: (in : string) -> string {
  if      in == "Vector4"  return "vec4";
  else if in == "Vector3"  return "vec3";
  else if in == "Vector2"  return "vec2";
  else if in == "IVector4" return "ivec4";
  else if in == "IVector3" return "ivec3";
  else if in == "IVector2" return "ivec2";
  else if in == "UVector4" return "uvec4";
  else if in == "UVector3" return "uvec3";
  else if in == "UVector2" return "uvec2";
  else if in == "BVector4" return "bvec4";
  else if in == "BVector3" return "bvec3";
  else if in == "BVector2" return "bvec2";
  
  else if in == "Matrix4" return "mat4";
  else if in == "Matrix3" return "mat3";
  else if in == "Matrix2" return "mat2";

  else if in == "Sampler1D" return "sampler1D";
  else if in == "Sampler2D" return "sampler2D";
  else if in == "Sampler3D" return "sampler3D";
  
  else if in == "float64" return "double";
  else if in == "s32" return "int";
  
  else return in;
}
