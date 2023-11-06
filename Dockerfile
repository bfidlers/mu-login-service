FROM semtech/mu-ruby-template:2.11.1

LABEL maintainer="ben.fidlers@gmail.com"

ENV MU_APPLICATION_SALT ''
ENV USERS_GRAPH 'http://mu.semte.ch/application'
ENV SESSIONS_GRAPH 'http://mu.semte.ch/application'
