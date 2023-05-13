get_plugin :: () -> *Metaprogram_Plugin {
  p := New(Metaprogram_Plugin);
  
  p.message = convert_procs;
  p.shutdown = p => { free(p); };
  
  return p;
}

convert_procs :: (p: *Metaprogram_Plugin, message: *Message) {
  if message.kind == {
    case .TYPECHECKED; {
      tc := cast(*Message_Typechecked) message;
      
      for tc.procedure_bodies {
        if proc_has_note(it.expression.header, "vertex_shader") {
          ctx: Shader_Write_Context;
          ctx.main_fn = it.expression;
          ctx.name = it.expression.header.name;
          s := write_vertex_shader(*ctx, it.expression);
          
          if ctx.waiting_functions.count != 0 {
            array_add(*currently_waiting_contexts, ctx);
          } else {
            add_build_string(s, p.workspace);
          }
        }
        if proc_has_note(it.expression.header, "fragment_shader") {
          ctx: Shader_Write_Context;
          ctx.main_fn = it.expression;
          ctx.name = it.expression.header.name;
          
          s := write_fragment_shader(*ctx, it.expression);
          if ctx.waiting_functions.count != 0 {
            array_add(*currently_waiting_contexts, ctx);
          } else {
            add_build_string(s, p.workspace);
          }
        }
        
        // Is this the best way?
        
        converted_code: string; // Cached code so that if multiple shaders depend on the thing,
                                // we wont have to emit it again
        for * waiter: currently_waiting_contexts {
          
          for waiter_fn, waiter_fn_idx: waiter.waiting_functions {
            if waiter_fn.name != it.expression.header.name continue;
            
            // We found a function we were waiting for
            if converted_code.count == 0 {
              fn_builder: String_Builder;
              print_function(waiter, *fn_builder, it.expression.header);
              converted_code = builder_to_string(*fn_builder);
            }
            array_add(*waiter.functions, .{
                    prototype=it.expression.header,
                    name=waiter_fn.name,
                    code=converted_code,
            });
            
            remove waiter_fn;
          }
          
          if waiter.waiting_functions.count == 0 {
            array_free(waiter.waiting_functions);
            
            sb: String_Builder;
            append(*sb, tprint("%_string", waiter.name));
            append(*sb, " :: #string END\n");
            append(*sb, "#version 330 core\n");
            print_in_vars(*sb, waiter.main_fn.header);
            print_uniforms(*sb, waiter.main_fn.header);
            print_out_vars(*sb, waiter.main_fn.header);
            // Output prototypes for "late binding"
            for waiter.functions {
              if it.name != "main" print_prototype(*sb, it.prototype);
            }
            append(*sb, "\n");
            // Output code
            for waiter.functions {
              append(*sb, it.code);
              append(*sb, "\n");
            }
            append(*sb, "\nEND");
            
            add_build_string(builder_to_string(*sb), p.workspace);
            remove waiter;
          }
          
        }
      }
    }
    
    case .COMPLETE; {
      if currently_waiting_contexts.count != 0 {
        compiler_report("Something went wrong while converting Jai Shaders to shader code");
      }
      array_free(currently_waiting_contexts);
    }
  }
}

// Here are some functions that glsl supports
// Unfortunately this is going to mean that you have to import this module in the places where
// you want to use these functions.
#scope_export

radians :: inline (degrees: float) -> float {
  return degrees * xx (3.1415926535/ 180);
}

degrees :: inline (radians: float) -> float {
  return radians * xx (180 / 3.1415926535);
}

exp2 :: inline (x: float) -> float {
  return xx pow(2, x);
}

fma :: inline (a: $T, b: T, c: T) -> T
#modify { return T == float || T == float64; }
{
  return a * b + c;
}

fract :: inline (x: $T) -> T
#modify { return T == float || T == float64; }
{
  return x - floor(x);
}

inversesqrt :: inline (x: $T) -> T
#modify { return T == float || T == float64; }
{
  return 1 / sqrt(x);
}

log2 :: inline (x: $T) -> T
#modify { return T == float || T == float64; }
{
  return log(x) / log(2);
}

mix :: (x: $T, y: T, t: $M) -> T #expand
#modify { return M == float || M == float64 || M == bool; }
{
  return lerp(x, y, xx t);
}

