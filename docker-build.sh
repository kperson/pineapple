#!/bin/bash

# docker-build.sh - Two-stage Docker build with local artifact extraction
#
# Usage: ./docker-build.sh pineapple
#
# What it does:
# 1. Cache stage: Creates build cache image with Swift dependencies
# 2. Runtime stage: Creates final Lambda runtime image  
# 3. Extract artifacts: Copies build artifacts to local .lambda-build/ directory
#
# Parameters:
# - $1: Base container name (creates {name}-cache and {name} images)
#
# Benefits:
# - Preserves Swift build cache between runs
# - Extracts compiled binaries for local testing
# - Enables faster subsequent builds by reusing dependencies

# Set up container names and paths
cache_container="$1-cache"
container=$1
build_dir=".lambda-build"
curr_dir=$(pwd)
build_dir_full_path="$curr_dir/$build_dir"

# Enable command tracing for debugging
set -o xtrace

# Build cache image (contains Swift dependencies and compiled code)
docker build --target build -t $cache_container .

# Build final runtime image (lightweight Lambda container)
docker build -t $container .

# Clean up any existing build directory
if [ -d "$build_dir_full_path" ]; then
     rm -rf $build_dir_full_path
fi
mkdir -p $build_dir_full_path

# Disable command tracing
set +o xtrace