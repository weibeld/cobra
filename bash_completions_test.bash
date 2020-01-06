# bash completion for root                                 -*- shell-script -*-

__root_debug()
{
    if [[ -n ${BASH_COMP_DEBUG_FILE} ]]; then
        # -e is necessary for color escape sequences
        echo -e "$*" >> "${BASH_COMP_DEBUG_FILE}"
    fi
}

__root_debug_func_entry() {
    local red='\e[31;1m' blue='\e[34;1m' green='\e[32;1m' reset='\e[0m'
    local wordscopy=("${words[@]}")
    wordscopy["$c"]="$green${words[$c]}$blue"
    __root_debug "$red$1:$reset ${green}c=$c$reset, words=$blue[${wordscopy[@]}]$reset, cur=$cur, cword=$cword, prev=$prev"
}

__root_debug_command_state() {
  local red='\e[31;1m' reset='\e[0m'
     __root_debug "$red$1:$reset
  commands = [${commands[@]}]
  command_aliases = [${command_aliases[@]}]
  flags= [${flags[@]}]
  two_word_flags = [${two_word_flags[@]}]
  local_nonpersistent_flags= [${local_nonpersistent_flags[@]}]
  flags_with_completion = [${flags_with_completion[@]}]
  flags_completion = [${flags_completion[@]}]
  must_have_one_flag = [${must_have_one_flag[@]}]
  must_have_one_noun = [${must_have_one_noun[@]}]
  noun_aliases= [${noun_aliases[@]}]
  aliashash = keys[${!aliashash[@]}] values[${aliashash[@]}]"
}

__root_debug_compreply() {
    local red='\e[31;1m' green='\e[32;1m' reset='\e[0m'
    __root_debug "$red$1:$reset COMPREPLY=$green[${COMPREPLY[@]}]$reset\n"
}


# Homebrew on Macs have version 1.3 of bash-completion which doesn't include
# _init_completion. This is a very minimal version of that function.
__root_init_completion()
{
    COMPREPLY=()
    _get_comp_words_by_ref "$@" cur prev words cword
}

__root_index_of_word()
{
    local w word=$1
    shift
    index=0
    for w in "$@"; do
        [[ $w = "$word" ]] && return
        index=$((index+1))
    done
    index=-1
}

__root_contains_word()
{
    local w word=$1; shift
    for w in "$@"; do
        [[ $w = "$word" ]] && return
    done
    return 1
}

