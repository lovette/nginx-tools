_nginx_sites()
{
	local cur prev opts cmd i max

	COMPREPLY=()
	cur="${COMP_WORDS[COMP_CWORD]}"
	prev="${COMP_WORDS[COMP_CWORD-1]}"
	cmd=""

	# Search for a command, skipping options, paths, etc.
	for (( i=1, max="${#COMP_WORDS[@]}"; i < max; i++ ))
	do
		[[ "${COMP_WORDS[$i]}" =~ ^(list|status|enable|disable)$ ]] || continue
		cmd="${COMP_WORDS[$i]}"
		break
	done

	# If we have a command, let it handle the request
	if [ -n "$cmd" ]; then
		opts=$(nginx-sites "${cmd}" compgen "$COMP_CWORD" "${COMP_WORDS[@]}" 2> /dev/null)
		[ $? -eq 0 ] || return $?
		COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )  
		return 0
	fi

	# Filename completions
	if [ "${prev}" = "-c" ]; then
		COMPREPLY=( $(compgen -f -- "${cur}") )

		if [ ${#COMPREPLY[@]} -gt 0 ]; then
			# This turns on -o filenames so a space doesn't get added after the initial
			# path completion. This option isn't enabled in the 'complete' call because
			# group names look like path names and those completions get munged if it's on.
			type compopt &>/dev/null && compopt -o filenames 2>/dev/null || \
				compgen -f /non-existing-dir/ >/dev/null
		fi

		return 0
	fi

	# Expand longopts
	if [[ "${cur}" = -* ]]; then
		opts="--help --version"
		COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )  
		return 0
	fi

	# If nothing else, show available commands
	opts="enable disable list status"
	COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )  
	return 0
}

complete -F _nginx_sites nginx-sites
