FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -B
COPY src ./src
RUN mvn package -DskipTests -B

FROM tomcat:10.1-jdk17

ARG SCOUTER_VERSION=2.20.0

# Scouter Java Agent 설치
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/* \
    && curl -fSL "https://github.com/scouter-project/scouter/releases/download/v${SCOUTER_VERSION}/scouter-all-${SCOUTER_VERSION}.tar.gz" \
       -o /tmp/scouter.tar.gz \
    && mkdir -p /opt/scouter \
    && tar -xzf /tmp/scouter.tar.gz -C /opt/scouter --strip-components=1 \
    && rm /tmp/scouter.tar.gz

RUN rm -rf /usr/local/tomcat/webapps/*
COPY --from=build /app/target/app.war /usr/local/tomcat/webapps/ROOT.war

EXPOSE 8080
CMD ["catalina.sh", "run"]
