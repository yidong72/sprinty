#!/usr/bin/env bash
# Sprinty Rate Limiter
# Manages API call rate limiting to prevent quota exhaustion
# Adapted from ralph-cursor-agent patterns

set -e

# Source utilities (use _LIB_DIR to avoid overwriting caller's SCRIPT_DIR)
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_LIB_DIR/utils.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================

# Rate limiting files
RATE_LIMIT_DIR="${SPRINTY_DIR:-.sprinty}"
CALL_COUNT_FILE="$RATE_LIMIT_DIR/.call_count"
TIMESTAMP_FILE="$RATE_LIMIT_DIR/.last_reset"
RATE_LIMIT_STATE_FILE="$RATE_LIMIT_DIR/.rate_limit_state"

# Default limits (can be overridden via config or environment)
MAX_CALLS_PER_HOUR=${MAX_CALLS_PER_HOUR:-100}
RATE_LIMIT_WINDOW_SECONDS=${RATE_LIMIT_WINDOW_SECONDS:-3600}  # 1 hour

# ============================================================================
# INITIALIZATION
# ============================================================================

# Load rate limit from config file
load_rate_limit_from_config() {
    local config_file="${SPRINTY_DIR:-${PWD}/.sprinty}/config.json"
    if [[ -f "$config_file" ]]; then
        local config_value=$(jq -r '.rate_limiting.max_calls_per_hour // empty' "$config_file" 2>/dev/null)
        if [[ -n "$config_value" && "$config_value" != "null" ]]; then
            MAX_CALLS_PER_HOUR=$config_value
        fi
        
        local wait_value=$(jq -r '.rate_limiting.wait_between_calls_seconds // empty' "$config_file" 2>/dev/null)
        if [[ -n "$wait_value" && "$wait_value" != "null" ]]; then
            RATE_LIMIT_WAIT_SECONDS=$wait_value
        fi
    fi
}

# Initialize rate limiting tracking
init_rate_limiter() {
    ensure_sprinty_dir
    
    # Load config values
    load_rate_limit_from_config
    
    local current_hour=$(date +%Y%m%d%H)
    local last_reset_hour=""

    if [[ -f "$TIMESTAMP_FILE" ]]; then
        last_reset_hour=$(cat "$TIMESTAMP_FILE" 2>/dev/null || echo "")
    fi

    # Reset counter if it's a new hour
    if [[ "$current_hour" != "$last_reset_hour" ]]; then
        echo "0" > "$CALL_COUNT_FILE"
        echo "$current_hour" > "$TIMESTAMP_FILE"
        log_debug "Rate limiter reset for new hour: $current_hour"
    fi

    # Initialize state file if needed
    if [[ ! -f "$RATE_LIMIT_STATE_FILE" ]]; then
        cat > "$RATE_LIMIT_STATE_FILE" << EOF
{
    "max_calls_per_hour": $MAX_CALLS_PER_HOUR,
    "current_calls": 0,
    "last_reset": "$(get_iso_timestamp)",
    "total_calls_session": 0,
    "rate_limit_hits": 0
}
EOF
    fi
}

# ============================================================================
# RATE LIMIT CHECKS
# ============================================================================

# Check if we can make another call
can_make_call() {
    init_rate_limiter
    
    local calls_made=0
    if [[ -f "$CALL_COUNT_FILE" ]]; then
        calls_made=$(cat "$CALL_COUNT_FILE" 2>/dev/null || echo "0")
    fi
    
    # Ensure numeric
    calls_made=$((calls_made + 0))

    if [[ $calls_made -ge $MAX_CALLS_PER_HOUR ]]; then
        log_status "WARN" "Rate limit reached: $calls_made/$MAX_CALLS_PER_HOUR calls this hour"
        return 1  # Cannot make call
    else
        return 0  # Can make call
    fi
}

