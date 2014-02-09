#!/bin/bash
#
# Manages nginx sites.
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

NGINX_SITES_VER="1.0.6"

NGINX_BIN=$(which nginx 2> /dev/null || echo /usr/sbin/nginx)
NGINX_CONF=
NGINX_DIR_CONF=
NGINX_SITES_DIR_AVAIL=
NGINX_SITES_DIR_ENABLED=

GETOPT_VERBOSE=0
GETOPT_DRYRUN=0
GETOPT_QUIET=0
GETOPT_PROMPT=1
GETOPT_NOCOLOR=0
GETOPT_SIMPLESTATUS=1
GETOPT_NGINX_RELOAD=0
GETOPT_NGINX_RESTART=0
GETOPT_NGINX_TEST=0

# Exit status codes
EXIT_ERROR_ARG=1
EXIT_ERROR_GENERAL=2
EXIT_ERROR_NOSITE=3
EXIT_ERROR_NOMATCH=4
EXIT_ERROR_NGINX=5
EXIT_STATUS_ENABLED=10
EXIT_STATUS_DISABLED=11

# You can find a list of color values at
# https://wiki.archlinux.org/index.php/Color_Bash_Prompt
TTYWHITEBOLD="\e[1;37m"
TTYGREEN="\e[0;32m"
TTYRED="\e[0;31m"
TTYRESET="\e[0m"

SITESPECREGEX="^(.+)/(.+)$"
SIMPLEGROUPNAMEREGEX="^[-_.A-Za-z0-9]+$"

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
	exit $EXIT_ERROR_ARG
}

# exit_gen_error(string)
# Outputs message to stderr and exits
function exit_gen_error()
{
	local message="$1"

	[ -n "$message" ] && echo_stderr "$CMDNAME: $message"
	exit $EXIT_ERROR_GENERAL
}

# exit_nosite_error(string)
# Outputs message to stderr and exits
function exit_nosite_error()
{
	local message="$1"

	[ -n "$message" ] && echo_stderr "$CMDNAME: $message"
	exit $EXIT_ERROR_NOSITE
}

# exit_nomatch_error(string)
# Outputs message to stderr and exits
function exit_nomatch_error()
{
	local message="$1"

	[ -n "$message" ] && echo_stderr "$message"
	exit $EXIT_ERROR_NOMATCH
}

# exit_nginx_error(string)
# Outputs message to stderr and exits
function exit_nginx_error()
{
	local message="$1"

	[ -n "$message" ] && echo_stderr "$message"
	exit $EXIT_ERROR_NGINX
}

# pluralize(integer, singular, plural)
# Outputs singular or plural phrase
function pluralize()
{
	if [ $1 -eq 1 ]; then
		echo $2
	else
		echo $3
	fi
}

# getopt_realpath(path)
# Outputs result of readlink path
# Returns success if file exists, otherwise exits
function getopt_realpath()
{
	[ -n "$1" ] || exit_arg_error "option requires an argument"
	[ -f "$1" ] || exit_gen_error "$1: No such file"

	echo $(readlink -f "$1")
	return 0
}

# Redirect stdout so we run in quiet mode
function close_stdout()
{
	# Link fd #6 with stdout and replace stdout with /dev/null
	exec 6>&1
	exec > /dev/null
}

