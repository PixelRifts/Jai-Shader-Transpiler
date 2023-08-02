write_hlsl_vertex_shader :: (ctx: *Shader_Write_Context, node: *Code_Procedure_Body) -> string {
  if node.header.returns.count != 1
    compiler_report("HLSL Backend: Jai Vertex Shader must return a structure", make_location(node.header));
  if node.header.returns[0].type_inst.result.type != .STRUCT
    compiler_report("HLSL Backend: Jai Vertex Shader must return a structure", make_location(node.header));
  if node.header.arguments.count == 0
    compiler_report("HLSL Backend: Jai Vertex Shader must get AT LEAST 1 structure as an argument. (Vertex Input and (if required) additional structs as Constant Buffers)", make_location(node.header));
  if node.header.arguments[0].type_inst.result.type != .STRUCT
    compiler_report("HLSL Backend: Jai Vertex Shader must have a structure as the input", make_location(node.header));
  
  main_sb: String_Builder;
  append(*main_sb, (cast(*Type_Info_Struct)node.header.returns[0].type_inst.result).name);
  append(*main_sb, " main(");
  append(*main_sb, (cast(*Type_Info_Struct)node.header.arguments[0].type_inst.result).name);
  append(*main_sb, " ");
  append(*main_sb, node.header.arguments[0].name);
  append(*main_sb, ") {\n");
  print_hlsl_stmt(ctx, *main_sb, node.block, is_main=true);
  append(*main_sb, "}\n");
  array_add(*ctx.functions, .{ prototype=node.header, name="main", code=builder_to_string(*main_sb) });
  
  return write_hlsl_shader_code(ctx, node);
}

write_hlsl_fragment_shader :: (ctx: *Shader_Write_Context, node: *Code_Procedure_Body) -> string {
  if node.header.returns.count != 1
    compiler_report("HLSL Backend: Jai Fragment Shader must return a structure", make_location(node.header));
  if node.header.returns[0].type_inst.result.type != .STRUCT
    compiler_report("HLSL Backend: Jai Fragment Shader must return a structure", make_location(node.header));
  if node.header.arguments.count >= 1
    compiler_report("HLSL Backend: Jai Fragment Shader must get AT LEAST 1 structure as an argument. (Fragment Input and (if required) additional structs as Constant Buffers)", make_location(node.header));
  if node.header.arguments[0].type_inst.result.type != .STRUCT
    compiler_report("HLSL Backend: Jai Fragment Shader must have a structure as the input", make_location(node.header));
  
  main_sb: String_Builder;
  append(*main_sb, (cast(*Type_Info_Struct)node.header.returns[0].type_inst.result).name);
  append(*main_sb, " main(");
  append(*main_sb, (cast(*Type_Info_Struct)node.header.arguments[0].type_inst.result).name);
  append(*main_sb, " ");
  append(*main_sb, node.header.arguments[0].name);
  append(*main_sb, ") {\n");
  print_hlsl_stmt(ctx, *main_sb, node.block, is_main=true);
  append(*main_sb, "}\n");
  array_add(*ctx.functions, .{ prototype=node.header, name="main", code=builder_to_string(*main_sb) });
  
  return write_hlsl_shader_code(ctx, node);
}

print_hlsl_procedure_call :: (ctx: *Shader_Write_Context, sb: *String_Builder, pc: *Code_Procedure_Call) {
  PP.print_expression(sb, pc.procedure_expression);
  append(sb, "(");
  for pc.arguments_sorted {
    print_hlsl_expr(ctx, sb, it);
    if it_index != pc.arguments_sorted.count-1 append(sb, ", ");
  }
  append(sb, ")");
}

