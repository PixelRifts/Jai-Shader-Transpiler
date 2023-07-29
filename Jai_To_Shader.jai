// TODOS:
// Add the different types of Vectors and implement the 'Component Comparison' set of GLSL functions
// Translation for more advanced jai features
// Add the differet types of Samplers
// Add support for out parameters
// Add support for structs and arrays
// Add support for Geometry and Compute Shaders

// Think about:
// Changing GLSL version without changing module code.


#load "glsl_backend.jai";
#load "hlsl_backend.jai";

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

        // Has a GLSL Note
        if proc_has_note(it.expression.header, "glsl") {
          ctx: Shader_Write_Context;
          ctx.main_fn = it.expression;
          ctx.language = .GLSL;
          ctx.name = it.expression.header.name;
          ctx.type = .Vertex;
          s: string;
          if proc_has_note(it.expression.header, "vertex_shader") {
            s = write_vertex_shader(*ctx, it.expression);
          } else if proc_has_note(it.expression.header, "fragment_shader") {
            s = write_fragment_shader(*ctx, it.expression);
          } else {
            compiler_report("Jai Shader Transpiler: No Shader type tag found. Use @vertex_shader or @fragment_shader",
                            make_location(it.expression.header));
          }
          
          if ctx.waiting_functions.count != 0 {
            array_add(*currently_waiting_contexts, ctx);
          } else {
            add_build_string(s, p.workspace);
          }
        }
        
        // Has a HLSL Note
        if proc_has_note(it.expression.header, "hlsl") {
          ctx: Shader_Write_Context;
          ctx.main_fn = it.expression;
          ctx.language = .HLSL;
          ctx.name = it.expression.header.name;
          ctx.type = .Vertex;
          s: string;
          if proc_has_note(it.expression.header, "vertex_shader") {
            s = write_vertex_shader(*ctx, it.expression);
          } else if proc_has_note(it.expression.header, "fragment_shader") {
            s = write_fragment_shader(*ctx, it.expression);
          } else {
            compiler_report("Jai Shader Transpiler: No Shader type tag found. Use @vertex_shader or @fragment_shader",
                            make_location(it.expression.header));
          }
          
          if ctx.waiting_functions.count != 0 {
            array_add(*currently_waiting_contexts, ctx);
          } else {
            add_build_string(s, p.workspace);
          }
        }

        // Has neither GLSL nor HLSL Notes, but has a vertex_shader or fragment_shader note
        if !(proc_has_note(it.expression.header, "glsl") || proc_has_note(it.expression.header, "hlsl")) {
          if proc_has_note(it.expression.header, "vertex_shader") ||
             proc_has_note(it.expression.header, "fragment_shader") {
            compiler_report("Jai Shader Transpiler: No Tag that maps to a language. Add @glsl or @hlsl to specify the language",
                            make_location(it.expression.header));
          }
        }

        
        // Is this the best way? I guess so.
        // This is checking whether any function we're waiting on got typechecked or not.
        
        converted_code: string; // Cached code so that if multiple shaders depend on the thing,
                                // we wont have to emit it again
        for * waiter: currently_waiting_contexts {
          for waiter_fn, waiter_fn_idx: waiter.waiting_functions {
            if waiter_fn.name != it.expression.header.name continue;
            
            // We found a function we were waiting for
            if converted_code.count == 0 {
              fn_builder: String_Builder;
              write_function(waiter, *fn_builder, it.expression.header);
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
            
            final_code := write_shader_code(waiter, waiter.main_fn);
            add_build_string(final_code, p.workspace);
            remove waiter;
          }
          
        }
      }
    }
    
    case .COMPLETE; {
      if currently_waiting_contexts.count != 0 {
        compiler_report("Jai Shader Transpiler: Something went wrong while converting Jai Shaders to shader code.\nThere's some functions that have not yet been transpiled, that a shader is waiting on. This is not good.");
      }
      array_free(currently_waiting_contexts);
    }
  }
}

//~
// Here are some functions that glsl supports
// Unfortunately this is going to mean that you have to import this module in the places where
// you want to use these functions.
#scope_export

floor :: inline (v: Vector2) -> Vector2 { return Vector2.{ floor(v.x), floor(v.y) }; }
floor :: inline (v: Vector3) -> Vector3 { return Vector3.{ floor(v.x), floor(v.y), floor(v.z) }; }
floor :: inline (v: Vector4) -> Vector4 { return Vector4.{ floor(v.x), floor(v.y), floor(v.z), floor(v.w) }; }


