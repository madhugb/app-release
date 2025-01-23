#!/usr/bin/env python3
"""
updateAppcast.py

Copyright 2024 Madhu G B - All rights reserved.
Appcast XML updater for Sparkle framework.
Manages the creation and updating of appcast.xml files for macOS application updates.
"""

import os
import hashlib
import datetime
import logging
import argparse
from typing import Tuple, List
from pathlib import Path
from dataclasses import dataclass
from lxml import etree
from lxml.etree import CDATA, _Element

# Configure logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

@dataclass
class UpdateInfo:
    """Container for update information."""
    version: str
    dmg_path: str
    release_notes: str
    file_size: str
    signature: str

class AppcastError(Exception):
    """Base exception for Appcast-related errors."""
    pass

class AppcastUpdater:
    """Manages the creation and updating of Sparkle appcast XML files."""
    
    SPARKLE_NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
    NAMESPACES = {
        'sparkle': SPARKLE_NS,
        None: ''  # default namespace
    }
    
    def __init__(self, appcast_path: str, base_url: str):
        """Initialize AppcastUpdater with file path and base URL."""
        self.appcast_path = Path(appcast_path)
        self.base_url = base_url.rstrip('/')
        logger.info(f"Initialized AppcastUpdater with path: {appcast_path}")

    def calculate_file_hash(self, file_path: str) -> str:
        """Calculate SHA-256 hash of the DMG file."""
        try:
            sha256_hash = hashlib.sha256()
            with open(file_path, 'rb') as f:
                for byte_block in iter(lambda: f.read(4096), b''):
                    sha256_hash.update(byte_block)
            return sha256_hash.hexdigest()
        except IOError as e:
            raise AppcastError(f"Failed to calculate file hash: {e}")

    def get_file_size(self, file_path: str) -> int:
        """Get file size in bytes."""
        try:
            return os.path.getsize(file_path)
        except OSError as e:
            raise AppcastError(f"Failed to get file size: {e}")

    def create_or_load_xml(self, update_info: UpdateInfo) -> _Element:
        """Create new or load existing appcast XML."""
        try:
            if self.appcast_path.exists():
                logger.info("Loading existing appcast file")
                parser = etree.XMLParser(remove_blank_text=True)
                tree = etree.parse(str(self.appcast_path), parser)
                return tree.getroot()

            logger.info("Creating new appcast file")
            root = etree.Element('rss', version="2.0", nsmap=self.NAMESPACES)
            channel = etree.SubElement(root, 'channel')

            # Add required channel elements
            channel_info = {
                'title': f'{update_info.name} Updates',
                'description': f'Most recent updates to {update_info.name}',
                'language': 'en'
            }

            for tag, text in channel_info.items():
                elem = etree.SubElement(channel, tag)
                elem.text = text

            return root

        except (etree.ParseError, OSError) as e:
            raise AppcastError(f"Failed to create/load XML: {e}")

    def version_to_tuple(self, version_str: str) -> Tuple[int, ...]:
        """Convert version string to tuple for comparison."""
        try:
            return tuple(map(int, version_str.split('.')))
        except (AttributeError, ValueError):
            return (0, 0)

    def create_enclosure(self, item: _Element, update_info: UpdateInfo, file_hash: str) -> None:
        """Create enclosure element with update information."""
        enclosure = etree.SubElement(item, 'enclosure')

        # Set basic attributes
        enclosure.set('url', f'{self.base_url}/{os.path.basename(update_info.dmg_path)}')
        enclosure.set('length', update_info.file_size)
        enclosure.set('type', 'application/x-apple-diskimage')

        # Set Sparkle-specific attributes
        sparkle_attrs = {
            'version': update_info.version,
            'shortVersionString': update_info.version,
            'sha256': file_hash,
            'edSignature': update_info.signature,
            'length': update_info.file_size
        }

        for key, value in sparkle_attrs.items():
            enclosure.set(f'{{{self.SPARKLE_NS}}}{key}', value)

    def sort_items(self, channel: _Element) -> List[_Element]:
        """Sort items by version number in descending order."""
        items = channel.findall('item')
        if not items:
            return []

        def get_version(item: _Element) -> Tuple[int, ...]:
            enclosure = item.find('enclosure')
            if enclosure is not None:
                version = enclosure.get(f'{{{self.SPARKLE_NS}}}version', '0.0')
                return self.version_to_tuple(version)
            return (0, 0)

        return sorted(items, key=get_version, reverse=True)

    def add_update(self, update_info: UpdateInfo) -> None:
        """Add a new update entry to the appcast."""
        try:
            root = self.create_or_load_xml(update_info)
            channel = root.find('channel')

            # Create new item
            item = etree.SubElement(channel, 'item')

            # Add title and publication date
            title = etree.SubElement(item, 'title')
            title.text = f'Version {update_info.version}'

            pub_date = etree.SubElement(item, 'pubDate')
            pub_date.text = datetime.datetime.now().strftime('%a, %d %b %Y %H:%M:%S +0000')

            # Calculate file hash and add enclosure
            file_hash = self.calculate_file_hash(update_info.dmg_path)
            self.create_enclosure(item, update_info, file_hash)

            # Add version elements
            for elem_name in ['version', 'shortVersionString']:
                version_elem = etree.SubElement(item, f'{{{self.SPARKLE_NS}}}{elem_name}')
                version_elem.text = update_info.version

            # Add release notes
            description = etree.SubElement(item, 'description')
            description.text = CDATA(update_info.release_notes)

            # Sort items by version
            items = self.sort_items(channel)
            if items:
                # Remove existing items
                for existing_item in channel.findall('item'):
                    channel.remove(existing_item)

                # Add back in sorted order
                for sorted_item in items:
                    sorted_item.set('description', CDATA(sorted_item.find('description').text))
                    channel.append(sorted_item)

            # Write updated XML
            self.write_xml(root)
            logger.info(f"Successfully added update for version {update_info.version}")

        except Exception as e:
            raise AppcastError(f"Failed to add update: {e}")

    def write_xml(self, root: _Element) -> None:
        """Write XML tree to file."""
        try:
            xml_str = etree.tostring(
                root,
                encoding='utf-8',
                xml_declaration=True,
                pretty_print=True
            )
            self.appcast_path.write_text(xml_str.decode('utf-8'))
            logger.info(f"Successfully wrote appcast to {self.appcast_path}")
        except IOError as e:
            raise AppcastError(f"Failed to write XML file: {e}")

