FROM maven:3.9-eclipse-temurin-17 AS builder
WORKDIR /workspace
COPY .mvn/settings.xml /root/.m2/settings.xml
COPY . .
RUN mvn -B -pl jeepay-manager -am package -DskipTests

FROM eclipse-temurin:17-jre-jammy
LABEL maintainer="Jeepay Team"
ENV LANG=C.UTF-8 TZ=Asia/Shanghai
RUN apt-get update && apt-get install -y --no-install-recommends curl fontconfig fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system jeepay && useradd --system --gid jeepay --home /jeepayhomes jeepay \
    && mkdir -p /jeepayhomes/service/app /jeepayhomes/service/logs /jeepayhomes/service/uploads \
    && chown -R jeepay:jeepay /jeepayhomes
COPY --from=builder --chown=jeepay:jeepay /workspace/jeepay-manager/target/jeepay-manager.jar /jeepayhomes/service/app/jeepay-manager.jar
COPY --chown=jeepay:jeepay conf/manager/application.yml /jeepayhomes/service/app/application.yml
USER jeepay
WORKDIR /jeepayhomes/service/app
EXPOSE 9217
HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=5 CMD curl --fail --silent http://localhost:9217/actuator/health || exit 1
ENTRYPOINT ["java", "-jar", "jeepay-manager.jar"]
