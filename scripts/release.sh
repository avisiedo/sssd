#!/bin/bash

function config()
{
    autoreconf -i -f || return $?
    ./configure
}

SAVED_PWD=$PWD
version=`head -n1 VERSION`
tag=$(echo ${version} | tr "." "_")

trap "cd $SAVED_PWD; rm -rf sssd-${version} sssd-${version}.tar" EXIT

git archive --format=tar --prefix=sssd-${version}/ sssd-${tag} > sssd-${version}.tar
if [ $? -ne 0 ]; then
    echo "Cannot perform git-archive, check if tag $tag is present in git tree"
    exit 1
fi
tar xf sssd-${version}.tar

pushd sssd-${version}
config || exit 1
make dist-gzip || exit 1  # also builds docs
popd

mv sssd-${version}/sssd-${version}.tar.gz .
gpg --detach-sign --armor sssd-${version}.tar.gz

