FROM ruby:3.1.1
ARG gemfile
ARG appdir=/usr/src/app
WORKDIR $appdir
ENV ASCLI_SDK_FOLDER $appdir/sdk
COPY $gemfile aspera-cli.gem
RUN mkdir $appdir/config
RUN mkdir /transfer
RUN gem install aspera-cli.gem
RUN gem install grpc
# download ascp
RUN ascli conf ascp install
# create key files
RUN ascli conf ascp info
# cleanup empty conf file
RUN rm -fr ~/.aspera
RUN rm aspera-cli.gem
CMD ["ascli"]
