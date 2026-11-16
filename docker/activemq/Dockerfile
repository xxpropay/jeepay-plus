FROM eclipse-temurin:17-jre-alpine

ENV ACTIVEMQ_VERSION 5.16.4
ENV ACTIVEMQ apache-activemq-$ACTIVEMQ_VERSION
ENV ACTIVEMQ_HOME /opt/activemq

RUN apk add --no-cache curl netcat-openbsd && \
    mkdir -p /opt && \
    curl -sSL --retry 5 --retry-delay 3 https://archive.apache.org/dist/activemq/$ACTIVEMQ_VERSION/$ACTIVEMQ-bin.tar.gz | tar -xvz -C /opt && \
    ln -s /opt/$ACTIVEMQ $ACTIVEMQ_HOME && \
    addgroup -S activemq && \
    adduser -S -H -G activemq -h $ACTIVEMQ_HOME activemq && \
    chown -R activemq:activemq /opt/$ACTIVEMQ && \
    chown -h activemq:activemq $ACTIVEMQ_HOME

COPY ./activemq.xml $ACTIVEMQ_HOME/conf/activemq.xml

EXPOSE 1883 5672 8161 61613 61614 61616

USER activemq
WORKDIR $ACTIVEMQ_HOME

CMD ["/bin/sh", "-c", "printf 'activemq.username=%s\nactivemq.password=%s\n' \"$ACTIVEMQ_USER\" \"$ACTIVEMQ_PASSWORD\" > conf/credentials.properties && bin/activemq console"]
