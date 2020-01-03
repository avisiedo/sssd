#!/bin/bash

cppcheck --force --enable=information -I ./ -I src/ -i src/shared/ --std=c99 --enable=all --suppress=missingIncludeSystem --xml "$@" 2>reports/cppcheck.xml
