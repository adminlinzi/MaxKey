FROM eclipse-temurin:21-jre

LABEL authors="MaxKey <support@maxsso.net>"

RUN mkdir -p /maxkey-mgt

WORKDIR /maxkey-mgt

ARG JAR_FILE=build/libs/maxkey-mgt-boot-*-ga.jar

COPY ${JAR_FILE} maxkey-mgt-boot.jar

EXPOSE 9526

ENV TZ=Asia/Shanghai JAVA_OPTS="-Xms256m -Xmx1536m -Djava.security.egd=file:/dev/./urandom"

CMD java -jar maxkey-mgt-boot.jar $JAVA_OPTS