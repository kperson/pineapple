# Multi-stage build for AWS Lambda with Swift 6.1
FROM swift:6.1-amazonlinux2 AS build
ARG build_config=release
WORKDIR /code
COPY . .

# Build the Lambda function
RUN swift build --build-path .lambda-build -c ${build_config} --static-swift-stdlib

# Runtime stage using AWS Lambda base image
FROM public.ecr.aws/lambda/provided:al2023
ARG build_config=release

# Copy the built executable as bootstrap (required by Lambda runtime)
COPY --from=build /code/.lambda-build/${build_config}/LambdaHandler ${LAMBDA_RUNTIME_DIR}/bootstrap

# Make bootstrap executable
RUN chmod +x ${LAMBDA_RUNTIME_DIR}/bootstrap