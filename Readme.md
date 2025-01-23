# macOS App Release Management System

A comprehensive toolset for managing macOS application releases using the Sparkle framework. This system automates the process of building, signing, notarizing, and distributing macOS applications with automatic update support.

## Features

- Automated version management
- DMG creation and signing
- Notarization with Apple's notary service
- [Sparkle](https://sparkle-project.org) framework integration for automatic updates
- Appcast XML generation and management (beta)
- Configurable release types (major, minor, patch) (beta)

## Prerequisites

- macOS development environment
- Xcode Command Line Tools
- Python 3.6+
- Required Python packages:
  - lxml
- Valid Apple Developer ID
- [Sparkle](https://sparkle-project.org) framework integration in your app
- AWS S3 bucket (or similar) for hosting updates

## Installation

1. Clone this repository into your project:
    ```bash
    git clone <repository-url> scripts
    cd scripts
    ```
2. Make the scripts executable:
    ```bash
    chmod +x release.sh
    chmod +x updateAppcast.py
    ```
3. Configure your environment in `config.sh`

## Configuration

Edit `config.sh` to match your application settings:

### Application Configuration

```bash
APP_NAME="YourAppName"
APP_BUNDLE_ID="com.yourcompany.YourAppName"
PROJECT_DIR="/path/to/your/project"
```

### Signing Configuration

```bash
KEYCHAIN_PROFILE="YourProfile"
DEVELOPER_ID="Developer ID Application: Your Name (TEAM_ID)"
```

### Distribution Configuration

```bash
S3_BASE_URL="https://your-updates-bucket.s3.amazonaws.com/"
```

## Usage

### Basic Release

To create a new release:

```bash
./release.sh --type minor --sparkle /path/to/sparkle --notes "Release notes here"
```

### Command Line Options

| Option | Description |
|--------|-------------|
| -t, --type    | Version type ( major \| minor \| patch ) |
| -s, --sparkle | Path to Sparkle binary [how to get it?](https://sparkle-project.org/documentation/#1-add-the-sparkle-framework-to-your-project) |
| -n, --notes   | Release notes ( HTML format supported ) |
| -p, --project | Path to Xcode project directory (overrides config.sh) |
| -h, --help    | Show help message |

### Example Workflow

1. Make your application changes in your project directory.
2. Commit your changes to git.
3. Clone this repository into your project directory or add the scripts directory to your environment.
4. Run the release script:
    ```bash
    ./release.sh \
    --type minor \
    --sparkle "/path/to/sparkle" \
    --notes "<h2>What's New</h2><ul><li>New feature added</li><li>Bug fixes</li></ul>"
    ```
5. Upload the generated DMG and appcast.xml to your distribution server

## File Structure

```
scripts/
├── release.sh: Main release script
├── config.sh: Configuration settings
├── updateAppcast.py: Python script for managing the Sparkle appcast
```

```
project/
├── appcast.xml: Generated update feed for Sparkle
├── exportOptions.plist: Xcode export options
├── Info.plist: Info.plist configuration for Sparkle
```

## Sparkle Integration

Ensure your application has [Sparkle](https://sparkle-project.org) framework integrated:

1. Add [Sparkle](https://sparkle-project.org/documentation/#1-add-the-sparkle-framework-to-your-project) to your Xcode project
2. Configure your `Info.plist` with:
    ```xml
    <key>SUFeedURL</key>
    <string>https://your-updates-bucket.s3.amazonaws.com/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>Your-Sparkle-Public-Key</string>
    ```

## AWS S3 Setup

1. Create an S3 bucket for hosting updates
2. Configure bucket policy for public read access
3. Enable static website hosting (optional)
4. Update `S3_BASE_URL` in `config.sh`

## Troubleshooting

Common Issues
- Signing Failed
    - Verify your Developer ID in `config.sh`
    - Ensure your certificates are valid
    - Check Keychain access
- Notarization Failed
    - Verify your Keychain profile
    - Check Apple Developer account status
    - Ensure proper entitlements
- Sparkle Updates Not Working
    - Verify `SUFeedURL` in `Info.plist`
    - Check `appcast.xml` accessibility
    - Validate Sparkle public key

## Contributing

- Fork the repository
- Create your feature branch
- Commit your changes
- Push to the branch
- Create a Pull Request

## License

see the LICENSE file for details.

## Support

For issues and feature requests, please create an issue in the repository.
