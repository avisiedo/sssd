#!/bin/bash


function die
{
	local ERR=$?
	[ $ERR -eq 0 ] && ERR=127
	echo "ERROR: $@" >&2
	exit $ERR
}


function not-found-dep
{
	echo "WARNING: $* was not found." >&2
	return 0
}


function cmd-checkdeps
{
	local RET
	RET=0
	for item in docker-compose docker
	do
		which "$item" &>/dev/null || ( not-found-dep "$item" && RET=1 )
	done
	[ $RET -ne 0 ] && die "ERROR: Dependencies not found."
	echo "All dependencies satisfaid" >&2
}


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


function cmd-run
{
	docker-compose -f container/docker-compose.yml run -e UID=$UID --rm sssd-devel "$@"
}


function cmd-shell
{
	docker-compose -f container/docker-compose.yml run -e UID=$UID --rm -w /sssd sssd-devel /bin/bash
}


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


function cmd-cppcheck
{
	return 0
}


function cmd-tests
{
    local __container
	[ -e reports ] || mkdir reports
	RET=0
    __container="$( docker run -d --rm -v $PWD:/sssd -w /sssd -e CMOCKA_MESSAGE_OUTPUT=xml -e LDB_MODULES_PATH=./ldb_mod_test_dir -e LD_LIBRARY_PATH=./.libs sssd/sssd-devel /bin/sleep 3600 )"

    if [ "$*" == "" ]
    then
        for item in test-* test_*_* *-tests *_test *_tests
        do
            [ -e "reports/.$item.xml" ] && echo "Passing $item" && continue
            [ "$item" == "test_ssh_client" ] && echo "Passing $item" && continue  # It needs arguments
            [ "$item" == "dlopen-tests" ] && echo "Passing $item" && continue
            [ "$item" == "stress-tests" ] && echo "Passing $item" && continue     # It takes too much time
            echo -e ">> $item"
            docker exec -it $__container ./$item 1>reports/$item.xml && touch reports/.$item.xml
            RET=$?
            [ $RET -ne 0 ] && break
        done
    else
        for item in "$@"
        do
            echo -e ">> $item"
            docker exec -it $__container ./$item 1>reports/$item.xml && touch reports/.$item.xml
            RET=$?
            [ $RET -ne 0 ] && break
        done
    fi
    docker kill $__container
	return $RET
}


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
	"help" | "build" | "exec" | "run" | "shell" | "checkdeps" )
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
		die "Subcommand $SUBCOMMAND is not recognized."
		;;
esac