print_hlsl_function :: (ctx: *Shader_Write_Context, sb: *String_Builder, fn: *Code_Procedure_Header) {
  if fn.returns.count != 0 {
    ret := fn.returns[0];
    if ret.type_inst
      print_hlsl_type(sb, ret.type_inst.result);
    else
      print_hlsl_type(sb, ret.expression.type);
  } else {
    append(sb, "void");
  }

  append(sb, tprint(" %(", fn.name));
  for fn.arguments {
    if it.type_inst
      print_hlsl_type(sb, it.type_inst.result);
    else
      print_hlsl_type(sb, it.expression.type);
    
    append(sb, " ");
    append(sb, it.name);
    
    if it_index != fn.arguments.count-1 append(sb, ", ");
  }
  append(sb, ") {\n");
  print_hlsl_stmt(ctx, sb, fn.body_or_null.block);
  append(sb, "}\n");
}

write_hlsl_shader_code :: (ctx: *Shader_Write_Context, node: *Code_Procedure_Body) -> string {
  sb: String_Builder;
  append(*sb, tprint("%_string", node.header.name));
  append(*sb, " :: #string END\n");
  print_hlsl_in_vars(*sb, node.header);
  if node.header.arguments.count >= 2 print_hlsl_cbuffers(*sb, node.header);
  print_hlsl_out_vars(*sb, node.header);
  // Output prototypes for "late binding"
  for ctx.functions {
    if it.name != "main" print_hlsl_prototype(*sb, it.prototype);
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

print_hlsl_in_vars :: (sb: *String_Builder, node: *Code_Procedure_Header) {
  struct_type_generic := node.arguments[0].type_inst.result;
  if struct_type_generic.type != .STRUCT
    compiler_report(tprint("HLSL Backend: Shader Input is not a struct, but is a %\n", struct_type_generic.type), make_location(node.arguments[0]));
  struct_type := cast(*Type_Info_Struct) struct_type_generic;
  
  append(sb, tprint("struct % {\n", struct_type.name));
  for * struct_type.members {
    if member_has_note(it, "inbuilt") continue;
    
    append(sb, "    ");
    print_hlsl_member_with_typename(sb, it);
    
    append(sb, tprint(" : %;\n", member_get_semantic(it)));
  }
  append(sb, "}\n");
}

print_hlsl_cbuffers :: (sb: *String_Builder, node: *Code_Procedure_Header) {
  others: [..] string;

  for buf_idx: 1..node.arguments.count-1 {
    struct_type_generic := node.arguments[buf_idx].type_inst.result;
    if struct_type_generic.type != .STRUCT
      compiler_report(tprint("HLSL Backend: Shader Input is not a struct, but is a %\n", struct_type_generic.type), make_location(node.arguments[0]));
    struct_type := cast(*Type_Info_Struct) struct_type_generic;
    
    append(sb, tprint("cbuffer % {\n", struct_type.name));
    for * struct_type.members {
      register, found := member_get_note_suffix(it, "register_");
      if found {
        inner: String_Builder;
        print_hlsl_member_with_typename(*inner, it);
        append(*inner, " : register(");
        append(*inner, register);
        append(*inner, ");\n");
        array_add(*others, builder_to_string(*inner));
        continue;
      }
      
      append(sb, "    ");
      print_hlsl_member_with_typename(sb, it);
      append(sb, ";\n");
    }
    append(sb, "}\n");
  }
  
  for others append(sb, it);
}

print_hlsl_out_vars :: (sb: *String_Builder, node: *Code_Procedure_Header) {
  struct_type_generic := node.returns[0].type_inst.result;
  if struct_type_generic.type != .STRUCT
    compiler_report(tprint("HLSL Backend: Shader Input is not a struct, but is a %\n", struct_type_generic.type), make_location(node.arguments[0]));
  struct_type := cast(*Type_Info_Struct) struct_type_generic;
  
  append(sb, tprint("struct % {\n", struct_type.name));
  for * struct_type.members {
    if member_has_note(it, "inbuilt") continue;
    
    append(sb, "    ");
    print_hlsl_member_with_typename(sb, it);
    
    append(sb, tprint(" : %;\n", member_get_semantic(it)));
  }
  append(sb, "}\n");
}

print_hlsl_prototype :: (sb: *String_Builder, header: *Code_Procedure_Header) {
  if header.returns.count != 0 {
    ret := header.returns[0];
    if ret.type_inst
      print_hlsl_type(sb, ret.type_inst.result);
    else
      print_hlsl_type(sb, ret.expression.type);
  } else {
    append(sb, "void");
  }
  
  append(sb, tprint(" %(", header.name));
  for header.arguments {
    if it.type_inst
      print_hlsl_type(sb, it.type_inst.result);
    else
      print_hlsl_type(sb, it.expression.type);
    
    append(sb, " ");
    append(sb, it.name);
    
    if it_index != header.arguments.count-1 append(sb, ", ");
  }
  append(sb, ");\n");
}


print_hlsl_stmt :: (using ctx: *Shader_Write_Context, sb: *String_Builder,
                         node: *Code_Block, is_main := false, indent := 1) {
  for node.statements {
    if it.kind == {
      case .DECLARATION; {
        add_indents(sb, indent);
        
        op := cast(*Code_Declaration) it;
        
        if op.type_inst
          print_hlsl_type(sb, op.type_inst.result);
        else
          print_hlsl_type(sb, op.expression.type);
        append(sb, " ");
        append(sb, op.name);
        
        if op.expression {
          append(sb, " = ");
          print_hlsl_expr(ctx, sb, op.expression);
        }
        append(sb, ";\n");
      }
      
      case .BINARY_OPERATOR; {
        add_indents(sb, indent);
        op := cast(*Code_Binary_Operator) it;
        
        print_hlsl_expr(ctx, sb, op.left);
        append(sb, operator_string(op.operator_type));
        print_hlsl_expr(ctx, sb, op.right);
        append(sb, ";\n");
      }
      
      case .IF; {
        add_indents(sb, indent);
        
        op := cast(*Code_If) it;
        
        if op.is_switch_statement {
          // GLSL switches only allow Integers for some reason, so we'll transpile other
          // things as a simple if-else chain
          // Unsure about HLSL so I'll keep this in unless required to change
          if op.condition.type.type == .INTEGER {
            append(sb, "[branch] switch (");
            print_hlsl_expr(ctx, sb, op.condition);
            append(sb, ") {\n");
            print_hlsl_stmt(ctx, sb, op.then_block, indent=indent+1);
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
              print_hlsl_expr(ctx, sb, op.condition);
              append(sb, " == ");
              print_hlsl_expr(ctx, sb, curr_case.condition);
              append(sb, ") {\n");
              print_hlsl_stmt(ctx, sb, curr_case.then_block, indent=indent+1);
              add_indents(sb, indent);
              
              if (curr == op.then_block.statements.count-1) && (default_case == null)
                append(sb, "}\n");
              else append(sb, "} else ");
              
              curr += 1;
            }
            if default_case {
              append(sb, "{\n");
              print_hlsl_stmt(ctx, sb, default_case.then_block, indent=indent+1);
              add_indents(sb, indent);
              append(sb, "}\n");
            }
          }
        } else {
          append(sb, "if (");
          print_hlsl_expr(ctx, sb, op.condition);
          append(sb, ") {\n");
          print_hlsl_stmt(ctx, sb, op.then_block, indent=indent+1);
          add_indents(sb, indent);
          append(sb, "}\n");
          if op.else_block {
            append(sb, " else {\n");
            print_hlsl_stmt(ctx, sb, op.else_block, indent=indent+1);
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
          print_hlsl_expr(ctx, sb, op.condition);
          append(sb, ": {\n");
        } else {
          append(sb, "default: {\n");
        }
        print_hlsl_stmt(ctx, sb, op.then_block, indent=indent+1);
        add_indents(sb, indent);
        append(sb, ifx op.marked_as_fallthrough then "}" else "} break;\n");
      }
      
      case .WHILE; {
        add_indents(sb, indent);
        op := cast(*Code_While) it;
        append(sb, "while (");
        print_hlsl_expr(ctx, sb, op.condition);
        append(sb, ") {\n");
        print_hlsl_stmt(ctx, sb, op.block, indent=indent+1);
        add_indents(sb, indent);
        append(sb, "}\n");
      }
      
      case .FOR; {
        add_indents(sb, indent);
        op := cast(*Code_For) it;
        if op.macro_expansion_procedure_call || !op.iteration_expression_right
          compiler_report("Can't use special iterators in Jai Shaders", make_location(op));
        if op.for_flags & .POINTER
          compiler_report("Iteration by Pointers is disallowed in Jai Shaders", make_location(op));
        
        append(sb, "for (int ");
        append(sb, op.ident_decl.name);
        append(sb, " = ");
        print_hlsl_expr(ctx, sb, op.iteration_expression);
        append(sb, "; ");
        append(sb, op.ident_decl.name);
        append(sb, ifx op.for_flags & .REVERSE then " > " else " < ");
        print_hlsl_expr(ctx, sb, op.iteration_expression_right);
        append(sb, "; ");
        append(sb, op.ident_decl.name);
        append(sb, ifx op.for_flags & .REVERSE then " -= 1) {\n" else " += 1) {\n");
        print_hlsl_stmt(ctx, sb, op.block, indent=indent+1);
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
          print_hlsl_expr(ctx, sb, op.arguments_sorted[0]);
          append(sb, ";\n");
        } else
          compiler_report("Multiple Return Arguments Disallowed in Jai Shaders", make_location(op));
      }
      
      case .PROCEDURE_CALL; {
        add_indents(sb, indent);
        
        pc := cast(*Code_Procedure_Call) node;
        if !pc.resolved_procedure_expression || pc.procedure_expression.kind != .IDENT
          compiler_report("Jai Shader Transpiler: Function Pointers are not supported by Jai Shaders", make_location(pc));
        name := cast(*Code_Ident) pc.procedure_expression;
        if !table_contains(*INBUILT_FUNCTIONS, name.name)
          handle_custom_procedure_call(ctx, sb, xx it);
        print_hlsl_procedure_call(ctx, sb, xx it);
        
        append(sb, ";\n");
      }
      
      // Ignore the using statements in the shader
      case .USING; continue;
      
      case; {
        compiler_report(tprint("The statement of type '%' is not supported in Jai Shaders", it.kind), make_location(it));
      }
    }
  }
}

// Expressions. All expressions are "supported".
// Most of them are not converted to HLSL currently however.
// Will have to add specific things for many of these
// We can't simply print_expression in many of them because a struct literal could be a subexpression
// which has to be converted correctly
print_hlsl_expr :: (using ctx: *Shader_Write_Context, sb: *String_Builder, node: *Code_Node) {
  if node.kind == {
    case .LITERAL; {
      lit := cast(*Code_Literal) node;
      if lit.value_type == .STRUCT {
        if !lit.struct_literal_info.type_expression {
          compiler_report("Unfortunately, we can't easily know enough about types without the explicit name here.", make_location(lit));
          return;
        }
        
        name := cast(*Code_Ident) lit.struct_literal_info.type_expression.type_valued_expression;
        
        append(sb, "(");
        for lit.struct_literal_info.arguments {
          if it_index != 0 append(sb, ", ");
          print_hlsl_expr(ctx, sb, it);
        }
        append(sb, ")");
      } else PP.print_expression(sb, node);
    }

    case .UNARY_OPERATOR; {
      un := cast(*Code_Unary_Operator) node;
      append(sb, operator_string(un.operator_type));
      print_hlsl_expr(ctx, sb, un.subexpression);
    }

    case .BINARY_OPERATOR; {
      bn := cast(*Code_Binary_Operator) node;
      print_hlsl_expr(ctx, sb, bn.left);
      append(sb, operator_string(bn.operator_type));
      print_hlsl_expr(ctx, sb, bn.right);
    }
    
    case .PROCEDURE_CALL; {
      pc := cast(*Code_Procedure_Call) node;
      if !pc.resolved_procedure_expression || pc.procedure_expression.kind != .IDENT
        compiler_report("Jai Shader Transpiler: Function Pointers are not supported by Jai Shaders", make_location(pc));
      
      name := cast(*Code_Ident) pc.procedure_expression;
      if !table_contains(*INBUILT_FUNCTIONS, name.name)
        handle_custom_procedure_call(ctx, sb, xx node);
      print_hlsl_procedure_call(ctx, sb, xx node);
    }
    
    case; PP.print_expression(sb, node);
  }
}


print_hlsl_member_with_typename :: (sb: *String_Builder, thing: *Type_Info_Struct_Member) {
  print_hlsl_type(sb, thing.type);
  append(sb, " ");
  append(sb, thing.name);
}

print_hlsl_type :: (sb: *String_Builder, type: *Type_Info) {
  if type.type == {
    case .INTEGER; {
      inttype := cast(*Type_Info_Integer) type;
      append(sb, ifx inttype.signed then "int" else "uint");
    }
    case .FLOAT; append(sb, ifx type.runtime_size == 64 then "double" else "float");
    case .BOOL; append(sb, "bool");
    case .STRUCT; {
      structtype := cast(*Type_Info_Struct) type;
      append(sb, jai_to_hlsl_type_name(structtype.name));
    }
    case .VOID; append(sb, "void");
    
    case .VARIANT; {
      t := cast(*Type_Info_Variant) type;
      append(sb, t.name);
    }
    
    case; compiler_report(tprint("The type '%' is currently unsupported in Jai Shaders\n", type.type));
  }
}

#scope_file

member_has_note :: (member: *Type_Info_Struct_Member, note: string) -> bool {
  for member.notes if it == note return true;
  return false;
}

member_get_note_suffix :: (member: *Type_Info_Struct_Member, prefix_check: string) -> (string, bool) {
  for member.notes if begins_with(it, prefix_check) {
    ret: string;
    ret.data = it.data + prefix_check.count;
    ret.count = it.count - prefix_check.count;
    return ret, true;
  }
  return "", false;
}

member_get_semantic :: (member: *Type_Info_Struct_Member) -> string {
  for member.notes if begins_with(it, "semantic_") {
    ret: string;
    ret.data = it.data + 9;
    ret.count = it.count - 9;
    return ret;
  }
  return to_upper_copy(member.name);
}

// This is some hardcoding, and is incomplete.
// More types need to be added here
jai_to_hlsl_type_map :: #run -> Table(string, string) {
  ret: Table(string, string);
  table_add(*ret, "s32", "int");
  table_add(*ret, "u32", "uint");
  table_add(*ret, "float32", "float");
  table_add(*ret, "float64", "double");
  table_add(*ret, "Vector2", "float2");
  table_add(*ret, "Vector3", "float3");
  table_add(*ret, "Vector4", "float4");
  table_add(*ret, "IVector2", "int2");
  table_add(*ret, "IVector3", "int3");
  table_add(*ret, "IVector4", "int4");
  table_add(*ret, "UVector2", "uint2");
  table_add(*ret, "UVector3", "uint3");
  table_add(*ret, "UVector4", "uint4");
  table_add(*ret, "BVector2", "bool2");
  table_add(*ret, "BVector3", "bool3");
  table_add(*ret, "BVector4", "bool4");
  table_add(*ret, "Matrix2", "float2x2");
  table_add(*ret, "Matrix3", "float3x3");
  table_add(*ret, "Matrix4", "float4x4");
  return ret;
}
jai_to_hlsl_type_name :: (in: string) -> string {
  val, success := table_find(*jai_to_hlsl_type_map, in);
  return ifx success then val else in;
}


INBUILT_FUNCTIONS_INTERNAL_ARRAY :: string.[
  // TODO: pain
];
// This is an obvious case for a HashSet... but whatever
INBUILT_FUNCTIONS :: #run -> Table(string, bool) {
  fn_str_table: Table(string, bool);
  for INBUILT_FUNCTIONS_INTERNAL_ARRAY table_add(*fn_str_table, it, true);
  return fn_str_table;
}
// END
