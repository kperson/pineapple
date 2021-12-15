#!/bin/sh

docker compose build
rm -rf .lambda-build
docker run -e IGNORE_LAMBDA=1 --rm -it -v $(pwd)/.lambda-build:/build-copy pineapple_runtime-api-test:latest /bin/sh -c "cp -R /code/.lambda-build/* /build-copy"