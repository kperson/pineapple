#!/bin/bash

cache_container="$1-cache"
container=$1
build_dir=".lambda-build"
curr_dir=$(pwd)
build_dir_full_path="$curr_dir/$build_dir"

set -o xtrace

docker build --target build -t $cache_container .
docker build -t $container .

if [ -d "$build_dir_full_path" ]; then
     rm -rf $build_dir_full_path
fi
mkdir -p $build_dir_full_path

docker run --rm -it -v $build_dir_full_path:/out/.lambda-build $cache_container cp -R /code/.lambda-build /out
set +o xtrace