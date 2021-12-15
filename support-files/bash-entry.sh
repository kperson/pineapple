#!/bin/bash

set -x

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