radians :: inline (degrees: float) -> float {
  return degrees * xx (3.1415926535/ 180);
}
radians :: inline (v: Vector2) -> Vector2 { return Vector2.{ radians(v.x), radians(v.y) }; }
radians :: inline (v: Vector3) -> Vector3 { return Vector3.{ radians(v.x), radians(v.y), radians(v.z) }; }
radians :: inline (v: Vector4) -> Vector4 { return Vector4.{ radians(v.x), radians(v.y), radians(v.z), radians(v.w) }; }

degrees :: inline (radians: float) -> float {
  return radians * xx (180 / 3.1415926535);
}
degrees :: inline (v: Vector2) -> Vector2 { return Vector2.{ degrees(v.x), degrees(v.y) }; }
degrees :: inline (v: Vector3) -> Vector3 { return Vector3.{ degrees(v.x), degrees(v.y), degrees(v.z) }; }
degrees :: inline (v: Vector4) -> Vector4 { return Vector4.{ degrees(v.x), degrees(v.y), degrees(v.z), degrees(v.w) }; }

exp2 :: inline (x: float) -> float {
  return xx pow(2, x);
}
exp2 :: inline (v: Vector2) -> Vector2 { return Vector2.{ exp2(v.x), exp2(v.y) }; }
exp2 :: inline (v: Vector3) -> Vector3 { return Vector3.{ exp2(v.x), exp2(v.y), exp2(v.z) }; }
exp2 :: inline (v: Vector4) -> Vector4 { return Vector4.{ exp2(v.x), exp2(v.y), exp2(v.z), exp2(v.w) }; }

fma :: inline (a: $T, b: T, c: T) -> T
#modify { return T == float || T == float64; }
{
  return a * b + c;
}
fma :: inline (a: Vector2, b: Vector2, c: Vector2) -> Vector2 { return Vector2.{ fma(a.x, b.x, c.x), fma(a.y, b.y, c.y) }; }
fma :: inline (a: Vector3, b: Vector3, c: Vector3) -> Vector3 { return Vector3.{ fma(a.x, b.x, c.x), fma(a.y, b.y, c.y), fma(a.z, b.z, c.z) }; }
fma :: inline (a: Vector4, b: Vector4, c: Vector4) -> Vector4 { return Vector4.{ fma(a.x, b.x, c.x), fma(a.y, b.y, c.y), fma(a.z, b.z, c.z), fma(a.w, b.w, c.w) }; }

fract :: inline (x: $T) -> T
#modify { return T == float || T == float64; }
{
  return x - floor(x);
}
fract :: inline (v: Vector2) -> Vector2 { return Vector2.{ fract(v.x), fract(v.y) }; }
fract :: inline (v: Vector3) -> Vector3 { return Vector3.{ fract(v.x), fract(v.y), fract(v.z) }; }
fract :: inline (v: Vector4) -> Vector4 { return Vector4.{ fract(v.x), fract(v.y), fract(v.z), fract(v.w) }; }

inversesqrt :: inline (x: $T) -> T
#modify { return T == float || T == float64; }
{
  return 1 / sqrt(x);
}
inversesqrt :: inline (v: Vector2) -> Vector2 { return Vector2.{ inversesqrt(v.x), inversesqrt(v.y) }; }
inversesqrt :: inline (v: Vector3) -> Vector3 { return Vector3.{ inversesqrt(v.x), inversesqrt(v.y), inversesqrt(v.z) }; }
inversesqrt :: inline (v: Vector4) -> Vector4 { return Vector4.{ inversesqrt(v.x), inversesqrt(v.y), inversesqrt(v.z), inversesqrt(v.w) }; }

log2 :: inline (x: $T) -> T
#modify { return T == float || T == float64; }
{
  return log(x) / log(2);
}
log2 :: inline (v: Vector2) -> Vector2 { return Vector2.{ log2(v.x), log2(v.y) }; }
log2 :: inline (v: Vector3) -> Vector3 { return Vector3.{ log2(v.x), log2(v.y), log2(v.z) }; }
log2 :: inline (v: Vector4) -> Vector4 { return Vector4.{ log2(v.x), log2(v.y), log2(v.z), log2(v.w) }; }

