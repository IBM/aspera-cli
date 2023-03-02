# argument for build: location of gem file and sdk file
ARG gem_file
ARG sdk_file
# based on latest ruby
FROM ruby:3.2.1 as build_beta
# install gem from local build and optional gems
ONBUILD COPY $gem_file aspera-cli.gem
RUN gem install grpc mimemagic aspera-cli.gem && \
  rm aspera-cli.gem && \
  useradd -m -u 1000 -s /bin/bash cliuser
# Ensures that the docker container always start with this user
USER cliuser
# The default dir when starting the docker container. 
WORKDIR /home/cliuser
# set SDK location in container
ENV ASCLI_SDK_FOLDER=/home/cliuser/.aspera/sdk
# SDK
COPY $sdk_file sdk.zip
# install SDK, create key files and check that ascp works
RUN mkdir -p .aspera/ascli .aspera/sdk && \
  ascli conf ascp install --sdk-url=file:///sdk.zip && \
  rm -f sdk.zip && \
  ascli conf ascp info
ENTRYPOINT ["ascli"]
CMD ["help"]
