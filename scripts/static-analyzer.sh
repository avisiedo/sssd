#!/bin/bash

#cppcheck --force --enable=information -I ./ -I src/ -i src/shared/ --std=c99 --enable=all --suppress=missingIncludeSystem --supress=noValidConfiguration --suppress=variableScope --suppress=ConfigurationNotChecked --xml --output-file=reports/cppcheck.xml --language=c -j 2 "$@"
cppcheck --force --enable=information -I ./ -I src/ -i src/shared/ --std=c99 --enable=all --suppress=missingIncludeSystem --suppress=variableScope --suppress=ConfigurationNotChecked --xml --output-file=reports/cppcheck.xml --language=c "$@"
