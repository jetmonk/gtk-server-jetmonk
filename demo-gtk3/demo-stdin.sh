#!/usr/bin/env sh
#
# POSIX shell stdin demo with the GTK-server
#
# Tested on dash 0.5.10.2, busybox 1.30.1 and
# bash 5.0 on Ubuntu 20.04
#
# August 19, 2021 by 10geek
#------------------------------------------------


err() {
	if [ $# -gt 1 ]; then
		printf %s\\n "$program_name: $2" >&2
	else
		printf %s\\n "$program_name: $1" >&2
	fi
	[ $# -gt 1 ] && exit "$1"
	return 1
}
checkutil() {
	unset -v checkutil__not_found_utils
	if [ ":$1" = :-s ]; then
		checkutil__silent=1
		shift
	else
		checkutil__silent=0
	fi
	[ ":$1" = :-- ] && shift
	set -- $*
	while [ $# -ne 0 ]; do
		{
			checkutil__util_path=$(command -v -- "$1") &&
			[ -n "$checkutil__util_path" ]
		} ||
			checkutil__not_found_utils=$checkutil__not_found_utils' '$1
		shift
	done
	[ -z "$checkutil__not_found_utils" ] || {
		checkutil__not_found_utils=${checkutil__not_found_utils# }
		[ $checkutil__silent -eq 0 ] &&
			err "\`$(printf %s\\n "$checkutil__not_found_utils" | sed 's/ /'\'', `/g; s/\(.*\), /\1 and /')' is not found in system, PATH=$PATH"
		return 1
	}
}
splitstream() {
	splitstream__stderr=$({ {
		{ "$@"; printf \\n%s $? >&2; echo; } | sed 's/^/1/'
	} 3>&2 2>&1 1>&3 3>&- | sed 's/^/2/'; } 2>&1)
	splitstream__stdout=$(printf %s\\n "$splitstream__stderr" | sed -n 's/^1//;tp;b;:p p')
	splitstream__retval=$(printf %s\\n "$splitstream__stderr" | LC_ALL=C awk 'END { print substr($0, 2) }')
	splitstream__stderr=$(printf %s\\n "$splitstream__stderr" | LC_ALL=C awk '{
		if(NR != 1 && substr(str, 1, 1) == 2) print substr(str, 2); str = $0
	}')
	return $splitstream__retval
}

waitpid() {
	while :; do
		wait "$1" 2>/dev/null
		waitpid__retval=$?
		sh -c 'trap '\'\'' '"$SIGNALS"'
		ps -Ao ppid,pid | LC_ALL=C awk -- '\''
			BEGIN { ARGC = 1; exit_code = 1 }
			$2 == ARGV[2] { if($1 == ARGV[1]) exit_code = 0; exit }
			END { exit exit_code }
		'\'' "$PPID" "$0"' "$1" || break
	done
	wait "$1" 2>/dev/null
	waitpid__last_retval=$?
	[ $waitpid__last_retval -ne 127 ] && return $waitpid__last_retval
	return $waitpid__retval
}

unset -v \
	gtk__fd_stdin \
	gtk__fd_stdout \
	gtk__pid
gtk__fifo_stdin=$HOME/.gtk-server/fifo-stdin
gtk__fifo_stdout=$HOME/.gtk-server/fifo-stdout
gtk__lock_file=$HOME/.gtk-server/lock
gtk__debug=0
gtk__err_fatal=1
gtk___nl=$(printf \\n.); gtk___nl=${gtk___nl%.}

# Usage: gtk__init <toolkit> <fd_stdin> <fd_stdout>
gtk__init() {
	checkutil flock gtk-server-"$1" || return 1
	gtk__fd_stdin=$2
	gtk__fd_stdout=$3
	mkdir -p "$HOME/.gtk-server" &&
	{
		flock 1 &&
		rm -f "$gtk__fifo_stdin" "$gtk__fifo_stdout" &&
		mkfifo "$gtk__fifo_stdin" "$gtk__fifo_stdout" &&
		{
			gtk-server-"$1" -stdin > "$gtk__fifo_stdout" < "$gtk__fifo_stdin" &
			gtk__pid=$!
		} &&
		eval "exec $gtk__fd_stdout<\"\$gtk__fifo_stdout\" $gtk__fd_stdin>\"\$gtk__fifo_stdin\"" &&
		rm -f "$gtk__fifo_stdin" "$gtk__fifo_stdout"
	} > "$gtk__lock_file" >&2 &&
	gtk gtk_server_enable_print_line_count &&
	gtk gtk_init NULL NULL &&
	return
	gtk__exit || return
	return 1
}
# Usage: gtk__exit
gtk__exit() {
	[ -z "$gtk__pid" ] && return
	set -- 0
	kill -TERM "$gtk__pid" 2>/dev/null || set -- 1
	waitpid $1 || set -- $?
	unset -v gtk__pid
	return $1
}
# Usage: gtk [<varname>=]<call> [<arg>] ...
gtk() {
	case $1 in =*) ;; *=*)
		eval "gtk__arg=\${1#*=}; shift; ${1%%=*}=; gtk \"\$gtk__arg\" \"\$@\" && ${1%%=*}=\$gtk__retval"
		return
	esac
	gtk__prep_call=; gtk__retval=
	while [ $# -ne 0 ]; do
		gtk__arg=$1
		gtk__esc=
		while :; do case $gtk__arg in
			*'\'*)
				gtk__esc=$gtk__esc${gtk__arg%%\\*}'\\'
				gtk__arg=${gtk__arg#*\\}
				;;
			*) break
		esac; done
		gtk__arg=$gtk__esc$gtk__arg
		gtk__esc=
		while :; do case $gtk__arg in
			*\'*)
				gtk__esc=$gtk__esc${gtk__arg%%\'*}'\'\'
				gtk__arg=${gtk__arg#*\'}
				;;
			*) break
		esac; done
		gtk__arg=$gtk__esc$gtk__arg
		gtk__esc=
		while :; do case $gtk__arg in
			*"$gtk___nl"*)
				gtk__esc=$gtk__esc${gtk__arg%%$gtk___nl*}'\n'
				gtk__arg=${gtk__arg#*$gtk___nl}
				;;
			*) break
		esac; done
		gtk__prep_call="$gtk__prep_call '$gtk__esc$gtk__arg'"
		shift
	done
	set -- 0
	{
		{ printf %s\\n "$gtk__prep_call" >&"$gtk__fd_stdin" || { set -- 1; false; }; } &&
		IFS= read -r gtk___buf <&"$gtk__fd_stdout" &&
		set -- 0 $((gtk___buf + 0)) &&
		while [ $2 -gt 0 ]; do
			IFS= read -r gtk___buf <&"$gtk__fd_stdout" || {
				set -- 1; break
			}
			gtk__retval=$gtk__retval$gtk___buf
			[ $2 -ne 1 ] && gtk__retval=$gtk__retval$gtk___nl
			set -- 0 $(($2 - 1))
		done
	} #2>/dev/null
	set -- $?
	unset -v gtk__arg gtk__esc
	[ $1 -eq 0 ] || {
		err "gtk(): failed to invoke the API call:$gtk__prep_call"
		unset -v gtk__prep_call
		[ $gtk__err_fatal -eq 0 ] || exit 1
		return 1
	}
	[ $gtk__debug -eq 0 ] ||
		err "gtk(): [debug]$gtk__prep_call -> $gtk__retval"
	unset -v gtk__prep_call
	return 0
}

SIGNALS='HUP INT QUIT ILL ABRT FPE SEGV PIPE ALRM TERM USR1 USR2'
signal_handler___ifs=$IFS
eval "signal_handler__register() { trap 'EXIT_CODE=\$?; trap '\\'\\'' $SIGNALS; IFS=\$signal_handler___ifs; signal_handler EXIT' EXIT;$(
	LC_ALL=C awk -- 'BEGIN { for(i = 2; i < ARGC; i++) print "trap \47trap \47\134\47\134\47\47 " ARGV[1] "; IFS=$signal_handler___ifs; signal_handler " ARGV[i] "; signal_handler__register\47 " ARGV[i] }' "$SIGNALS" $SIGNALS
);}"


program_name=${0##*/}

signal_handler() {
	case $1 in
	EXIT) gtk__exit;;
	*) exit;;
	esac
}
signal_handler__register


