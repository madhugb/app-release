#!/bin/bash
set -euo pipefail

# release.sh
#
# Copyright 2024 Madhu G B - All rights reserved.
# Script to release macOS applications using Sparkle framework.
# Manages the creation and updating of appcast.xml files for macOS application updates.
# Uses updateAppcast.py to update the appcast.xml file.
# Assumes that the project directory is already setup with the correct build configuration.
# See config.sh for configuration options.

# Usage:
# ./release.sh --type minor --sparkle /path/to/sparkle --notes "Added feature X" --project /path/to/project
# OR
# ./release.sh -t minor -s /path/to/sparkle -n "Added feature X" -p /path/to/project


# Load configuration
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPTS_DIR}/config.sh"
GIT=$(sh /etc/profile; which git)

PYTHON_UPDATER="${SCRIPTS_DIR}/updateAppcast.py"

# Color output helpers
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

log() { echo -e "${GREEN}→${NC} $1" >&2; }
warn() { echo -e "${YELLOW}!${NC} $1" >&2; }
error() { echo -e "${RED}✗${NC} $1" >&2; }

usage() {
    cat << EOF
Usage: $(basename "$0") <options>

Options:
    -t, --type      Version type (major|minor|patch)
    -s, --sparkle   Path to Sparkle binary
    -n, --notes     Release notes
    -p, --project   Path to Xcode project directory (overrides config.sh)
    -h, --help      Show this help message

Example:
    $(basename "$0") --type minor --sparkle /path/to/sparkle --notes "Added feature X"
    $(basename "$0") --type minor --sparkle /path/to/sparkle --notes "Added feature X" --project /path/to/project
EOF
    exit 1
}

# Validate project directory
validate_project_dir() {
    local project_dir=$1

    # Check if directory exists
    if [[ ! -d "$project_dir" ]]; then
        error "Project directory not found: $project_dir" >&2
        exit 1
    fi

    # Check for xcodeproj file
    if [[ ! -d "$project_dir/${APP_NAME}.xcodeproj" ]]; then
        error "Xcode project not found: $project_dir/${APP_NAME}.xcodeproj" >&2
        exit 1
    fi

    # Check for Info.plist
    if [[ ! -f "$project_dir/${APP_NAME}/Info.plist" ]]; then
        error "Info.plist not found: $project_dir/${APP_NAME}/Info.plist" >&2
        exit 1
    fi
}

# Parse command line arguments
parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -t|--type) VERSION_TYPE="$2"; shift ;;
            -s|--sparkle) SPARKLE_BIN="$2"; shift ;;
            -n|--notes) RELEASE_NOTES="$2"; shift ;;
            -p|--project) 
                PROJECT_DIR="$2"
                # Update dependent paths
                INFO_PLIST_PATH="${PROJECT_DIR}/${APP_NAME}/Info.plist"
                BUILD_PATH="${PROJECT_DIR}/build/export"
                EXPORT_OPTIONS_PATH="${PROJECT_DIR}/exportOptions.plist"
                APPCAST_PATH="${PROJECT_DIR}/appcast.xml"
                SCRIPTS_DIR="${PROJECT_DIR}/scripts"
                PYTHON_UPDATER="${SCRIPTS_DIR}/updateAppcast.py"
                shift ;;
            -h|--help) usage ;;
            *) error "Unknown parameter: $1"; usage ;;
        esac
        shift
    done

    # Validate required arguments
    if [[ -z "${VERSION_TYPE:-}" ]] || [[ -z "${SPARKLE_BIN:-}" ]] || [[ -z "${RELEASE_NOTES:-}" ]]; then
        error "Missing required arguments" >&2
        usage
    fi

    # Validate project directory
    validate_project_dir "$PROJECT_DIR"
}

# Cleanup function
cleanup() {
    log "🧹 Cleaning up..." >&2
    rm -rf "${BUILD_PATH}" 2>/dev/null || true
}

