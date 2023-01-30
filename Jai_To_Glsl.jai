get_plugin :: () -> *Metaprogram_Plugin {
	p := New(Metaprogram_Plugin);
	
	p.message = receive_message;
	p.shutdown = p => { free(p); };
	
	return p;
}

receive_message :: (p: *Metaprogram_Plugin, message: *Message) {
	if message.kind == {
		case .TYPECHECKED; {
			tc := cast(*Message_Typechecked) message;
			for tc.procedure_bodies {
				if proc_has_note(it.expression.header, "vertex_shader") {
					s := write_vertex_shader(it.expression);
					add_build_string(s, p.workspace);
				}
				if proc_has_note(it.expression.header, "fragment_shader") {
					s := write_fragment_shader(it.expression);
					add_build_string(s, p.workspace);
				}
			}
		}
	}
}

#scope_file

#import "Basic";
#import "Compiler";
#import "Program_Print";
#import "String";
#import "Hash_Table";

proc_has_note :: (node : *Code_Procedure_Header, note : string) -> bool #expand {
	for node.notes if it.text == note return true;
	return false;
}


write_vertex_shader :: (node : *Code_Procedure_Body) -> string {
	sb : String_Builder;
	print("Converting Vertex Shader: %\n", node.header.name);
	
	if node.header.returns.count != 1
		compiler_report("Jai Vertex Shader must return a structure with at least a Vector4 gl_Position field");
	if node.header.arguments.count != 2
		compiler_report("Jai Vertex Shader must get two structures as arguments (Vertex Input and Uniforms)");
	if node.header.parameter_usings.count != 2
		compiler_report("The struct arguments to a Jai Vertex Shader must be marked 'using'");
	
	append(*sb, tprint("%_string", node.header.name));
	append(*sb, " :: #string END\n");
	append(*sb, "#version 330 core\n");
	
	print_in_vars(*sb, node.header);
	print_uniforms(*sb, node.header);
	print_out_vars(*sb, node.header);
	
	append(*sb, "\nvoid main() {\n");
	print_stmt_glslstyle(*sb, node.block);
	append(*sb, "}\nEND");
	
	return builder_to_string(*sb);
}

write_fragment_shader :: (node : *Code_Procedure_Body) -> string {
	sb : String_Builder;
	
	print("Converting Fragment Shader: %\n", node.header.name);
	
	if node.header.returns.count != 1
		compiler_report("Jai Fragment Shader must return a structure with at least one Vector4");
	if node.header.arguments.count != 2
		compiler_report("Jai Fragment Shader must get two structures as arguments (Vertex output and Uniforms)");
	if node.header.parameter_usings.count != 2
		compiler_report("The struct arguments to a Jai Fragment Shader must be marked 'using'");
	
	append(*sb, tprint("%_string", node.header.name));
	append(*sb, " :: #string END\n");
	append(*sb, "#version 330 core\n");
	
	print_in_vars(*sb, node.header);
	print_uniforms(*sb, node.header);
	print_out_vars(*sb, node.header);
	
	append(*sb, "\nvoid main() {\n");
	print_stmt_glslstyle(*sb, node.block);
	append(*sb, "}\nEND");
	
	return builder_to_string(*sb);
}

//~ Misc Helpers

add_indents :: (sb : *String_Builder, indent : s64) #expand {
	for i: 0..indent*4 append(sb, " ");
}

