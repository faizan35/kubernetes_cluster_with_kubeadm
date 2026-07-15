#!/bin/bash

# Check if the join command is provided
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <user_command>"
    echo "Example: bash worker.sh \"kubeadm join 10.0.0.5:6443 --token xyz...\""
    exit 1
fi

# Perform a clean reset to avoid conflicts from previous failed joins
echo "Cleaning up any previous Kubernetes configurations..."
sudo kubeadm reset -f

# Extract the user-specific command from the arguments
user_command="$1"

# Build the complete command (adding verbosity for debugging if it fails)
full_command="sudo $user_command --v=5"

# Execute the final command
echo "Joining the cluster..."
eval "$full_command"