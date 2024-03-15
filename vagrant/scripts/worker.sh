#!/bin/bash

# Check if the join command is provided
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <user_command>"
    exit 1
fi

# Perform pre-flight checks
sudo kubeadm reset pre-flight checks

# Extract the user-specific command from the arguments
user_command="$1"

# Build the complete command
full_command="sudo $user_command --v=5"

# Execute the final command
eval "$full_command"
