#!/bin/bash

##
# Terminate the execution of the script with an error message,
# and use the last errorcode as return code. If the ret code of
# the last operation is Zero, then this is set to the value of 127.
##
function die
{
	local ERR=$?
	[ $ERR -eq 0 ] && ERR=127
	echo "ERROR: $@" >&2
	exit $ERR
}

##
# Write a warning message for a dependency not found.
# $* List of dependencies.
##
function not-found-dep
{
	[ $# -eq 1 ] && echo "WARNING: $* was not found." >&2
	[ $# -gt 1 ] && echo "WARNING: $* were not found." >&2
	return 0
}

##
# Helper to delay a return code which have been got in
# early steps along the script.
##
function delayed-retcode
{
	local __retcode="$1"

	re='^[0-9]+$'
	if ! [[ "$__retcode" =~ $re ]]
	then
		die "$__retcode is not a number"
	fi

	return $__retcode
}

##
# Check docker dependencies only, as the rest of tools are
# inside the docker images.
##
function cmd-checkdeps
{
	local RET
	RET=0
	for item in docker-compose docker
	do
		which "$item" &>/dev/null || ( not-found-dep "$item" && RET=1 )
	done
	[ $RET -eq 0 ] || delayed-retcode $RET || die "Dependencies not found."
	echo "All dependencies satisfaid" >&2
	return 0
}

##
# Build the docker images.
##
function cmd-build
{
	local GID
	GID="$( id -g $USER )"

cat <<EOB
Using build arguments:
  UID=$UID
  GID=$GID
  TOKEN=$TOKEN
  \$*=$*
EOB
	[ "$*" == "" ] && docker-compose -f container/docker-compose.yml build --build-arg UID=$UID --build-arg GID=$GID --build-arg TOKEN=$TOKEN
}

##
# Run a command in a container with the development environment.
# $@ Comand to be run and their arguments.
##
function cmd-run
{
	docker-compose -f container/docker-compose.yml run -e UID=$UID --rm sssd-devel "$@"
}

##
# Open a terminal inside the development environment.
##
function cmd-shell
{
	docker-compose -f container/docker-compose.yml run -e UID=$UID --rm -w /sssd sssd-devel /bin/bash
}


function cmd-rshell
{
	docker-compose -f container/docker-compose.yml run -u root -e UID=$UID --rm -w /sssd sssd-devel /bin/bash
}

##
# Execute a command inside a running container.
##
function cmd-exec
{
	local __options
	local __environment
	local __service
	local __command

	__options=""
	__environment=""
	__service=""
	__command=""

	while true
	do
		case "$1" in
			"-d" | "--detach" | "--privileged" | "-T" )
				__options="${__options} $1"
				shift 1
				;;
			"-u" | "--user" )
				__options="${__options} $1 \"$2\""
				shift 2
				;;
			"-e" | "--env" )
				__environment="${__environment} $1 \"$2\""
				shift 2
				;;
			*)
				break
				;;
		esac
	done

	__service="$1"
	__command="$2"
	shift 2

	docker-compose exec -f container/docker-compose.yml $__options $__environment $__service $__command "$@"
}

##
# Run the static analyzer to create a report with potential bugs.
##
function cmd-cppcheck
{
    local __container
    local __paths
	[ -e reports ] || mkdir reports

    __paths=""
    __paths="$__paths src/db/"
    __paths="$__paths src/confdb/"
    __paths="$__paths src/krb5_plugin/"
    __paths="$__paths src/ldb_modules/"
    __paths="$__paths src/monitor/"
    __paths="$__paths src/p11_child/"
    __paths="$__paths src/providers/"
    __paths="$__paths src/python/"
    __paths="$__paths src/resolv/"
    __paths="$__paths src/responder/"
    __paths="$__paths src/sbus"
    __paths="$__paths src/sss_client"
    __paths="$__paths src/sss_iface"
    #__paths="$__paths src/tests"
    __paths="$__paths src/tools"
    __paths="$__paths src/util"

    docker run --rm -it -v $PWD:/sssd -w /sssd -e CMOCKA_MESSAGE_OUTPUT=xml -e LDB_MODULES_PATH=./ldb_mod_test_dir -e LD_LIBRARY_PATH=./.libs sssd/sssd-devel ./scripts/static-analyzer.sh $__paths
	return 0
}

function cmd-compile
{
	local __container
    __container="$( docker run -d --rm -v $PWD:/sssd -w /sssd -e CMOCKA_MESSAGE_OUTPUT=xml -e LDB_MODULES_PATH=./ldb_mod_test_dir sssd/sssd-devel sleep 3600 )"
	docker exec -it $__container autoreconf -vfi && docker exec -it $__container make all tests
    docker kill $__container
}

##
# Build and run the tests of the project.
# $@ If no arguments, try to launch all the tests found, else try
# the list of tests indicated.
##
function cmd-tests
{
    local __container
	[ -e reports ] || mkdir reports
	RET=0
    __container="$( docker run -d --rm -v $PWD:/sssd -w /sssd -e CMOCKA_MESSAGE_OUTPUT=xml -e LDB_MODULES_PATH=./ldb_mod_test_dir -e LD_LIBRARY_PATH=./.libs sssd/sssd-devel /bin/sleep 3600 )"

    if [ "$*" == "" ]
    then
		# TODO Keep consistency naming the test binaries
        for item in test-* test_*_* *-tests *_test *_tests
        do
            [ -e "reports/.$item.xml" ] && echo "Passing $item" && continue
            [ "$item" == "test_ssh_client" ] && echo "Passing $item" && continue  # It needs arguments
            [ "$item" == "dlopen-tests" ] && echo "Passing $item" && continue
            [ "$item" == "stress-tests" ] && echo "Passing $item" && continue     # It takes too much time
            echo -e ">> $item"
            docker exec -it $__container ./scripts/generate-test-report.sh ./$item && touch reports/.$item.xml
            RET=$?
            [ $RET -ne 0 ] && break
        done
    else
        for item in "$@"
        do
            echo -e ">> $item"
            docker exec -it $__container ./scripts/generate-test-report.sh ./$item && touch reports/.$item.xml
            RET=$?
            [ $RET -ne 0 ] && break
        done
    fi
    docker kill $__container
	return $RET
}

##
# Show an overview of the subcommands supported by this helper script.
##
function cmd-help
{
cat <<EOF
Usage: ./helper.sh subcommand ...
    checkdeps  Check dependencies.
    help       Display this help text.
    build      Build the docker image.
    exec       Execute a command inside the container.
    run        Override entrypoint and run a command in a new container.
    shell      Open a shell inside a new container with the dev environment.
	rshell     Open a root shell.

    cppcheck   Run static analyzer for detecting code smells.
    compile    Compile project inside the development container.
    docs       Generate documentation.
    tests      Build tests and run all of them.
EOF
	return 0
}


SUBCOMMAND="$1"
shift

case "$SUBCOMMAND" in
	"help" | "build" | "exec" | "run" | "shell" | "rshell" | "checkdeps" )
		cmd-$SUBCOMMAND "$@"
		;;
	"cppcheck" | "tests" | "compile" )
		cmd-$SUBCOMMAND
		;;
	"" )
		cmd-help
		die "No subcommand was specified."
		;;
	* )
		die "'$SUBCOMMAND' is not a recognized subcommand."
		;;
esac
