#!/bin/bash

# Navigate to your git repository
echo "Please enter your project name:"
read -r project_name

cd "$HOME" || { echo "Failed to change to home directory"; exit 1; }
cd /r
#cd / || exit

# Perform git pull
git pull origin main  # Replace 'main' with your branch name if different