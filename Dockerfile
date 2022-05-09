# Add Your Code, Customize your build, maybe do unit tests, up to you
FROM swift:5.5.2-xenial AS build
ADD . /code
WORKDIR /code
RUN mkdir -p .lambda-build
RUN swift build --build-path .lambda-build -c release

# Copy just the executable into the container
FROM swift:5.5.2-xenial-slim
WORKDIR /
COPY --from=build /code/.lambda-build/release/SystemTestsApp /SystemTestsApp
CMD ["/SystemTestsApp"]