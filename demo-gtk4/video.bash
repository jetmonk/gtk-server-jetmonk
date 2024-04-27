#!/usr/bin/env bash
#
# Video Demo with GTK4
#
# Make sure your system has the 'libgtk-4-media-gstreamer' library available!
#
# April 2024 - PvE.
#------------------------------------------------
#
# Communication function; assignment function
function gtk
{
    echo "${@}" >&"${COPROC[1]}"
    read GTK <&"${COPROC[0]}"
}
function def { gtk "$2"; eval $1='${GTK}'; }

# Start GTK-server in STDIN mode
coproc gtk-server-gtk4 -stdin -log=/tmp/$0.log -debug

# The GTK4 API has changed a lot, make sure to redefine some GTK functions correctly.
gtk "gtk_server_redefine gtk_window_new close-request WIDGET 0"
gtk "gtk_server_redefine gtk_box_new NONE WIDGET 2 INT INT"
gtk "gtk_server_redefine gtk_box_append NONE NONE 2 WIDGET WIDGET"
gtk "gtk_server_redefine gtk_widget_set_hexpand NONE NONE 2 WIDGET INT"
gtk "gtk_server_redefine gtk_widget_set_vexpand NONE NONE 2 WIDGET INT"
gtk "gtk_server_redefine gtk_video_new NONE WIDGET 0"
gtk "gtk_server_redefine gtk_video_set_autoplay NONE NONE 2 WIDGET INT"
gtk "gtk_server_redefine gtk_video_set_filename NONE NONE 2 WIDGET STRING"
gtk "gtk_server_redefine gtk_file_chooser_get_file NONE POINTER 1 WIDGET"
gtk "gtk_server_redefine g_file_get_path NONE STRING 1 POINTER"
gtk "gtk_server_redefine g_object_set NONE NONE 4 WIDGET STRING WIDGET INT"

# Define GUI
def WINDOW "gtk_window_new"
gtk "gtk_window_set_title $WINDOW 'GTK4 Video Player'"
def BOX1 "gtk_box_new 1 5"
gtk "g_object_set $WINDOW child $BOX1 0"
def VIDEO "gtk_video_new"
gtk "gtk_video_set_autoplay $VIDEO 1"
gtk "gtk_widget_set_size_request $VIDEO 600 400"
gtk "gtk_widget_set_hexpand $VIDEO 1"
gtk "gtk_widget_set_vexpand $VIDEO 1"
gtk "gtk_box_append $BOX1 $VIDEO"
def BUTTON "gtk_button_new_with_label 'Select video...'"
gtk "gtk_box_append $BOX1 $BUTTON"
def FILE "gtk_window_new"
gtk "gtk_window_set_title $FILE 'Open Video'"
def BOX2 "gtk_box_new 1 5"
gtk "g_object_set $FILE child $BOX2 0"
def CHOOSER "gtk_file_chooser_widget_new 0"
gtk "gtk_widget_set_vexpand $CHOOSER 1"
gtk "gtk_widget_set_size_request $CHOOSER 500 500"
gtk "gtk_box_append $BOX2 $CHOOSER"
def OPEN "gtk_button_new_with_label 'Select video...'"
gtk "gtk_box_append $BOX2 $OPEN"
gtk "gtk_widget_show $WINDOW"

# Mainloop
while [[ $EVENT != $WINDOW ]]
do
    def EVENT "gtk_server_callback wait"

    # Check events
    case $EVENT in
        $BUTTON)
            gtk "gtk_widget_show $FILE";;
        $FILE)
            gtk "gtk_widget_hide $FILE";;
        $OPEN)
            gtk "gtk_widget_hide $FILE"
            def SELECT "gtk_file_chooser_get_file $CHOOSER"
            def NAME "g_file_get_path $SELECT"
            gtk "gtk_video_set_filename $VIDEO \"$NAME\"";;
    esac
done
