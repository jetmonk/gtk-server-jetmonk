#!/usr/bin/env bash
#
# Demo with GTK4
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
function def { gtk "$2"; eval $1=$GTK; }

# Start GTK-server in STDIN mode
coproc gtk-server-gtk4 -stdin -log=/tmp/$0.log -debug

# The GTK4 API has changed a lot, make sure to redefine your GTK functions. 
gtk "gtk_server_redefine gtk_window_new close-request WIDGET 0"
gtk "gtk_server_redefine gtk_grid_new NONE WIDGET 0"
gtk "gtk_server_redefine gtk_grid_attach NONE NONE 6 WIDGET WIDGET INT INT INT INT"
gtk "gtk_server_redefine gtk_widget_set_hexpand NONE NONE 2 WIDGET INT"
gtk "gtk_server_redefine gtk_widget_set_vexpand NONE NONE 2 WIDGET INT"
gtk "gtk_server_redefine gtk_widget_set_halign NONE NONE 2 WIDGET INT"
gtk "gtk_server_redefine gtk_widget_set_valign NONE NONE 2 WIDGET INT"
gtk "gtk_server_redefine gtk_entry_get_buffer NONE WIDGET 1 WIDGET"
gtk "gtk_server_redefine gtk_entry_buffer_get_text NONE STRING 1 WIDGET"
gtk "gtk_server_redefine gtk_entry_buffer_set_text NONE NONE 3 WIDGET STRING INT"
gtk "gtk_server_redefine g_object_set NONE NONE 4 WIDGET STRING WIDGET INT"

# Define GUI
def WINDOW "gtk_window_new"
gtk "gtk_window_set_title $WINDOW 'This is a title'"
gtk "gtk_widget_set_size_request $WINDOW 250 100"
def GRID "gtk_grid_new"
gtk "g_object_set $WINDOW child $GRID 0"
def ENTRY "gtk_entry_new"
gtk "gtk_widget_set_hexpand $ENTRY 1"
gtk "gtk_widget_set_valign $ENTRY 2"
gtk "gtk_grid_attach $GRID $ENTRY 0 0 2 1"
def SETBUTTON "gtk_button_new_with_label 'Set Text'"
gtk "gtk_widget_set_halign $SETBUTTON 1"
gtk "gtk_widget_set_valign $SETBUTTON 2"
gtk "gtk_widget_set_vexpand $SETBUTTON 1"
gtk "gtk_grid_attach $GRID $SETBUTTON 0 1 1 1"
def GETBUTTON "gtk_button_new_with_label 'Get Text'"
gtk "gtk_widget_set_halign $GETBUTTON 2"
gtk "gtk_widget_set_valign $GETBUTTON 2"
gtk "gtk_grid_attach $GRID $GETBUTTON 1 1 1 1"
gtk "gtk_widget_set_vexpand $GETBUTTON 1"
gtk "gtk_widget_show $WINDOW"

# Mainloop
while [[ $EVENT != $WINDOW ]]
do
    def EVENT "gtk_server_callback wait"

    if [[ $EVENT = $ENTRY || $EVENT = $GETBUTTON ]]
    then
        def BUFFER "gtk_entry_get_buffer $ENTRY"
        gtk "gtk_entry_buffer_get_text $BUFFER"
		echo "$GTK"
    fi
    if [[ $EVENT = $SETBUTTON ]]
    then
        def BUFFER "gtk_entry_get_buffer $ENTRY"
        gtk "gtk_entry_buffer_set_text $BUFFER 'This is a GTK4 demo' -1"
    fi
done

# Exit GTK
gtk "gtk_server_exit"