mod :: inline (x: $T, y: T) -> T
#modify { return T == float || T == float64; }
{
  return x - y * floor(x / y);
}


round :: (x: $T) -> T
#modify { return T == float || T == float64; }
{
  if x - floor(x) > 0.5 return ceil(x);
  else return floor(x);
}

roundEven :: (x: $T) -> T
#modify { return T == float || T == float64; }
{
  pivot := x - floor(x);
  if pivot > 0.5 return ceil(x);
  else if pivot < 0.5 return floor(x);
  else return ifx is_even(ceil(x)) then ceil(x) else floor(x);
}

sign :: (x: $T) -> T
#modify { return is_number(T); }
{
  if x == 0 return 0;
  return ifx x < 0 then -1 else 1;
}

smoothstep :: inline (edge0: $T, edge1: T, x: T) -> T
#modify { return T == float || T == float64; }
{
  t := clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

step :: (x: $T, pivot: T) -> T
#modify { return T == float || T == float64; }
{
  return ifx x < pivot then 0 else 1;
}

trunc :: floor;

faceforward :: inline (N: $T, I: T, Nref: T) -> T
#modify { return T == Vector2 || T == Vector3 || T == Vector4; }
{
  return ifx dot(Nref, I) < 0 then N else -N;
}

normalize :: inline (v: $T) -> T
#modify { return T == Vector2 || T == Vector3 || T == Vector4; }
{
  return v / length(v);
}

reflect :: (I: $T, N: T) -> T
#modify { return T == Vector2 || T == Vector3 || T == Vector4; }
{
  return I - 2 * dot(N, I) * N;
}

refract :: (I: $T, N: T, eta: float) -> T
#modify { return T == Vector2 || T == Vector3 || T == Vector4; }
{
  k := 1.0 - eta * eta * (1.0 - dot(N, I) * dot(N, I));
  if (k < 0.0)
      return .{};
  else
      return eta * I - (eta * dot(N, I) + sqrt(k)) * N;
}

#scope_file

is_number :: (T: Type) -> bool {
  return T == float ||
         T == float64 ||
         T == int ||
         T == s8  ||
         T == s16 ||
         T == s32 ||
         T == s64 ||
         T == u8  ||
         T == u16 ||
         T == u32 ||
         T == u64;
}

INBUILT_FUNCTIONS_INTERNAL_ARRAY :: string.[
  "sin", "cos", "tan", "asin", "acos", "atan",
  "degrees", "radians",
  
  "abs", "ceil", "exp", "exp2", "floor", "isinf", "isnan", "log", "log2", "max", "min",
  "mix", "mod", "pow", "round", "roundEven", "sign", "smoothstep", "sqrt", "step", "trunc",
  
  "cross", "distance", "dot", "faceforward", "length", "normalize", 
  
  // These don't exist in jai yet and I have no idea how to implement them efficiently :P
  // "sinh", "cosh", "tanh", "asinh", "acosh", "atanh",
  // "dFdx", "dFdy", "fwidth", "noise1", "noise2", "noise3", "noise4",
  
  // These require higher glsl versions than 3.3 which is hardcoded for now
  // "fma",
  
  // These require "out" parameters, which haven't been implemented yet
  // "modf"

  // These require adding vectors of different base types, which haven't been implemented yet
  // "equal", "notEqual"
];
// This is an obvious case for a HashSet... but whatever
INBUILT_FUNCTIONS :: #run -> Table(string, bool) {
  fn_str_table: Table(string, bool);
  for INBUILT_FUNCTIONS_INTERNAL_ARRAY table_add(*fn_str_table, it, true);
  return fn_str_table;
}
// END

#scope_file


proc_has_note :: (node : *Code_Procedure_Header, note : string) -> bool #expand {
  for node.notes if it.text == note return true;
  return false;
}


