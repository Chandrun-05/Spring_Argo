#
# Build stage
#
FROM maven:3.9.11-eclipse-temurin-25 AS build
COPY src /home/app/src
COPY pom.xml /home/app
RUN mvn -f /home/app/pom.xml clean package -DskipTests

#
# Package stage
#
FROM eclipse-temurin:25-jre
COPY --from=build /home/app/target/spring-boot-example-0.0.1-SNAPSHOT.jar /usr/local/lib/demo.jar
RUN rm -rf /home/app
EXPOSE 8080
ENTRYPOINT ["java","-jar","/usr/local/lib/demo.jar"]