mix :: (x: $T, y: T, t: $M) -> T #expand
#modify { return (T == float || T == float64) && (M == float || M == float64 || M == bool); }
{
  return lerp(x, y, xx t);
}
mix :: inline (a: Vector2, b: Vector2, m: BVector2) -> Vector2 { return Vector2.{ mix(a.x, b.x, m.x), mix(a.y, b.y, m.y) }; }
mix :: inline (a: Vector3, b: Vector3, m: BVector3) -> Vector3 { return Vector3.{ mix(a.x, b.x, m.x), mix(a.y, b.y, m.y), mix(a.z, b.z, m.z) }; }
mix :: inline (a: Vector4, b: Vector4, m: BVector4) -> Vector4 { return Vector4.{ mix(a.x, b.x, m.x), mix(a.y, b.y, m.y), mix(a.z, b.z, m.z), mix(a.w, b.w, m.w) }; }

mod :: inline (x: $T, y: T) -> T
#modify { return T == float || T == float64; }
{
  return x - y * floor(x / y);
}
mod :: inline (a: Vector2, b: Vector2) -> Vector2 { return Vector2.{ mod(a.x, b.x), mod(a.y, b.y) }; }
mod :: inline (a: Vector3, b: Vector3) -> Vector3 { return Vector3.{ mod(a.x, b.x), mod(a.y, b.y), mod(a.z, b.z) }; }
mod :: inline (a: Vector4, b: Vector4) -> Vector4 { return Vector4.{ mod(a.x, b.x), mod(a.y, b.y), mod(a.z, b.z), mod(a.w, b.w) }; }

round :: (x: $T) -> T
#modify { return T == float || T == float64; }
{
  if x - floor(x) > 0.5 return ceil(x);
  else return floor(x);
}
round :: inline (v: Vector2) -> Vector2 { return Vector2.{ round(v.x), round(v.y) }; }
round :: inline (v: Vector3) -> Vector3 { return Vector3.{ round(v.x), round(v.y), round(v.z) }; }
round :: inline (v: Vector4) -> Vector4 { return Vector4.{ round(v.x), round(v.y), round(v.z), round(v.w) }; }

roundEven :: (x: $T) -> T
#modify { return T == float || T == float64; }
{
  pivot := x - floor(x);
  if pivot > 0.5 return ceil(x);
  else if pivot < 0.5 return floor(x);
  else return ifx is_even(ceil(x)) then ceil(x) else floor(x);
}
roundEven :: inline (v: Vector2) -> Vector2 { return Vector2.{ roundEven(v.x), roundEven(v.y) }; }
roundEven :: inline (v: Vector3) -> Vector3 { return Vector3.{ roundEven(v.x), roundEven(v.y), roundEven(v.z) }; }
roundEven :: inline (v: Vector4) -> Vector4 { return Vector4.{ roundEven(v.x), roundEven(v.y), roundEven(v.z), roundEven(v.w) }; }

sign :: (x: $T) -> T
#modify { return is_number(T); }
{
  if x == 0 return 0;
  return ifx x < 0 then -1 else xx 1;
}
sign :: inline (v: $T) -> T #modify { return T == Vector2 || T == IVector2 || T == UVector2; } { return Vector2.{ sign(v.x), sign(v.y) }; }
sign :: inline (v: $T) -> T #modify { return T == Vector3 || T == IVector3 || T == UVector3; } { return Vector3.{ sign(v.x), sign(v.y), sign(v.z) }; }
sign :: inline (v: $T) -> T #modify { return T == Vector4 || T == IVector4 || T == UVector4; } { return Vector4.{ sign(v.x), sign(v.y), sign(v.z), sign(v.w) }; }

smoothstep :: inline (edge0: $T, edge1: T, x: T) -> T
#modify { return T == float || T == float64; }
{
  t := clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}
smoothstep :: inline (a: Vector2, b: Vector2, t: Vector2) -> Vector2 { return Vector2.{ smoothstep(a.x, b.x, t.x), smoothstep(a.y, b.y, t.y) }; }
smoothstep :: inline (a: Vector3, b: Vector3, t: Vector3) -> Vector3 { return Vector3.{ smoothstep(a.x, b.x, t.x), smoothstep(a.y, b.y, t.y), smoothstep(a.z, b.z, t.z) }; }
smoothstep :: inline (a: Vector4, b: Vector4, t: Vector4) -> Vector4 { return Vector4.{ smoothstep(a.x, b.x, t.x), smoothstep(a.y, b.y, t.y), smoothstep(a.z, b.z, t.z), smoothstep(a.w, b.w, t.w) }; }

