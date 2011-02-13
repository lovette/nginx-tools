#!/bin/bash
#
# This script generates a minified nginx configuration file.
#
# Copyright (c) 2011 Lance Lovette. All rights reserved.
# Licensed under the BSD License.
# See the file LICENSE.txt for the full license text.
#
# Available from https://github.com/lovette/nginx-tools

CMDPATH=$(readlink -f "$0")
CMDNAME=$(basename "$CMDPATH")
CMDDIR=$(dirname "$CMDPATH")
CMDARGS=$@

NGINX_MINIFY_VER="1.0.0"

NGINX_BIN=$(which nginx 2> /dev/null || echo /usr/sbin/nginx)

OPT_EXPANDINCLUDES=1
OPT_STRIPBLANKLINES=1
OPT_STRIPCOMMENTS=1
OPT_REFORMAT=1
OPT_DEMARCATEINCLUDES=0
OPT_MAXINCLUDEDEPTH=-1
OPT_OUTFILE=
OPT_MINIFYLEVEL=0

##########################################################################
# Functions

# echo_stderr(string)
# Outputs message to stderr
function echo_stderr()
{
	echo $* 1>&2
}

# exit_arg_error(string)
# Outputs message to stderr and exits
function exit_arg_error()
{
	local message="$1"

	[ -n "$message" ] && echo_stderr "$CMDNAME: $message"
	echo_stderr "Try '$CMDNAME --help' for more information."
	exit 1
}

# exit_error(string)
# Outputs message to stderr and exits
function exit_error()
{
	local message="$1"

	[ -n "$message" ] && echo_stderr "$CMDNAME: $message"
	exit 1
}

# Called when script exits
function onexit()
{
	[ -f "$TMPINFILE" ] && /bin/rm -f "$TMPINFILE"
	[ -f "$TMPOUTFILE" ] && /bin/rm -f "$TMPOUTFILE"
}

# Print version and exit
function version()
{
	echo "nginx-minify-conf $NGINX_MINIFY_VER"
	echo
	echo "Copyright (C) 2011 Lance Lovette"
	echo "Licensed under the BSD License."
	echo "See the distribution file LICENSE.txt for the full license text."
	echo
	echo "Written by Lance Lovette <https://github.com/lovette>"

	exit 0
}

# Print usage and exit
function usage()
{
	echo "Creates a minified version of a nginx configuration file by expanding includes"
	echo "and optionally removing blank lines and comments."
	echo "The result is reformatted by default to improve readability."
	echo "If CONFFILE is not specified, the default configuration file is used."
	echo
	echo "Usage: nginx-minify-conf [OPTION]... [CONFFILE]"
	echo
	echo "Options:"
	echo "  -1             Expand includes"
	echo "  -2             Expand includes, remove blank lines"
	echo "  -3             Expand includes, remove blank lines and comments (default)"
	echo "  -h, --help     Show this help and exit"
	echo "  -i             Demarcate begin and end of included files (if comments are preserved)"
	echo "  -I DEPTH       Limit include file expansion to DEPTH (0=none; default is all)"
	echo "  -o FILE        Write output to FILE"
	echo "  -u             Do not reformat"
	echo "  -V, --version  Print version and exit"
	echo
	echo "Report bugs to <https://github.com/lovette/nginx-tools/issues>"

	exit 0
}

# Attempts to determine nginx configuration file path as compiled in the binary
function getdefaultconfpath()
{
	local path=

	[ -x "$NGINX_BIN" ] || exit_error "$NGINX_BIN: Cannot locate the nginx binary, confirm it is on your PATH"

	path=$($NGINX_BIN -V 2>&1 | awk 'BEGIN {RS=" "} {if(split($0,a,"=")==2 && a[1]=="--conf-path") print a[2]}')
	[ -n "$path" ] || exit_error "Cannot determine nginx configuration file path from 'nginx -V'"

	echo "$path"
	return 0;
}