def parse_arguments() -> argparse.Namespace:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description='Update Sparkle Appcast XML')

    parser.add_argument('--name', required=True, help='Application name')
    parser.add_argument('--version', required=True, help='Version number (e.g., 1.0)')
    parser.add_argument('--size', required=True, help='File size in bytes')
    parser.add_argument('--dmg', required=True, help='Path to DMG file')
    parser.add_argument('--signature', required=True, help='Sparkle signature')
    parser.add_argument('--notes', required=True, help='Release notes in HTML format')
    parser.add_argument('--output', default='appcast.xml', help='Output appcast.xml path')
    parser.add_argument('--base-url', required=True, help='Base URL for downloads')
    return parser.parse_args()

def main() -> None:
    """Main entry point."""
    try:
        args = parse_arguments()

        update_info = UpdateInfo(
            name=args.name,
            version=args.version,
            dmg_path=args.dmg,
            release_notes=args.notes,
            file_size=args.size,
            signature=args.signature
        )

        updater = AppcastUpdater(args.output, args.base_url)
        updater.add_update(update_info)
        logger.info(f'Appcast update completed successfully for {update_info.name}')
    except AppcastError as e:
        logger.error(f"Failed to update appcast: {e}")
        exit(1)
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        exit(1)

if __name__ == '__main__':
    main()