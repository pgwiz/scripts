
# Install necessary packages using apt
echo -e "\033[0;31mInstalling necessary packages...\033[0m"
apt update && apt install -y git nodejs ffmpeg imagemagick yarn || {
  echo -e "\033[0;31mFailed to install necessary packages. Please check your internet connection or try again manually.\033[0m"
  exit 1
}

# Function to check for any remaining missing packages
check_packages() {
  missing_packages=()
  for pkg in "$@"; do
    if ! command -v "$pkg" >/dev/null 2>&1; then
      missing_packages+=("$pkg")
    fi
  done

  if [ ${#missing_packages[@]} -gt 0 ]; then
    echo -e "\033[0;31mThe following packages are still missing: ${missing_packages[*]}\033[0m"
    echo -e "\033[0;31mInstalling missing packages...\033[0m"
    apt install -y "${missing_packages[@]}" || {
      echo -e "\033[0;31mFailed to install missing packages. Please install manually:\033[0m"
      echo -e "\033[0;31mapt install -y ${missing_packages[*]}\033[0m"
      exit 1
    }
  else
    echo -e "\033[0;31mAll required packages are already installed.\033[0m"
  fi
}

# Check for missing packages
required_packages=("git" "nodejs" "ffmpeg" "imagemagick" "yarn")
check_packages "${required_packages[@]}"

# Ask user for GitHub repository link and bot folder name
read -p "Enter the GitHub repository link: " repo_link
read -p "Enter the name for the bot folder (leave blank for random): " bot_folder

# Generate a random folder name if none is provided
if [ -z "$bot_folder" ]; then
  bot_folder="bot_$RANDOM"
  echo -e "\033[0;31mNo folder name provided. Using default: $bot_folder\033[0m"
fi

# Clone the repository into the specified folder
echo -e "\033[0;31mCloning the repository...\033[0m"
git clone "$repo_link" "$bot_folder" || {
  echo -e "\033[0;31mFailed to clone the repository. Please check the link or your internet connection.\033[0m"
  exit 1
}

cd "$bot_folder" || {
  echo -e "\033[0;31mError: Could not access the repository directory.\033[0m"
  exit 1
}

# Install project dependencies
echo -e "\033[0;31mInstalling project dependencies...\033[0m"
yarn install && npm install || {
  echo -e "\033[0;31mFailed to install project dependencies. Please try again.\033[0m"
  exit 1
}

# Search for index.js and execute with PM2
file=$(find . -type f -name "index.js" -not -path "./node_modules/*" -print -quit)

if [ -n "$file" ]; then
  echo -e "\033[0;31mFound $file. Starting the bot with PM2...\033[0m"
  npm i -g pm2 && pm2 start "$file" && pm2 save && pm2 logs
else
  echo -e "\033[0;31mError: index.js not found in the repository directory (excluding node_modules).\033[0m"
  exit 1
fi