# Called when the cursor word (i.e. the word to be completed) is parsed (c==cword)
__root_handle_reply()
{
    __root_debug_func_entry "${FUNCNAME[0]}"
    case $cur in
        -*)
            if [[ $(type -t compopt) = "builtin" ]]; then
                compopt -o nospace
            fi
            local allflags
            if [ ${#must_have_one_flag[@]} -ne 0 ]; then
                allflags=("${must_have_one_flag[@]}")
            else
                allflags=("${flags[*]} ${two_word_flags[*]}")
            fi
            COMPREPLY=( $(compgen -W "${allflags[*]}" -- "$cur") )
            if [[ $(type -t compopt) = "builtin" ]]; then
                [[ "${COMPREPLY[0]}" == *= ]] || compopt +o nospace
            fi

            # complete after --flag=abc
            if [[ $cur == *=* ]]; then
                if [[ $(type -t compopt) = "builtin" ]]; then
                    compopt +o nospace
                fi

                local index flag
                flag="${cur%=*}"
                __root_index_of_word "${flag}" "${flags_with_completion[@]}"
                COMPREPLY=()
                if [[ ${index} -ge 0 ]]; then
                    PREFIX=""
                    cur="${cur#*=}"
                    ${flags_completion[${index}]}
                    if [ -n "${ZSH_VERSION}" ]; then
                        # zsh completion needs --flag= prefix
                        eval "COMPREPLY=( \"\${COMPREPLY[@]/#/${flag}=}\" )"
                    fi
                fi
            fi
            __root_debug_compreply "${FUNCNAME[0]}"
            return 0;
            ;;
    esac

    # check if we are handling a flag with special work handling
    local index
    __root_index_of_word "${prev}" "${flags_with_completion[@]}"
    if [[ ${index} -ge 0 ]]; then
        ${flags_completion[${index}]}
        __root_debug_compreply "${FUNCNAME[0]}"
        return
    fi

    # we are parsing a flag and don't have a special handler, no completion
    if [[ ${cur} != "${words[cword]}" ]]; then
        __root_debug_compreply "${FUNCNAME[0]}"
        return
    fi

    local completions
    completions=("${commands[@]}")
    if [[ ${#must_have_one_noun[@]} -ne 0 ]]; then
        completions=("${must_have_one_noun[@]}")
    fi
    if [[ ${#must_have_one_flag[@]} -ne 0 ]]; then
        completions+=("${must_have_one_flag[@]}")
    fi
    COMPREPLY=( $(compgen -W "${completions[*]}" -- "$cur") )

    if [[ ${#COMPREPLY[@]} -eq 0 && ${#noun_aliases[@]} -gt 0 && ${#must_have_one_noun[@]} -ne 0 ]]; then
        COMPREPLY=( $(compgen -W "${noun_aliases[*]}" -- "$cur") )
    fi

    if [[ ${#COMPREPLY[@]} -eq 0 ]]; then
		if declare -F __root_custom_func >/dev/null; then
			# try command name qualified custom func
			__root_custom_func
		else
			# otherwise fall back to unqualified for compatibility
			declare -F __custom_func >/dev/null && __custom_func
		fi
    fi

    # available in bash-completion >= 2, not always present on macOS
    if declare -F __ltrim_colon_completions >/dev/null; then
        __ltrim_colon_completions "$cur"
    fi

    # If there is only 1 completion and it is a flag with an = it will be completed
    # but we don't want a space after the =
    if [[ "${#COMPREPLY[@]}" -eq "1" ]] && [[ $(type -t compopt) = "builtin" ]] && [[ "${COMPREPLY[0]}" == --*= ]]; then
       compopt -o nospace
    fi
    __root_debug_compreply "${FUNCNAME[0]}"
}

# The arguments should be in the form "ext1|ext2|extn"
__root_handle_filename_extension_flag()
{
    local ext="$1"
    _filedir "@(${ext})"
}

__root_handle_subdirs_in_dir_flag()
{
    local dir="$1"
    pushd "${dir}" >/dev/null 2>&1 && _filedir -d && popd >/dev/null 2>&1
}

__root_handle_flag()
{
    __root_debug_func_entry "${FUNCNAME[0]}"

    # if a command required a flag, and we found it, unset must_have_one_flag()
    local flagname=${words[c]}
    local flagvalue
    # if the word contained an =
    if [[ ${words[c]} == *"="* ]]; then
        flagvalue=${flagname#*=} # take in as flagvalue after the =
        flagname=${flagname%=*} # strip everything after the =
        flagname="${flagname}=" # but put the = back
    fi
    if __root_contains_word "${flagname}" "${must_have_one_flag[@]}"; then
        must_have_one_flag=()
    fi

    # if you set a flag which only applies to this command, don't show subcommands
    if __root_contains_word "${flagname}" "${local_nonpersistent_flags[@]}"; then
      commands=()
    fi

    # keep flag value with flagname as flaghash
    # flaghash variable is an associative array which is only supported in bash > 3.
    if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
        if [ -n "${flagvalue}" ] ; then
            flaghash[${flagname}]=${flagvalue}
        elif [ -n "${words[ $((c+1)) ]}" ] ; then
            flaghash[${flagname}]=${words[ $((c+1)) ]}
        else
            flaghash[${flagname}]="true" # pad "true" for bool flag
        fi
    fi

    # skip the argument to a two word flag
    if [[ ${words[c]} != *"="* ]] && __root_contains_word "${words[c]}" "${two_word_flags[@]}"; then
			  __root_debug "${FUNCNAME[0]}: found a flag ${words[c]}, skip the next argument"
        c=$((c+1))
        # if we are looking for a flags value, don't show commands
        if [[ $c -eq $cword ]]; then
            commands=()
        fi
    fi

    c=$((c+1))

}

__root_handle_noun()
{
    __root_debug_func_entry "${FUNCNAME[0]}"

    if __root_contains_word "${words[c]}" "${must_have_one_noun[@]}"; then
        must_have_one_noun=()
    elif __root_contains_word "${words[c]}" "${noun_aliases[@]}"; then
        must_have_one_noun=()
    fi

    nouns+=("${words[c]}")
    c=$((c+1))
}

__root_handle_command()
{
    __root_debug_func_entry "${FUNCNAME[0]}"

    local next_command
    if [[ -n ${last_command} ]]; then
        next_command="_${last_command}_${words[c]//:/__}"
    else
        if [[ $c -eq 0 ]]; then
            next_command="_root_root_command"
        else
            next_command="_${words[c]//:/__}"
        fi
    fi
    c=$((c+1))
    declare -F "$next_command" >/dev/null && $next_command
}

__root_handle_word()
{
    __root_debug_func_entry "${FUNCNAME[0]}"
    if [[ $c -ge $cword ]]; then
        __root_handle_reply
        return
    fi
    if [[ "${words[c]}" == -* ]]; then
        __root_handle_flag
    elif __root_contains_word "${words[c]}" "${commands[@]}"; then
        __root_handle_command
    elif [[ $c -eq 0 ]]; then
        __root_handle_command
    elif __root_contains_word "${words[c]}" "${command_aliases[@]}"; then
        # aliashash variable is an associative array which is only supported in bash > 3.
        if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
            words[c]=${aliashash[${words[c]}]}
            __root_handle_command
        else
            __root_handle_noun
        fi
    else
        __root_handle_noun
    fi
    __root_handle_word
}

__root_custom_func() {
	COMPREPLY=( "hello" )
}

_root_cmd__colon()
{
    last_command="root_cmd__colon"

    commands=()
    command_aliases=()
    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()
    must_have_one_flag=()
    must_have_one_noun=()

    noun_aliases=()
    __root_debug_command_state "${FUNCNAME[0]}"
}

_root_echo_times()
{
    last_command="root_echo_times"

    commands=()
    command_aliases=()
    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()
    must_have_one_flag=()
    must_have_one_noun=()

    must_have_one_noun+=("four")
    must_have_one_noun+=("one")
    must_have_one_noun+=("three")
    must_have_one_noun+=("two")
    noun_aliases=()
    __root_debug_command_state "${FUNCNAME[0]}"
}

_root_echo()
{
    last_command="root_echo"

    commands=()
    command_aliases=()
    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()
    must_have_one_flag=()
    must_have_one_noun=()
    commands+=("times")

    flags+=("--config=")
    two_word_flags+=("--config=")
    local_nonpersistent_flags+=("--config=")
    flags_with_completion+=("--config=")
    flags_completion+=("__root_handle_subdirs_in_dir_flag config")
    flags+=("--filename=")
    two_word_flags+=("--filename=")
    local_nonpersistent_flags+=("--filename=")
    flags_with_completion+=("--filename=")
    flags_completion+=("__root_handle_filename_extension_flag json|yaml|yml")
    flags+=("--persistent-filename=")
    two_word_flags+=("--persistent-filename=")
    flags_with_completion+=("--persistent-filename=")
    flags_completion+=("_filedir")
    noun_aliases=()
    __root_debug_command_state "${FUNCNAME[0]}"
}

_root_print()
{
    last_command="root_print"

    commands=()
    command_aliases=()
    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()
    must_have_one_flag=()
    must_have_one_noun=()

    noun_aliases=()
    __root_debug_command_state "${FUNCNAME[0]}"
}

_root_root_command()
{
    last_command="root"

    commands=()
    command_aliases=()
    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()
    must_have_one_flag=()
    must_have_one_noun=()
    commands+=("cmd:colon")
    commands+=("echo")
    if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
        command_aliases+=("say")
        aliashash["say"]="echo"
    fi
    commands+=("print")

    flags+=("--custom=")
    two_word_flags+=("--custom=")
    local_nonpersistent_flags+=("--custom=")
    flags_with_completion+=("--custom=")
    flags_completion+=("__complete_custom")
    flags+=("--filename=")
    two_word_flags+=("--filename=")
    local_nonpersistent_flags+=("--filename=")
    flags_with_completion+=("--filename=")
    flags_completion+=("__root_handle_filename_extension_flag json|yaml|yml")
    flags+=("--filename-ext=")
    two_word_flags+=("--filename-ext=")
    local_nonpersistent_flags+=("--filename-ext=")
    flags_with_completion+=("--filename-ext=")
    flags_completion+=("_filedir")
    flags+=("--introot=")
    flags+=("-i=")
    two_word_flags+=("--introot=")
    two_word_flags+=("-i=")
    local_nonpersistent_flags+=("--introot=")
    local_nonpersistent_flags+=("-i=")
    must_have_one_flag+=("--introot=")
    must_have_one_flag+=("-i=")
    flags+=("--persistent-filename=")
    two_word_flags+=("--persistent-filename=")
    flags_with_completion+=("--persistent-filename=")
    flags_completion+=("_filedir")
    must_have_one_flag+=("--persistent-filename=")
    flags+=("--theme=")
    two_word_flags+=("--theme=")
    local_nonpersistent_flags+=("--theme=")
    flags_with_completion+=("--theme=")
    flags_completion+=("__root_handle_subdirs_in_dir_flag themes")
    flags+=("--two=")
    flags+=("-t=")
    two_word_flags+=("--two=")
    two_word_flags+=("-t=")
    local_nonpersistent_flags+=("--two=")
    local_nonpersistent_flags+=("-t=")
    flags+=("--two-w-default")
    flags+=("-T")
    local_nonpersistent_flags+=("--two-w-default")
    local_nonpersistent_flags+=("-T")
    must_have_one_noun+=("node")
    must_have_one_noun+=("pod")
    must_have_one_noun+=("replicationcontroller")
    must_have_one_noun+=("service")
    noun_aliases=()
    noun_aliases+=("no")
    noun_aliases+=("nodes")
    noun_aliases+=("po")
    noun_aliases+=("pods")
    noun_aliases+=("rc")
    noun_aliases+=("replicationcontrollers")
    noun_aliases+=("services")
    noun_aliases+=("svc")
    __root_debug_command_state "${FUNCNAME[0]}"
}

__start_root()
{
    local cur prev words cword
    declare -A flaghash 2>/dev/null || :
    declare -A aliashash 2>/dev/null || :
    if declare -F _init_completion >/dev/null 2>&1; then
        _init_completion -s || return
    else
        __root_init_completion -n "=" || return
    fi

    local c=0
    local flags=()
    local two_word_flags=()
    local local_nonpersistent_flags=()
    local flags_with_completion=()
    local flags_completion=()
    local commands=("root")
    local must_have_one_flag=()
    local must_have_one_noun=()
    local last_command
    local nouns=()

    __root_handle_word
}

if [[ $(type -t compopt) = "builtin" ]]; then
    complete -o default -F __start_root root
else
    complete -o default -o nospace -F __start_root root
fi

# ex: ts=4 sw=4 et filetype=sh
