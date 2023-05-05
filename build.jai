#import "Basic";
#import "Compiler";
#import "Program_Print";
#import "String";
#import "Hash_Table";

#import "Metaprogram_Plugins";

#load "Jai_To_Glsl.jai";

jai_to_glsl_plugin: *Metaprogram_Plugin;

#run build();
build :: () {
  w := compiler_create_workspace("Shaders");
  
  options := get_build_options(w);
  options.output_executable_name = "Shaders";
  set_build_options(options, w);
  
  jai_to_glsl_plugin = jglsl_get_plugin();
  jai_to_glsl_plugin.workspace = w;
  
  compiler_begin_intercept(w);
  add_build_file("./src/example.jai", w);
  message_loop(w);
  compiler_end_intercept(w);
  
  set_build_options_dc(.{do_output=false, write_added_strings=false});
}

message_loop :: (w: Workspace) {
  while true {
    message := compiler_wait_for_message();
    
    jglsl_receive_message(jai_to_glsl_plugin, message);
    
    if message.kind == .COMPLETE break;
  }
}