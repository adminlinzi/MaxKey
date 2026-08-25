FROM eclipse-temurin:21-jre

LABEL authors="MaxKey <support@maxsso.net>"

RUN mkdir -p /maxkey

WORKDIR /maxkey

ARG JAR_FILE=build/libs/maxkey-boot-*-ga.jar

COPY ${JAR_FILE} maxkey-boot.jar

EXPOSE 9527

ENV TZ=Asia/Shanghai JAVA_OPTS="-Xms256m -Xmx1536m -Djava.security.egd=file:/dev/./urandom"

CMD java -jar maxkey-boot.jar $JAVA_OPTS