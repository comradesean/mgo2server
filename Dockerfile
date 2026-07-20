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
FROM maven:3.9-eclipse-temurin-25@sha256:4ae259079c38a5544bccdbf874dddc84b6d59cbc13b985576c92d905ba0dcd42 AS build

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
FROM eclipse-temurin:25-jre-noble@sha256:7161e12dbcd2791d1fc8b9cf6f1c1519a84c4acea5706c6a0659bc254a4c55d7 AS runtime

LABEL org.opencontainers.image.title="mgo2server" \
      org.opencontainers.image.description="Metal Gear Online 2 server emulator" \
      org.opencontainers.image.source="https://github.com/comradesean/nomad" \
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
