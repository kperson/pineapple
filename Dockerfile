# Add Your Code, Customize your build, maybe do unit tests, up to you

# https://github.com/apple/swift-package-manager/blob/main/Documentation/Usage.md
FROM swift:5.5.2-xenial AS build
ARG build_config=debug
ADD . /code
WORKDIR /code
RUN mkdir -p .lambda-build
RUN swift build --build-path .lambda-build -c ${build_config}

# Copy just the executable into the container
FROM swift:5.5.2-xenial-slim
ARG build_config=debug
WORKDIR /
COPY --from=build /code/.lambda-build/${build_config}/SystemTestsApp /SystemTestsApp
CMD ["/SystemTestsApp"]