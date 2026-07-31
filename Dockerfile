# syntax=docker/dockerfile:1
#
# Multi-stage build: the JDK and the Maven cache stay in the build stage, so the shipped image
# carries a JRE and the application jar and nothing else.
#
# Base images are pinned by digest. Tags move; digests do not, and a moving base image is the
# difference between a reproducible build and one that quietly changes underneath you. Refresh
# them deliberately with:
#   docker manifest inspect -v <tag> | jq -r '.Descriptor.digest'

# ---------- build ----------
FROM maven:3-eclipse-temurin-26@sha256:d5617b9a6307e1b51dc7c55edf09bacb66f1c91fb861949c34a3a0d4e16bd241 AS build

WORKDIR /build

# Dependencies resolve in their own layer, keyed on pom.xml alone, so source edits do not
# re-download the world.
COPY pom.xml ./
RUN --mount=type=cache,target=/root/.m2 \
    mvn -B -q dependency:go-offline

COPY src ./src
# Tests are deliberately skipped: the integration tests need a Docker daemon, which is not
# available inside the build. CI runs `mvn verify` separately.
RUN --mount=type=cache,target=/root/.m2 \
    mvn -B -q package -DskipTests

# ---------- runtime ----------
FROM eclipse-temurin:25-jre-noble@sha256:2f1da100788559b397bcf48c736169ea5b070bde84e55f203bbee8e83d87a175 AS runtime

LABEL org.opencontainers.image.title="mgo2server" \
      org.opencontainers.image.description="Metal Gear Online 2 server emulator" \
      org.opencontainers.image.source="https://github.com/comradesean/mgo2server" \
      org.opencontainers.image.licenses="MIT"

# Unprivileged runtime user; nothing here needs root.
RUN groupadd --system --gid 1001 mgo2server \
 && useradd --system --uid 1001 --gid mgo2server --no-create-home mgo2server

WORKDIR /app

COPY --from=build --chown=mgo2server:mgo2server /build/target/mgo2server.jar ./mgo2server.jar

USER mgo2server

# Game protocol and web API respectively; both are overridable via MGO2SERVER_GAME_PORT/MGO2SERVER_WEB_PORT.
EXPOSE 5730 8080

ENV JAVA_OPTS="-XX:MaxRAMPercentage=75.0 -XX:+UseZGC"

# Container-aware defaults: let the JVM size the heap from the cgroup limit rather than the host.
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/mgo2server.jar \"$@\"", "--"]

CMD ["game"]
