# Add Your Code, Customize your build, maybe do unit tests, up to you
FROM swift:5.5.2-xenial AS build
ADD . /code
WORKDIR /code
RUN mkdir -p .lambda-build
RUN swift build --build-path .lambda-build -c release

# Decide on a Base Image for Execution (this is a multi-stage build)
# https://docs.docker.com/develop/develop-images/multistage-build/
FROM swift:5.5.2-xenial-slim
ADD ./support-files/aws-lambda-rie-arm64 /usr/local/bin/aws-lambda-rie
ADD ./support-files/bash-entry.sh /bash-entry.sh
RUN chmod +x /bash-entry.sh
RUN chmod +x /usr/local/bin/aws-lambda-rie
# Set The Enviorment variable IGNORE_LAMBDA=1, to run as a regular script
# Alternatively, you can customize your entrypoint
ENTRYPOINT ["/bash-entry.sh"]

# Copy just the executable into the container
WORKDIR /
COPY --from=build /code/.lambda-build/release/LambdaVaporDemo /LambdaVaporDemo
CMD ["/LambdaVaporDemo"]