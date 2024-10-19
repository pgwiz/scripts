#!/bin/bash

# Navigate to your git repository
echo "Please enter your project name:"
read -r project_name

cd "$HOME" || { echo "Failed to change to home directory"; exit 1; }

cd /r

repo_path=$(pwd)

#cd / || exit

# Perform git pull
git pull origin main  # Replace 'main' with your branch name if different


#!/bin/bash

# Define the new cron job
new_cron_job="*/10 * * * * $repo_path/script.sh >> $repo_path/git_logfile.log 2>&1"

# Check if the cron job already exists
if crontab -l | grep -Fxq "$new_cron_job"; then
    echo "Cron job already exists."
else#!/bin/bash

# Navigate to your git repository
echo "Please enter your project name:"
read -r project_name

cd "$HOME" || { echo "Failed to change to home directory"; exit 1; }

cd /r || { echo "Failed to change to repository directory"; exit 1; }

repo_path=$(pwd)

# Perform git pull
git pull origin main  # Replace 'main' with your branch name if different

# Define the new cron job
new_cron_job="*/10 * * * * $repo_path/script.sh >> $repo_path/git_logfile.log 2>&1"

# Check if the cron job already exists
if crontab -l | grep -Fxq "$new_cron_job"; then
    echo "Cron job already exists."
else
    # Add the new cron job
    (crontab -l; echo "$new_cron_job") | crontab -
    echo "New cron job added."
fi
    # Add the new cron job
    (crontab -l; echo "$new_cron_job") | crontab -
    echo "New cron job added."
fi
