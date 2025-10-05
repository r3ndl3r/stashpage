FROM debian:trixie-slim

WORKDIR /app

# Install dependencies as root, then create non-root user
RUN apt-get update && apt-get install -y --no-install-recommends \
    perl \
    libdbd-mariadb-perl \
    libdbd-sqlite3-perl \
    sqlite3 \
    libdbi-perl \
    libmojolicious-perl \
    libcrypt-eksblowfish-perl \
    libemail-sender-perl \
    libemail-mime-perl \
    libwww-perl \
    libjson-perl \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Create non-root user with fixed UID/GID for volume permissions
RUN groupadd -r stashpage -g 1001 && \
    useradd -r -g stashpage -u 1001 -m -s /bin/bash stashpage

# Create directories with correct ownership
RUN mkdir -p /app/log /app/data && \
    chown -R stashpage:stashpage /app

# Copy application code with correct ownership
COPY --chown=stashpage:stashpage . .

# Switch to non-root user for all subsequent operations
USER stashpage

# Expose internal port (documentation only)
EXPOSE 3000

# Healthcheck inside container
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

# Run application as non-root user
CMD ["perl", "stashpage.pl", "daemon", "-l", "http://*:3000"]