# Get current call count
get_call_count() {
    if [[ -f "$CALL_COUNT_FILE" ]]; then
        cat "$CALL_COUNT_FILE" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Get remaining calls
get_remaining_calls() {
    local calls_made=$(get_call_count)
    calls_made=$((calls_made + 0))
    local remaining=$((MAX_CALLS_PER_HOUR - calls_made))
    if [[ $remaining -lt 0 ]]; then
        remaining=0
    fi
    echo "$remaining"
}

# ============================================================================
# CALL TRACKING
# ============================================================================

# Increment call counter
# Returns: new call count
increment_call_counter() {
    init_rate_limiter
    
    local calls_made=0
    if [[ -f "$CALL_COUNT_FILE" ]]; then
        calls_made=$(cat "$CALL_COUNT_FILE" 2>/dev/null || echo "0")
    fi
    calls_made=$((calls_made + 0))
    
    calls_made=$((calls_made + 1))
    echo "$calls_made" > "$CALL_COUNT_FILE"
    
    # Update state file
    if [[ -f "$RATE_LIMIT_STATE_FILE" ]]; then
        local state=$(cat "$RATE_LIMIT_STATE_FILE")
        local total_session=$(echo "$state" | jq -r '.total_calls_session' | tr -d '[:space:]')
        total_session=$((total_session + 1))
        
        echo "$state" | jq --argjson cc "$calls_made" --argjson ts "$total_session" \
            '.current_calls = $cc | .total_calls_session = $ts' > "$RATE_LIMIT_STATE_FILE"
    fi
    
    echo "$calls_made"
}

# Record a rate limit hit
record_rate_limit_hit() {
    if [[ -f "$RATE_LIMIT_STATE_FILE" ]]; then
        local state=$(cat "$RATE_LIMIT_STATE_FILE")
        local hits=$(echo "$state" | jq -r '.rate_limit_hits' | tr -d '[:space:]')
        hits=$((hits + 1))
        
        echo "$state" | jq --argjson h "$hits" '.rate_limit_hits = $h' > "$RATE_LIMIT_STATE_FILE"
    fi
    
    log_status "WARN" "Rate limit hit recorded"
}

# ============================================================================
# WAIT FUNCTIONS
# ============================================================================

# Wait for rate limit reset with countdown
wait_for_reset() {
    local calls_made=$(get_call_count)
    log_status "WARN" "Rate limit reached ($calls_made/$MAX_CALLS_PER_HOUR). Waiting for reset..."
    
    # Calculate time until next hour
    local current_minute=$(date +%M)
    local current_second=$(date +%S)
    local wait_time=$(((60 - current_minute - 1) * 60 + (60 - current_second)))
    
    # Ensure positive wait time
    if [[ $wait_time -lt 0 ]]; then
        wait_time=60
    fi
    
    log_status "INFO" "Sleeping for $wait_time seconds until next hour..."
    
    # Countdown display
    while [[ $wait_time -gt 0 ]]; do
        local hours=$((wait_time / 3600))
        local minutes=$(((wait_time % 3600) / 60))
        local seconds=$((wait_time % 60))
        
        printf "\r${YELLOW}Time until reset: %02d:%02d:%02d${NC}" $hours $minutes $seconds
        sleep 1
        ((wait_time--)) || true
    done
    printf "\n"
    
    # Reset counter
    echo "0" > "$CALL_COUNT_FILE"
    echo "$(date +%Y%m%d%H)" > "$TIMESTAMP_FILE"
    
    # Update state
    if [[ -f "$RATE_LIMIT_STATE_FILE" ]]; then
        local state=$(cat "$RATE_LIMIT_STATE_FILE")
        echo "$state" | jq --arg lr "$(get_iso_timestamp)" \
            '.current_calls = 0 | .last_reset = $lr' > "$RATE_LIMIT_STATE_FILE"
    fi
    
    log_status "SUCCESS" "Rate limit reset! Ready for new calls."
}

# Short wait between successful calls
wait_between_calls() {
    local wait_seconds=${1:-5}
    log_debug "Waiting $wait_seconds seconds between calls..."
    sleep $wait_seconds
}

# ============================================================================
# STATUS DISPLAY
# ============================================================================

# Show rate limiter status
show_rate_limit_status() {
    init_rate_limiter
    
    local calls_made=$(get_call_count)
    local remaining=$(get_remaining_calls)
    
    # Calculate percentage
    local percentage=0
    if [[ $MAX_CALLS_PER_HOUR -gt 0 ]]; then
        percentage=$((calls_made * 100 / MAX_CALLS_PER_HOUR))
    fi
    
    # Get session stats
    local total_session=0
    local rate_limit_hits=0
    if [[ -f "$RATE_LIMIT_STATE_FILE" ]]; then
        local state=$(cat "$RATE_LIMIT_STATE_FILE")
        total_session=$(echo "$state" | jq -r '.total_calls_session' | tr -d '[:space:]')
        rate_limit_hits=$(echo "$state" | jq -r '.rate_limit_hits' | tr -d '[:space:]')
    fi
    
    # Color based on usage
    local color=$GREEN
    if [[ $percentage -ge 90 ]]; then
        color=$RED
    elif [[ $percentage -ge 70 ]]; then
        color=$YELLOW
    fi
    
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           Rate Limiter Status                              ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo -e "Calls this hour:      ${color}$calls_made / $MAX_CALLS_PER_HOUR ($percentage%)${NC}"
    echo -e "Remaining calls:      $remaining"
    echo -e "Total session calls:  $total_session"
    echo -e "Rate limit hits:      $rate_limit_hits"
    echo -e "Next reset:           $(get_next_hour_time)"
    echo ""
}

# ============================================================================
# RESET
# ============================================================================

# Force reset rate limiter
reset_rate_limiter() {
    ensure_sprinty_dir
    
    echo "0" > "$CALL_COUNT_FILE"
    echo "$(date +%Y%m%d%H)" > "$TIMESTAMP_FILE"
    
    cat > "$RATE_LIMIT_STATE_FILE" << EOF
{
    "max_calls_per_hour": $MAX_CALLS_PER_HOUR,
    "current_calls": 0,
    "last_reset": "$(get_iso_timestamp)",
    "total_calls_session": 0,
    "rate_limit_hits": 0
}
EOF
    
    log_status "SUCCESS" "Rate limiter reset"
}

# ============================================================================
# EXPORT FUNCTIONS
# ============================================================================

export MAX_CALLS_PER_HOUR RATE_LIMIT_WINDOW_SECONDS
export CALL_COUNT_FILE TIMESTAMP_FILE RATE_LIMIT_STATE_FILE

export -f init_rate_limiter
export -f can_make_call
export -f get_call_count
export -f get_remaining_calls
export -f increment_call_counter
export -f record_rate_limit_hit
export -f wait_for_reset
export -f wait_between_calls
export -f show_rate_limit_status
export -f reset_rate_limiter
