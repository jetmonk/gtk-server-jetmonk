#!/bin/bash
#
# With the GTK-server it is possible to open any library from a shellscript,
# without using configfile, as is shown below.
#
# August 2019, PvE - tested with GTK-server 2.4.6 on Mageia Linux 7.
#
#---------------------------------------------------------------------

# Name of PIPE file
declare PI=/tmp/bash.gtk.$$

#---------------------------------------------------------------------
# Communication function; assignment function
#---------------------------------------------------------------------

function cairo() { echo $1 > $PI; read CAIRO < $PI; }
function define() { $2 "$3"; eval $1="\"$CAIRO\""; }

# Start GTK-server in PIPE mode
gtk-server -fifo=$PI -debug &
while [ ! -p $PI ]; do continue; done

# Open Cairo library
define LIB cairo "gtk_server_require libcairo.so"
if [[ ${LIB} != "ok" ]]
then
    echo "No libcairo found on this system! Exiting..."
    cairo "gtk_server_exit"
    exit 1
fi

# Define some cairo calls
cairo "gtk_server_define cairo_image_surface_create NONE WIDGET 3 INT INT INT"
cairo "gtk_server_define cairo_create NONE WIDGET 1 WIDGET"
cairo "gtk_server_define cairo_select_font_face NONE NONE 4 WIDGET STRING INT INT"
cairo "gtk_server_define cairo_set_font_size NONE NONE 2 WIDGET DOUBLE"
cairo "gtk_server_define cairo_set_source_rgb NONE NONE 4 WIDGET DOUBLE DOUBLE DOUBLE"
cairo "gtk_server_define cairo_move_to NONE NONE 3 WIDGET DOUBLE DOUBLE"
cairo "gtk_server_define cairo_show_text NONE NONE 2 WIDGET STRING"
cairo "gtk_server_define cairo_destroy NONE BOOL 1 WIDGET"
cairo "gtk_server_define cairo_surface_write_to_png NONE NONE 2 WIDGET STRING"
cairo "gtk_server_define cairo_surface_destroy NONE NONE 1 WIDGET"

# Cairo constants from the header files
CAIRO_FORMAT_ARGB32=0
CAIRO_FONT_SLANT_NORMAL=0
CAIRO_FONT_WEIGHT_BOLD=1

define surface cairo "cairo_image_surface_create ${CAIRO_FORMAT_ARGB32} 240 80"
define cr cairo "cairo_create ${surface}"

cairo "cairo_select_font_face ${cr} serif ${CAIRO_FONT_SLANT_NORMAL} ${CAIRO_FONT_WEIGHT_BOLD}"
cairo "cairo_set_font_size ${cr} 32.0"
cairo "cairo_set_source_rgb ${cr} 0.0 0.0 1.0"
cairo "cairo_move_to ${cr} 10.0 50.0"
cairo "cairo_show_text ${cr} 'Hello, world'"
cairo "cairo_destroy ${cr}"
cairo "cairo_surface_write_to_png ${surface} hello.png"
cairo "cairo_surface_destroy ${surface}"

# Exit GTK-server
cairo "gtk_server_exit"

echo "File 'hello.png' created."
