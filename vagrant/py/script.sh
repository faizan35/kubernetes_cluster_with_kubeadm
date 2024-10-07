#!/bin/bash

# Function to bring up both VMs
vagrant_up() {
    echo "Bringing up the VM..."
    vagrant up 
    wait
    echo "This is your VM's IP =" $(vagrant ssh -c "ip addr show eth1 | grep -oP '(?<=inet\s)\d+(\.\d+){3}'")
    wait
    echo "VMs is up."
}

# Function to destroy both VMs
vagrant_destroy() {
    echo "Destroying the VM..."
    vagrant destroy -f
    wait
    echo "VM Destroyed."
}

# Main script
echo "Choose an action:"
echo "1. Bring up the VM"
echo "2. Destroy the VM"

read choice

case $choice in
    1)
        vagrant_up
        ;;
    2)
        vagrant_destroy
        ;;
    *)
        echo "Invalid choice. Please choose either 1 or 2."
        ;;
esac
