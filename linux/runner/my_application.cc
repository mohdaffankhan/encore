#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  GtkHeaderBar* header_bar;
  FlMethodChannel* window_channel;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// The window's size (and place, where the desktop allows apps to choose
// it: X11, not Wayland), kept between runs.
static gchar* window_state_path() {
  return g_build_filename(g_get_user_config_dir(), "encore", "window.ini",
                          nullptr);
}

static void restore_window(GtkWindow* window) {
  gtk_window_set_default_size(window, 1280, 800);
  g_autoptr(GKeyFile) file = g_key_file_new();
  g_autofree gchar* path = window_state_path();
  if (!g_key_file_load_from_file(file, path, G_KEY_FILE_NONE, nullptr)) {
    return;
  }
  gint width = g_key_file_get_integer(file, "window", "width", nullptr);
  gint height = g_key_file_get_integer(file, "window", "height", nullptr);
  if (width >= 400 && height >= 300) {
    gtk_window_set_default_size(window, width, height);
  }
  if (g_key_file_has_key(file, "window", "x", nullptr)) {
    gint x = g_key_file_get_integer(file, "window", "x", nullptr);
    gint y = g_key_file_get_integer(file, "window", "y", nullptr);
    // Only onto a screen that is still there.
    GdkDisplay* display = gdk_display_get_default();
    GdkMonitor* monitor =
        display ? gdk_display_get_monitor_at_point(display, x, y) : nullptr;
    GdkRectangle area;
    if (monitor) {
      gdk_monitor_get_geometry(monitor, &area);
      if (x >= area.x && y >= area.y && x < area.x + area.width &&
          y < area.y + area.height) {
        gtk_window_move(window, x, y);
      }
    }
  }
  if (g_key_file_get_boolean(file, "window", "maximized", nullptr)) {
    gtk_window_maximize(window);
  }
}

static gboolean save_window(GtkWidget* widget, GdkEvent* event,
                            gpointer user_data) {
  GtkWindow* window = GTK_WINDOW(widget);
  g_autoptr(GKeyFile) file = g_key_file_new();
  g_autofree gchar* path = window_state_path();
  // Keeps the size from before maximizing.
  g_key_file_load_from_file(file, path, G_KEY_FILE_NONE, nullptr);
  gboolean maximized = gtk_window_is_maximized(window);
  g_key_file_set_boolean(file, "window", "maximized", maximized);
  if (!maximized) {
    gint width, height, x, y;
    gtk_window_get_size(window, &width, &height);
    gtk_window_get_position(window, &x, &y);
    g_key_file_set_integer(file, "window", "width", width);
    g_key_file_set_integer(file, "window", "height", height);
    g_key_file_set_integer(file, "window", "x", x);
    g_key_file_set_integer(file, "window", "y", y);
  }
  g_autofree gchar* dir = g_path_get_dirname(path);
  g_mkdir_with_parents(dir, 0700);
  g_key_file_save_to_file(file, path, nullptr);
  return FALSE;  // Close as usual.
}

// The app sets the window title to the song playing.
static void window_method_cb(FlMethodChannel* channel, FlMethodCall* call,
                             gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (g_strcmp0(fl_method_call_get_name(call), "title") == 0) {
    FlValue* args = fl_method_call_get_args(call);
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_STRING) {
      const gchar* title = fl_value_get_string(args);
      if (self->header_bar != nullptr) {
        gtk_header_bar_set_title(self->header_bar, title);
      }
      gtk_window_set_title(self->window, title);
    }
  }
  // Anything else (the tray, on Windows only) is fine to ignore.
  fl_method_call_respond_success(call, nullptr, nullptr);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Encore");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
    self->header_bar = header_bar;
  } else {
    gtk_window_set_title(window, "Encore");
  }

  restore_window(window);
  g_signal_connect(window, "delete-event", G_CALLBACK(save_window), nullptr);

  // Window icon, shipped as a Flutter asset next to the executable.
  g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
  if (exe != nullptr) {
    g_autofree gchar* dir = g_path_get_dirname(exe);
    g_autofree gchar* icon = g_build_filename(
        dir, "data", "flutter_assets", "assets", "brand", "icon_256.png",
        nullptr);
    gtk_window_set_icon_from_file(window, icon, nullptr);
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->window_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "dev.encore.app/window", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->window_channel,
                                            window_method_cb, self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->window_channel);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
