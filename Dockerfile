FROM ruby:3.1.1
# argument for build: location of gem file
ARG gemfile
# in container, by default store CLI files in a specific folder, not user's home
ARG appdir=/usr/src/app
WORKDIR $appdir
# replaces ~/.aspera/ascli/sdk
ENV ASCLI_SDK_FOLDER $appdir/sdk
# replaces ~/.aspera/ascli
RUN mkdir $appdir/config
# this folder can be mounted as volume
RUN mkdir /transfer
# install gem from local build
COPY $gemfile aspera-cli.gem
RUN gem install aspera-cli.gem
RUN rm aspera-cli.gem
# install optional gems
RUN gem install grpc
RUN gem install mimemagic
# install SDK
RUN ascli conf ascp install
# create key files
RUN ascli conf ascp info
# cleanup empty conf file
RUN rm -fr ~/.aspera
CMD ["ascli"]