# Find Sparkle binary directory
find_sparkle_bin() {
    local derived_data_path="$HOME/Library/Developer/Xcode/DerivedData"
    local sparkle_pattern="${APP_NAME}-*/SourcePackages/artifacts/sparkle/Sparkle/bin"

    log "Looking for Sparkle in DerivedData..." >&2
    log "Search path: ${derived_data_path}/${sparkle_pattern}" >&2

    # Try to find the directory using bash glob
    local sparkle_dirs=("${derived_data_path}"/${sparkle_pattern})

    # Check if directory was found
    if [ ${#sparkle_dirs[@]} -eq 0 ] || [ ! -d "${sparkle_dirs[0]}" ]; then
        error "Sparkle binary directory not found in DerivedData" >&2
        error "Expected pattern: ${derived_data_path}/${sparkle_pattern}" >&2
        exit 1
    fi

    # If multiple directories found, use the most recent one
    if [ ${#sparkle_dirs[@]} -gt 1 ]; then
        log "Multiple Sparkle directories found, using most recent" >&2
        # Sort by modification time and take the most recent
        local most_recent
        most_recent=$(ls -td "${sparkle_dirs[@]}" | head -n1)
        printf "%s" "$most_recent"
    else
        printf "%s" "${sparkle_dirs[0]}"
    fi
}

can_update_version() {
    log "🔍 Verifying version update..." >&2
    local current_dir
    current_dir=$(pwd)
    cd "$PROJECT_DIR"
    local bundleVersion=$(${GIT} rev-list --all | wc -l | xargs)
    local current_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST_PATH")
    local current_bundleVersion=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST_PATH")
    if [ "$bundleVersion" -le "$current_bundleVersion" ]; then
        error "Error: Bundle version is not greater than current bundle version: ${current_bundleVersion}" >&2
        error "Please ensure you have committed all changes before releasing." >&2
        exit 1
    fi
    cd "$current_dir"
}

# Version update function
update_version() {
    local version_type=$1
    local current_version
    local new_version

    local current_dir

    current_dir=$(pwd)

    cd "$PROJECT_DIR"
    bundleVersion=$(${GIT} rev-list --all | wc -l | xargs)
    cd "$current_dir"

    log "Bundle version: $bundleVersion" >&2

    current_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST_PATH")

    # Split version into components
    local major minor patch
    IFS='.' read -r major minor patch <<< "$current_version"

    case $version_type in
        major) new_version="$((major + 1)).0.0" ;;
        minor) new_version="${major}.$((minor + 1)).0" ;;
        patch) new_version="${major}.${minor}.$((patch + 1))" ;;
        *) error "Invalid version type: $version_type"; exit 1 ;;
    esac


    # Update the version in Info.plist
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $bundleVersion" "$INFO_PLIST_PATH"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $new_version" "$INFO_PLIST_PATH"

    # Log after the version is updated
    log "Updating version from $current_version -> $new_version" >&2

    # Return just the new version
    printf "%s" "$new_version"
}

# Build and package function
build_and_package() {
    local version=$1

    log "Building ${APP_NAME}..." >&2
    # Change to project directory before building
    cd "$PROJECT_DIR"

    xcodebuild -quiet -project "${APP_NAME}.xcodeproj" \
        -scheme "${APP_NAME}" \
        -configuration Release \
        -archivePath "${BUILD_PATH}/${APP_NAME}.xcarchive" \
        archive

    log "Creating DMG..." >&2
    xcodebuild -quiet -exportArchive \
        -archivePath "${BUILD_PATH}/${APP_NAME}.xcarchive" \
        -exportPath "${BUILD_PATH}" \
        -exportOptionsPlist "${EXPORT_OPTIONS_PATH}"

    create_dmg "$version"
}

