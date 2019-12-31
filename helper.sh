#!/bin/bash




function die
{
	local ERR=$?
	[ $ERR -eq 0 ] && ERR=127
	echo "ERROR: $@" >&2
	exit $ERR
}


function cmd-help
{
}


function cmd-build
{
	local __token
	__token="$1"
	docker build -t sssd/sssd-devel --build-arg UID=$UID -f container/Dockerfile.devel .
	[ "$__token" != "" ] && docker build -t sssd/sssd-devel --build-arg TOKEN="$__token" -f container/Dockerfile.github-runner .
}


function cmd-run
{
	docker-compose run 
}



SUBCOMMAND="$1"
shift 1



case "$SUBCOMMAND" in
	"build" | "help" )
		cmd-$SUBCOMMAND "$@"
		;;
	* )
		cmd-help
		die "Subcommand '$SUBCOMMAND' unknown."
		;;
esac