# expandincludes(path)
# Expand include directives in conf file 'path'
# Outputs result
function expandincludes()
{
	local path="$1"

	(
		# Paths are relative to the configuration file
		cd "$NGINX_DIR_CONF"

		awk -v demarcateincludes=$OPT_DEMARCATEINCLUDES '
		function include(path)
		{
			if (demarcateincludes == 1)
			{
				print "#=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
				print "# BEGIN include " path
			}

			while ((getline line < path) > 0)
				print line;
			close(path);

			if (demarcateincludes == 1)
			{
				print "# END include " path
				print "#=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
			}
		}

		BEGIN {
			FS = "\n"
		}

		{
			# Replace nginx include directive with content of referenced file
			# Wildcards are expanded and replaced with full file paths
			if (match($0, "^[[:space:]]*include[[:space:]]+(.+);$", parts))
			{
				cmd = "ls -1 " parts[1] " | xargs -r -n 1 readlink -f"
				while (cmd | getline > 0)
					include($0)
				close(cmd);
			}
			else
			{
				print 
			}
		}' "$path" 2>&1
	)

	return $?
}

# reformat(path)
# Reformat whitespace in conf file 'path'
function reformat()
{
	local path="$1"

	awk --re-interval -v stripcomments=$OPT_STRIPCOMMENTS '
	function spaces(n)
	{
		s=""; for (i=0; i < n; i++) { s=s "   " } return s;
	}

	BEGIN {
		FS = "\n";
		IGNORECASE=1;
		indent=0;
		insertblankline=0;
	}

	{
		directive = $0
		args = "";

		# Remove leading/trailing whitespace
		gsub(/^[ \t]+|[ \t]+$/, "", directive)

		if (substr(directive, 1, 1) != "#")
		{
			# Remove inline comments, unless quotes are involved
			if (stripcomments == 1) gsub(/[[:space:]]*#[^"]+$/, "", directive);

			# Collapse internal spaces, unless quotes are involved
			if (index(directive, "\"") == 0) gsub(/\t+| {2,}+/, " ", directive);

			# Extract the directive if possible
			if (match(directive, "^([^[:space:]]+)[[:space:]]+(.+)$", parts))
			{
				directive = parts[1];
				args = parts[2];
			}
		}

		# Manage indentation based on open/close brackets (very crude)
		if (match(args, "{$") > 0)
		{
			print "";
			print spaces(indent) directive " " args;
			indent++;
			insertblankline=0;
		}
		else if (directive == "{")
		{
			print spaces(indent) directive " " args;
			indent++;
			insertblankline=0;
		}
		else if (directive == "}")
		{
			indent--;
			print spaces(indent) directive " " args;
			insertblankline=1;
		}
		else
		{
			if (insertblankline) print ""
			insertblankline=0;

			# Indent line continuations that begin with a single quote
			if (substr(directive, 1, 1) == "\047")
				print spaces(indent+1) directive " " args;
			else
				print spaces(indent) directive " " args;
		}
	}' "$path" 2>&1
}

# minify(path)
# Minifies conf file 'path'
function minify()
{
	local path="$1"

	cat "$path" > "$TMPINFILE"
	[ $? -eq 0 ] ||	exit_error "An error occured"

	if [ $OPT_EXPANDINCLUDES -eq 1 ]; then
		local depth=0
		while egrep -q "^[[:space:]]*include[[:space:]]+" "$TMPINFILE"
		do
			[ $OPT_MAXINCLUDEDEPTH -ge 0 ] && [ $depth -ge $OPT_MAXINCLUDEDEPTH ] && break
			TMPFILE=$(mktemp -t "$TMPFILESPEC")
			expandincludes "$TMPINFILE" > "$TMPFILE"
			[ $? -eq 0 ] ||	exit_error "An error occured"
			/bin/rm -f "$TMPINFILE"
			TMPINFILE="$TMPFILE"
			(( depth++ ))
		done
	fi

	if [ $OPT_STRIPBLANKLINES -eq 1 ]; then
		TMPFILE=$(mktemp -t "$TMPFILESPEC")
		egrep -v "^[[:space:]]*$" "$TMPINFILE" > "$TMPFILE"
		[ $? -eq 0 ] ||	exit_error "An error occured"
		/bin/rm -f "$TMPINFILE"
		TMPINFILE="$TMPFILE"
	fi

	if [ $OPT_STRIPCOMMENTS -eq 1 ]; then
		TMPFILE=$(mktemp -t "$TMPFILESPEC")
		egrep -v "^[[:space:]]*#" "$TMPINFILE" > "$TMPFILE"
		[ $? -eq 0 ] ||	exit_error "An error occured"
		/bin/rm -f "$TMPINFILE"
		TMPINFILE="$TMPFILE"
	fi

	if [ $OPT_REFORMAT -eq 1 ]; then
		TMPFILE=$(mktemp -t "$TMPFILESPEC")
		reformat "$TMPINFILE" > "$TMPFILE"
		[ $? -eq 0 ] ||	exit_error "An error occured"
		/bin/rm -f "$TMPINFILE"
		TMPINFILE="$TMPFILE"
	fi

	# Generate the new configuration
	(
		echo "# Regenerate this file with '$CMDNAME $CMDARGS'"
		echo "# This file was generated "$(date)
		echo

		cat "$TMPINFILE"
	)

	return $?
}

##########################################################################
# Main

# Check for usage longopts
case "$1" in
	"--help"    ) usage;;
	"--version" ) version;;
