#!/usr/bin/env bash
# Sprinty Done Detector
# Completion detection logic for graceful project termination
# Adapted from ralph-cursor-agent exit detection patterns

set -e

# Source utilities (use _LIB_DIR to avoid overwriting caller's SCRIPT_DIR)
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_LIB_DIR/utils.sh"
source "$_LIB_DIR/backlog_manager.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================

EXIT_SIGNALS_FILE="${SPRINTY_DIR:-.sprinty}/.exit_signals"

# Thresholds for exit detection
MAX_CONSECUTIVE_IDLE_LOOPS=${MAX_CONSECUTIVE_IDLE_LOOPS:-5}
MAX_CONSECUTIVE_DONE_SIGNALS=${MAX_CONSECUTIVE_DONE_SIGNALS:-3}
MAX_CONSECUTIVE_TEST_LOOPS=${MAX_CONSECUTIVE_TEST_LOOPS:-5}

# ============================================================================
# INITIALIZATION
# ============================================================================

# Initialize exit signals tracking
init_exit_signals() {
    ensure_sprinty_dir
    
    if [[ -f "$EXIT_SIGNALS_FILE" ]]; then
        if ! jq '.' "$EXIT_SIGNALS_FILE" > /dev/null 2>&1; then
            rm -f "$EXIT_SIGNALS_FILE"
        fi
    fi
    
    if [[ ! -f "$EXIT_SIGNALS_FILE" ]]; then
        cat > "$EXIT_SIGNALS_FILE" << 'EOF'
{
    "idle_loops": [],
    "done_signals": [],
    "completion_indicators": [],
    "test_only_loops": [],
    "last_updated": null
}
EOF
    fi
    
    # Update timestamp
    jq --arg ts "$(get_iso_timestamp)" '.last_updated = $ts' "$EXIT_SIGNALS_FILE" > "${EXIT_SIGNALS_FILE}.tmp" \
        && mv "${EXIT_SIGNALS_FILE}.tmp" "$EXIT_SIGNALS_FILE"
}

# Reset exit signals (for new session/sprint)
reset_exit_signals() {
    ensure_sprinty_dir
    
    # Force recreation by removing existing file
    rm -f "$EXIT_SIGNALS_FILE"
    
    cat > "$EXIT_SIGNALS_FILE" << 'EOF'
{
    "idle_loops": [],
    "done_signals": [],
    "completion_indicators": [],
    "test_only_loops": [],
    "last_updated": null
}
EOF
    
    # Update timestamp
    jq --arg ts "$(get_iso_timestamp)" '.last_updated = $ts' "$EXIT_SIGNALS_FILE" > "${EXIT_SIGNALS_FILE}.tmp" \
        && mv "${EXIT_SIGNALS_FILE}.tmp" "$EXIT_SIGNALS_FILE"
    
    log_status "INFO" "Exit signals reset for new session"
}

# ============================================================================
# SIGNAL RECORDING
# ============================================================================

# Record an idle loop (no progress made)
record_idle_loop() {
    local loop_number=$1
    local reason=${2:-"no_changes"}
    
    init_exit_signals
    
    local timestamp=$(get_iso_timestamp)
    jq --argjson loop "$loop_number" --arg reason "$reason" --arg ts "$timestamp" '
        .idle_loops += [{loop: $loop, reason: $reason, timestamp: $ts}] |
        .idle_loops = (.idle_loops | .[-10:]) |
        .last_updated = $ts
    ' "$EXIT_SIGNALS_FILE" > "${EXIT_SIGNALS_FILE}.tmp" \
        && mv "${EXIT_SIGNALS_FILE}.tmp" "$EXIT_SIGNALS_FILE"
    
    log_debug "Recorded idle loop #$loop_number: $reason"
}

# Record a done signal from agent response
record_done_signal() {
    local loop_number=$1
    local source=${2:-"agent_response"}
    
    init_exit_signals
    
    local timestamp=$(get_iso_timestamp)
    jq --argjson loop "$loop_number" --arg source "$source" --arg ts "$timestamp" '
        .done_signals += [{loop: $loop, source: $source, timestamp: $ts}] |
        .done_signals = (.done_signals | .[-10:]) |
        .last_updated = $ts
    ' "$EXIT_SIGNALS_FILE" > "${EXIT_SIGNALS_FILE}.tmp" \
        && mv "${EXIT_SIGNALS_FILE}.tmp" "$EXIT_SIGNALS_FILE"
    
    log_status "INFO" "Recorded done signal from $source (loop #$loop_number)"
}

