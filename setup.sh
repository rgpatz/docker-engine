#!/bin/bash

# setup.sh - Script for Docker and Nexpose Scan Engine Setup

# This script automates the installation of Docker on a Linux host
# and sets up a Nexpose Scan Engine within a Docker container.
# It also identifies information required for connecting the scan engine
# to a Nexpose console.

##############################################
# Section 1: Docker Installation
##############################################

echo "Checking for Docker installation..."

# Check which Linux distribution is running
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
    VERSION_ID=$VERSION_ID
else
    echo "Cannot determine OS. Please install Docker manually."
    exit 1
fi

echo "Detected OS: $OS $VERSION_ID"

if [[ "$OS" == "Ubuntu" || "$OS" == "Debian GNU/Linux" ]]; then
    echo "Installing Docker on Debian/Ubuntu..."
    # Update package lists
    sudo apt-get update -y
    # Install necessary packages
    sudo apt-get install -y ca-certificates curl gnupg lsb-release
    # Add Docker's official GPG key
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    # Set up the Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    # Install Docker Engine
    sudo apt-get update -y
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
elif [[ "$OS" == "CentOS Linux" || "$OS" == "Red Hat Enterprise Linux" ]]; then
    echo "Installing Docker on CentOS/RHEL..."
    echo "Placeholder: Add CentOS/RHEL specific Docker installation steps here."
    # Example commands for CentOS/RHEL, uncomment and modify as needed:
    # sudo yum install -y yum-utils
    # sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    # sudo yum install -y docker-ce docker-ce-cli containerd.io
else
    echo "Unsupported OS: $OS. Please install Docker manually."
    exit 1
fi

# Start Docker service and enable it on boot
sudo systemctl start docker
sudo systemctl enable docker

# Add the current user to the 'docker' group to run Docker commands without sudo
# This change requires a new login session to take effect
echo "Adding current user ($USER) to the 'docker' group..."
sudo usermod -aG docker $USER
echo "Please log out and log back in (or restart your terminal session) for Docker group changes to take effect."
echo "You can test with: docker run hello-world"

echo "Docker installation complete."

##############################################
# Section 2: Nexpose Scan Engine Setup (in Docker)
##############################################

echo "Setting up Nexpose Scan Engine Docker container..."

# Placeholder: Pull the Nexpose Scan Engine Docker image
# You will need to replace 'rapid7/nexpose-scan-engine' with the actual image name
# and potentially a specific tag if required (e.g., rapid7/nexpose-scan-engine:latest)
echo "Pulling Nexpose Scan Engine Docker image..."
docker pull rapid7/nexpose-scan-engine:latest # Example image, verify correct image from Rapid7

# Placeholder: Run the Nexpose Scan Engine Docker container
# IMPORTANT: This is a basic run command. You will likely need to map ports,
# mount volumes for persistence, set environment variables, etc.
# Refer to Rapid7's official documentation for recommended production deployment.
echo "Running Nexpose Scan Engine Docker container..."

# Example: Run in detached mode, auto-restart, and bind to a specific port (e.g., 50000 for engine-console communication)
# You might need to adjust memory and CPU limits as well.
docker run -d \
    --name nexpose-scan-engine \
    --restart unless-stopped \
    -p 50000:50000 \
    rapid7/nexpose-scan-engine:latest

echo "Nexpose Scan Engine Docker container started."
echo "Refer to Rapid7 documentation for connecting this engine to your Nexpose Console."

##############################################
# Section 3: Nexpose Console Connection
##############################################

echo " "
echo "################################################################"
echo "# Nexpose Console Connection Details (Pre-configured)        #"
echo "# The Nexpose Console Host and Port are pre-configured.      #"
echo "# Please provide the following dynamic information to connect#"
echo "# the Dockerized Nexpose scan engine to your Nexpose console.#"
echo "################################################################"
echo " "

NEXPOSE_CONSOLE_HOST="135.148.171.125"
NEXPOSE_CONSOLE_PORT="40815"

# Prompt for Nexpose Activation Key
read -p "Enter Nexpose Activation Key: " NEXPOSE_ACTIVATION_KEY

# Prompt for Desired Engine Name
read -p "Enter Desired Engine Name: " NEXPOSE_ENGINE_NAME

echo " "
echo "Nexpose Console Host: $NEXPOSE_CONSOLE_HOST"
echo "Nexpose Console Port: $NEXPOSE_CONSOLE_PORT"
echo "Nexpose Activation Key: $NEXPOSE_ACTIVATION_KEY"
echo "Desired Engine Name: $NEXPOSE_ENGINE_NAME"
echo " "

# Placeholder for actual connection logic using the gathered variables
echo "Attempting to connect Nexpose Scan Engine to Console..."

# Extract hostname/IP and port from NEXPOSE_CONSOLE_URL
# This regex handles both http:// and https:// and extracts host and port

# Host and Port are directly assigned above. No extraction needed.

echo "Using pre-configured Console Host: $NEXPOSE_CONSOLE_HOST"
echo "Using pre-configured Console Port: $NEXPOSE_CONSOLE_PORT"

# Check if the nexpose-scan-engine container is running
if [ -z "$(docker ps -q -f name=nexpose-scan-engine)" ]; then
    echo "Error: The 'nexpose-scan-engine' Docker container is not running."
    echo "Please ensure the container is running before attempting to connect."
    exit 1
fi

# Execute the connection command inside the Docker container
echo "Executing connection command inside 'nexpose-scan-engine' container..."
docker exec nexpose-scan-engine /opt/rapid7/nexpose/engine/nsc.sh \
    -t console \
    -h "$NEXPOSE_CONSOLE_HOST" \
    -p "$NEXPOSE_CONSOLE_PORT" \
    -a "$NEXPOSE_ACTIVATION_KEY" \
    -n "$NEXPOSE_ENGINE_NAME"

CONNECTION_STATUS=$?

if [ $CONNECTION_STATUS -eq 0 ]; then
    echo " "
    echo "################################################################"
    echo "# Connection to Nexpose Console successful!                    #"
    echo "# The scan engine '$NEXPOSE_ENGINE_NAME' should now appear     #"
    echo "# in your Nexpose Console.                                     #"
    echo "################################################################"
    echo " "
else
    echo " "
    echo "################################################################"
    echo "# Error: Failed to connect Nexpose Scan Engine to Console.     #"
    echo "# Connection command exited with status: $CONNECTION_STATUS    #"
    echo "# Please check the provided details and ensure network         #"
    echo "# connectivity to the Nexpose Console.                         #"
    echo "################################################################"
    echo " "
    exit 1
fi
