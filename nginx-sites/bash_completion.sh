_nginx_sites()
{
	local cur prev opts cmd

	cur="${COMP_WORDS[COMP_CWORD]}"
	prev="${COMP_WORDS[COMP_CWORD-1]}"
	cmd="${COMP_WORDS[1]}"


	case "${cmd}" in
	list)
		opts=$(nginx-sites "${cmd}" compgen "$COMP_CWORD" "${COMP_WORDS[@]}" 2> /dev/null)
		;;
	status)
		opts=$(nginx-sites "${cmd}" compgen "$COMP_CWORD" "${COMP_WORDS[@]}" 2> /dev/null)
		;;
	enable)
		opts=$(nginx-sites "${cmd}" compgen "$COMP_CWORD" "${COMP_WORDS[@]}" 2> /dev/null)
		;;
	disable)
		opts=$(nginx-sites "${cmd}" compgen "$COMP_CWORD" "${COMP_WORDS[@]}" 2> /dev/null)
		;;
	*)
		if [[ "${cur}" = -* ]]; then
			opts="--help --version"
		else
			opts="enable disable list status"
		fi
		;;
	esac

	COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )  
	return 0
}

complete -F _nginx_sites nginx-sites