#gtk__debug=1
#export GTK_DEBUG=interactive

gtk__init gtk3 6 7 || exit 1

# Definitions that are missing in gtk-server.cfg.
# Refer to the documentation https://docs.gtk.org/gtk3/ for information about
# function definitions.
#
# Usage: gtk gtk_server_define <func> <callback> <type> <amount> [<arg>] ...
# <func>       Function name
# <callback>   Callback signal if applicable. The real names for the GTK
#              callback signals must be used here.
# <type>       Type of the return value. The type can be one of  the following:
#              NONE, VOID, WIDGET, POINTER, BOOL, STRING, INT, LONG,
#              DOUBLE, FLOAT or ADDRESS.
# <amount>     How many arguments the GTK function needs.
# [<arg>] ...  Type of each indivdual argument. The type of the arguments can be
#              one of the following: NULL, WIDGET, POINTER, BOOL, STRING,
#              INT, LONG, DOUBLE, FLOAT, ENUM, STR, CLASS, MACRO, DATA,
#              BASE64 or VARARGS.
gtk gtk_server_define gtk_box_new NONE WIDGET 2 ENUM INT
gtk gtk_server_define gtk_combo_box_new_with_model NONE WIDGET 1 WIDGET
gtk gtk_server_define gtk_dialog_set_default_response NONE VOID 2 WIDGET INT
gtk gtk_server_define gtk_file_filter_add_mime_type NONE VOID 2 WIDGET STRING
gtk gtk_server_define gtk_image_menu_item_new_with_label NONE WIDGET 1 STRING
gtk gtk_server_define gtk_image_menu_item_set_image NONE VOID 2 WIDGET WIDGET
gtk gtk_server_define gtk_image_new_from_icon_name NONE WIDGET 2 STRING ENUM
gtk gtk_server_define gtk_separator_tool_item_new NONE WIDGET 0
gtk gtk_server_define gtk_separator_tool_item_set_draw NONE VOID 2 WIDGET BOOL
gtk gtk_server_define gtk_style_context_add_class NONE VOID 2 WIDGET STRING
gtk gtk_server_define gtk_tool_button_new NONE WIDGET 2 WIDGET STRING
gtk gtk_server_define gtk_tool_item_set_tooltip_markup NONE VOID 2 WIDGET STRING
gtk gtk_server_define gtk_toolbar_insert NONE VOID 3 WIDGET WIDGET INT
gtk gtk_server_define gtk_toolbar_new NONE WIDGET 0
gtk gtk_server_define gtk_toolbar_set_style NONE VOID 2 WIDGET ENUM
gtk gtk_server_define gtk_widget_get_style_context NONE WIDGET 1 WIDGET

