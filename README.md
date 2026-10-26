# gtk-server-jetmonk

An unofficial variant of [GTK-server](https://gtk-server.org/) by Peter van
Eerten, maintained by jetmonk. It fixes building and running on macOS with
Apple Silicon, fixes calls to variadic C functions, and adds memory mapped
buffers for pixel data. It is not affiliated with or endorsed by the original
project; for the official GTK-server, see the links below.

GTK-server lets any language that can read and write text, such as a shell
script, build a GTK user interface. The script sends commands like
`gtk_window_new` over stdin, a pipe or a socket.

The programs, the configfile and the `gtk_server_*` commands keep their
original names, so scripts written for GTK-server 2.4.7 work with this
variant. It does diverge from upstream where that helps: for example, support
for the C/Invoke calling library has been removed. All differences are listed
below.

## Origin

The upstream project lives in a Fossil repository on chiselapp:
<https://chiselapp.com/user/gtk-server/repository/gtk-server/timeline>.
This repository's history up to `Baseline for GTK-server 2.4.7.` is converted
from that repository, one git commit per Fossil check-in. Each commit message
ends with a `Fossil-check-in:` line giving the original hash. That commit is
identical to the gtk-server-2.4.7 release tarball.

The original documentation is in [README.1ST](README.1ST), [INSTALL](INSTALL)
and [documentation/](documentation/).

## What this variant changes

The commits after the 2.4.7 baseline:

1. **Building on macOS, in particular Apple Silicon.**
   - `config.guess` and `config.sub` are updated, so arm64 Macs are recognized.
   - `configure` no longer breaks the macOS build by adding a `.dylib` target
     without a make rule, and no longer passes linker flags Apple's linker rejects.
   - The Motif and GTK2 backends are only enabled when they can actually be built.
   - The SSL libraries are also linked into the shared libraries.

2. **Calls to variadic C functions on arm64 macOS.** Functions with a
   variable argument list, such as `g_object_set` or `gtk_list_store_set`,
   were called as if their argument list were fixed. On Apple Silicon this
   passes the variable arguments in the wrong place, so these calls silently
   did nothing or crashed. They are now called correctly with each of the
   calling libraries GTK-server can be built with: libffi (with
   `ffi_prep_cif_var`), dyncall (with its variadic call modes) and ffcall.
   ffcall cannot call variadic functions by itself, so on Apple Silicon a
   workaround puts the variable arguments where variadic functions expect
   them. The configfile gets a new definition that gives the amount of fixed
   arguments:

   ```
   # C: void g_object_set(gpointer object, const gchar *first_property_name, ...)
   # name, callback, return type, total args, fixed args (before the ...), arg types
   VARIADIC_FUNCTION_NAME = g_object_set, NONE, NONE, 4, 2, WIDGET, STRING, INT, NULL
   ```

   Here the first 2 argument types, `WIDGET` and `STRING`, are the fixed
   arguments `object` and `first_property_name`. The rest, `INT` and `NULL`,
   are passed as the variable arguments `...`: a property value and the `NULL`
   that ends the list.

   Scripts can do the same at runtime with `gtk_server_define_variadic` and
   `gtk_server_redefine_variadic`. A function that a script redefines with
   `gtk_server_redefine` stays variadic. See `man documentation/gtk-server.cfg.1`.

3. **Memory mapped buffers for pixel data (prototype).** Instead of
   sending images as BASE64, a client writes raw pixels into a buffer it
   shares with GTK-server, and turns the buffer into an image: a texture on
   GTK4, a pixbuf on GTK3. Creating and freeing buffers works in every
   backend on Unix-like systems:

   ```
   # Create a buffer of <size> bytes: a temp file at <path>, mapped into gtk-server's
   #     memory at <address> (only meaningful inside gtk-server, e.g. as a POINTER argument).
   #     The client writes pixels to <path>, e.g. with: dd ... conv=notrunc
   gtk_server_mmap_create <size>        -> <handle> <path> <address>

   # GTK4 only: copy the bytes the client put in buffer <handle> into a new GdkTexture,
   #     as an image of <width> by <height> pixels, starting [offset] bytes into the buffer
   #     (default 0).
   #     <stride> is the number of bytes from the start of one row to the next
   #     (at least <width> * bytes per pixel). <format> is one of:
   #         RGBA, BGRA, ARGB, RGBA_PREMULTIPLIED, BGRA_PREMULTIPLIED   (4 bytes per pixel)
   #         RGB, BGR                                                   (3 bytes per pixel)
   #     Returns an integer handle for the texture. The pixels are copied, so the buffer can
   #     be rewritten right away. Release the texture with g_object_unref when done with it.
   gtk_server_mmap_texture <handle> <width> <height> <stride> <format> [offset]   -> <texture>

   # GTK3 only: the same, but into a new GdkPixbuf. A pixbuf only knows 8 bit RGBA and RGB
   #     without premultiplied alpha, so <format> is RGBA or RGB. Release it with
   #     g_object_unref when done with it.
   gtk_server_mmap_pixbuf <handle> <width> <height> <stride> <format> [offset]    -> <pixbuf>

   # Unmap the buffer and delete its file. Textures and pixbufs made from it stay valid.
   gtk_server_mmap_free <handle>        -> ok
   ```

   The buffer is a file, so a shell script can write to it with
   `dd conv=notrunc`, and other languages can map it themselves.
   [demo-gtk4/mmap.bash](demo-gtk4/mmap.bash) and
   [demo-gtk3/mmap.bash](demo-gtk3/mmap.bash) animate a 512x512 picture
   from bash, at about 140 (GTK4) and 210 (GTK3) frames per second on an
   Apple Silicon Mac. Run with `base64` as first argument, they send the same
   frames as BASE64 text instead, which manages about 10 frames per second.

   On GTK4, which cannot show a Cairo surface directly, a buffer can also be
   drawn on with Cairo: create the surface on top of the buffer with
   `cairo_image_surface_create_for_data <address> CAIRO_FORMAT_ARGB32 ...`,
   draw, call `cairo_surface_flush`, and make a texture with the format
   `BGRA_PREMULTIPLIED`, which is how Cairo stores its pixels on little-endian
   machines. [demo-gtk4/cairo-mmap.bash](demo-gtk4/cairo-mmap.bash) draws
   circling dots this way. Each Cairo call is one round trip of about 25
   microseconds from bash, so about 600 Cairo calls fit in a frame at 60
   frames per second. In a bash client, avoid `$(...)` in the drawing loop:
   each one starts a process, which costs more than the drawing.

   GTK-server removes its buffer files when it exits, also after an error,
   but not when it is killed by a signal. The files are named
   `gtk-server-mmap-*`, in `/dev/shm` on Linux and in `$TMPDIR` elsewhere.

4. **C/Invoke removed.** GTK-server could be built with one of four calling
   libraries. C/Invoke has not been developed since about 2007 and does not
   support arm64, so it is gone; `configure --with-cinv` stops with an error.
   libffi, ffcall and dyncall remain.

5. **Fast parsing of long commands.** The command parser and the BASE64
   decoder measured the length of their input again for every character, so
   the time grew with the square of the input length: one megabyte of BASE64
   data took about 45 seconds to decode. It now takes about 0.03 seconds.

6. **An icon in the macOS Dock.** A program outside an application bundle
   gets the generic black executable icon in the Dock. A script can now set
   its own icon, after creating its first window:

   ```
   # Set the Dock icon from an image file: PNG, JPEG, TIFF, ICNS, PDF, ...
   #     Returns 1 if the icon was set, 0 if the file could not be read.
   #     On other systems, or the console and Motif backends, it does nothing and returns 0.
   gtk_server_macos_icon <file>        -> 1 or 0
   ```

   The code is in [src/macos.m](src/macos.m), in Objective-C. configure adds
   it, and the AppKit framework, to the GTK3 and GTK4 builds on macOS only.

7. **No more lost events.** GTK-server kept only the last signal: when one
   command caused several, such as closing a window (`close-request`, then
   `destroy`) or setting an entry's text twice, `gtk_server_callback`
   reported only the last one. Signals are now queued, and
   `gtk_server_callback` reports them one by one, oldest first, before it
   waits for new ones. `gtk_server_callback_value`, `gtk_server_key` and
   `gtk_server_mouse` give the data of the event reported last. The queue
   holds 256 events; if the client falls that far behind, the oldest are
   dropped.

8. **Detailed signal names.** `gtk_server_connect` and
   `gtk_server_connect_after` now accept signals with a detail, like
   `notify::label` or `notify::selected`, so a client can react to any
   property change. GTK-server used to stop with "Cannot find signal" for
   them.

9. **Long string results come back whole.** Every result longer than 1024
   characters, such as the text of a long label or a text buffer, lost its
   last character.

10. **Mouse and keyboard events in GTK4.** GTK4 no longer has
    `button-press-event` and `key-press-event`; widgets get pointer and key
    events through event controllers, whose signals pass the coordinates as
    doubles that GTK-server's generic callbacks could not receive.
    `gtk_server_mouse`, `gtk_server_key` and `gtk_server_state` now work with
    the controllers' signals: `pressed` and `released` of a `GtkGestureClick`,
    `motion` and `enter` of a `GtkEventControllerMotion`, `key-pressed` and
    `key-released` of a `GtkEventControllerKey`, and `scroll` of a
    `GtkEventControllerScroll`. Also, `gtk_server_mouse` printed GTK4's
    coordinates as if they were integers, which gave nonsense.

    ```
    gtk_gesture_click_new                         -> <gesture>
    gtk_widget_add_controller <widget> <gesture>
    gtk_server_connect <gesture> pressed clicked
    ...
    gtk_server_callback wait                      -> clicked
    gtk_server_mouse 0                            -> x, in pixels from the widget's left
    gtk_server_mouse 1                            -> y
    gtk_server_mouse 2                            -> the button, 1 for the primary one
    gtk_server_state                              -> the modifier keys (GdkModifierType)
    ```

11. **Commands end at their newline.** GTK-server took whatever one read
    returned as one command. Commands sent together ran as one, and a long
    command that arrived in pieces, such as BASE64 data from a slow client,
    could run before it was complete. Now each line is one command, in the
    STDIN and TCP modes. So a client can send many commands before reading
    the replies, which still come one per command, in order: 3000
    `gtk_server_echo` calls take 1.5 µs each this way instead of 11 µs.
    Don't send more than a few hundred commands ahead, though: if the
    unread replies fill the pipe, GTK-server waits for the client to read
    them, and a client still writing would then wait too.

12. **Several definitions of one function.** A definition's name may end in
    `@` and a tag. It calls the function named before the `@`, but is a
    definition of its own, so one function can have several definitions with
    different argument types at once:

    ```
    gtk_server_define_variadic g_object_set@int    NONE NONE 4 2 WIDGET STRING INT NULL
    gtk_server_define_variadic g_object_set@string NONE NONE 4 2 WIDGET STRING STRING NULL
    g_object_set@int <widget> "margin-top" 4 NULL
    g_object_set@string <widget> "label" "Hello" NULL
    ```

    Before, a client setting properties of different types had to redefine
    `g_object_set` again and again, an extra round trip each time. Names
    without `@` work as before. GTK-server also looks each function up in the
    libraries only once now, instead of at every call.

13. **Signals from objects that are not widgets, in GTK4.** Connecting a
    signal of, for example, a `GtkSingleSelection` gave GTK critical
    warnings at each signal, because GTK-server took the object for a
    widget to read the pointer position. And for widgets, that position was
    read over a new, never shown window, so it was meaningless. It is now
    the position over the widget that sent the signal, and 0, 0 for other
    objects.

## Building on macOS

With GTK and libffi from MacPorts:

```sh
cd src
./configure CPPFLAGS="-I/opt/local/include" LDFLAGS="-L/opt/local/lib"
make
```

configure builds every backend it finds, for example `gtk-server-gtk3` and
`gtk-server-gtk4`. Add `--with-gtk3` or `--with-gtk4` to build only one.
With Homebrew, use `/opt/homebrew` instead of `/opt/local`.

configure uses libffi if it is installed. To use another calling library,
add `--with-ffcall` or `--with-dyncall`.

To run the demos without installing, put `src` first on your `PATH` and make
sure GTK-server finds `src/gtk-server.cfg`, for example by copying it into the
demo directory. The `.bash` demos need bash 4 or later, because they use
`coproc`. The bash in macOS is 3.2, so use bash from MacPorts or Homebrew.

```sh
cd demo-gtk4
cp ../src/gtk-server.cfg .
PATH="$PWD/../src:$PATH" /opt/local/bin/bash demo-stdin.bash
```

## Status

Tested on macOS 26 (arm64) with the GTK3 and GTK4 backends, built with each of
libffi (the default), ffcall 2.5 and dyncall 1.4.

Not tested:

- Linux, Intel Macs, Windows. The changes are meant to be portable, but
  nobody has run them there yet.
- Library mode (`libgtk-server.so`) and the Motif backend. Both build.

Known problem inherited from 2.4.7:

- The stock definition `FUNCTION_NAME = g_object_set, ..., WIDGET, STRING, INT, NULL`
  declares the value as `INT`. Passing a widget through it truncates the
  pointer on 64-bit systems. The GTK4 demos redefine it with `WIDGET`.

## License

GTK-server is released under the GNU General Public License, version 2 or
(at your option) any later version, see the header of `src/gtk-server.c`.
The license text is in [COPYING](COPYING).
The included uthash library is under the BSD license.
