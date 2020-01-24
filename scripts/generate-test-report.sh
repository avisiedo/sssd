#!/bin/bash

# Run this script from the root path of the repository

for item in "$@"
do
    __test_bin="$( basename $item )"
    [ ! -e "reports/${__test_bin}.xml" ] || rm -f "reports/${__test_bin}i.xml"
    CMOCKA_MESSAGE_OUTPUT=xml CMOCKA_XML_FILE="reports/${__test_bin}.xml" ./${__test_bin} 
done