// Short explanation...
// Every function is dumped to a separate string, which the Shader_Write_Context holds a list of
// The functions are appended onto the functions list, and then the for loop runs to push onto
//  the main builder
write_vertex_shader :: (ctx: *Shader_Write_Context, node : *Code_Procedure_Body) -> string {
  print("Converting Vertex Shader: %\n", node.header.name);
  
  if node.header.returns.count != 1
    compiler_report("Jai Vertex Shader must return a structure with at least a Vector4 gl_Position field");
  if node.header.arguments.count != 2
    compiler_report("Jai Vertex Shader must get two structures as arguments (Vertex Input and Uniforms)");
  if node.header.parameter_usings.count != 2
    compiler_report("The struct arguments to a Jai Vertex Shader must be marked 'using'");
  
  // main function string builder
  main_sb: String_Builder;
  append(*main_sb, "void main() {\n");
  print_stmt_glslstyle(ctx, *main_sb, node.block, is_main=true);
  append(*main_sb, "}\n");
  array_add(*ctx.functions, .{ prototype=node.header, name="main", code=builder_to_string(*main_sb) });
  
  if ctx.waiting_functions.count return "";

  // full vertex shader string builder
  sb: String_Builder;
  append(*sb, tprint("%_string", node.header.name));
  append(*sb, " :: #string END\n");  
  append(*sb, "#version 330 core\n");
  print_in_vars(*sb, node.header);
  print_uniforms(*sb, node.header);
  print_out_vars(*sb, node.header);
  // Output prototypes for "late binding"
  for ctx.functions {
    if it.name != "main" print_prototype(*sb, it.prototype);
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

write_fragment_shader :: (ctx: *Shader_Write_Context, node : *Code_Procedure_Body) -> string {
  print("Converting Fragment Shader: %\n", node.header.name);
  
  if node.header.returns.count != 1
    compiler_report("Jai Fragment Shader must return a structure with at least one Vector4");
  if node.header.arguments.count != 2
    compiler_report("Jai Fragment Shader must get two structures as arguments (Vertex output and Uniforms)");
  if node.header.parameter_usings.count != 2
    compiler_report("The struct arguments to a Jai Fragment Shader must be marked 'using'");
  
  // main function string builder
  main_sb: String_Builder;
  append(*main_sb, "void main() {\n");
  print_stmt_glslstyle(ctx, *main_sb, node.block, is_main=true);
  append(*main_sb, "}\n");
  array_add(*ctx.functions, .{ prototype=node.header, name="main", code=builder_to_string(*main_sb) });

  if ctx.waiting_functions.count return "";
  
  // full fragment shader string builder
  sb: String_Builder;
  append(*sb, tprint("%_string", node.header.name));
  append(*sb, " :: #string END\n");
  append(*sb, "#version 330 core\n");
  print_in_vars(*sb, node.header);
  print_uniforms(*sb, node.header);
  print_out_vars(*sb, node.header);
  // Output prototypes for "late binding"
  for ctx.functions {
    if it.name != "main" print_prototype(*sb, it.prototype);
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

//~ Misc Helpers

add_indents :: (sb : *String_Builder, indent : s64) #expand {
  for i: 0..indent*4 append(sb, " ");
}

// The big boy, statement converter
print_stmt_glslstyle :: (using ctx: *Shader_Write_Context, sb: *String_Builder,
                         node: *Code_Block, is_main := false, indent := 1) {
  for node.statements {
    if it.kind == {
      case .DECLARATION; {
        add_indents(sb, indent);
        
        op := cast(*Code_Declaration) it;
        
        if op.type_inst
          print_type(sb, op.type_inst.result);
        else
          print_type(sb, op.expression.type);
        
        append(sb, " ");
        append(sb, op.name);
        if op.expression {
          append(sb, " = ");
          print_expr_glslstyle(ctx, sb, op.expression);
        }
        append(sb, ";\n");
      }
      
      case .BINARY_OPERATOR; {
        add_indents(sb, indent);
        op := cast(*Code_Binary_Operator) it;
        
        print_expr_glslstyle(ctx, sb, op.left);
        append(sb, operator_string(op.operator_type));
        print_expr_glslstyle(ctx, sb, op.right);
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
            print_expr_glslstyle(ctx, sb, op.condition);
            append(sb, ") {\n");
            print_stmt_glslstyle(ctx, sb, op.then_block, indent=indent+1);
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
              print_expr_glslstyle(ctx, sb, op.condition);
              append(sb, " == ");
              print_expr_glslstyle(ctx, sb, curr_case.condition);
              append(sb, ") {\n");
              print_stmt_glslstyle(ctx, sb, curr_case.then_block, indent=indent+1);
              add_indents(sb, indent);
              
              if (curr == op.then_block.statements.count-1) && (default_case == null)
                append(sb, "}\n");
              else append(sb, "} else ");
              
              curr += 1;
            }
            if default_case {
              append(sb, "{\n");
              print_stmt_glslstyle(ctx, sb, default_case.then_block, indent=indent+1);
              add_indents(sb, indent);
              append(sb, "}\n");
            }
          }
        } else {
          append(sb, "if (");
          print_expr_glslstyle(ctx, sb, op.condition);
          append(sb, ") {\n");
          print_stmt_glslstyle(ctx, sb, op.then_block, indent=indent+1);
          add_indents(sb, indent);
          append(sb, "}\n");
          if op.else_block {
            append(sb, " else {\n");
            print_stmt_glslstyle(ctx, sb, op.else_block, indent=indent+1);
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
          print_expr_glslstyle(ctx, sb, op.condition);
          append(sb, ": {\n");
        } else {
          append(sb, "default: {\n");
        }
        print_stmt_glslstyle(ctx, sb, op.then_block, indent=indent+1);
        add_indents(sb, indent);
        append(sb, ifx op.marked_as_fallthrough then "}" else "} break;\n");
      }
      
      case .WHILE; {
        add_indents(sb, indent);
        op := cast(*Code_While) it;
        append(sb, "while (");
        print_expr_glslstyle(ctx, sb, op.condition);
        append(sb, ") {\n");
        print_stmt_glslstyle(ctx, sb, op.block, indent=indent+1);
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
        print_expr_glslstyle(ctx, sb, op.iteration_expression);
        append(sb, "; ");
        append(sb, op.ident_decl.name);
        append(sb, ifx op.for_flags & .REVERSE then " > " else " < ");
        print_expr_glslstyle(ctx, sb, op.iteration_expression_right);
        append(sb, "; ");
        append(sb, op.ident_decl.name);
        append(sb, ifx op.for_flags & .REVERSE then " -= 1) {\n" else " += 1) {\n");
        print_stmt_glslstyle(ctx, sb, op.block, indent=indent+1);
        add_indents(sb, indent);
        append(sb, "}\n");
      }
      
      // TODO(voxel): STRUCTS
      case .RETURN; {
        if is_main continue;
        add_indents(sb, indent);
        op := cast(*Code_Return) it;
        append(sb, "return ");
        if op.arguments_sorted.count == 0 {
          append(sb, ";\n");
        } else if op.arguments_sorted.count == 1 {
          print_expr_glslstyle(ctx, sb, op.arguments_sorted[0]);
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

print_type :: (sb : *String_Builder, type: *Type_Info) {
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
    
    // TODO(voxel): Arrays
    
    case; compiler_report(tprint("The type '%' is currently unsupported in Jai Shaders\n", type.type));
  }
}

// In, out and Uniforms

print_in_vars :: (sb : *String_Builder, node : *Code_Procedure_Header) {
  struct_type_generic := node.arguments[0].type_inst.result;
  if struct_type_generic.type != .STRUCT
    compiler_report(tprint("Shader Input is not a struct, but is a %\n", struct_type_generic.type));
  struct_type := cast(*Type_Info_Struct) struct_type_generic;
  
  for struct_type.members {
    if begins_with(it.name, "gl_") continue;
    
    append(sb, tprint("layout (location=%) in ", it_index));
    print_member_with_typename(sb, *it);
    append(sb, ";\n");
  }
  append(sb, "\n");
}

print_out_vars :: (sb : *String_Builder, node : *Code_Procedure_Header) {
  struct_type_generic := node.returns[0].type_inst.result;
  if struct_type_generic.type != .STRUCT
    compiler_report("Shader Output is not a struct\n");
  struct_type := cast(*Type_Info_Struct) struct_type_generic;
  
  for struct_type.members {
    if begins_with(it.name, "gl_") continue;
    
    append(sb, "out ");
    print_member_with_typename(sb, *it);
    append(sb, ";\n");
  }
  append(sb, "\n");
}

print_uniforms :: (sb : *String_Builder, node : *Code_Procedure_Header) {
  struct_type_generic := node.arguments[1].type_inst.result;
  if struct_type_generic.type != .STRUCT
    compiler_report("Shader Input is not a struct\n");
  struct_type := cast(*Type_Info_Struct) struct_type_generic;
  
  for struct_type.members {
    append(sb, "uniform ");
    print_member_with_typename(sb, *it);
    append(sb, ";\n");
  }
  append(sb, "\n");
}

print_member_with_typename :: (sb : *String_Builder, thing : *Type_Info_Struct_Member) {
  print_type(sb, thing.type);
  append(sb, " ");
  append(sb, thing.name);
}

// Expressions. All expressions are "supported".
// Most of them are not converted to GLSL currently however.
// Will have to add specific things for many of these
// We can't simply print_expression in many of them because a struct literal could be a subexpression
// which has to be converted correctly
print_expr_glslstyle :: (using ctx: *Shader_Write_Context, sb : *String_Builder, node : *Code_Node) {
  if node.kind == {

    case .LITERAL; {
      lit := cast(*Code_Literal) node;
      if lit.value_type == .STRUCT {
        name := cast(*Code_Ident) lit.struct_literal_info.type_expression.type_valued_expression;
        append(sb, jai_to_glsl_type_name(name.name));
        
        append(sb, "(");
        for lit.struct_literal_info.arguments {
          if it_index != 0 append(sb, ", ");
          print_expr_glslstyle(ctx, sb, it);
        }
        append(sb, ")");
        
        return;
      } else PP.print_expression(sb, node);
    }

    case .UNARY_OPERATOR; {
      un := cast(*Code_Unary_Operator) node;
      append(sb, operator_string(un.operator_type));
      print_expr_glslstyle(ctx, sb, un.subexpression);
    }

    case .BINARY_OPERATOR; {
      bn := cast(*Code_Binary_Operator) node;
      print_expr_glslstyle(ctx, sb, bn.left);
      append(sb, operator_string(bn.operator_type));
      print_expr_glslstyle(ctx, sb, bn.right);
    }
    
    case .PROCEDURE_CALL; {
      handle_procedure_call(ctx, sb, xx node);
    }
    
    case; PP.print_expression(sb, node);
  }
}

handle_procedure_call :: (ctx: *Shader_Write_Context, sb: *String_Builder, pc: *Code_Procedure_Call) {
  if !pc.resolved_procedure_expression || pc.procedure_expression.kind != .IDENT
    compiler_report("Function Pointers are not supported by Jai Shaders");
  name := cast(*Code_Ident) pc.procedure_expression;
  
  if !table_contains(*INBUILT_FUNCTIONS, name.name) {
    // Make sure we're not writing the function again
    found := false;
    for ctx.functions if it.name == name.name found = true;
    if !found {
    
      called_function := cast(*Code_Procedure_Header) pc.resolved_procedure_expression;
      
      // We can't be sure the function is actually typechecked already.
      // We can just build the code immediately if it is.
      // But otherwise we wait on the function 
      if called_function.body_or_null {
        function_code: String_Builder;
        print_function(ctx, *function_code, called_function);
        
        array_add(*ctx.functions, .{
                      prototype=called_function,
                      name=name.name,
                      code=builder_to_string(*function_code),
        });
      } else { // called_function.body_or_null
        // We need to wait on this function
        array_add(*ctx.waiting_functions, .{
                      prototype=called_function,
                      name=name.name,
                      code="",
        });
      }
    } // !found
  }
  PP.print_expression(sb, pc.procedure_expression);
  append(sb, "(");
  for pc.arguments_sorted {
    print_expr_glslstyle(ctx, sb, it);
  }
  append(sb, ")");
}

print_function :: (ctx: *Shader_Write_Context, sb: *String_Builder, fn: Code_Procedure_Header) {
  if fn.returns.count != 0 {
    ret := fn.returns[0];
    if ret.type_inst
      print_type(sb, ret.type_inst.result);
    else
      print_type(sb, ret.expression.type);
  } else {
    append(sb, "void");
  }
  
  append(sb, tprint(" %(", fn.name));
  for fn.arguments {
    if it.type_inst
      print_type(sb, it.type_inst.result);
    else
      print_type(sb, it.expression.type);
    
    append(sb, " ");
    append(sb, it.name);
    
    if it_index != fn.arguments.count-1 append(sb, ", ");
  }
  append(sb, ") {\n");
  print_stmt_glslstyle(ctx, sb, fn.body_or_null.block);
  append(sb, "}\n");
}

print_prototype :: (sb: *String_Builder, header: *Code_Procedure_Header) {
  if header.returns.count != 0 {
    ret := header.returns[0];
    if ret.type_inst
      print_type(sb, ret.type_inst.result);
    else
      print_type(sb, ret.expression.type);
  } else {
    append(sb, "void");
  }
  
  append(sb, tprint(" %(", header.name));
  for header.arguments {
    if it.type_inst
      print_type(sb, it.type_inst.result);
    else
      print_type(sb, it.expression.type);
    
    append(sb, " ");
    append(sb, it.name);
    
    if it_index != header.arguments.count-1 append(sb, ", ");
  }
  append(sb, ");\n");
}

// This is some hardcoding, and is incomplete.
// More types need to be added here
jai_to_glsl_type_name :: (in : string) -> string {
  if      in == "Vector4" return "vec4";
  else if in == "Vector3" return "vec3";
  else if in == "Vector2" return "vec2";
  
  else if in == "Matrix4" return "mat4";
  else if in == "Matrix3" return "mat3";
  else if in == "Matrix2" return "mat2";
  
  else if in == "float64" return "double";
  else if in == "s32" return "int";
  
  else return in;
}


// @whatthefuckisthis im 99% sure there's a simpler way of converting an int to a string directly.
// or atleast printing it as a character, because the first switch is.... yikes
operator_string :: (op : s32) -> string {
  if op == {
    case #char "="; return "=";
    case #char "<"; return "<";
    case #char "?"; return "?";
    case #char ">"; return ">";
    case #char "!"; return "!";
    case #char "+"; return "+";
    case #char "-"; return "-";
    case #char "*"; return "*";
    case #char "/"; return "/";
    case #char "%"; return "%";
    case #char "~"; return "~";
    case #char "."; return ".";
  }
  if cast(Operator_Type)op == {
    case .PLUS_EQUALS; return "+=";
    case .MINUS_EQUALS; return "-=";
    case .TIMES_EQUALS; return "*=";
    case .DIV_EQUALS; return "/=";
    case .MOD_EQUALS; return "%=";
    case .IS_EQUAL; return "==";
    case .IS_NOT_EQUAL; return "!=";
    case .LOGICAL_AND; return "&&";
    case .LOGICAL_OR; return "||";
    case .LESS_EQUALS; return "<=";
    case .GREATER_EQUALS; return ">=";
    
    case .SHIFT_LEFT; return "<<";
    case .SHIFT_RIGHT; return ">>";
    
    // I don't think operators below this are supported in glsl
    // But this can stay just incase...
    case .ROTATE_LEFT; return "<<<";
    case .ROTATE_RIGHT; return ">>>";
    case .SHIFT_LEFT_EQUALS; return "<<=";
    case .SHIFT_RIGHT_EQUALS; return ">>=";
    case .ROTATE_LEFT_EQUALS; return "<<<=";
    case .ROTATE_RIGHT_EQUALS; return ">>>=";
    case .BITWISE_AND_EQUALS; return "&=";
    case .BITWISE_OR_EQUALS; return "|=";
    case .BITWISE_XOR_EQUALS; return "^=";
    case .LOGICAL_AND_EQUALS; return "&&=";
    case .LOGICAL_OR_EQUALS; return "||=";
    
    //case ARRAY_SUBSCRIPT; return "[]";
    
    case; return "<operator_not_supported>";
  }
}

//~

Shader_Function :: struct {
  prototype: *Code_Procedure_Header;
  name: string; // @Cleanup This doesn't have to be here
  code: string;
}

Shader_Write_Context :: struct {
  name: string;
  main_fn: *Code_Procedure_Body;
  functions: [..] Shader_Function;
  waiting_functions: [..] Shader_Function;
}

// Outputting Shader string can't just happen all at one time because functions might not have come \
// through Message_Typechecked that were called.
// This means that the writing has to be deferred somehow
currently_waiting_contexts: [..] Shader_Write_Context;

#import "Basic";
#import "Compiler";
PP :: #import "Program_Print";
#import "String";
#import "Math";
#import "Hash_Table";