gtk start_iter=gtk_server_opaque
gtk end_iter=gtk_server_opaque


# win
gtk win=gtk_window_new GTK_WINDOW_TOPLEVEL
gtk gtk_window_set_title "$win" 'POSIX shell GTK-server demo'
gtk gtk_window_set_icon_name "$win" dialog-information
gtk gtk_window_set_default_size "$win" 480 320
#gtk gtk_window_set_resizable "$win" 0
gtk gtk_window_set_position "$win" GTK_WIN_POS_CENTER
gtk accel_group_main=gtk_accel_group_new
gtk gtk_window_add_accel_group "$win" "$accel_group_main"

# win / vbox
gtk vbox=gtk_box_new 1 0
gtk gtk_container_add "$win" "$vbox"

# win / vbox / menubar
gtk menubar=gtk_menu_bar_new
gtk gtk_box_pack_start "$vbox" "$menubar" 0 0 0

fn() {
	case $1 in
	1) shift
		gtk item=gtk_menu_item_new_with_mnemonic "$1"
		gtk gtk_menu_shell_append "$menubar" "$item"

		gtk submenu=gtk_menu_new
		gtk gtk_menu_item_set_submenu "$item" "$submenu"
		;;
	2) shift
		[ $# -eq 0 ] && {
			gtk item=gtk_separator_menu_item_new
			gtk gtk_menu_shell_append "$submenu" "$item"
			return
		}
		if [ -n "$2" ]; then
			gtk item=gtk_image_menu_item_new_with_label "$1"
			gtk gtk_image_new_from_icon_name "$2" 1
			gtk gtk_image_menu_item_set_image "$item" "$gtk__retval"
		else
			gtk item=gtk_menu_item_new_with_label "$1"
		fi
		[ $# -ge 4 ] &&
			gtk gtk_widget_add_accelerator "$item" activate "$accel_group_main" "$4" "$5" 1
		gtk gtk_menu_shell_append "$submenu" "$item"
		gtk gtk_server_connect "$item" activate "$3"
		;;
	esac
}
fn 1 '_File'
fn 2 'New' document-new new 110 4
fn 2 'Open' document-open open 111 4
fn 2 'Save' document-save save 115 4
fn 2
fn 2 'Exit' application-exit exit 113 4

