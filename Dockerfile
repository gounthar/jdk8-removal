# Use Debian trixie (next stable) minimal slim image
FROM debian:trixie-slim

# Install necessary tools such as parallel, jq, git, curl, gnupg2, software-properties-common, and Python
RUN apt-get update && apt-get install -y --no-install-recommends \
    parallel \
    jq \
    git \
    curl \
    gnupg2 \
    ca-certificates \
    python3 \
    python3-pip \
    python3-venv \
    xmlstarlet \
    && rm -rf /var/lib/apt/lists/*  # Clean up to reduce the size of the image

# Install GitHub CLI
# First, add the GitHub CLI Debian repository's GPG key
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Install Maven
RUN apt-get update && apt-get install -y maven

# Add the 'll' alias for 'ls -artl' to the .bashrc file
# This makes the 'll' command available in every new bash shell
RUN echo "alias ll='ls -artl'" >> ~/.bashrc

# Copy all shell scripts and CSV files into the /scripts and /data directories in the image, respectively
COPY *.sh /scripts/
COPY *.csv /data/
COPY requirements.txt /scripts/
COPY *.py /scripts/

# Set the working directory to /scripts
# This is the directory that commands will run in by default
WORKDIR /scripts

# Install Python dependencies inside an isolated virtual environment (PEP 668 compliant)
RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --upgrade pip \
    && /opt/venv/bin/pip install -r requirements.txt \
    && ln -s /opt/venv/bin/pip /usr/local/bin/pip \
    && ln -s /opt/venv/bin/python /usr/local/bin/python

# Make all shell scripts in the /scripts directory executable
RUN chmod +x *.sh
