#!/bin/bash

#docker build --target build -t pineapple-cache .

BUILD_DIR=".lambda-build"
if [ -d "$BUILD_DIR" ]; then
    rm -rf $BUILD_DIR
fi