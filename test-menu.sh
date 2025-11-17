#!/bin/bash

# Test script to debug menu issues

echo "Test 1: Simple echo"
echo "This is a test"

echo ""
echo "Test 2: Variables"
VERSION="2.0.0"
echo "Version is: $VERSION"

echo ""
echo "Test 3: Colors"
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
echo -e "${RED}Red text${NC}"
echo -e "${GREEN}Green text${NC}"

echo ""
echo "Test 4: Clear screen"
read -p "Press Enter to clear screen..."
clear

echo ""
echo "Test 5: After clear"
echo "Can you see this after clear?"

echo ""
echo "Test 6: Menu"
echo "1) Option 1"
echo "2) Option 2"
echo "3) Option 3"
read -p "Select: " choice
echo "You selected: $choice"