# Record a completion indicator (keywords in output)
record_completion_indicator() {
    local loop_number=$1
    local indicator=$2
    
    init_exit_signals
    
    local timestamp=$(get_iso_timestamp)
    jq --argjson loop "$loop_number" --arg indicator "$indicator" --arg ts "$timestamp" '
        .completion_indicators += [{loop: $loop, indicator: $indicator, timestamp: $ts}] |
        .completion_indicators = (.completion_indicators | .[-10:]) |
        .last_updated = $ts
    ' "$EXIT_SIGNALS_FILE" > "${EXIT_SIGNALS_FILE}.tmp" \
        && mv "${EXIT_SIGNALS_FILE}.tmp" "$EXIT_SIGNALS_FILE"
    
    log_debug "Recorded completion indicator: $indicator"
}

# Record a test-only loop (only ran tests, no implementation)
record_test_only_loop() {
    local loop_number=$1
    
    init_exit_signals
    
    local timestamp=$(get_iso_timestamp)
    jq --argjson loop "$loop_number" --arg ts "$timestamp" '
        .test_only_loops += [{loop: $loop, timestamp: $ts}] |
        .test_only_loops = (.test_only_loops | .[-10:]) |
        .last_updated = $ts
    ' "$EXIT_SIGNALS_FILE" > "${EXIT_SIGNALS_FILE}.tmp" \
        && mv "${EXIT_SIGNALS_FILE}.tmp" "$EXIT_SIGNALS_FILE"
    
    log_debug "Recorded test-only loop #$loop_number"
}

# ============================================================================
# DETECTION FROM AGENT OUTPUT
# ============================================================================

# Analyze agent output file for completion signals
analyze_output_for_completion() {
    local output_file=$1
    local loop_number=$2
    
    if [[ ! -f "$output_file" ]]; then
        return 1
    fi
    
    local signals_found=0
    
    # Check for PROJECT_DONE: true in SPRINTY_STATUS block
    if grep -q "PROJECT_DONE:.*true" "$output_file" 2>/dev/null; then
        record_done_signal "$loop_number" "sprinty_status_block"
        signals_found=$((signals_found + 1))
    fi
    
    # NOTE: PHASE_COMPLETE: true is NOT a completion indicator!
    # It's a normal phase transition signal that happens after every phase.
    
    # NOTE: We intentionally DO NOT check for "completion keywords" from agent output.
    # Keyword matching is unreliable and causes false positives (e.g., "Sprint 1 complete"
    # being interpreted as "project complete"). Instead, we rely on:
    # 1. Actual backlog state (check_backlog_completion) - most reliable
    # 2. Explicit PROJECT_DONE: true signal from agent
    # 3. Idle loop detection (no progress being made)
    
    # Detect test-only loop patterns
    if grep -qiE "(only.*test|ran.*tests|test.*pass|all.*tests.*passing)" "$output_file" 2>/dev/null; then
        # Only count as test-only if no implementation was done
        if ! grep -qiE "(implement|creat|add|fix|updat|modif)" "$output_file" 2>/dev/null; then
            record_test_only_loop "$loop_number"
        fi
    fi
    
    echo "$signals_found"
}

# ============================================================================
# PROJECT COMPLETION CHECKS
# ============================================================================

# Check if backlog is complete (all items done)
check_backlog_completion() {
    if ! is_backlog_initialized; then
        return 1  # Not complete, backlog doesn't exist
    fi
    
    local total_items=$(jq '.items | length' "$BACKLOG_FILE")
    local done_items=$(jq '[.items[] | select(.status == "done" or .status == "cancelled")] | length' "$BACKLOG_FILE")
    local undone_items=$((total_items - done_items))
    
    # Check for P1 bugs
    local p1_bugs=$(jq '[.items[] | select(.type == "bug" and .priority == 1 and .status != "done")] | length' "$BACKLOG_FILE")
    
    if [[ $total_items -gt 0 ]] && [[ $undone_items -eq 0 ]] && [[ $p1_bugs -eq 0 ]]; then
        log_status "SUCCESS" "All backlog items complete ($done_items/$total_items)"
        return 0
    fi
    
    log_debug "Backlog incomplete: $undone_items undone, $p1_bugs P1 bugs"
    return 1
}

