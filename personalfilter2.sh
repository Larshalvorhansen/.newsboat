#!/bin/bash

# Script to:
# 1. Find RSS feeds with articles that have fewer than 5 lines
# 2. Log those feed URLs to a file
# 3. Create a new urls2.txt with only the good feeds
# 4. Delete the short articles from the database
#
# Usage: ./remove_short_articles.sh urls.txt

# Configuration
NEWSBOAT_DIR="${HOME}/.newsboat"
CACHE_DB="${NEWSBOAT_DIR}/cache.db"
MIN_LINES=5
BACKUP_SUFFIX=".backup.$(date +%Y%m%d_%H%M%S)"
LOG_FILE="feeds_with_short_articles_$(date +%Y%m%d_%H%M%S).log"
OUTPUT_FILE="urls2.txt"

# Check arguments
if [ $# -eq 0 ]; then
  echo "Usage: $0 <url_file>"
  echo "Example: $0 urls.txt"
  echo ""
  echo "The url_file should contain one RSS feed URL per line."
  echo "Good feeds will be saved to urls2.txt"
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

# Create backup of database
echo "Creating backup of cache database..."
cp "$CACHE_DB" "${CACHE_DB}${BACKUP_SUFFIX}"
echo "Database backup created: ${CACHE_DB}${BACKUP_SUFFIX}"
echo ""

# Initialize log file
echo "Feeds with short articles - $(date)" >"$LOG_FILE"
echo "==========================================" >>"$LOG_FILE"
echo "" >>"$LOG_FILE"

# Initialize output file
echo "# Good RSS feeds (no short articles)" >"$OUTPUT_FILE"
echo "# Generated on $(date)" >>"$OUTPUT_FILE"
echo "" >>"$OUTPUT_FILE"

# Arrays to store URLs
declare -a FEEDS_TO_REMOVE=()
declare -a FEEDS_TO_KEEP=()

# Count articles before deletion
BEFORE_COUNT=$(sqlite3 "$CACHE_DB" "SELECT COUNT(*) FROM rss_item;")
echo "Total articles in database: $BEFORE_COUNT"
echo ""

# Read URLs from file and check each one
TOTAL_DELETED=0

while IFS= read -r feed_url || [ -n "$feed_url" ]; do
  # Skip empty lines and comments
  if [[ -z "$feed_url" ]] || [[ "$feed_url" =~ ^[[:space:]]*# ]]; then
    echo "$feed_url" >>"$OUTPUT_FILE"
    continue
  fi

  # Trim whitespace
  feed_url=$(echo "$feed_url" | xargs)

  echo "Checking feed: $feed_url"

  # Check if feed exists in database
  FEED_EXISTS=$(sqlite3 "$CACHE_DB" "SELECT COUNT(*) FROM rss_feed WHERE rssurl='$feed_url';")

  if [ "$FEED_EXISTS" -eq 0 ]; then
    echo "  Warning: Feed not found in database, keeping anyway..."
    FEEDS_TO_KEEP+=("$feed_url")
    echo "$feed_url" >>"$OUTPUT_FILE"
    echo ""
    continue
  fi

  # Count total articles in this feed
  TOTAL_ARTICLES=$(sqlite3 "$CACHE_DB" "SELECT COUNT(*) FROM rss_item WHERE feedurl='$feed_url';")

  # Count short articles in this feed
  SHORT_ARTICLES=$(sqlite3 "$CACHE_DB" "SELECT COUNT(*) FROM rss_item 
        WHERE feedurl='$feed_url'
        AND (
            (LENGTH(content) - LENGTH(REPLACE(content, CHAR(10), ''))) < $MIN_LINES
            OR LENGTH(TRIM(REPLACE(REPLACE(REPLACE(content, CHAR(10), ''), CHAR(13), ''), ' ', ''))) < 50
        );")

  echo "  Total articles: $TOTAL_ARTICLES"
  echo "  Short articles: $SHORT_ARTICLES"

  if [ "$SHORT_ARTICLES" -gt 0 ]; then
    echo "  ⚠️  This feed has short articles - excluding from urls2.txt"
    FEEDS_TO_REMOVE+=("$feed_url")

    # Log to file
    echo "URL: $feed_url" >>"$LOG_FILE"
    echo "  Total articles: $TOTAL_ARTICLES" >>"$LOG_FILE"
    echo "  Short articles: $SHORT_ARTICLES" >>"$LOG_FILE"
    echo "" >>"$LOG_FILE"

    # Delete short articles from this feed
    sqlite3 "$CACHE_DB" <<EOF
DELETE FROM rss_item 
WHERE feedurl='$feed_url'
AND (
    (LENGTH(content) - LENGTH(REPLACE(content, CHAR(10), ''))) < $MIN_LINES
    OR LENGTH(TRIM(REPLACE(REPLACE(REPLACE(content, CHAR(10), ''), CHAR(13), ''), ' ', ''))) < 50
);
EOF

    TOTAL_DELETED=$((TOTAL_DELETED + SHORT_ARTICLES))
  else
    echo "  ✓ No short articles - adding to urls2.txt"
    FEEDS_TO_KEEP+=("$feed_url")
    echo "$feed_url" >>"$OUTPUT_FILE"
  fi

  echo ""

done <"$URL_FILE"

# Count articles after deletions
AFTER_COUNT=$(sqlite3 "$CACHE_DB" "SELECT COUNT(*) FROM rss_item;")

echo "==========================================="
echo "Summary:"
echo "==========================================="
echo "Feeds checked: $((${#FEEDS_TO_REMOVE[@]} + ${#FEEDS_TO_KEEP[@]}))"
echo "Feeds with short articles (excluded): ${#FEEDS_TO_REMOVE[@]}"
echo "Good feeds (in urls2.txt): ${#FEEDS_TO_KEEP[@]}"
echo ""
echo "Total articles before: $BEFORE_COUNT"
echo "Total articles after: $AFTER_COUNT"
echo "Short articles deleted: $TOTAL_DELETED"
echo ""
echo "Good feeds saved to: $OUTPUT_FILE"
echo "Excluded feeds logged to: $LOG_FILE"
echo ""

if [ ${#FEEDS_TO_REMOVE[@]} -gt 0 ]; then
  echo "Feeds excluded from urls2.txt:"
  for feed in "${FEEDS_TO_REMOVE[@]}"; do
    echo "  - $feed"
  done
  echo ""
fi

# Vacuum the database to reclaim space
echo "Optimizing database..."
sqlite3 "$CACHE_DB" "VACUUM;"

echo "Done!"
echo ""
echo "Files created:"
echo "  Good feeds: $OUTPUT_FILE"
echo "  Excluded feeds log: $LOG_FILE"
echo "  Database backup: ${CACHE_DB}${BACKUP_SUFFIX}"