step :: (x: $T, pivot: T) -> T
#modify { return T == float || T == float64; }
{
  return ifx x < pivot then 0.0 else 1.0;
}
step :: inline (v: Vector2, s: Vector2) -> Vector2 { return Vector2.{ step(v.x, s.x), step(v.y, s.y) }; }
step :: inline (v: Vector3, s: Vector3) -> Vector3 { return Vector3.{ step(v.x, s.x), step(v.y, s.y), step(v.z, s.z) }; }
step :: inline (v: Vector4, s: Vector4) -> Vector4 { return Vector4.{ step(v.x, s.x), step(v.y, s.y), step(v.z, s.z), step(v.w, s.w) }; }

trunc :: inline (x: $T) -> T #modify { return T == float || T == float64; } { return floor(x); };
trunc :: inline (v: Vector2) -> Vector2 { return Vector2.{ trunc(v.x), trunc(v.y) }; }
trunc :: inline (v: Vector3) -> Vector3 { return Vector3.{ trunc(v.x), trunc(v.y), trunc(v.z) }; }
trunc :: inline (v: Vector4) -> Vector4 { return Vector4.{ trunc(v.x), trunc(v.y), trunc(v.z), trunc(v.w) }; }

equal :: inline (a: $T, b: T) -> BVector2 #modify { return T == Vector2 || T == IVector2 || T == UVector2; } { return BVector2.{ a.x == b.x, a.y == b.y }; }
equal :: inline (a: $T, b: T) -> BVector3 #modify { return T == Vector3 || T == IVector3 || T == UVector3; } { return BVector3.{ a.x == b.x, a.y == b.y, a.z == b.z }; }
equal :: inline (a: $T, b: T) -> BVector4 #modify { return T == Vector4 || T == IVector4 || T == UVector4; } { return BVector4.{ a.x == b.x, a.y == b.y, a.z == b.z, a.w == b.w }; }

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

notEqual :: inline (a: $T, b: T) -> BVector2 #modify { return T == Vector2 || T == IVector2 || T == UVector2; } { return BVector2.{ a.x != b.x, a.y != b.y }; }
notEqual :: inline (a: $T, b: T) -> BVector3 #modify { return T == Vector3 || T == IVector3 || T == UVector3; } { return BVector3.{ a.x != b.x, a.y != b.y, a.z != b.z }; }
notEqual :: inline (a: $T, b: T) -> BVector4 #modify { return T == Vector4 || T == IVector4 || T == UVector4; } { return BVector4.{ a.x != b.x, a.y != b.y, a.z != b.z, a.w != b.w }; }

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

