# based on latest ruby
FROM ruby:3.1.3
# argument for build: location of gem file and sdk file
ARG gemfile
ARG sdkfile
# install gem from local build and optional gems
COPY $gemfile aspera-cli.gem
RUN ["gem","install","grpc","mimemagic","aspera-cli.gem"]
RUN rm aspera-cli.gem
# add user to run cli
RUN useradd -m -u 1000 -s /bin/bash cliuser
# Ensures that the docker container always start with this user
USER cliuser
# The default dir when starting the docker container. 
WORKDIR /home/cliuser
RUN mkdir -p .aspera/ascli .aspera/sdk
# SDK
COPY $sdkfile sdk.zip
# set SDK location in container
ENV ASCLI_SDK_FOLDER=/home/cliuser/.aspera/sdk
# install SDK
RUN ["ascli","conf","ascp","install","--sdk-url=file:///sdk.zip"]
RUN rm -f sdk.zip
# create key files and check that ascp works
RUN ["ascli","conf","ascp","info"]
ENTRYPOINT ["ascli"]
CMD ["help"]
