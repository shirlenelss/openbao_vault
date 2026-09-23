FROM maven:3.9-eclipse-temurin-21 AS build

WORKDIR /build
COPY pom.xml .
COPY src ./src
RUN mvn -q package -DskipTests

FROM eclipse-temurin:21-jre-alpine

RUN apk add --no-cache curl

WORKDIR /app
COPY --from=build /build/target/pki-cert-client-*.jar app.jar

# Non-root for plain `docker run`; under OpenShift's restricted SCC this is
# overridden with an arbitrary UID in group 0 anyway - fine here since the app
# only reads its own jar and writes nothing under /app.
USER 1000:0

EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=5s --retries=5 \
    CMD curl -f http://localhost:8080/actuator/health || exit 1

ENTRYPOINT ["java", "-jar", "app.jar"]
