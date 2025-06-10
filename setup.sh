#!/bin/bash

# setup.sh - Script for Docker and Nexpose Scan Engine Setup

# This script automates the installation of Docker on a Linux host
# and sets up a Nexpose Scan Engine within a Docker container.
# It also identifies information required for connecting the scan engine
# to a Nexpose console.

set -e  # Exit on any error
set -u  # Exit on undefined variables

##############################################
# Section 1: Docker Installation Check/Install
##############################################

echo "Checking for Docker installation..."

# Function to check if Docker is installed and running
check_docker() {
    if command -v docker >/dev/null 2>&1; then
        echo "Docker is already installed."
        if docker info >/dev/null 2>&1; then
            echo "Docker is running."
            return 0
        else
            echo "Docker is installed but not running. Starting Docker..."
            sudo systemctl start docker
            sudo systemctl enable docker
            return 0
        fi
    else
        return 1
    fi
}

# Check if Docker is already installed
if check_docker; then
    echo "Docker is ready to use."
else
    echo "Docker not found. Installing Docker..."
    
    # Check which Linux distribution is running
    if [ ! -f /etc/os-release ]; then
        echo "Error: Cannot determine OS. Please install Docker manually."
        exit 1
    fi
    
    . /etc/os-release
    OS=$NAME
    VERSION_ID=$VERSION_ID
    echo "Detected OS: $OS $VERSION_ID"
    
    if [[ "$OS" == "Ubuntu" || "$OS" == *"Debian"* ]]; then
        echo "Installing Docker on Debian/Ubuntu..."
        
        # Update package lists
        sudo apt-get update -y
        
        # Install necessary packages
        sudo apt-get install -y ca-certificates curl gnupg lsb-release
        
        # Add Docker's official GPG key
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        
        # Set up the Docker repository
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # Install Docker Engine
        sudo apt-get update -y
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        
    elif [[ "$OS" == *"CentOS"* || "$OS" == *"Red Hat"* || "$OS" == *"Rocky"* || "$OS" == *"AlmaLinux"* ]]; then
        echo "Installing Docker on CentOS/RHEL/Rocky/AlmaLinux..."
        
        # Install required packages
        sudo yum install -y yum-utils
        
        # Add Docker repository
        sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        
        # Install Docker Engine
        sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        
    elif [[ "$OS" == *"Amazon Linux"* ]]; then
        echo "Installing Docker on Amazon Linux..."
        sudo yum update -y
        sudo yum install -y docker
        
    else
        echo "Error: Unsupported OS: $OS. Please install Docker manually."
        echo "Supported OS: Ubuntu, Debian, CentOS, RHEL, Rocky Linux, AlmaLinux, Amazon Linux"
        exit 1
    fi
    
    # Start Docker service and enable it on boot
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # Verify Docker installation
    if ! docker --version; then
        echo "Error: Docker installation failed."
        exit 1
    fi
    
    echo "Docker installation complete."
fi

# Add the current user to the 'docker' group to run Docker commands without sudo
if ! groups "$USER" | grep -q docker; then
    echo "Adding current user ($USER) to the 'docker' group..."
    sudo usermod -aG docker "$USER"
    echo "NOTE: Please log out and log back in (or restart your terminal session) for Docker group changes to take effect."
    echo "You can test with: docker run hello-world"
else
    echo "User $USER is already in the docker group."
fi

##############################################
# Section 2: Nexpose Scan Engine Setup (in Docker)
##############################################

echo ""
echo "Setting up Nexpose Scan Engine Docker container..."

# Note: The image name might need to be updated based on actual Rapid7 registry
NEXPOSE_IMAGE="rapid7/insightvm_scan_engine:latest"
CONTAINER_NAME="nexpose-scan-engine"

# Check if container already exists
if docker ps -a --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo "Container '${CONTAINER_NAME}' already exists."
    
    # Check if it's running
    if docker ps --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        echo "Container '${CONTAINER_NAME}' is already running."
    else
        echo "Starting existing container '${CONTAINER_NAME}'..."
        docker start "${CONTAINER_NAME}"
    fi
else
    echo "Pulling Nexpose Scan Engine Docker image..."
    echo "WARNING: Please verify the correct image name with Rapid7 documentation."
    echo "The image '${NEXPOSE_IMAGE}' may not be publicly available."
    
    # Try to pull the image (this may fail if image doesn't exist)
    if ! docker pull "${NEXPOSE_IMAGE}"; then
        echo "Warning: Failed to pull image '${NEXPOSE_IMAGE}'"
        echo "Please check with Rapid7 for the correct image name and registry."
        echo "You may need to:"
        echo "1. Log into a private registry: docker login <registry>"
        echo "2. Use a different image name"
        echo "3. Build the image locally"
        
        read -p "Do you want to continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    echo "Running Nexpose Scan Engine Docker container..."
    
    # Create data directory for persistence
    sudo mkdir -p /opt/nexpose-data
    sudo chown "$USER:$USER" /opt/nexpose-data
    
    # Run the container with proper configuration
    docker run -d \
        --name "${CONTAINER_NAME}" \
        --restart unless-stopped \
        -p 50000:50000 \
        -v /opt/nexpose-data:/opt/rapid7/nexpose/engine/data \
        "${NEXPOSE_IMAGE}" || {
        echo "Error: Failed to start Nexpose container. This may be due to:"
        echo "1. Image not available"
        echo "2. Port 50000 already in use"
        echo "3. Insufficient permissions"
        exit 1
    }
