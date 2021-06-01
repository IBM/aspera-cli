FROM ruby:2.7.2
ARG gemfile
WORKDIR /usr/src/app
COPY $gemfile aspera-cli.gem
RUN mkdir /usr/src/app/config
RUN gem install aspera-cli.gem
RUN ascli conf ascp install
CMD ["ascli"]
