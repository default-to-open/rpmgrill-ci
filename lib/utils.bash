if [ -z ${RPMDIFF_BASH_UTILS_SOURCED+xxx} ]; then
RPMDIFF_BASH_UTILS_SOURCED=true

set -e -u
declare -a __init_exit_todo_list=()
declare -i __init_script_exit_code=0

declare -r UTILS_INITIAL_PWD=$(pwd -P)
declare -r UTILS_SCRIPT_CMD=$0
declare -r UTILS_SCRIPT_PATH=$(readlink -f "$0")
declare -r UTILS_SCRIPT_FILENAME=$(basename "$0")

declare -r UTILS_DIR=$(readlink -f ${BASH_SOURCE[0]%/*})

declare -r RED='\e[31m'
declare -r GREEN='\e[32m'
declare -r YELLOW='\e[33m'
declare -r BLUE='\e[34m'
declare -r MAGENTA='\e[35m'
declare -r CYAN='\e[36m'
declare -r WHITE='\e[37m'

declare -r BOLD='\e[1m'
declare -r RESET='\e[0m'

log() {
    echo -e "$@ $RESET"
}

log.debug() {
    local caller_file=${BASH_SOURCE[1]##*/}
    local caller_line=${BASH_LINENO[0]}

    local caller_info="${WHITE}$caller_file${BLUE}(${caller_line}${BLUE})"
    local caller_fn=""
    if [ ${#FUNCNAME[@]} != 2 ]; then
        caller_fn="${FUNCNAME[1]:+${FUNCNAME[1]}}"
        caller_info+=" ${GREEN}$caller_fn"
    fi
    log "${YELLOW}DEBUG:${RESET} $caller_info $RESET: $@" >&2
}

log.info() {
    log "$GREEN${BOLD}INFO:$RESET" "$@"
}


log.warn() {
    log "${RED}WARNING:$RESET" "$@"
}


log.error() {
    log "$RED${BOLD}ERROR:$RESET" "$@"
}


debug.print_callstack() {

    log $BOLD${RED} \
        "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
        "\nTraceback ... \n"
        "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

    local cs_depth=$(( ${#BASH_SOURCE[@]} - 1 ))
    local i=0;
    pushd ${UTILS_INITIAL_PWD} >/dev/null
    for (( i=$cs_depth; i >= 2; i-- )); do
        local cs_file=${BASH_SOURCE[i]}
        local cs_fn=${FUNCNAME[i]}
        local cs_line=${BASH_LINENO[i-1]}

        # extract the line from the file
        local line=$(sed -n "${cs_line}{s/^ *//;p}" "$cs_file")

        local trim_pwd=${cs_file/$SCRIPT_DIR/.}   ### replace pwd with .
        log "  $trim_pwd[$cs_line]:" "$cs_fn:\t" "$line"
    done

    popd >/dev/null

    log "${RED}~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
}

# on_exit_handler <exit-value>
_on_exit_handler() {
    # store the script exit code to be used later
    __init_script_exit_code=${1:-0}

    # print callstack
    test $__init_script_exit_code -eq 0 || debug.print_callstack

    echo "Exit cleanup ... ${__init_exit_todo_list[@]} "
    for cmd in "${__init_exit_todo_list[@]}" ; do
        echo "    running: $cmd"
        # run commands in a subshell so that the failures
        # can be ignored
        ($cmd) || {
            local cmd_type=$(type -t $cmd)
            local cmd_text="$cmd"
            local failed="FAILED"
            echo "    $cmd_type: $cmd_text - $failed to execute ..."
        }
    done
}

on_exit() {
    local cmd="$*"

    local n=${#__init_exit_todo_list[*]}
    if [[ $n -eq 0 ]]; then
        trap '_on_exit_handler $?' EXIT
        __init_exit_todo_list=("$cmd")
    else
        __init_exit_todo_list=("$cmd" "${__init_exit_todo_list[@]}") #execute in reverse order
    fi
}

utils.print_result() {
    local exit_code=$__init_script_exit_code
    if [[  $exit_code == 0 ]]; then
        log.info "$UTILS_SCRIPT_CMD: ${GREEN}PASSED${RESET}"
    else
        log.error "$UTILS_SCRIPT_CMD: $BOLD${RED}FAILED${RESET}" \
             " -   exit code: [ ${RED}$exit_code${RESET} ]"
    fi
}

execute() {
  log.info "Running:${BOLD}$BLUE $@ $RESET"
  ${DRY_RUN:-false} || "$@"
}

### mute_success <command> <to> <run>
### Print the arguments passed and runs it as it is a command and
### prints the output only if there is a failure
### so successful execution of command results in no output
mute_success() {
    echo "Running: $@"

    local exit_code=0
    local output=''         # must be on a separate line otherwise local
                            # overrides the exit code
    output=$($@ 2>&1)  || exit_code=$?

    test $exit_code -ne 0 && {
        echo "ERROR: $@ failed"
        echo "-----------------------------------------------------"
        echo "$output"
        echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    }
    return $exit_code
}

# script._poll_parent timeout interval
#
# polls if the parent process $$ exists at every <interval>
# until <timeout>.
# returns:
#   0 if parent process isn't found
#   1 if it exists
script._poll_parent() {
    local -i timeout=$1; shift
    local -i interval=${1:-1}

    if [[ $interval -gt $timeout ]]; then
        interval=$(($timeout - 1))
    fi

    local -i slept=1
    while [[ $slept -lt $timeout ]]; do
        sleep $interval
        kill -s 0 $$ 2>/dev/null || return 0
        slept=$((slept + $interval))

        if [[ $(($slept + $interval)) -gt $timeout ]]; then
            interval=$(($timeout - $slept))
        fi
    done
    return 1
}


#script.set_timeout <soft-timeout> [hard-timeout] [timeout-handler]
# sends HUP after soft-timeout and then KILL if process doesn't
# exit after <hard-timeout>
# hard-timeout  [ default: 30 seconds ]
script.set_timeout() {
    local -i soft_timeout=$1; shift
    local -i hard_timeout=${1:-30}
    [[ $# -ge 1 ]] && shift

    _timeout_handler() { exit 1; }

    local handler=${1:-'_timeout_handler'}
    [[ $# -ge 1 ]] && shift

    trap  "$handler $@" SIGHUP
    (
        script._poll_parent $soft_timeout 4 && exit 0

        log.warn "$RED${BOLD}$BINGO_SCRIPT_FILE $RESET" \
            "timed out after $soft_timeout;" \
            "sending ${RED}SIGHUP$RESET to cleanup"
        kill -s HUP $$

        script._poll_parent $hard_timeout && exit 0

        log.warn "$RED${BOLD}$BINGO_SCRIPT_FILE $RESET" \
            "did not finish cleaning up in $hard_timeout;" \
            "sending ${RED}SIGKILL$RESET to $$"
        kill -s KILL $$
    )&
}

time.to_seconds () {
    IFS=: read h m s <<< "$1"
    #echo "h: $h | m: $m | s: $s"
    [[ -z $s ]] && [[ -z $m ]] && { s=$h; h=; }
    [[ -z $s ]] && { s=$m; m=; }
    [[ -z $m ]] && { m=$h; h=; }
    #echo "h: $h | m: $m | s: $s"
    echo $(( 10#$h * 3600 + 10#$m * 60 + 10#$s ))
}

is_function() {
    local method=$1; shift
    [[ $(type -t $method) == "function" ]]
}

is_defined() {
    local v=$1; shift
    [[ -v $v ]]
}

is_empty() {
    local var_name=$1; shift
    ! is_defined $var_name || test -z "${!var_name}"
}

is_dir() {
    local path=$1; shift
    [[ -d "$path" ]]
}

is_file() {
    local path=$1; shift
    [[ -f "$path" ]]
}

is_present() {
    type "$1" > /dev/null 2>&1
}

is_python_package_installed() {
    /usr/bin/python -c "import $1" 2>/dev/null
}


str.to_lower() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

str.to_upper() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
}


usage() {
    local exit_val=${1:-1}

    # use stdout if exit value is 0 else stderr
    if [[ $exit_val -eq 0 ]]; then
        print_usage
    else
        print_usage  >&2
    fi
    exit $exit_val
}

fi # RPMDIFF_BASH_UTILS_SOURCED
