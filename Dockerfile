FROM swift:5.5.2-amazonlinux2

# START: Must Add To Custom Docker Image
ADD ./support-files/aws-lambda-rie-arm64 /usr/local/bin/aws-lambda-rie
ADD ./support-files/bash-entry.sh /bash-entry.sh
RUN chmod +x /bash-entry.sh
RUN chmod +x /usr/local/bin/aws-lambda-rie
# Set The Enviorment variable IGNORE_LAMBDA=1, to run as a regular script
# Alternatively, you can customize your entrypoint
ENTRYPOINT ["/bash-entry.sh"]
# END: Must Add To Custom Docker Image

# Add Your Code, Customize your build, maybe do unit tests, up to you
ADD . /code
WORKDIR /code
RUN mkdir -p .lambda-build
RUN swift build --build-path .lambda-build -c release && rm -rf /code/.swiftpm
CMD ["/code/.lambda-build/release/LambdaRuntimeAPIDemo"]