all :: inline (v: BVector2) -> bool { return v.x && v.y; }
all :: inline (v: BVector3) -> bool { return v.x && v.y && v.z; }
all :: inline (v: BVector4) -> bool { return v.x && v.y && v.z && v.w; }
any :: inline (v: BVector2) -> bool { return v.x || v.y; }
any :: inline (v: BVector3) -> bool { return v.x || v.y || v.z; }
any :: inline (v: BVector4) -> bool { return v.x || v.y || v.z || v.w; }
greaterThan :: inline (a: $T, b: T) -> BVector2 #modify { return T == Vector2 || T == IVector2 || T == UVector2; } { return BVector2.{ a.x > b.x, a.y > b.y }; }
greaterThan :: inline (a: $T, b: T) -> BVector3 #modify { return T == Vector3 || T == IVector3 || T == UVector3; } { return BVector3.{ a.x > b.x, a.y > b.y, a.z > b.z }; }
greaterThan :: inline (a: $T, b: T) -> BVector4 #modify { return T == Vector4 || T == IVector4 || T == UVector4; } { return BVector3.{ a.x > b.x, a.y > b.y, a.z > b.z, a.w > b.w }; }
greaterThanEqual :: inline (a: $T, b: T) -> BVector2 #modify { return T == Vector2 || T == IVector2 || T == UVector2; } { return BVector2.{ a.x >= b.x, a.y >= b.y }; }
greaterThanEqual :: inline (a: $T, b: T) -> BVector3 #modify { return T == Vector3 || T == IVector3 || T == UVector3; } { return BVector3.{ a.x >= b.x, a.y >= b.y, a.z >= b.z }; }
greaterThanEqual :: inline (a: $T, b: T) -> BVector4 #modify { return T == Vector4 || T == IVector4 || T == UVector4; } { return BVector3.{ a.x >= b.x, a.y >= b.y, a.z >= b.z, a.w >= b.w }; }
lessThan :: inline (a: $T, b: T) -> BVector2 #modify { return T == Vector2 || T == IVector2 || T == UVector2; } { return BVector2.{ a.x < b.x, a.y < b.y }; }
lessThan :: inline (a: $T, b: T) -> BVector3 #modify { return T == Vector3 || T == IVector3 || T == UVector3; } { return BVector3.{ a.x < b.x, a.y < b.y, a.z < b.z }; }
lessThan :: inline (a: $T, b: T) -> BVector4 #modify { return T == Vector4 || T == IVector4 || T == UVector4; } { return BVector3.{ a.x < b.x, a.y < b.y, a.z < b.z, a.w < b.w }; }
lessThanEqual :: inline (a: $T, b: T) -> BVector2 #modify { return T == Vector2 || T == IVector2 || T == UVector2; } { return BVector2.{ a.x <= b.x, a.y <= b.y }; }
lessThanEqual :: inline (a: $T, b: T) -> BVector3 #modify { return T == Vector3 || T == IVector3 || T == UVector3; } { return BVector3.{ a.x <= b.x, a.y <= b.y, a.z <= b.z }; }
lessThanEqual :: inline (a: $T, b: T) -> BVector4 #modify { return T == Vector4 || T == IVector4 || T == UVector4; } { return BVector3.{ a.x <= b.x, a.y <= b.y, a.z <= b.z, a.w <= b.w }; }
not :: inline (v: BVector2) -> BVector2 { return BVector2.{ !v.x, !v.y }; }
not :: inline (v: BVector3) -> BVector3 { return BVector3.{ !v.x, !v.y, !v.z }; }
not :: inline (v: BVector4) -> BVector4 { return BVector4.{ !v.x, !v.y, !v.z, !v.w }; }


texture :: (sampler: $T, point: $S, bias: float = 0) -> Vector4
#modify { return (T == Sampler1D && S == float  )
              || (T == Sampler2D && S == Vector2)
              || (T == Sampler3D && S == Vector3); }
{ /* I guess this has to be specific to glsl */ }



//~ Types and Helpers for GLSL


operator * :: (a: Matrix2, b: Vector2) -> Vector2 {
    return inline multiply(a, b);
}


IVector2 :: struct { x, y: s32; }
IVector3 :: struct { x, y, z: s32; }
IVector4 :: struct { x, y, z, w: s32; }
UVector2 :: struct { x, y: u32; }
UVector3 :: struct { x, y, z: u32; }
UVector4 :: struct { x, y, z, w: u32; }
BVector2 :: struct { x, y: bool; }
BVector3 :: struct { x, y, z: bool; }
BVector4 :: struct { x, y, z, w: bool; }

Sampler1D :: #type,distinct s32;
Sampler2D :: #type,distinct s32;
Sampler3D :: #type,distinct s32;


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
is_even :: (v: float) -> bool   { return (cast(s32) floor(v)) % 2 == 0; }
is_even :: (v: float64) -> bool { return (cast(s32) floor(v)) % 2 == 0; }

INBUILT_FUNCTIONS_INTERNAL_ARRAY :: string.[
  "sin", "cos", "tan", "asin", "acos", "atan",
  "degrees", "radians",
  
  "abs", "ceil", "exp", "exp2", "floor", "isinf", "isnan", "log", "log2", "max", "min",
  "mix", "mod", "pow", "round", "roundEven", "sign", "smoothstep", "sqrt", "step", "trunc",
  
  "cross", "distance", "dot", "equal", "faceforward", "length", "normalize", "notEqual",
  "all", "any", "greaterThan", "lessThan", "greaterThanEqual", "lessThanEqual", "not",
  
  "texture",
  
  // These don't exist in jai yet and I have no idea how to implement them efficiently :P
  // "sinh", "cosh", "tanh", "asinh", "acosh", "atanh",
  // "dFdx", "dFdy", "fwidth", "noise1", "noise2", "noise3", "noise4",
  
  // These require higher glsl versions than 3.3 which is hardcoded for now
  // "fma",
  // "interpolateAtCentroid", "interpolateAtOffset", "interpolateAtSample",
  
  // These require "out" parameters, which haven't been implemented yet
  // "modf"
];
// This is an obvious case for a HashSet... but whatever
INBUILT_FUNCTIONS :: #run -> Table(string, bool) {
  fn_str_table: Table(string, bool);
  for INBUILT_FUNCTIONS_INTERNAL_ARRAY table_add(*fn_str_table, it, true);
  return fn_str_table;
}
// END

