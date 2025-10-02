FROM debian:trixie-slim

WORKDIR /app

# Install Perl and ALL modules from apt
RUN apt-get update && apt-get install -y \
    perl \
    libdbd-mariadb-perl \
    libdbi-perl \
    libmojolicious-perl \
    libcrypt-eksblowfish-perl \
    libemail-sender-perl \
    libemail-mime-perl \
    libwww-perl \
    && rm -rf /var/lib/apt/lists/*

# Copy application code
COPY . .

# Create symlink
RUN mkdir -p /root && ln -s /app /root/stashpage

# Expose internal port
EXPOSE 3000

# Run application (no entrypoint needed!)
CMD ["perl", "stashpage.pl", "daemon", "-l", "http://*:3000"]

