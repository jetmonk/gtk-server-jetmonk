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

3. **Memory mapped buffers for pixel data (GTK4 prototype).** Instead of
   sending images as BASE64, a client writes raw pixels into a buffer it
   shares with GTK-server, and turns the buffer into a texture:

   ```
   gtk_server_mmap_create <size>        -> <handle> <path> <address>
   gtk_server_mmap_texture <handle> <width> <height> <stride> <format> [offset]
   gtk_server_mmap_free <handle>
   ```

   The buffer is a file, so a shell script can write to it with
   `dd conv=notrunc`, and other languages can map it themselves.
   [demo-gtk4/mmap.bash](demo-gtk4/mmap.bash) animates a 512x512 picture
   from bash at about 140 frames per second on an Apple Silicon Mac.

4. **C/Invoke removed.** GTK-server could be built with one of four calling
   libraries. C/Invoke has not been developed since about 2007 and does not
   support arm64, so it is gone; `configure --with-cinv` stops with an error.
   libffi, ffcall and dyncall remain.

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

Known problems inherited from 2.4.7:

- Large `BASE64` arguments are very slow: one megabyte takes more than
  20 seconds, because the parser rescans the input for every character.
- The stock definition `FUNCTION_NAME = g_object_set, ..., WIDGET, STRING, INT, NULL`
  declares the value as `INT`. Passing a widget through it truncates the
  pointer on 64-bit systems. The GTK4 demos redefine it with `WIDGET`.

## License

GTK-server is released under the GNU General Public License, version 2 or
(at your option) any later version, see the header of `src/gtk-server.c`.
The license text is in [COPYING](COPYING).
The included uthash library is under the BSD license.
