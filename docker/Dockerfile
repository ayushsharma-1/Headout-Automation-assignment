# Production-ready Dockerfile for Java Application
# Base Image: OpenJDK 11 JRE (slim variant for reduced size)
# Application: Java JAR running on port 9000
# Security: Non-root user execution
# Health: Integrated health checks with curl
# Optimization: G1GC, memory limits, headless mode

FROM openjdk:11-jre-slim

# Metadata
LABEL maintainer="Deployment Team"
LABEL version="1.0"
LABEL description="Java Application Container for EC2 Deployment"

# Set working directory
WORKDIR /app

# Install necessary packages for health checks and debugging
RUN apt-get update && apt-get install -y \
    curl \
    netcat \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Create application user for security
RUN groupadd -r appuser && useradd -r -g appuser appuser

# Copy the JAR file
COPY build/libs/project.jar /app/project.jar

# Change ownership to appuser
RUN chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Expose application port
EXPOSE 9000

# Health check configuration
# Checks every 30 seconds, timeout after 10 seconds
# Start checking after 60 seconds, retry 3 times before marking unhealthy
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:9000/ || exit 1

# JVM optimization settings
# -Xmx512m: Maximum heap size
# -Xms256m: Initial heap size  
# -XX:+UseG1GC: Use G1 garbage collector for better performance
# -Djava.awt.headless=true: Run in headless mode (no GUI)
ENV JAVA_OPTS="-Xmx512m -Xms256m -XX:+UseG1GC -Djava.awt.headless=true"

# Run the application
CMD ["sh", "-c", "java $JAVA_OPTS -jar project.jar"]
