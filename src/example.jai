#import "Basic";
#import "Math";

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

my_jai_vertex_shader :: (using in : VertexShader_In, using un : VertexShader_Uniforms) -> VertexShader_Out {
	using out: VertexShader_Out;
	
	gl_Position = projection * Vector4.{ pos.x, pos.y, 0.0, 1.0 };
	adder := Vector4.{ 0.1, 0.1, 0.1, 0.0 };
	if adder.x == {
		case 0.1; color = Vector4.{ a_color.x, a_color.y, a_color.z, 1.0 } + adder;
		case; color = Vector4.{ a_color.x, a_color.y, a_color.z, 1.0 } + adder;
		case 0.2; color = Vector4.{ a_color.x, a_color.y, a_color.z, 1.0 } + (adder / 2);
	}
	
	if 1 == {
		case 1; color = Vector4.{ a_color.x, a_color.y, a_color.z, 1.0 } + adder;
		case 2; color = Vector4.{ a_color.x, a_color.y, a_color.z, 1.0 } + (adder / 2);
		case; color = Vector4.{ a_color.x, a_color.y, a_color.z, 1.0 } + adder;
	}
	
	i := 0;
	while i < 3 {
		i += 1;
	}
	
	for l:1..2 {
	}
	
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
