#!/bin/bash

# Script to extract the 10 most popular keyboard layouts
# Based on usage statistics and common distributions

set -e

LAYOUTS_DIR="layouts"
EXTRACTOR="../extract_xkb_layouts.cr"

# Ensure layouts directory exists
mkdir -p "$LAYOUTS_DIR"

echo "Extracting popular keyboard layouts..."
echo "====================================="

# List of most popular keyboard layouts by usage
# Source: Various statistics including Ubuntu, Windows, and macOS usage data

layouts=(
    "us"             # US English (QWERTY) - most common globally
    "gb"             # UK English (QWERTY)
    "fr"             # French (AZERTY)
    "de"             # German (QWERTZ)
    "es"             # Spanish
    "it"             # Italian
    "pt"             # Portuguese
    "se"             # Swedish
    "fi"             # Finnish
    "no"             # Norwegian
    "dk"             # Danish
    "nl"             # Dutch
    "be"             # Belgian
    "ru"             # Russian
    "br"             # Brazilian ABNT
    "ca"             # Canadian French
    "pl"             # Polish
    "cz"             # Czech QWERTZ
    "hu"             # Hungarian
    "tr"             # Turkish
    "gr"             # Greek
    "il"             # Hebrew
    "ar"             # Arabic
    "th"             # Thai
    "jp"             # Japanese
    "kr"             # Korean
    "cn"             # Chinese Simplified
    "tw"             # Chinese Traditional
)

echo "This will extract the following layouts:"
echo

# Count and display layouts
count=${#layouts[@]}
for layout in "${layouts[@]}"; do
    echo "  - $layout"
done

echo
echo "Total: $count layouts"
echo

# Extract each layout
for layout in "${layouts[@]}"; do
    echo "Extracting $layout..."
    crystal run "$EXTRACTOR" -- "$layout" -o "$LAYOUTS_DIR/" || \
        echo "  Warning: Failed to extract $layout"
done

echo
echo "Layout extraction complete!"
echo "Generated files are in the '$LAYOUTS_DIR' directory"
echo
echo "To integrate these layouts, copy the generated code into src/keyboard_layouts.cr"