// The big boy, statement converter
print_stmt_glslstyle :: (sb : *String_Builder, node : *Code_Block, indent := 1) {
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
					print_expr_glslstyle(sb, op.expression);
				}
				append(sb, ";\n");
			}
			
			case .BINARY_OPERATOR; {
				add_indents(sb, indent);
				op := cast(*Code_Binary_Operator) it;
				
				print_expr_glslstyle(sb, op.left);
				append(sb, operator_string(op.operator_type));
				print_expr_glslstyle(sb, op.right);
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
						print_expr_glslstyle(sb, op.condition);
						append(sb, ") {\n");
						print_stmt_glslstyle(sb, op.then_block, indent + 1);
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
							print_expr_glslstyle(sb, op.condition);
							append(sb, " == ");
							print_expr_glslstyle(sb, curr_case.condition);
							append(sb, ") {\n");
							print_stmt_glslstyle(sb, curr_case.then_block, indent + 1);
							add_indents(sb, indent);
							
							if (curr == op.then_block.statements.count-1) && (default_case == null)
								append(sb, "}\n");
							else append(sb, "} else ");
							
							curr += 1;
						}
						if default_case {
							append(sb, "{\n");
							print_stmt_glslstyle(sb, default_case.then_block, indent + 1);
							add_indents(sb, indent);
							append(sb, "}\n");
						}
					}
				} else {
					append(sb, "if (");
					print_expr_glslstyle(sb, op.condition);
					append(sb, ") {\n");
					print_stmt_glslstyle(sb, op.then_block, indent + 1);
					add_indents(sb, indent);
					append(sb, "}\n");
					if op.else_block {
						append(sb, " else {\n");
						print_stmt_glslstyle(sb, op.else_block, indent + 1);
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
					print_expr_glslstyle(sb, op.condition);
					append(sb, ": {\n");
				} else {
					append(sb, "default: {\n");
				}
				print_stmt_glslstyle(sb, op.then_block, indent + 1);
				add_indents(sb, indent);
				append(sb, ifx op.marked_as_fallthrough then "}" else "} break;\n");
			}
			
			case .WHILE; {
				add_indents(sb, indent);
				op := cast(*Code_While) it;
				append(sb, "while (");
				print_expr_glslstyle(sb, op.condition);
				append(sb, ") {\n");
				print_stmt_glslstyle(sb, op.block, indent + 1);
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
				print_expr_glslstyle(sb, op.iteration_expression);
				append(sb, "; ");
				append(sb, op.ident_decl.name);
				append(sb, ifx op.for_flags & .REVERSE then " > " else " < ");
				print_expr_glslstyle(sb, op.iteration_expression_right);
				append(sb, "; ");
				append(sb, op.ident_decl.name);
				append(sb, ifx op.for_flags & .REVERSE then " -= 1) {\n" else " += 1) {\n");
				print_stmt_glslstyle(sb, op.block, indent + 1);
				add_indents(sb, indent);
				append(sb, "}\n");
			}
			
			// TODO(voxel): FUNCTIONS, RETURNS, STRUCTS
			// This may need a slight rework of the overall structure unfortunately.
			
			// Ignore the return and using statements in the shader for now
			case .RETURN; continue;
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
		compiler_report("Shader Input is not a struct\n");
	struct_type := cast(*Type_Info_Struct) struct_type_generic;
	
	for struct_type.members {
		if begins_with(it.name, "gl_") continue;
		
		append(sb, tprint("layout (location=%) in ", it_index));
		print_member_with_typename(sb, *it);
		append(sb, ";\n");
	}
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
print_expr_glslstyle :: (sb : *String_Builder, node : *Code_Node) {
	if node.kind == .LITERAL {
		lit := cast(*Code_Literal) node;
		if lit.value_type == .STRUCT {
			name := cast(*Code_Ident) lit.struct_literal_info.type_expression.type_valued_expression;
			append(sb, jai_to_glsl_type_name(name.name));
			
			append(sb, "(");
			for lit.struct_literal_info.arguments {
				if it_index != 0 append(sb, ", ");
				print_expr_glslstyle(sb, it);
			}
			append(sb, ")");
			
			return;
		} else print_expression(sb, node);
		
	} else if node.kind == .UNARY_OPERATOR {
		un := cast(*Code_Unary_Operator) node;
		append(sb, operator_string(un.operator_type));
		print_expr_glslstyle(sb, un.subexpression);
	} else if node.kind == .BINARY_OPERATOR {
		bn := cast(*Code_Binary_Operator) node;
		print_expr_glslstyle(sb, bn.left);
		append(sb, operator_string(bn.operator_type));
		print_expr_glslstyle(sb, bn.right);
	} else print_expression(sb, node);
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
