#!/usr/bin/env bash
# Sprinty Utilities
# Common functions used across all Sprinty modules

set -e

# ============================================================================
# COLOR DEFINITIONS
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================================================
# DATE UTILITIES
# Cross-platform date functions (GNU/BSD compatible)
# ============================================================================

# Get current timestamp in ISO 8601 format
# Returns: YYYY-MM-DDTHH:MM:SS+00:00
get_iso_timestamp() {
    local os_type
    os_type=$(uname)

    if [[ "$os_type" == "Darwin" ]]; then
        # macOS (BSD date)
        date -u +"%Y-%m-%dT%H:%M:%S%z" | sed 's/\(..\)$/:\1/'
    else
        # Linux (GNU date)
        date -u -Iseconds
    fi
}

# Get time component for one hour from now
# Returns: HH:MM:SS
get_next_hour_time() {
    local os_type
    os_type=$(uname)

    if [[ "$os_type" == "Darwin" ]]; then
        date -v+1H '+%H:%M:%S'
    else
        date -d '+1 hour' '+%H:%M:%S'
    fi
}

# Get basic timestamp
# Returns: YYYY-MM-DD HH:MM:SS
get_basic_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Get Unix epoch timestamp
get_unix_timestamp() {
    date +%s
}

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

# Global log directory (can be overridden)
SPRINTY_LOG_DIR="${SPRINTY_LOG_DIR:-logs}"
SPRINTY_LOG_FILE="${SPRINTY_LOG_FILE:-$SPRINTY_LOG_DIR/sprinty.log}"

# Ensure log directory exists
ensure_log_dir() {
    mkdir -p "$SPRINTY_LOG_DIR"
}

# Log function with timestamps and colors
# Usage: log_status LEVEL MESSAGE
# Levels: INFO, WARN, ERROR, SUCCESS, LOOP, DEBUG
log_status() {
    local level=$1
    local message=$2
    local timestamp=$(get_basic_timestamp)
    local color=""
    local icon=""
    
    case $level in
        "INFO")    color=$BLUE;   icon="ℹ️ " ;;
        "WARN")    color=$YELLOW; icon="⚠️ " ;;
        "ERROR")   color=$RED;    icon="❌" ;;
        "SUCCESS") color=$GREEN;  icon="✅" ;;
        "LOOP")    color=$PURPLE; icon="🔄" ;;
        "DEBUG")   color=$CYAN;   icon="🔍" ;;
        "SPRINT")  color=$GREEN;  icon="🏃" ;;
        "PHASE")   color=$BLUE;   icon="📋" ;;
        *)         color=$NC;     icon="" ;;
    esac
    
    # Console output with color
    echo -e "${color}[$timestamp] [$level] $icon $message${NC}"
    
    # Log file output (no color codes)
    ensure_log_dir
    echo "[$timestamp] [$level] $message" >> "$SPRINTY_LOG_FILE"
}

# Debug logging (only when SPRINTY_DEBUG is set)
log_debug() {
    if [[ "${SPRINTY_DEBUG:-false}" == "true" ]]; then
        log_status "DEBUG" "$1"
    fi
}

# ============================================================================
# FILE UTILITIES
# ============================================================================

# Safely write JSON to a file (atomic write)
safe_write_json() {
    local target_file=$1
    local json_content=$2
    local tmp_file="${target_file}.tmp.$$"
    
    # Validate JSON before writing
    if ! echo "$json_content" | jq '.' > /dev/null 2>&1; then
        log_status "ERROR" "Invalid JSON content for $target_file"
        return 1
    fi
    
    # Write to temp file, then move (atomic)
    echo "$json_content" > "$tmp_file"
    mv "$tmp_file" "$target_file"
}

# Read JSON file with validation
read_json_file() {
    local file=$1
    
    if [[ ! -f "$file" ]]; then
        log_status "ERROR" "File not found: $file"
        return 1
    fi
    
    if ! jq '.' "$file" 2>/dev/null; then
        log_status "ERROR" "Invalid JSON in file: $file"
        return 1
    fi
}

# ============================================================================
# SPRINTY DIRECTORY UTILITIES
# ============================================================================

# Sprinty data directory
SPRINTY_DIR="${SPRINTY_DIR:-.sprinty}"

# Ensure Sprinty directory structure exists
ensure_sprinty_dir() {
    mkdir -p "$SPRINTY_DIR"
    mkdir -p "$SPRINTY_LOG_DIR"
    mkdir -p "sprints"
    mkdir -p "reviews"
}

# Get path to a Sprinty file
sprinty_path() {
    local filename=$1
    echo "$SPRINTY_DIR/$filename"
}

# Check if Sprinty is initialized in current directory
is_sprinty_initialized() {
    [[ -d "$SPRINTY_DIR" ]] && [[ -f "$SPRINTY_DIR/config.json" ]]
}

# ============================================================================
# JSON HELPERS (using jq)
# ============================================================================

# Get value from JSON file
json_get() {
    local file=$1
    local path=$2
    jq -r "$path" "$file" 2>/dev/null
}

# Set value in JSON file
json_set() {
    local file=$1
    local path=$2
    local value=$3
    local tmp_file="${file}.tmp.$$"
    
    jq "$path = $value" "$file" > "$tmp_file" && mv "$tmp_file" "$file"
}

# ============================================================================
# VALIDATION HELPERS
# ============================================================================

# Check if jq is available
check_jq_installed() {
    if ! command -v jq &> /dev/null; then
        log_status "ERROR" "jq is required but not installed"
        echo "Install jq:"
        echo "  Ubuntu/Debian: sudo apt-get install jq"
        echo "  macOS: brew install jq"
        echo "  CentOS/RHEL: sudo yum install jq"
        return 1
    fi
    return 0
}

# Validate required dependencies
check_dependencies() {
    local missing=0
    
    # Check bash version >= 4.0
    if [[ "${BASH_VERSION%%.*}" -lt 4 ]]; then
        log_status "ERROR" "Bash 4.0+ required (current: $BASH_VERSION)"
        missing=1
    fi
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        log_status "ERROR" "jq is required but not installed"
        missing=1
    fi
    
    return $missing
}

# ============================================================================
# EXPORT FUNCTIONS
# ============================================================================

export RED GREEN YELLOW BLUE PURPLE CYAN NC
export SPRINTY_DIR SPRINTY_LOG_DIR SPRINTY_LOG_FILE

export -f get_iso_timestamp
export -f get_next_hour_time
export -f get_basic_timestamp
export -f get_unix_timestamp
export -f ensure_log_dir
export -f log_status
export -f log_debug
export -f safe_write_json
export -f read_json_file
export -f ensure_sprinty_dir
export -f sprinty_path
export -f is_sprinty_initialized
export -f json_get
export -f json_set
export -f check_jq_installed
export -f check_dependencies
