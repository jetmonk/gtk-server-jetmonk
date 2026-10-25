#!/usr/bin/env bash
#
# Demo with GTK4: animate pixels through a memory mapped buffer.
#
# The script writes raw RGBA pixels into the buffer file with 'dd', the
# GTK-server copies them into a texture. No encoding or decoding needed.
#
# Usage: mmap.bash [mmap|base64] [frames]
#   mmap    - pass pixels through gtk_server_mmap_create (default)
#   base64  - pass the same pixels as BASE64 argument, for comparison
#   frames  - stop after this many frames and print the frame rate
#
# Needs bash 4 or later for 'coproc' and $EPOCHREALTIME.
#------------------------------------------------

MODE=${1:-mmap}
FRAMES=${2:-0}
SIZE=512
STRIDE=$((SIZE*4))

# Communication function; assignment function
function gtk
{
    echo "${@}" >&"${COPROC[1]}"
    read GTK <&"${COPROC[0]}"
}
function def { gtk "$2"; eval $1=$GTK; }

# Create a vertical rainbow of SIZE rows, twice, so a window of SIZE rows can scroll through it
STRIP=$(mktemp "${TMPDIR:-/tmp}/gtk-server-strip-XXXXXX")
trap 'rm -f "$STRIP"' EXIT
# Bash strings cannot hold a NUL byte, so color values are kept between 1 and 255
function tri { local x=$(( $1 % 512 )); (( x >= 256 )) && x=$((511 - x)); echo $((x > 0 ? x : 1)); }
for ((row = 0; row < SIZE; row++))
do
    t=$((row * 512 / SIZE))
    printf -v PIXEL '\\x%02x\\x%02x\\x%02x\\xff' $(tri $t) $(tri $((t + 170))) $(tri $((t + 340)))
    printf -v LINE '%b' "$PIXEL"
    # Double the pixel until the line is SIZE pixels wide, SIZE must be a power of 2
    for ((w = 1; w < SIZE; w *= 2)); do LINE=$LINE$LINE; done
    printf '%s' "$LINE"
done > "$STRIP"
cat "$STRIP" "$STRIP" > "$STRIP.2" && mv "$STRIP.2" "$STRIP"

# Start GTK-server in STDIN mode
coproc gtk-server-gtk4 -stdin

gtk "gtk_server_redefine gtk_window_new close-request WIDGET 0"
gtk "gtk_server_redefine g_object_set NONE NONE 4 WIDGET STRING WIDGET INT"
gtk "gtk_server_define gtk_picture_new NONE WIDGET 0"
gtk "gtk_server_define gtk_picture_set_paintable NONE NONE 2 WIDGET WIDGET"
gtk "gtk_server_define g_bytes_new NONE POINTER 2 BASE64 LONG"
gtk "gtk_server_define g_bytes_unref NONE NONE 1 POINTER"
gtk "gtk_server_define gdk_memory_texture_new NONE WIDGET 5 INT INT INT POINTER LONG"

# Define GUI
def WINDOW "gtk_window_new"
gtk "gtk_window_set_title $WINDOW 'GTK4 mmap demo ($MODE)'"
def PICTURE "gtk_picture_new"
gtk "gtk_widget_set_size_request $PICTURE $SIZE $SIZE"
gtk "g_object_set $WINDOW child $PICTURE 0"
gtk "gtk_widget_show $WINDOW"

if [[ $MODE = mmap ]]
then
    gtk "gtk_server_mmap_create $((STRIDE * SIZE))"
    read -r HANDLE BUFFER ADDRESS <<< "$GTK"
fi

# Mainloop
FRAME=0
OLD=0
START=$EPOCHREALTIME
while [[ $EVENT != $WINDOW ]] && (( FRAMES == 0 || FRAME < FRAMES ))
do
    SKIP=$(( (FRAME * 4) % SIZE ))
    if [[ $MODE = mmap ]]
    then
        # conv=notrunc is essential, truncating the buffer file would make the GTK-server stop
        dd if="$STRIP" of="$BUFFER" bs=$STRIDE skip=$SKIP count=$SIZE conv=notrunc 2>/dev/null
        def TEXTURE "gtk_server_mmap_texture $HANDLE $SIZE $SIZE $STRIDE RGBA"
    else
        B64=$(dd if="$STRIP" bs=$STRIDE skip=$SKIP count=$SIZE 2>/dev/null | base64 | tr -d '\n')
        def BYTES "g_bytes_new $B64 $((STRIDE * SIZE))"
        # 5 is GDK_MEMORY_R8G8B8A8
        def TEXTURE "gdk_memory_texture_new $SIZE $SIZE 5 $BYTES $STRIDE"
        gtk "g_bytes_unref $BYTES"
    fi
    gtk "gtk_picture_set_paintable $PICTURE $TEXTURE"
    (( OLD != 0 )) && gtk "g_object_unref $OLD"
    OLD=$TEXTURE
    def EVENT "gtk_server_callback update"
    ((FRAME++))
done

ELAPSED=$(echo "$EPOCHREALTIME - $START" | bc)
echo "$MODE: $FRAME frames of ${SIZE}x${SIZE} in ${ELAPSED}s, $(echo "scale=1; $FRAME / $ELAPSED" | bc) frames/s"

# Exit GTK
gtk "gtk_server_exit"