proc_has_note :: (node: *Code_Procedure_Header, note: string) -> bool {
  for node.notes if it.text == note return true;
  return false;
}

#scope_export




write_vertex_shader :: (ctx: *Shader_Write_Context, node: *Code_Procedure_Body) -> string {
  print("Converting Vertex Shader: %\n", node.header.name);
  
  if ctx.language == {
    case .GLSL; return write_glsl_vertex_shader(ctx, node);
    case .HLSL; return write_hlsl_vertex_shader(ctx, node);
  }
  
  return "";
}

write_fragment_shader :: (ctx: *Shader_Write_Context, node: *Code_Procedure_Body) -> string {
  print("Converting Fragment Shader: %\n", node.header.name);
  
  if ctx.language == {
    case .GLSL; return write_glsl_fragment_shader(ctx, node);
    case .HLSL; return write_hlsl_fragment_shader(ctx, node);
  }
  
  return "";
}

write_procedure_call :: (ctx: *Shader_Write_Context, node: *String_Builder, pc: *Code_Procedure_Call) {
  if ctx.language == {
    case .GLSL; print_glsl_procedure_call(ctx, node, pc);
    case .HLSL; print_hlsl_procedure_call(ctx, node, pc);
  }
}

write_function :: (ctx: *Shader_Write_Context, sb: *String_Builder, called_fn: *Code_Procedure_Header) {
  if ctx.language == {
    case .GLSL; print_glsl_function(ctx, sb, called_fn);
    case .HLSL; print_hlsl_function(ctx, sb, called_fn);
  }
}

write_shader_code :: (ctx: *Shader_Write_Context, node: *Code_Procedure_Body) -> string {
  if ctx.language == {
    case .GLSL; return write_glsl_shader_code(ctx, node);
    case .HLSL; return write_hlsl_shader_code(ctx, node);
  }

  return "";
}




// Only function that has to be called from a backend

handle_procedure_call :: (ctx: *Shader_Write_Context, sb: *String_Builder, pc: *Code_Procedure_Call) {
  if !pc.resolved_procedure_expression || pc.procedure_expression.kind != .IDENT
    compiler_report("Jai Shader Transpiler: Function Pointers are not supported by Jai Shaders", make_location(pc));
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
        
        write_function(ctx, *function_code, called_function);
        
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
  write_procedure_call(ctx, sb, pc);
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
    // case .ROTATE_LEFT; return "<<<";
    // case .ROTATE_RIGHT; return ">>>";
    // case .SHIFT_LEFT_EQUALS; return "<<=";
    // case .SHIFT_RIGHT_EQUALS; return ">>=";
    // case .ROTATE_LEFT_EQUALS; return "<<<=";
    // case .ROTATE_RIGHT_EQUALS; return ">>>=";
    // case .BITWISE_AND_EQUALS; return "&=";
    // case .BITWISE_OR_EQUALS; return "|=";
    // case .BITWISE_XOR_EQUALS; return "^=";
    // case .LOGICAL_AND_EQUALS; return "&&=";
    // case .LOGICAL_OR_EQUALS; return "||=";
    
    //case ARRAY_SUBSCRIPT; return "[]";
    
    case; return "<operator_not_supported>";
  }
}

//~

Shader_Type :: enum {
  Vertex;
  Fragment;
}

Shader_Language :: enum {
  NONE;
  GLSL;
  HLSL;
}

Shader_Function :: struct {
  prototype: *Code_Procedure_Header;
  name: string; // @Cleanup This doesn't have to be here
  code: string;
}

Shader_Write_Context :: struct {
  name: string;
  type: Shader_Type;
  language: Shader_Language;
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
