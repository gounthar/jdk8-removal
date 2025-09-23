# Use the minimal version of Debian as the base image
FROM debian:bookworm-20250908-slim

# Install necessary tools such as parallel, jq, git, curl, gnupg2, software-properties-common, and Python
RUN apt-get update && apt-get install -y \
    parallel \
    jq \
    git \
    curl \
    gnupg2 \
    software-properties-common \
    python3 \
    python3-pip \
    python3-venv \
    xmlstarlet \
    && rm -rf /var/lib/apt/lists/*  # Clean up to reduce the size of the image

# Install GitHub CLI
# First, add the GitHub CLI Debian repository's GPG key
RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-key C99B11DEB97541F0 \
    # Then, add the GitHub CLI Debian repository
    && apt-add-repository https://cli.github.com/packages \
    # Update the package list
    && apt update \
    # Install the GitHub CLI
    && apt install gh

# Install Maven
RUN apt-get update && apt-get install -y maven

# Add the 'll' alias for 'ls -artl' to the .bashrc file
# This makes the 'll' command available in every new bash shell
RUN echo "alias ll='ls -artl'" >> ~/.bashrc

# Copy all shell scripts and CSV files into the /scripts and /data directories in the image, respectively
COPY *.sh /scripts/
COPY *.csv /data/
COPY *.py /scripts/
COPY requirements.txt /scripts/

# Set the working directory to /scripts
# This is the directory that commands will run in by default
WORKDIR /scripts

# Install Python dependencies
RUN python3 -m pip install --upgrade pip && \
    pip3 install -r requirements.txt

# Make all shell scripts in the /scripts directory executable
RUN chmod +x *.sh