# win / vbox / toolbar
gtk toolbar=gtk_toolbar_new
gtk gtk_toolbar_set_style "$toolbar" 2
gtk gtk_widget_get_style_context "$toolbar"
gtk gtk_style_context_add_class "$gtk__retval" primary-toolbar

fn() {
	[ $# -eq 0 ] && {
		gtk item=gtk_separator_tool_item_new
		gtk gtk_separator_tool_item_set_draw "$item" 1
		gtk gtk_toolbar_insert "$toolbar" "$item" -1
		return
	}
	gtk gtk_image_new_from_icon_name "$3" 1
	gtk item=gtk_tool_button_new "$gtk__retval" "$1"
	[ -n "$2" ] &&
		gtk gtk_tool_item_set_tooltip_markup "$item" "$2"
	gtk gtk_toolbar_insert "$toolbar" "$item" -1
	gtk gtk_server_connect "$item" clicked "$4"
	[ $# -ge 5 ] &&
		gtk gtk_widget_add_accelerator "$item" clicked "$accel_group_main" "$5" "$6" 1
}
fn 'New' 'Clear text buffer' document-new new # 110 4
fn 'Open' 'Open file' document-open open # 111 4
fn 'Save' 'Save text buffer' document-save save # 115 4
fn
fn 'Exit' '' application-exit exit # 113 4

gtk gtk_box_pack_start "$vbox" "$toolbar" 0 0 0

# win / vbox / scrollwin
gtk scrollwin=gtk_scrolled_window_new
gtk gtk_scrolled_window_set_shadow_type "$scrollwin" GTK_SHADOW_IN
gtk gtk_container_set_border_width "$scrollwin" 10
gtk gtk_box_pack_start "$vbox" "$scrollwin" 1 1 0

# win / vbox / scrollwin / textview
gtk text_buf=gtk_text_buffer_new
gtk textview=gtk_text_view_new_with_buffer "$text_buf"
gtk gtk_text_view_set_border_window_size "$textview" 3 5
gtk gtk_text_view_set_border_window_size "$textview" 4 5
gtk gtk_text_view_set_border_window_size "$textview" 5 5
gtk gtk_text_view_set_border_window_size "$textview" 6 5
gtk gtk_text_view_set_wrap_mode "$textview" 2
gtk gtk_container_add "$scrollwin" "$textview"

gtk gtk_widget_show_all "$win"


# Mainloop
while :; do
	gtk event=gtk_server_callback WAIT
	case $event in
	"$win"|exit)
		break
		;;
	new)
		gtk gtk_text_buffer_get_bounds "$text_buf" "$start_iter" "$end_iter"
		gtk gtk_text_buffer_delete "$text_buf" "$start_iter" "$end_iter"
		;;
	open)
		gtk dialog=gtk_file_chooser_dialog_new 'Open file' "$win" 0 'Cancel' 0 'Open' 1
		gtk gtk_dialog_set_default_response "$dialog" 1

		fn() {
			gtk filter=gtk_file_filter_new
			gtk gtk_file_filter_set_name "$filter" "$1"
			gtk gtk_file_filter_add_"$2" "$filter" "$3"
			gtk gtk_file_chooser_add_filter "$dialog" "$filter"
		}
		fn 'Text file' mime_type 'text/plain'
		fn 'All files' pattern '*'

		while :; do
			gtk gtk_dialog_run "$dialog"
			[ ":$gtk__retval" = :1 ] && {
				gtk file_path=gtk_file_chooser_get_filename "$dialog"
				[ -f "$file_path" ] && {
					fn() { cat < "$file_path"; }
					splitstream fn && break
					gtk dialog_err=gtk_message_dialog_new "$dialog" 0 3 2 %s "${splitstream__stderr:-Unknown error}"
					gtk gtk_window_set_title "$dialog_err" 'Error'
					gtk gtk_dialog_run "$dialog_err"
					gtk gtk_widget_destroy "$dialog_err"
				}
				continue
			}
			file_path=
			break
		done
		gtk gtk_widget_destroy "$dialog"
		[ -n "$file_path" ] &&
		gtk gtk_text_buffer_set_text "$text_buf" "$splitstream__stdout" ${#splitstream__stdout}
		unset -v splitstream__stdout
		;;
	save)
		gtk dialog=gtk_file_chooser_dialog_new 'Save file' "$win" 1 'Cancel' 0 'Save' 1
		gtk gtk_dialog_set_default_response "$dialog" 1

		# Always something doesn't work for incomprehensible reasons...
		#gtk gtk_server_define gtk_file_chooser_set_do_overwrite_confirmation NONE VOID 2 WIDGET BOOL
		#gtk gtk_file_chooser_set_do_overwrite_confirmation "$dialog" 1

		while :; do
			gtk gtk_dialog_run "$dialog"
			[ ":$gtk__retval" = :1 ] && {
				gtk file_path=gtk_file_chooser_get_filename "$dialog"
				[ -d "$file_path" ] && continue
				[ -f "$file_path" ] && {
					gtk dialog_confirm=gtk_message_dialog_new "$dialog" 0 2 4 %s "A file \"$file_path\" already exists. Do you want to replace it?"
					gtk answer=gtk_dialog_run "$dialog_confirm"
					gtk gtk_widget_destroy "$dialog_confirm"
					[ ":$answer" = :-8 ] || continue
				}
				gtk gtk_text_buffer_get_bounds "$text_buf" "$start_iter" "$end_iter"
				gtk gtk_text_buffer_get_text "$text_buf" "$start_iter" "$end_iter" 0
				error=$({ printf %s\\n "$gtk__retval" > "$file_path"; } 2>&1) || {
					unset -v gtk__retval
					gtk dialog_err=gtk_message_dialog_new "$dialog" 0 3 2 %s "${error:-Unknown error}"
					gtk gtk_window_set_title "$dialog_err" 'Error'
					gtk gtk_dialog_run "$dialog_err"
					gtk gtk_widget_destroy "$dialog_err"
					continue
				}
				unset -v gtk__retval
				break
			}
			break
		done
		gtk gtk_widget_destroy "$dialog"
		;;
	*)
		err "unknown event: $event"
		;;
	esac
done
