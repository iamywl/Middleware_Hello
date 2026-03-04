FROM eclipse-temurin:11-jre

ARG SCOUTER_VERSION=2.20.0

RUN apt-get update && apt-get install -y curl unzip && rm -rf /var/lib/apt/lists/* \
    && curl -fSL "https://github.com/scouter-project/scouter/releases/download/v${SCOUTER_VERSION}/scouter-all-${SCOUTER_VERSION}.tar.gz" \
       -o /tmp/scouter.tar.gz \
    && mkdir -p /opt/scouter \
    && tar -xzf /tmp/scouter.tar.gz -C /opt/scouter --strip-components=1 \
    && rm /tmp/scouter.tar.gz

COPY server.conf /opt/scouter/server/conf/scouter.conf

WORKDIR /opt/scouter/server
EXPOSE 6100 6180

CMD ["java", "-Xmx512m", "-classpath", "./scouter-server-boot.jar", "scouter.boot.Boot", "./lib"]
