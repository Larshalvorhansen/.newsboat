#!/bin/bash

# Script to remove RSS articles with fewer than 5 lines of content
# from specific feeds listed in a text file
# Usage: ./remove_short_articles.sh urls.txt

# Configuration
NEWSBOAT_DIR="${HOME}/.newsboat"
CACHE_DB="${NEWSBOAT_DIR}/cache.db"
MIN_LINES=5
BACKUP_SUFFIX=".backup.$(date +%Y%m%d_%H%M%S)"

# Check arguments
if [ $# -eq 0 ]; then
  echo "Usage: $0 <url_file>"
  echo "Example: $0 urls.txt"
  echo ""
  echo "The url_file should contain one RSS feed URL per line."
  exit 1
fi

URL_FILE="$1"

# Check if URL file exists
if [ ! -f "$URL_FILE" ]; then
  echo "Error: URL file not found: $URL_FILE"
  exit 1
fi

# Check if cache database exists
if [ ! -f "$CACHE_DB" ]; then
  echo "Error: Newsboat cache database not found at $CACHE_DB"
  echo "Please check your Newsboat directory location."
  exit 1
fi

# Create backup
echo "Creating backup of cache database..."
cp "$CACHE_DB" "${CACHE_DB}${BACKUP_SUFFIX}"
echo "Backup created: ${CACHE_DB}${BACKUP_SUFFIX}"

# Count articles before deletion
BEFORE_COUNT=$(sqlite3 "$CACHE_DB" "SELECT COUNT(*) FROM rss_item;")
echo "Total articles before: $BEFORE_COUNT"
echo ""

# Read URLs from file and process each one
TOTAL_DELETED=0

while IFS= read -r feed_url || [ -n "$feed_url" ]; do
  # Skip empty lines and comments
  [[ -z "$feed_url" ]] && continue
  [[ "$feed_url" =~ ^[[:space:]]*# ]] && continue

  # Trim whitespace
  feed_url=$(echo "$feed_url" | xargs)

  echo "Processing feed: $feed_url"

  # Get feed ID
  FEED_ID=$(sqlite3 "$CACHE_DB" "SELECT rssurl FROM rss_feed WHERE rssurl='$feed_url';")

  if [ -z "$FEED_ID" ]; then
    echo "  Warning: Feed not found in database, skipping..."
    continue
  fi

  # Count articles in this feed before deletion
  FEED_BEFORE=$(sqlite3 "$CACHE_DB" "SELECT COUNT(*) FROM rss_item WHERE feedurl='$feed_url';")

  # Delete short articles from this feed
  sqlite3 "$CACHE_DB" <<EOF
DELETE FROM rss_item 
WHERE feedurl='$feed_url'
AND (
    (LENGTH(content) - LENGTH(REPLACE(content, CHAR(10), ''))) < $MIN_LINES
    OR LENGTH(TRIM(REPLACE(REPLACE(REPLACE(content, CHAR(10), ''), CHAR(13), ''), ' ', ''))) < 50
);
EOF

  # Count articles after deletion
  FEED_AFTER=$(sqlite3 "$CACHE_DB" "SELECT COUNT(*) FROM rss_item WHERE feedurl='$feed_url';")
  FEED_DELETED=$((FEED_BEFORE - FEED_AFTER))
  TOTAL_DELETED=$((TOTAL_DELETED + FEED_DELETED))

  echo "  Articles before: $FEED_BEFORE"
  echo "  Articles after: $FEED_AFTER"
  echo "  Removed: $FEED_DELETED"
  echo ""

done <"$URL_FILE"

# Count articles after all deletions
AFTER_COUNT=$(sqlite3 "$CACHE_DB" "SELECT COUNT(*) FROM rss_item;")

echo "================================"
echo "Summary:"
echo "Total articles before: $BEFORE_COUNT"
echo "Total articles after: $AFTER_COUNT"
echo "Total articles removed: $TOTAL_DELETED"
echo ""

# Vacuum the database to reclaim space
echo "Optimizing database..."
sqlite3 "$CACHE_DB" "VACUUM;"

echo "Done! Restart Newsboat to see the changes."
echo "If something went wrong, restore from: ${CACHE_DB}${BACKUP_SUFFIX}"