# Check fix plan completion
check_fix_plan_completion() {
    local fix_plan_file="${FIX_PLAN_FILE:-@fix_plan.md}"
    
    if [[ ! -f "$fix_plan_file" ]]; then
        log_debug "No @fix_plan.md found"
        return 1  # No fix plan, can't determine completion
    fi
    
    local total_items
    local completed_items
    local unchecked_items
    
    total_items=$(grep -c "^- \[" "$fix_plan_file" 2>/dev/null | head -1 || echo "0")
    completed_items=$(grep -c "^- \[x\]" "$fix_plan_file" 2>/dev/null | head -1 || echo "0")
    unchecked_items=$(grep -c "^- \[ \]" "$fix_plan_file" 2>/dev/null | head -1 || echo "0")
    
    # Ensure integers (strip any whitespace)
    total_items=${total_items//[^0-9]/}
    completed_items=${completed_items//[^0-9]/}
    unchecked_items=${unchecked_items//[^0-9]/}
    total_items=${total_items:-0}
    completed_items=${completed_items:-0}
    unchecked_items=${unchecked_items:-0}
    
    if [[ $total_items -gt 0 ]] && [[ $completed_items -eq $total_items ]] && [[ $unchecked_items -eq 0 ]]; then
        log_status "SUCCESS" "All @fix_plan.md items complete ($completed_items/$total_items)"
        return 0
    fi
    
    log_debug "Fix plan incomplete: $unchecked_items unchecked items remain"
    return 1
}

# Check if there's remaining work in fix plan
has_remaining_fix_plan_work() {
    local fix_plan_file="${FIX_PLAN_FILE:-@fix_plan.md}"
    
    if [[ ! -f "$fix_plan_file" ]]; then
        return 1  # No fix plan
    fi
    
    local unchecked
    unchecked=$(grep -c "^- \[ \]" "$fix_plan_file" 2>/dev/null | head -1 || echo "0")
    unchecked=${unchecked//[^0-9]/}
    unchecked=${unchecked:-0}
    
    [[ $unchecked -gt 0 ]]
}

# ============================================================================
# EXIT CONDITION CHECKS
# ============================================================================

# Main function: Check if project should exit gracefully
# Returns: 0 if should exit (with reason in stdout), 1 if should continue
should_exit_gracefully() {
    init_exit_signals
    
    log_debug "Checking exit conditions..."
    
    # First, check hard completion criteria
    
    # 1. Backlog complete
    if check_backlog_completion; then
        # Double-check with fix plan if it exists
        if has_remaining_fix_plan_work; then
            log_debug "Backlog complete but fix plan has remaining work - continuing"
        else
            echo "backlog_complete"
            return 0
        fi
    fi
    
    # 2. Fix plan complete (without remaining work check)
    if check_fix_plan_completion; then
        echo "fix_plan_complete"
        return 0
    fi
    
    # If there's still work in fix plan, don't exit on soft signals
    if has_remaining_fix_plan_work; then
        log_debug "Work remains in @fix_plan.md - soft exit signals ignored"
        return 1
    fi
    
    # Check soft signals (only if no remaining work)
    local signals=$(cat "$EXIT_SIGNALS_FILE")
    
    # 3. Multiple consecutive done signals
    local done_signal_count=$(echo "$signals" | jq '.done_signals | length' 2>/dev/null || echo "0")
    done_signal_count=$((done_signal_count + 0))
    
    if [[ $done_signal_count -ge $MAX_CONSECUTIVE_DONE_SIGNALS ]]; then
        log_status "INFO" "Exit condition: $done_signal_count consecutive done signals"
        echo "done_signals"
        return 0
    fi
    
    # 4. Multiple idle loops
    local idle_loop_count=$(echo "$signals" | jq '.idle_loops | length' 2>/dev/null || echo "0")
    idle_loop_count=$((idle_loop_count + 0))
    
    if [[ $idle_loop_count -ge $MAX_CONSECUTIVE_IDLE_LOOPS ]]; then
        log_status "INFO" "Exit condition: $idle_loop_count consecutive idle loops"
        echo "idle_loops"
        return 0
    fi
    
    # 5. Too many test-only loops
    local test_loop_count=$(echo "$signals" | jq '.test_only_loops | length' 2>/dev/null || echo "0")
    test_loop_count=$((test_loop_count + 0))
    
    if [[ $test_loop_count -ge $MAX_CONSECUTIVE_TEST_LOOPS ]]; then
        log_status "INFO" "Exit condition: $test_loop_count test-only loops (possible saturation)"
        echo "test_saturation"
        return 0
    fi
    
    # 6. Strong completion indicators (3+)
    local completion_count=$(echo "$signals" | jq '.completion_indicators | length' 2>/dev/null || echo "0")
    completion_count=$((completion_count + 0))
    
    if [[ $completion_count -ge 3 ]]; then
        log_status "INFO" "Exit condition: $completion_count strong completion indicators"
        echo "completion_indicators"
        return 0
    fi
    
    log_debug "No exit conditions met - continuing"
    return 1
}

# Check if project should be marked as done
is_project_complete() {
    # Hard requirements for project completion:
    # 1. Backlog must exist and be complete
    # 2. No P1 bugs open
    # 3. (Optional) Fix plan complete if it exists
    
    if ! is_backlog_initialized; then
        return 1
    fi
    
    # Check backlog completion
    if ! check_backlog_completion; then
        return 1
    fi
    
    # Check fix plan if it exists
    if [[ -f "@fix_plan.md" ]]; then
        if has_remaining_fix_plan_work; then
            return 1
        fi
    fi
    
    return 0
}

# ============================================================================
# STATUS DISPLAY
# ============================================================================

# Show exit detection status
show_exit_status() {
    init_exit_signals
    
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║              Exit Detection Status                         ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    
    # Backlog status
    if is_backlog_initialized; then
        local total=$(jq '.items | length' "$BACKLOG_FILE")
        local done=$(jq '[.items[] | select(.status == "done")] | length' "$BACKLOG_FILE")
        local cancelled=$(jq '[.items[] | select(.status == "cancelled")] | length' "$BACKLOG_FILE")
        local remaining=$((total - done - cancelled))
        
        if [[ $remaining -eq 0 && $total -gt 0 ]]; then
            echo -e "Backlog:              ${GREEN}✅ Complete ($done done, $cancelled cancelled)${NC}"
        else
            echo -e "Backlog:              ${YELLOW}⏳ $remaining/$total remaining${NC}"
        fi
    else
        echo -e "Backlog:              ${RED}✗ Not initialized${NC}"
    fi
    
    # Fix plan status
    if [[ -f "@fix_plan.md" ]]; then
        local total=$(grep -c "^- \[" "@fix_plan.md" 2>/dev/null || echo "0")
        local completed=$(grep -c "^- \[x\]" "@fix_plan.md" 2>/dev/null || echo "0")
        local unchecked=$(grep -c "^- \[ \]" "@fix_plan.md" 2>/dev/null || echo "0")
        
        if [[ $unchecked -eq 0 && $total -gt 0 ]]; then
            echo -e "Fix Plan:             ${GREEN}✅ Complete ($completed/$total)${NC}"
        else
            echo -e "Fix Plan:             ${YELLOW}⏳ $unchecked unchecked items${NC}"
        fi
    else
        echo -e "Fix Plan:             ${CYAN}N/A (no @fix_plan.md)${NC}"
    fi
    
    # Exit signals
    if [[ -f "$EXIT_SIGNALS_FILE" ]]; then
        local signals=$(cat "$EXIT_SIGNALS_FILE")
        local idle=$(echo "$signals" | jq '.idle_loops | length' 2>/dev/null || echo "0")
        local done_sig=$(echo "$signals" | jq '.done_signals | length' 2>/dev/null || echo "0")
        local test_only=$(echo "$signals" | jq '.test_only_loops | length' 2>/dev/null || echo "0")
        
        echo ""
        echo -e "${CYAN}Exit Signals:${NC}"
        echo "  Idle loops:         $idle / $MAX_CONSECUTIVE_IDLE_LOOPS"
        echo "  Done signals:       $done_sig / $MAX_CONSECUTIVE_DONE_SIGNALS"
        echo "  Test-only loops:    $test_only / $MAX_CONSECUTIVE_TEST_LOOPS"
    fi
    
    echo ""
    
    # Overall status
    local exit_reason=$(should_exit_gracefully)
    if [[ -n "$exit_reason" ]]; then
        echo -e "Overall Status:       ${GREEN}🏁 Ready to exit ($exit_reason)${NC}"
    else
        echo -e "Overall Status:       ${BLUE}🔄 In progress${NC}"
    fi
}

# ============================================================================
# EXPORT FUNCTIONS
# ============================================================================

export EXIT_SIGNALS_FILE
export MAX_CONSECUTIVE_IDLE_LOOPS MAX_CONSECUTIVE_DONE_SIGNALS MAX_CONSECUTIVE_TEST_LOOPS

export -f init_exit_signals
export -f reset_exit_signals
export -f record_idle_loop
export -f record_done_signal
export -f record_completion_indicator
export -f record_test_only_loop
export -f analyze_output_for_completion
export -f check_backlog_completion
export -f check_fix_plan_completion
export -f has_remaining_fix_plan_work
export -f should_exit_gracefully
export -f is_project_complete
export -f show_exit_status
