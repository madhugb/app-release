#!/bin/bash
# Copyright 2024 Madhu G B - All rights reserved.
# Configuration for macOS application release script.
# Manages the configuration for the release script.
# See release.sh for usage.

# Application Configuration
APP_NAME="MyMacApp"
APP_BUNDLE_ID="com.yourcompany.MyMacApp"

# Source paths - you only need to modify this section
# Set the path to your Xcode project directory
PROJECT_DIR="/Users/username/MyMacApp"

# Build Configuration (don't modify these)
INFO_PLIST_PATH="${PROJECT_DIR}/${APP_NAME}/Info.plist"
BUILD_PATH="${PROJECT_DIR}/build/export"
EXPORT_OPTIONS_PATH="${PROJECT_DIR}/exportOptions.plist"

# Signing Configuration
KEYCHAIN_PROFILE="MyMacApp"
DEVELOPER_ID="your-developer-id"

# Distribution Configuration
S3_BASE_URL="https://my-mac-app-updates.s3.us-east-1.amazonaws.com/"
APPCAST_PATH="${PROJECT_DIR}/appcast.xml"