esac

# Parse command line options
while getopts "123hiI:o:uV" opt
do
	case $opt in
	1  ) [ $OPT_MINIFYLEVEL -eq 0 ] || exit_arg_error "ambiguous minify level"; OPT_MINIFYLEVEL=$opt;;
	2  ) [ $OPT_MINIFYLEVEL -eq 0 ] || exit_arg_error "ambiguous minify level"; OPT_MINIFYLEVEL=$opt;;
	3  ) [ $OPT_MINIFYLEVEL -eq 0 ] || exit_arg_error "ambiguous minify level"; OPT_MINIFYLEVEL=$opt;;
	h  ) usage;;
	i  ) OPT_DEMARCATEINCLUDES=1;;
	I  ) OPT_MAXINCLUDEDEPTH=$OPTARG;;
	o  ) OPT_OUTFILE="$OPTARG";;
	u  ) OPT_REFORMAT=0;;
	V  ) version;;
	\? ) exit_arg_error;;
	esac
done

shift $(($OPTIND - 1))
NGINX_CONF="$1"

# Use the default configuration file if none is specified
[ -n "$NGINX_CONF" ] || NGINX_CONF=$(getdefaultconfpath)

# Confirm conf file exists and is readable
[ -f "$NGINX_CONF" ] || exit_error "$NGINX_CONF: No such file"
[ -r "$NGINX_CONF" ] || exit_error "$NGINX_CONF: Read permission denied"

# Confirm we can write to outfile if necessary
if [ -e "$OPT_OUTFILE" ]; then
	[ -f "$OPT_OUTFILE" ] || exit_error "$OPT_OUTFILE: Output path cannot be a directory"
	[ -w "$OPT_OUTFILE" ] || exit_error "$OPT_OUTFILE: Write permission denied"
fi

# We need to know if any of our pipe commands fail, not just the last one
set -o pipefail

# Set options based on minify level
case $OPT_MINIFYLEVEL in
0  ) ;;
1  ) OPT_STRIPBLANKLINES=0; OPT_STRIPCOMMENTS=0;;
2  ) OPT_STRIPBLANKLINES=1; OPT_STRIPCOMMENTS=0;;
3  ) ;;
*  ) exit_arg_error "invalid minify level"
esac

NGINX_DIR_CONF=$(dirname "$NGINX_CONF")

TMPFILESPEC=$(basename "$CMDNAME" ".sh")"="$(basename "$NGINX_CONF")".XXXXXX"
TMPINFILE=$(mktemp -t "$TMPFILESPEC") || exit_error
TMPOUTFILE=$(mktemp -t "$TMPFILESPEC") || exit_error

# Remove temp files on exit
trap "onexit" EXIT

minify "$NGINX_CONF" > "$TMPOUTFILE"
[ $? -eq 0 ] ||	exit_error "An error occured"

if [ -z "$OPT_OUTFILE" ]; then
	cat "$TMPOUTFILE"
	RETVAL=$?
else
	/bin/mv -f "$TMPOUTFILE" "$OPT_OUTFILE"
	RETVAL=$?
fi

exit $RETVAL