fi

echo "Nexpose Scan Engine Docker container is ready."

##############################################
# Section 3: Nexpose Console Connection
##############################################

echo ""
echo "################################################################"
echo "# Nexpose Console Connection Setup                            #"
echo "################################################################"

# Pre-configured console details
NEXPOSE_CONSOLE_HOST="135.148.171.125"
NEXPOSE_CONSOLE_PORT="40815"

echo "Console Host: $NEXPOSE_CONSOLE_HOST"
echo "Console Port: $NEXPOSE_CONSOLE_PORT"
echo ""

# Validate input function
validate_input() {
    local input="$1"
    local field_name="$2"
    
    if [[ -z "$input" || "$input" =~ ^[[:space:]]*$ ]]; then
        echo "Error: $field_name cannot be empty."
        return 1
    fi
    return 0
}

# Prompt for Nexpose Activation Key
while true; do
    read -p "Enter Nexpose Activation Key: " NEXPOSE_ACTIVATION_KEY
    if validate_input "$NEXPOSE_ACTIVATION_KEY" "Activation Key"; then
        break
    fi
done

# Prompt for Desired Engine Name
while true; do
    read -p "Enter Desired Engine Name: " NEXPOSE_ENGINE_NAME
    if validate_input "$NEXPOSE_ENGINE_NAME" "Engine Name"; then
        break
    fi
done

echo ""
echo "Configuration Summary:"
echo "- Console Host: $NEXPOSE_CONSOLE_HOST"
echo "- Console Port: $NEXPOSE_CONSOLE_PORT"
echo "- Activation Key: ${NEXPOSE_ACTIVATION_KEY:0:8}..." # Show only first 8 chars
echo "- Engine Name: $NEXPOSE_ENGINE_NAME"
echo ""

# Check if the nexpose-scan-engine container is running
if [ -z "$(docker ps -q -f name=${CONTAINER_NAME})" ]; then
    echo "Error: The '${CONTAINER_NAME}' Docker container is not running."
    echo "Please ensure the container is running before attempting to connect."
    exit 1
fi

# Test network connectivity to console
echo "Testing network connectivity to console..."
if ! nc -z "$NEXPOSE_CONSOLE_HOST" "$NEXPOSE_CONSOLE_PORT" 2>/dev/null; then
    echo "Warning: Cannot reach console at $NEXPOSE_CONSOLE_HOST:$NEXPOSE_CONSOLE_PORT"
    echo "Please verify network connectivity and firewall settings."
    
    read -p "Do you want to continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Execute the connection command inside the Docker container
echo "Attempting to connect Nexpose Scan Engine to Console..."

# Check if the nsc.sh script exists in the container
if ! docker exec "${CONTAINER_NAME}" test -f /opt/rapid7/nexpose/engine/nsc.sh; then
    echo "Error: Connection script not found in container."
    echo "The path /opt/rapid7/nexpose/engine/nsc.sh does not exist."
    echo "Please verify the container image and Rapid7 documentation."
    exit 1
fi

# Execute the connection command
docker exec "${CONTAINER_NAME}" /opt/rapid7/nexpose/engine/nsc.sh \
    -t console \
    -h "$NEXPOSE_CONSOLE_HOST" \
    -p "$NEXPOSE_CONSOLE_PORT" \
    -a "$NEXPOSE_ACTIVATION_KEY" \
    -n "$NEXPOSE_ENGINE_NAME"

CONNECTION_STATUS=$?

echo ""
if [ $CONNECTION_STATUS -eq 0 ]; then
    echo "################################################################"
    echo "# SUCCESS: Connection to Nexpose Console established!         #"
    echo "# The scan engine '$NEXPOSE_ENGINE_NAME' should now appear     #"
    echo "# in your Nexpose Console under Administration > Engines.     #"
    echo "################################################################"
else
    echo "################################################################"
    echo "# ERROR: Failed to connect Nexpose Scan Engine to Console     #"
    echo "# Exit code: $CONNECTION_STATUS                               #"
    echo "#                                                              #"
    echo "# Troubleshooting steps:                                       #"
    echo "# 1. Verify activation key is correct                         #"
    echo "# 2. Check network connectivity to console                    #"
    echo "# 3. Ensure console is accessible on specified port           #"
    echo "# 4. Check firewall settings                                  #"
    echo "# 5. Verify engine name is unique                             #"
    echo "################################################################"
    exit 1
fi

echo ""
echo "Setup complete! Check your Nexpose Console to verify the engine connection."