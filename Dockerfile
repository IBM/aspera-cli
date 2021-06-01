FROM ruby:2.7.2
ARG gemfile
ARG appdir=/usr/src/app
WORKDIR $appdir
ENV ASCLI_SDK_FOLDER $appdir/sdk
COPY $gemfile aspera-cli.gem
RUN mkdir $appdir/config
RUN gem install aspera-cli.gem
# download ascp
RUN ascli conf ascp install
# create key files
RUN ascli conf ascp info
# cleanup empty conf file
RUN rm -fr ~/.aspera
RUN rm aspera-cli.gem
CMD ["ascli"]
