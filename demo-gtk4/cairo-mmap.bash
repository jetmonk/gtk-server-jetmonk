#!/usr/bin/env bash
#
# Demo with GTK4: draw with Cairo into a memory mapped buffer.
#
# GTK4 cannot show a Cairo surface directly. This demo creates the Cairo
# surface on top of a GTK-server buffer from gtk_server_mmap_create, draws on
# it every frame, and turns the buffer into a texture with
# gtk_server_mmap_texture. Cairo's ARGB32 format is premultiplied and stored
# as the bytes B, G, R, A on little-endian machines (x86, ARM), which is the
# BGRA_PREMULTIPLIED texture format.
#
# Usage: cairo-mmap.bash [dots] [frames]
#   dots    - amount of circling dots, each costs 8 Cairo calls (default 40)
#   frames  - stop after this many frames and print the frame rate
#
# Needs bash 4 or later for 'coproc' and $EPOCHREALTIME.
#------------------------------------------------

DOTS=${1:-40}
FRAMES=${2:-0}
SIZE=512

# Communication function; assignment function
function gtk
{
    echo "${@}" >&"${COPROC[1]}"
    read GTK <&"${COPROC[0]}"
}
function def { gtk "$2"; eval $1=$GTK; }

# Start GTK-server in STDIN mode
coproc gtk-server-gtk4 -stdin

gtk "gtk_server_redefine gtk_window_new close-request WIDGET 0"
gtk "gtk_server_redefine g_object_set NONE NONE 4 WIDGET STRING WIDGET INT"
gtk "gtk_server_define gtk_picture_new NONE WIDGET 0"
gtk "gtk_server_define gtk_picture_set_paintable NONE NONE 2 WIDGET WIDGET"
gtk "gtk_server_define cairo_format_stride_for_width NONE INT 2 INT INT"
gtk "gtk_server_define cairo_image_surface_create_for_data NONE WIDGET 5 POINTER INT INT INT INT"
gtk "gtk_server_define cairo_rotate NONE NONE 2 WIDGET DOUBLE"

# Define GUI
def WINDOW "gtk_window_new"
gtk "gtk_window_set_title $WINDOW 'GTK4 Cairo mmap demo'"
def PICTURE "gtk_picture_new"
gtk "gtk_widget_set_size_request $PICTURE $SIZE $SIZE"
gtk "g_object_set $WINDOW child $PICTURE 0"
gtk "gtk_widget_show $WINDOW"

# A Cairo surface on top of a GTK-server buffer: both use the same memory
def STRIDE "cairo_format_stride_for_width CAIRO_FORMAT_ARGB32 $SIZE"
gtk "gtk_server_mmap_create $((STRIDE * SIZE))"
read -r HANDLE BUFFER ADDRESS <<< "$GTK"
def SURFACE "cairo_image_surface_create_for_data $ADDRESS CAIRO_FORMAT_ARGB32 $SIZE $SIZE $STRIDE"
def CR "cairo_create $SURFACE"
gtk "cairo_select_font_face $CR Sans 0 1"
gtk "cairo_set_font_size $CR 18"

# Color and ring of each dot, fixed for the whole run
for ((k = 0; k < DOTS; k++))
do
    COLOR[k]="0.$(( 30 + (k * 37) % 70 )) 0.$(( 30 + (k * 53) % 70 )) 0.$(( 30 + (k * 71) % 70 )) 0.85"
    RING[k]=$(( 60 + (k % 4) * 50 ))
done

# Mainloop
FRAME=0
OLD=0
FPS="-"
START=$EPOCHREALTIME
while [[ $EVENT != $WINDOW ]] && (( FRAMES == 0 || FRAME < FRAMES ))
do
    # Dark background
    gtk "cairo_set_source_rgba $CR 0.08 0.08 0.12 1"
    gtk "cairo_paint $CR"

    # Each dot: move to the center, rotate, move out along its ring, draw.
    # Bash has no floating point, so angles are computed in milliradians.
    # printf -v instead of $(...): a subshell per dot would cost more than the drawing.
    for ((k = 0; k < DOTS; k++))
    do
        A=$(( (FRAME * 12 * (1 + k % 3) + k * 6283 / DOTS) % 6283 ))
        printf -v ANGLE '%d.%03d' $((A / 1000)) $((A % 1000))
        gtk "cairo_save $CR"
        gtk "cairo_translate $CR $((SIZE / 2)) $((SIZE / 2))"
        gtk "cairo_rotate $CR $ANGLE"
        gtk "cairo_translate $CR ${RING[k]} 0"
        gtk "cairo_set_source_rgba $CR ${COLOR[k]}"
        gtk "cairo_arc $CR 0 0 $(( 8 + k % 3 * 4 )) 0 6.2832"
        gtk "cairo_fill $CR"
        gtk "cairo_restore $CR"
    done

    # Frame counter and frame rate
    gtk "cairo_set_source_rgba $CR 1 1 1 1"
    gtk "cairo_move_to $CR 12 28"
    gtk "cairo_show_text $CR 'frame $FRAME   $FPS frames/s   $(( DOTS * 8 + 6 )) Cairo calls per frame'"

    # Make sure Cairo has written everything, then copy the buffer into a texture
    gtk "cairo_surface_flush $SURFACE"
    def TEXTURE "gtk_server_mmap_texture $HANDLE $SIZE $SIZE $STRIDE BGRA_PREMULTIPLIED"
    gtk "gtk_picture_set_paintable $PICTURE $TEXTURE"
    (( OLD != 0 )) && gtk "g_object_unref $OLD"
    OLD=$TEXTURE
    def EVENT "gtk_server_callback update"
    ((FRAME++))
    (( FRAME % 30 == 0 )) && FPS=$(echo "scale=1; $FRAME / ($EPOCHREALTIME - $START)" | bc)
done

ELAPSED=$(echo "$EPOCHREALTIME - $START" | bc)
echo "$FRAME frames with $DOTS dots in ${ELAPSED}s, $(echo "scale=1; $FRAME / $ELAPSED" | bc) frames/s"

# Exit GTK
gtk "cairo_destroy $CR"
gtk "cairo_surface_destroy $SURFACE"
gtk "gtk_server_exit"
