# Use a lightweight JDK base image
FROM eclipse-temurin:17-jdk-alpine

# Set working directory
WORKDIR /app

# Copy the fat JAR
COPY gbfs-validator-java-api.jar app.jar

# org.entur.gbfs.validator.api.handler.OpenApiGeneratorApplication
# Run the app
ENTRYPOINT ["java", "-jar", "app.jar"]