# safe_exec(args)
# Executes arguments unless dry run option is set
function safe_exec()
{
	if [ $GETOPT_DRYRUN -eq 0 ]; then
		eval $@
	elif [ $GETOPT_VERBOSE -gt 2 ]; then
		echo "$@"
	fi
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

# enum_groups()
# Outputs list of site groups, including the faux root group "-"
# Returns success if enumeration is successful
# Exits if find command fails
function enum_groups()
{
	local groupnames=

	groupnames=$(/usr/bin/find "$NGINX_SITES_DIR_AVAIL" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" 2> /dev/null | sort | tr '[:space:]' ' ')
	[ $? -eq 0 ] || exit_gen_error "$NGINX_SITES_DIR_AVAIL: Failed to enumerate directories"

	# Remove trailing spaces
	echo "-" ${groupnames%% }
	return 0
}

# enum_sites(spec, optfullname)
# 'spec' must be <group>/<pattern>
# Outputs list of available sites matching pattern
# Sites will be prefixed by their group if 'optfullname' is nonzero
# Returns success if enumeration is successful
# Exits if find command fails
function enum_sites()
{
	local sitespec="$1"
	local optfullname=$2
	local groupname=
	local sitepattern=
	local grouppath="$NGINX_SITES_DIR_AVAIL"
	local siteprefix=
	local sitenames=

	[[ "$sitespec" =~ $SITESPECREGEX ]] || return 1

	groupname="${BASH_REMATCH[1]}"
	sitepattern="${BASH_REMATCH[2]}"

	[ "$groupname" = "-" ] || grouppath="$NGINX_SITES_DIR_AVAIL/$groupname"
	[ $optfullname -eq 1 ] && siteprefix="${groupname}/"

	[ -d "$grouppath" ] || return 1

	sitenames=$(/usr/bin/find "$grouppath" -mindepth 1 -maxdepth 1 -type f \( -name "${sitepattern}" -or -name "${sitepattern}.conf" \) -printf "${siteprefix}%f\n" 2> /dev/null | sed "s/.conf$//" | sort | tr '[:space:]' ' ')
	[ $? -eq 0 ] || exit_gen_error "$grouppath: Failed to enumerate files"

	# Remove trailing spaces
	echo ${sitenames%% }
	return 0
}

# enum_enabled_paths()
# Outputs list of paths in enabled sites directory
# Returns success if enumeration is successful
# Exits if find command fails
function enum_enabled_paths()
{
	local paths=

	paths=$(/usr/bin/find "$NGINX_SITES_DIR_ENABLED" -mindepth 1 -maxdepth 1 \( -type f -or -type l \) -print 2> /dev/null | sort | tr '[:space:]' ' ')
	[ $? -eq 0 ] || exit_gen_error "$NGINX_SITES_DIR_ENABLED: Failed to enumerate files"

	# Remove trailing spaces
	echo ${paths%% }
	return 0
}

# combine_subdomains(array)
# Combines domains with subdomains to compact text
# Example: [foo.com www.foo.com] becomes (www.)foo.com
# Outputs reduced domains
function combine_subdomains()
{
	local servers=( "$@" )
	local i j max

	# Sort domains by length so root domains are before subdomains
	servers=( $(echo "${servers[@]}" | tr " " "\n" | awk '{print length"\t"$0}' | sort -n | cut -f2-) )

	for (( i=0, max="${#servers[@]}"; i < max; i++ ))
	do
		# Skip subdomains we've combined already
		[ -n "${servers[$i]}" ] || continue;

		# Escape special characters
		local regex="^(.+)\.${servers[$i]//./\.}$"

		local subdomains=( )

		# Build list of subdomains for domain
		for (( j=i+1; j < max; j++ ))
		do
			if [[ "${servers[$j]}" =~ $regex ]]; then
				subdomains=( ${subdomains[@]} "${BASH_REMATCH[1]}" )
				servers[$j]=""
			fi
		done

		if [ ${#subdomains[@]} -gt 0 ]; then
			subdomains="${subdomains[@]}"
			echo "(${subdomains// /|}.)${servers[$i]}"
		else
			echo "${servers[$i]}"
		fi
	done
}

# get_site_server_names(name)
# 'name' can be <site> or <group>/<site>
# Parses nginx configuration file and outputs server_name and listen values of site
# Returns success if path exists
function get_site_server_names()
{
	local site="$1"
	local servers=( )
	local listen=( )
	local availpath=
	local servercnt=0

	availpath=$(get_path_avail "$site")
	[ $? -eq 0 ] || exit_nosite_error "$site: Site not found"

	servers=( $(awk '/^[[:space:]]*server_name[[:space:]]+/ { for (i=2;i<=NF;i++) print $i }' "$availpath" | tr -d ";" | sort -u | tr "[:space:]" " ") )
	listen=( $(awk '/^[[:space:]]*listen[[:space:]]+/ { for (i=2;i<=NF;i++) if (match($i, ":?([[:digit:]]+);?$", parts)) print parts[1] }' "$availpath" | sort -un | tr "[:space:]" " ") )

	servercnt=${#servers[@]}

	[ "${#servers[@]}" -gt 1 ] && servers=( $(combine_subdomains "${servers[@]}" | sort) )

	listen="${listen[@]}"

	[ -z "$listen" ] || listen="[:"${listen// /:}"]"

	if [ "${#servers[@]}" -gt 2 ]; then
		echo "${servers[0]}, ${servers[1]}, ... ($servercnt total) $listen"
	else
		servers="${servers[@]}"
		echo ${servers// /, } "$listen"
	fi

	return 0
}

# is_group(name)
# Returns success if 'name' refers to a group, including the faux root group "-"
function is_group()
{
	local group="$1"

	[ "$group" = "-" ] && return 0
	[ -d "$NGINX_SITES_DIR_AVAIL/$group" ] && return 0
	return 1
}

# is_site(name)
# name can be <site> or <group>/<site>
# Returns success if 'name' refers to an available site
function is_site()
{
	local site="$1"

	get_path_avail "$site" > /dev/null
	return $?
}

# is_site_pattern(name)
# name must be <group>/<pattern>
# Returns success if 'name' is a pattern
function is_site_pattern()
{
	local site="$1"
	local group=

	[[ "$site" =~ $SITESPECREGEX ]] || return 1

	group="${BASH_REMATCH[1]}"
	site="${BASH_REMATCH[2]}"

	is_group "$group" || return 1
	[[ "$site" =~ $SIMPLEGROUPNAMEREGEX ]] && return 1
	return 0
}

# full_site_name(name)
# Outputs site name prepended with root group prefix if no group is specified
function full_site_name()
{
	local site="$1"

	if [[ "$site" =~ $SITESPECREGEX ]]; then
		echo "$site"
	else
		echo "-/$site"
	fi
}

# resolve_sitespec(spec)
# Outputs list of full site names referenced by 'spec'
# 'spec' can be a <site>, <group>, or <group>/<pattern>
# Returns success if name is resolved
function resolve_sitespec()
{
	local spec="$1"

	# Remove trailing / (probably added by shell completion)
	spec=${spec%%/}

	if is_site_pattern "$spec"; then
		enum_sites "$spec" 1
	elif is_site "$spec"; then
		full_site_name "$spec"
	elif is_group "$spec"; then
		enum_sites "$spec/*" 1
	else
		return 1
	fi

	return 0
}

# get_path_avail(name)
# get_path_avail(group, site)
# 'name' can be <site> or <group>/<site>
# Outputs full path of available site conf file
# Returns success if path exists
function get_path_avail()
{
	local group=
	local site=
	local availpath=

	if [ $# -gt 1 ]; then
		group="$1"
		site="$2"
	elif [[ "$1" =~ $SITESPECREGEX ]]; then
		group="${BASH_REMATCH[1]}"
		site="${BASH_REMATCH[2]}"
	else
		group="-"
		site="$1"
	fi

	if [ "$group" = "-" ]; then
		availpath="$NGINX_SITES_DIR_AVAIL/$site"
	else
		availpath="$NGINX_SITES_DIR_AVAIL/$group/$site"
	fi

	for path in "${availpath}" "${availpath}.conf"
	do
		if [ -f "$path" ]; then
			echo "$path"
			return 0
		fi
	done

	return 1
}

# get_path_enabled(name)
# get_path_enabled(group, site)
# 'name' can be <site> or <group>/<site>
# Outputs full path of enabled site symlink
# Returns success if path is determined
function get_path_enabled()
{
	local group=
	local site=

	if [ $# -gt 1 ]; then
		group="$1"
		site="$2"
	elif [[ "$1" =~ $SITESPECREGEX ]]; then
		group="${BASH_REMATCH[1]}"
		site="${BASH_REMATCH[2]}"
	else
		group="-"
		site="$1"
	fi

	# Priority:
	# 1) default site
	# 2) default group
	# 3) ungrouped sites
	# 4) other groups

	case "$site" in
	"default" ) site="000-${site}";;
	*         ) site="002-${site}";;
	esac

	case "$group" in
	"-"       ) echo "$NGINX_SITES_DIR_ENABLED/${site}";;
	"default" )	echo "$NGINX_SITES_DIR_ENABLED/001-${group}--${site}";;
	*         )	echo "$NGINX_SITES_DIR_ENABLED/003-${group}--${site}";;
	esac

	return 0
}

# is_site_enabled(name)
# is_site_enabled(group, site)
# 'name' can be <site> or <group>/<site>
# Returns success if a site is enabled
function is_site_enabled()
{
	local enabledpath=

	enabledpath=$(get_path_enabled "$@")
	[ $? -eq 0 ] || exit_gen_error

	[ -f "$enabledpath" ] && return 0
	return 1
}

# enable_site(optenablesite, site)
# Enables a site if 'optenablesite' is nonzero, otherwise disables a site
# 'site' must be <group>/<pattern>
# Returns success if status is set
function enable_site()
{
	local optenablesite=$1
	local site="$2"
	local availpath=
	local enabledpath=

	availpath=$(get_path_avail "$site")
	[ $? -eq 0 ] || exit_nosite_error "$site: Site not found"

	enabledpath=$(get_path_enabled "$site")
	[ $? -eq 0 ] || exit_gen_error "$site: Site malformed"

	if [ $optenablesite -eq 1 ]; then
		# Create a link from ENABLED to AVAIL
		safe_exec /bin/ln -sf "$availpath" "$enabledpath"
		[ $? -eq 0 ] || exit_gen_error
	else
		# Remove link from ENABLED
		safe_exec /bin/rm -f "$enabledpath"
		[ $? -eq 0 ] || exit_gen_error
	fi

	return 0
}

# print_sites_status_grid(array)
# Output sites status grid
function print_sites_status_grid()
{
	local selectsites=( "$@" )
	local allgroups=( )
	local groupname=
	local siteserverstitle=

	[ $GETOPT_QUIET -eq 0 ] || return

	allgroups=( $(enum_groups) )
	[ $? -eq 0 ] || exit $?

	[ $GETOPT_SIMPLESTATUS -eq 0 ] || siteserverstitle="SERVERS"

	printf "%b%-20s %-10s %s%b\n" "${TTYWHITEBOLD}" "GROUP/SITE" "STATUS" "$siteserverstitle" "${TTYRESET}"

	# We do this loop-inside-a-loop thing to ensure that the
	# group output order is consistent across commands
	for groupname in "${allgroups[@]}"
	do
		local indent=
		local printgroup=1
		local fullsitename=
		local extractsitenameregex="^$groupname/(.+)$"

		for fullsitename in "${selectsites[@]}"
		do
			[[ "$fullsitename" =~ $extractsitenameregex ]] || continue

			local sitename="${BASH_REMATCH[1]}"
			local sitestatus="enabled"
			local sitestatuscolor="$TTYGREEN"
			local siteservers=

			if ! is_site_enabled "$fullsitename"; then
				sitestatus="disabled"
				sitestatuscolor="$TTYRED"
			fi

			if [ $printgroup -eq 1 ] && [ "$groupname" != "-" ]; then
				echo -e "${TTYWHITEBOLD}${groupname}${TTYRESET}/"
				indent="  "
				printgroup=0
			fi

			[ $GETOPT_SIMPLESTATUS -eq 0 ] || siteservers=$(get_site_server_names "$fullsitename")

			printf "%-20s %b%-10s%b %s\n" "${indent}${sitename}" "$sitestatuscolor" "$sitestatus" "$TTYRESET" "$siteservers"
		done
	done
}

# Set AVAIL and ENABLED directory variables
function set_sites_dirs()
{
	NGINX_DIR_CONF=$(dirname "$NGINX_CONF")

	# Parse configuration file comments for directory settings
	NGINX_SITES_DIR_AVAIL=$(awk '/^#[[:space:]]+nginx-sites-available-dir[[:space:]]+/ { print $3 }' "$NGINX_CONF" | tail -n1 | tr -d "[:space:]")
	NGINX_SITES_DIR_ENABLED=$(awk '/^#[[:space:]]+nginx-sites-enabled-dir[[:space:]]+/ { print $3 }' "$NGINX_CONF" | tail -n1 | tr -d "[:space:]")

	# Set defaults if necessary
	[ -n "$NGINX_SITES_DIR_AVAIL" ] || NGINX_SITES_DIR_AVAIL="$NGINX_DIR_CONF/sites-available"
	[ -n "$NGINX_SITES_DIR_ENABLED" ] || NGINX_SITES_DIR_ENABLED="$NGINX_DIR_CONF/sites-enabled"

	# Verify available sites directory at this point
	[ -d "$NGINX_SITES_DIR_AVAIL" ] || exit_gen_error "Available sites: $NGINX_SITES_DIR_AVAIL: No such directory"
	[ -r "$NGINX_SITES_DIR_AVAIL" ] || exit_gen_error "Available sites: $NGINX_SITES_DIR_AVAIL: Read permission denied"
}

# Print version and exit
function version()
{
	echo "nginx-sites $NGINX_SITES_VER"
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
	echo "Simple tool to manage nginx sites."
	echo
	echo "Usage: nginx-sites [--help|-h] [--version|-V]"
	echo "   or: nginx-sites [OPTION]... list [--prefixroot] [group <group>]... [enabled|disabled]"
	echo "   or: nginx-sites [OPTION]... status [--oneline] [<site>...]"
	echo "   or: nginx-sites [OPTION]... enable <site>..."
	echo "   or: nginx-sites [OPTION]... disable <site>..."
	echo
	echo "Options:"
	echo "  -c FILE        Override default configuration file"
	echo "  -h, --help     Show this help and exit"
	echo "  -n             Dry run; do not change configuration"
	echo "  -q             Quiet; do not write anything to standard output; implies -y"
	echo "  -r             Reload nginx if status changes are made"
	echo "  -R             Restart nginx if status changes are made"
	echo "  -s             Show simple status; do not show server names or ports"
	echo "  -t             Test nginx configuration after status changes are made"
	echo "  -T             Text only, no color"
	echo "  -v             Increase verbosity (can specify more than once)"
	echo "  -V, --version  Print version and exit"
	echo "  -y             Answer yes for all questions"
	echo
	echo "Report bugs to <https://github.com/lovette/nginx-tools/issues>"

	exit 0
}

##########################################################################
# Commands

# cmd_list(command args)
#
# list [group <group>]... [enabled|disabled]
function cmd_list()
{
	local selectgroups=( )
	local filterstatus=
	local allgroups=( )
	local ordergroupname=
	local groupname=
	local sitename=
	local rootprefix=

	# Parse command arguments
	while (($#))
	do
		case "$1" in
		"--prefixroot")
			rootprefix="-/"
			;;
		"compgen")
			shift
			local cword=$1
			shift
			local words=( "$@" )
			local cur="${words[cword]}"
			local prev="${words[cword-1]}"
			local opts=""
			local optsgroupregex=" (enabled|disabled) "

			case "$prev" in
			"list")
				if [[ "${cur}" = -* ]]; then
					opts="--prefixroot"
				else
					opts="group enabled disabled"
				fi;;
			"group")
				opts=$(enum_groups);;
			"enabled")
				opts="group";;
			"disabled")
				opts="group";;
			*)
				opts="group"; [[ "${words[@]}" =~ $optsgroupregex ]] || opts="$opts enabled disabled";;
			esac

			echo "$opts"
			exit 0
			;;
		"group")
			shift;
			[ $# -ge 1 ] || exit_arg_error "missing group name"
			groupname=${1%%/}
			is_group "$groupname" || exit_nosite_error "$groupname: No such group"
			selectgroups=( ${selectgroups[@]} "$groupname" )
			;;
		"enabled")
			[ -z "$filterstatus" ] || exit_arg_error "ambiguous status filter"
			filterstatus="$1"
			;;
		"disabled")
			[ -z "$filterstatus" ] || exit_arg_error "ambiguous status filter"
			filterstatus="$1"
			;;
		*)
			exit_arg_error "illegal command argument -- $1"
			;;
		esac
		shift
	done

	allgroups=( $(enum_groups) )
	[ $? -eq 0 ] || exit $?

	if [ ${#selectgroups[@]} -gt 0 ]; then
		# Remove duplicates
		selectgroups=( $(echo "${selectgroups[@]}" | tr " " "\n" | sort -u) )
	else
		# No arguments=all
		selectgroups=( "${allgroups[@]}" )
	fi

	# For this command no output is not an error condition
	[ ${#selectgroups[@]} -gt 0 ] || exit 0

	# We do this loop-inside-a-loop thing to ensure that the
	# group output order is consistent across commands
	for ordergroupname in "${allgroups[@]}"
	do
		for groupname in "${selectgroups[@]}"
		do
			local sites

			[ "$ordergroupname" = "$groupname" ] || continue;

			sites=$(enum_sites "$groupname/*" 0)
			[ $? -eq 0 ] || exit $?

			for sitename in $sites
			do
				local status="enabled"

				is_site_enabled "$groupname" "$sitename" || status="disabled"

				if [ -z "$filterstatus" ] || [ "$filterstatus" = "$status" ]; then
					if [ "$groupname" = "-" ]; then
						echo "${rootprefix}${sitename}"
					else
						echo "${groupname}/${sitename}"
					fi
				fi
			done
		done
	done

	exit 0
}

# cmd_status(command args)
#
# status [<site>...]
function cmd_status()
{
	local selectsites=( )
	local optselectall=0
	local isfiltered=0
	local sitesenabled=0
	local sitesdisabled=0
	local site=
	local optoneline=0

	# Parse command arguments
	while (($#))
	do
		case "$1" in
		"--oneline")
			optoneline=1
			;;
		"compgen")
			shift
			local cword=$1
			shift
			local words=( "$@" )
			local cur="${words[cword]}"
			local prev="${words[cword-1]}"
			local opts=""

			case "$prev" in
			"status")
				if [[ "${cur}" = -* ]]; then
					opts="--oneline"
				else
					opts="all group $(cmd_list)"
				fi;;
			"all") opts="";;
			"group") opts=$(enum_groups);;
			*) opts="group $(cmd_list)";;
			esac

			echo "$opts"
			exit 0
			;;
		"all")
			[ $isfiltered -eq 0 ] || exit_arg_error "ambiguous site selection"
			optselectall=1
			;;
		"group")
			shift;
			local groupname=${1%%/}
			[ $optselectall -eq 0 ] || exit_arg_error "ambiguous site selection"
			[ $# -ge 1 ] || exit_arg_error "missing group name"
			is_group "$groupname" || exit_nosite_error "$groupname: No such group"
			selectsites=( ${selectsites[@]} $(enum_sites "$groupname/*" 1) )
			[ $? -eq 0 ] || exit $?
			isfiltered=1
			;;
		*)
			[ $optselectall -eq 0 ] || exit_arg_error "ambiguous site selection"
			selectsites=( ${selectsites[@]} $(resolve_sitespec "$1") )
			[ $? -eq 0 ] || exit_nosite_error "$1: No such site or group"
			isfiltered=1
			;;
		esac
		shift
	done

	if [ $isfiltered -eq 1 ]; then
		# Remove duplicates
		selectsites=( $(echo "${selectsites[@]}" | tr " " "\n" | sort -u) )
		[ ${#selectsites[@]} -gt 0 ] || exit_nomatch_error "No sites matched"
	else
		# No arguments=all
		selectsites=( $(cmd_list --prefixroot) )
		[ $? -eq 0 ] || exit $?
		[ ${#selectsites[@]} -gt 0 ] || exit_nomatch_error "No sites available"
	fi

	# Count enabled sites
	for site in "${selectsites[@]}"
	do
		is_site_enabled "$site" && sitesenabled=$(( sitesenabled+1 ))
	done

	sitesdisabled=$(( ${#selectsites[@]} - $sitesenabled ))

	if [ $optoneline -eq 1 ]; then
		echo -e "$sitesenabled of ${#selectsites[@]} $(pluralize ${#selectsites[@]} "site is" "sites are") ${TTYGREEN}enabled${TTYRESET}"
	else
		print_sites_status_grid "${selectsites[@]}"

		# Print a total summary
		echo
		echo -e "$sitesenabled $(pluralize $sitesenabled site sites) ${TTYGREEN}enabled${TTYRESET}"
		echo -e "$sitesdisabled $(pluralize $sitesdisabled site sites) ${TTYRED}disabled${TTYRESET}"
	fi

	# Exit code signals site status
	[ $sitesdisabled -eq 0 ] && exit $EXIT_STATUS_ENABLED
	[ $sitesenabled -eq 0 ] && exit $EXIT_STATUS_DISABLED
	exit 0
}

# cmd_enable_disable(boolean, command args)
#
# enable  <site>...
# disable <site>...
function cmd_enable()
{
	local optenablesite=$1
	local curstatus="disabled"
	local newstatus="enabled"
	local optselectall=0
	local isfiltered=0
	local selectsites=( )
	local newstatuscolor="$TTYGREEN"

	# First argument is internal enable/disable boolean
	shift

	if [ $optenablesite -eq 0 ]; then
		curstatus="enabled"
		newstatus="disabled"
	fi

	[ "$newstatus" = "enabled" ] || newstatuscolor="$TTYRED"

	# Parse command arguments
	while (($#))
	do
		case "$1" in
		"compgen")
			shift
			local cword=$1
			shift
			local words=( "$@" )
			local prev="${words[cword-1]}"
			local opts=""

			case "$prev" in
			"enable") opts="all group $(cmd_list $curstatus)";;
			"disable") opts="all group $(cmd_list $curstatus)";;
			"all") opts="";;
			"group") opts=$(enum_groups);;
			*) opts="group $(cmd_list $curstatus)";;
			esac

			echo "$opts"
			exit 0
			;;
		"all")
			[ $isfiltered -eq 0 ] || exit_arg_error "ambiguous site selection"
			optselectall=1
			;;
		"group")
			shift;
			local groupname=${1%%/}
			[ $optselectall -eq 0 ] || exit_arg_error "ambiguous site selection"
			[ $# -ge 1 ] || exit_arg_error "missing group name"
			is_group "$groupname" || exit_nosite_error "$groupname: No such group"
			selectsites=( ${selectsites[@]} $(enum_sites "$groupname/*" 1) )
			[ $? -eq 0 ] || exit $?
			isfiltered=1
			;;
		*)
			[ $optselectall -eq 0 ] || exit_arg_error "ambiguous site selection"
			selectsites=( ${selectsites[@]} $(resolve_sitespec "$1") )
			[ $? -eq 0 ] || exit_nosite_error "$1: No such site or group"
			isfiltered=1
			;;
		esac
		shift
	done

	if [ ! -d "$NGINX_SITES_DIR_ENABLED" ]; then
		/bin/mkdir -p "$NGINX_SITES_DIR_ENABLED"
		[ $? -eq 0 ] || exit_gen_error
	fi

	[ -w "$NGINX_SITES_DIR_ENABLED" ] || exit_gen_error "Enabled sites: $NGINX_SITES_DIR_ENABLED: Write permission denied"

	if [ $isfiltered -eq 1 ]; then
		# Remove duplicates
		selectsites=( $(echo "${selectsites[@]}" | tr " " "\n" | sort -u) )
		[ ${#selectsites[@]} -gt 0 ] || exit_nomatch_error "No sites matched"
	elif [ $optselectall -eq 1 ]; then
		selectsites=( $(cmd_list --prefixroot) )
		[ $? -eq 0 ] || exit $?
		[ ${#selectsites[@]} -gt 0 ] || exit_nomatch_error "No sites available"
	else
		exit_arg_error "missing site selection"
	fi

	if [ $optenablesite -eq 0 ] && [ $optselectall -eq 1 ]; then
		# This is the "disable all" branch. It is a special case where we delete
		# ALL files in the ENABLED directory to ensure orphaned sites
		# (sites that are no longer in the AVAIL directory) are disabled too

		local unlinkpaths=( )

		unlinkpaths=( $(enum_enabled_paths) )
		[ $? -eq 0 ] || exit $?

		if [ ${#unlinkpaths[@]} -eq 0 ]; then
			echo "No sites are enabled"
			exit 0
		fi

		if [ $GETOPT_PROMPT -eq 1 ]; then
			echo -e "${#unlinkpaths[@]} $(pluralize ${#unlinkpaths[@]} site sites) will be ${TTYRED}disabled${TTYRESET}"

			# Prompt for confirmation before making any changes
			read -p "Is this ok [y/N]? " yn
			case "$yn" in
			[Yy]* ) ;;
				* ) exit 0;;
			esac
		fi

		# Unlink enabled sites
		safe_exec "echo ${unlinkpaths[@]} | xargs /bin/rm -f"
		[ $? -eq 0 ] || exit $?

		if [ $GETOPT_PROMPT -eq 0 ]; then
			echo -e "${#unlinkpaths[@]} $(pluralize ${#unlinkpaths[@]} site sites) ${TTYRED}disabled${TTYRESET}"
		fi
	else
		# This is the "disable selected sites " branch

		local siteschanged=( )
		local site=

		# Make list of sites to change
		for site in "${selectsites[@]}"
		do
			local sitestatus="enabled"
			is_site_enabled "$site" || sitestatus="disabled"
			[ "$sitestatus" = "$newstatus" ] || siteschanged=( ${siteschanged[@]} "$site" )
		done

		if [ ${#siteschanged[@]} -eq 0 ]; then
			echo "${#selectsites[@]} $(pluralize ${#selectsites[@]} site sites) already ${newstatus}"
			exit 0
		fi

		local unchanged=$(( ${#selectsites[@]} - ${#siteschanged[@]} ))
		[ $unchanged -gt 0 ] && echo -e "$unchanged $(pluralize $unchanged "site is" "sites are") currently ${newstatuscolor}${newstatus}${TTYRESET}"

		# If prompted for confirmation, show status before changes
		if [ $GETOPT_PROMPT -eq 1 ]; then
			echo
			print_sites_status_grid "${siteschanged[@]}"
			echo
			echo -e "$(pluralize ${#siteschanged[@]} This These) ${#siteschanged[@]} $(pluralize ${#siteschanged[@]} site sites) will be ${newstatuscolor}${newstatus}${TTYRESET}"

			# Prompt for confirmation before making any changes
			read -p "Is this ok [y/N]? " yn
			case "$yn" in
			[Yy]* ) ;;
				* ) exit 0;;
			esac
		fi

		# Change site status
		for site in "${siteschanged[@]}"
		do
			enable_site $optenablesite "$site"
			[ $? -eq 0 ] || exit $?
		done

		# If not prompted for confirmation, show status after changes
		if [ $GETOPT_PROMPT -eq 0 ]; then
			echo -e "The following $(pluralize ${#siteschanged[@]} site "${#siteschanged[@]} sites") changed status:"
			echo
			print_sites_status_grid "${siteschanged[@]}"
			echo
		fi
	fi

	# Test new configuration if necessary
	if [ $GETOPT_NGINX_TEST -eq 1 ]; then
		echo "Testing nginx configuration..."
		service nginx configtest
		[ $? -eq 0 ] || exit_nginx_error "Fix configuration and reload nginx for changes to take effect";
	fi

	# Activate new configuration if necessary
	if [ $GETOPT_NGINX_RELOAD -eq 1 ]; then
		echo "Reloading nginx configuration..."
		service nginx reload
		[ $? -eq 0 ] || exit_nginx_error "Fix configuration and reload nginx for changes to take effect";
	elif [ $GETOPT_NGINX_RESTART -eq 1 ]; then
		echo "Restarting nginx..."
		service nginx restart
		[ $? -eq 0 ] || exit_nginx_error "Fix configuration and reload nginx for changes to take effect";
	else
		echo "Reload nginx for changes to take effect"
	fi

	exit 0
}

##########################################################################
# Main

# Expand glob patterns which match no files to a null string
shopt -s nullglob

# We need to know if any of our pipe commands fail, not just the last one
set -o pipefail

# Check for usage longopts
case "$1" in
	"--help"    ) usage;;
	"--version" ) version;;
esac

# Parse command line options
while getopts "c:hnqrRstTvVy" opt
do
	case $opt in
	c  ) NGINX_CONF=$(getopt_realpath "$OPTARG"); [ $? -eq 0 ] || exit $?;;
	h  ) usage;;
	n  ) GETOPT_DRYRUN=1;;
	q  ) GETOPT_QUIET=1; GETOPT_PROMPT=0; close_stdout;;
	r  ) GETOPT_NGINX_RELOAD=1;;
	R  ) GETOPT_NGINX_RESTART=1;;
	s  ) GETOPT_SIMPLESTATUS=0;;
	t  ) GETOPT_NGINX_TEST=1;;
	T  ) GETOPT_NOCOLOR=1;;
	v  ) (( GETOPT_VERBOSE++ ));;
	V  ) version;;
	y  ) GETOPT_PROMPT=0;;
	\? ) exit_arg_error;;
	esac
done

shift $(($OPTIND - 1))

# First argument is the command
COMMAND="$1"
shift

# Use the default configuration file if none is specified
[ -n "$NGINX_CONF" ] || NGINX_CONF=$(getdefaultconfpath)

# Confirm conf file exists and is readable
[ -f "$NGINX_CONF" ] || exit_gen_error "$NGINX_CONF: Cannot open file for reading (no such file)"
[ -r "$NGINX_CONF" ] || exit_gen_error "$NGINX_CONF: Cannot open file for reading (permission denied)"

set_sites_dirs

if [ $GETOPT_NOCOLOR -eq 1 ]; then
	TTYWHITEBOLD=""
	TTYGREEN=""
	TTYRED=""
	TTYRESET=""
fi

case "$COMMAND" in
	"") exit_arg_error "missing command";;
	"l"|"list") cmd_list "$@";;
	"s"|"status") cmd_status "$@";;
	"e"|"enable") cmd_enable 1 "$@";;
	"d"|"disable") cmd_enable 0 "$@";;
	*) exit_arg_error "illegal command -- $COMMAND";;
esac