# Create DMG function
create_dmg() {
    local version=$1
    local dmg_name="${APP_NAME}-${version}.dmg"
    local tmp_dir
    local current_dir

    # Save current directory
    current_dir=$(pwd)

    # Create temp directory
    tmp_dir=$(mktemp -d)
    log "📁 Creating temporary directory: ${tmp_dir}" >&2

    # Copy app to temp directory
    cp -R "${BUILD_PATH}/${APP_NAME}.app" "${tmp_dir}/"
    ln -s /Applications "${tmp_dir}/Applications"

    # Create DMG in project directory
    cd "${PROJECT_DIR}"
    log "Creating DMG in: $(pwd)" >&2

    if [ -f "${dmg_name}" ]; then
        log "🗑️ Removing existing DMG" >&2
        rm "${dmg_name}"
    fi

    hdiutil create -volname "${APP_NAME}" \
        -srcfolder "${tmp_dir}" \
        -ov -format UDBZ \
        "${dmg_name}"

    # Cleanup
    rm -rf "${tmp_dir}"

    # Return to original directory
    cd "${current_dir}"

}

# Sign DMG function
sign_dmg() {
    local dmg_name=$1
    local current_dir

    # Save current directory
    current_dir=$(pwd)

    # Change to project directory
    cd "${PROJECT_DIR}"

    # Verify DMG exists
    if [ ! -f "${dmg_name}" ]; then
        error "DMG file not found to sign: ${dmg_name}" >&2
        cd "${current_dir}"
        exit 1
    fi

    log "📝 Signing DMG: ${dmg_name}" >&2

    codesign --force --sign "${DEVELOPER_ID}" \
        --options runtime \
        --timestamp \
        "${dmg_name}"

    log "📦 Notarizing..." >&2
    xcrun notarytool submit "${dmg_name}" \
        --keychain-profile "${KEYCHAIN_PROFILE}" \
        --wait

    log "📎 Stapling..." >&2
    xcrun stapler staple "${dmg_name}"

    # Return to original directory
    cd "${current_dir}"
}

main() {
    parse_args "$@"
    trap cleanup EXIT

    if [ -z "${SPARKLE_BIN:-}" ]; then
        SPARKLE_BIN=$(find_sparkle_bin)
        log "Found Sparkle binary at: ${SPARKLE_BIN}" >&2
    fi

    # Verify Sparkle directory exists and contains required files
    if [ ! -f "${SPARKLE_BIN}/sign_update" ]; then
        error "Sparkle sign_update binary not found in: ${SPARKLE_BIN}" >&2
        exit 1
    fi

    # Validate version type
    if [[ "${VERSION_TYPE}" != "major" ]] && 
       [[ "${VERSION_TYPE}" != "minor" ]] && 
       [[ "${VERSION_TYPE}" != "patch" ]]; then
        error "Invalid version type: ${VERSION_TYPE}" >&2
        usage
    fi

    can_update_version

    # Update version
    VERSION=$(update_version "${VERSION_TYPE}")

    # Build and package
    build_and_package "${VERSION}"

    DMG_NAME="${APP_NAME}-${VERSION}.dmg"
    log "🏗️ Build complete" >&2

    # Sign and notarize
    sign_dmg "${DMG_NAME}"

    # Sign with Sparkle
    log "📝 Signing with Sparkle..." >&2
    SIGN_OUTPUT=$("${SPARKLE_BIN}/sign_update" "${PROJECT_DIR}/${DMG_NAME}")
    SIGNATURE=$(echo "${SIGN_OUTPUT}" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
    SIZE=$(stat -f %z "${PROJECT_DIR}/${DMG_NAME}")

    # Update appcast
    log "📒 Updating appcast..." >&2
    python3 "${PYTHON_UPDATER}" \
        --name "${APP_NAME}" \
        --version "${VERSION}" \
        --dmg "${PROJECT_DIR}/${DMG_NAME}" \
        --size "${SIZE}" \
        --signature "${SIGNATURE}" \
        --notes "<h2>Version ${VERSION}</h2><p>${RELEASE_NOTES}</p>" \
        --base-url "${S3_BASE_URL}"

    # Print summary
    cat << EOF
----------------------------------------
✅ Release completed successfully!
📦 DMG File: ${DMG_NAME}
📏 Size: ${SIZE} bytes
🔑 Signature: ${SIGNATURE}
----------------------------------------

Next steps:
1. Upload ${DMG_NAME} to ${S3_BASE_URL}
2. Upload appcast.xml to ${S3_BASE_URL}appcast.xml


EOF
}

main "$@"