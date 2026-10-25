#!/usr/bin/env bash
#
# Demo with GTK3: animate pixels through a memory mapped buffer.
#
# The script writes raw RGBA pixels into the buffer file with 'dd', the
# GTK-server copies them into a pixbuf. No encoding or decoding needed.
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
coproc gtk-server-gtk3 -stdin

gtk "gtk_init NULL NULL"
gtk "gtk_server_redefine gtk_image_set_from_pixbuf NONE NONE 2 WIDGET WIDGET"
gtk "gtk_server_define g_bytes_new NONE POINTER 2 BASE64 LONG"
gtk "gtk_server_define g_bytes_unref NONE NONE 1 POINTER"
gtk "gtk_server_define gdk_pixbuf_new_from_bytes NONE WIDGET 7 POINTER INT INT INT INT INT INT"

# Define GUI
def WINDOW "gtk_window_new 0"
gtk "gtk_window_set_title $WINDOW 'GTK3 mmap demo ($MODE)'"
def IMAGE "gtk_image_new"
gtk "gtk_widget_set_size_request $IMAGE $SIZE $SIZE"
gtk "gtk_container_add $WINDOW $IMAGE"
gtk "gtk_widget_show_all $WINDOW"

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
        def PIXBUF "gtk_server_mmap_pixbuf $HANDLE $SIZE $SIZE $STRIDE RGBA"
    else
        B64=$(dd if="$STRIP" bs=$STRIDE skip=$SKIP count=$SIZE 2>/dev/null | base64 | tr -d '\n')
        def BYTES "g_bytes_new $B64 $((STRIDE * SIZE))"
        # 0 is GDK_COLORSPACE_RGB, then has_alpha, bits per sample, width, height, rowstride
        def PIXBUF "gdk_pixbuf_new_from_bytes $BYTES 0 1 8 $SIZE $SIZE $STRIDE"
        gtk "g_bytes_unref $BYTES"
    fi
    gtk "gtk_image_set_from_pixbuf $IMAGE $PIXBUF"
    (( OLD != 0 )) && gtk "g_object_unref $OLD"
    OLD=$PIXBUF
    def EVENT "gtk_server_callback update"
    ((FRAME++))
done

ELAPSED=$(echo "$EPOCHREALTIME - $START" | bc)
echo "$MODE: $FRAME frames of ${SIZE}x${SIZE} in ${ELAPSED}s, $(echo "scale=1; $FRAME / $ELAPSED" | bc) frames/s"

# Exit GTK
gtk "gtk_server_exit"
