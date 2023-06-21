#if OS == .WINDOWS {
    the_gl_context: HGLRC;
    the_hdc_for_pixel_format_cloning: HDC;

    #import "Windows";

    windows_change_pixel_format :: (hdc: HDC) {
        assert(the_hdc_for_pixel_format_cloning != null);

        pfd: PIXELFORMATDESCRIPTOR;
        format := GetPixelFormat(the_hdc_for_pixel_format_cloning);
        result := DescribePixelFormat(the_hdc_for_pixel_format_cloning, format, size_of(type_of(pfd)), *pfd);
        assert(result != 0);
        
        SetPixelFormat(hdc, format, *pfd);
    }
} else #if OS == .LINUX {
    the_gl_context: GLXContext;
    the_gl_fbc: GLXFBConfig;

    #import "X11";
} else {
    the_gl_context: *NSOpenGLContext;

    #import "Objective_C";
}

load_gl :: (window : *Window_Type) {
    do_first_time_init := false;
    
    if the_gl_context {
        #if OS == .WINDOWS {
            hdc := GetDC(window);
            windows_change_pixel_format(hdc);
        }
    } else {
        do_first_time_init = true;
        
        #if OS == .WINDOWS {
            hglrc, hdc := wgl_create_context(window, null, 4, 6);
            the_gl_context = hglrc;
            the_hdc_for_pixel_format_cloning = hdc;
        }
        #if OS == .LINUX {
            the_gl_context, the_gl_fbc = glx_create_context(4, 6);
        } 
        #if OS == .MACOS {
            the_gl_context = nsgl_create_context(4, 6);
            autorelease(the_gl_context);
        }
    }

    #if OS == .MACOS {
        // Get the GL view from the window.
        // This relies on this window having a content view with OpenGL support (eg. as created by Window_Creation).
        view := NSWindow.contentView(window);
        assert(view != null);
        NSView.setWantsBestResolutionOpenGLSurface(view, YES);
        NSOpenGLContext.setView(the_gl_context, view);
        NSOpenGLContext.update(the_gl_context);
    }
    
    #if OS == .LINUX {
        // Make dumb wrapper window.
        // Mst happen before glGen*, because we make current.
        glx_window := glXCreateWindow(x_global_display, the_gl_fbc, info.window, null);
        info.specific.glx_window = glx_window;
    }

    if do_first_time_init {
        #if OS == .LINUX  glXMakeCurrent(x_global_display, glx_window, the_gl_context);
        #if OS == .MACOS {
            NSOpenGLContext.makeCurrentContext(the_gl_context);
        }
        
        gl_load(*gl);
        gl_enable_debug_output(break_on_error = true);

        DumpGLErrors("context");
    }
}

swap_buffers :: (window: Window_Type, vsync := true) {
    #if OS == .WINDOWS {
        dc := GetDC(window);
        SwapBuffers(dc);
    } else #if OS == .LINUX {
        info := find_window_info(window);
        if (!info) || !info.specific.glx_window {
            log_error("Simp: Attempt to swap_buffers on a previously unseen window!\n");
            return;
        }
        
        glXSwapBuffers(x_global_display, info.specific.glx_window);
    } else #if OS == .MACOS {
        // On macOS, OpenGL buffer swapping is done on the context, not on the view.
        // So we can only swap for the active window. (And you need to swap before switching to another view).
        assert(window == state.current_window_info.window);
        NSOpenGLContext.flushBuffer(the_gl_context);
    } else {
        assert(false);
    }
}