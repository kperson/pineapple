#!/bin/bash

set -x

#unset LD_LIBRARY_PATH
#unset PYTHONPATH
#unset NODE_PATH
#unset CLASSPATH
#unset RUBYLIB
#unset GEM_PATH
#export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
#printenv

if [ "${IGNORE_LAMBDA}" = "1" ]; then
    echo 'Treating As Regular Script'
    exec "$@"
else
    if [ -z "${AWS_LAMBDA_RUNTIME_API}" ]; then
        echo 'Using Lambda Runtime Emulator'
      exec /usr/local/bin/aws-lambda-rie "$@"
    else
        echo 'Running Lambda'
        exec "$@"
    fi
fi
