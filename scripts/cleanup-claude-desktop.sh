#!/bin/bash
# Cleans up Claude Desktop's Application Support folder to prevent bloat.
# Scheduled via launchd to run weekly.
#
# What it cleans:
#   - Old Claude Code versions (keeps only the latest)
#   - Old Claude Code VM versions (keeps only the latest)
#   - Electron browser cache
#   - Old agent-mode session data (keeps last 7 days)

set -euo pipefail

CLAUDE_DIR="$HOME/Library/Application Support/Claude"
LOG_FILE="$HOME/Library/Logs/claude-cleanup.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

cleanup_old_versions() {
    local dir="$1"
    local label="$2"

    if [ ! -d "$dir" ]; then
        return
    fi

    # List version directories, sorted newest first
    local versions
    versions=$(ls -1t "$dir" 2>/dev/null | grep -v '^\.' || true)
    local count
    count=$(echo "$versions" | grep -c . || true)

    if [ "$count" -le 1 ]; then
        return
    fi

    # Keep the newest, delete the rest
    echo "$versions" | tail -n +2 | while read -r old_version; do
        local old_path="$dir/$old_version"
        local size
        size=$(du -sh "$old_path" 2>/dev/null | cut -f1)
        rm -rf "$old_path"
        log "Removed old $label version: $old_version ($size)"
    done
}

log "=== Claude Desktop cleanup started ==="

# 1. Clean old Claude Code versions
cleanup_old_versions "$CLAUDE_DIR/claude-code" "Claude Code"
cleanup_old_versions "$CLAUDE_DIR/claude-code-vm" "Claude Code VM"

# 2. Clear Electron browser cache
if [ -d "$CLAUDE_DIR/Cache" ]; then
    size=$(du -sh "$CLAUDE_DIR/Cache" 2>/dev/null | cut -f1)
    rm -rf "$CLAUDE_DIR/Cache/Cache_Data"
    log "Cleared browser cache ($size)"
fi

# 3. Clear GPU/graphics caches
for cache_dir in DawnGraphiteCache DawnWebGPUCache GPUCache; do
    if [ -d "$CLAUDE_DIR/$cache_dir" ]; then
        rm -rf "$CLAUDE_DIR/$cache_dir"
        log "Cleared $cache_dir"
    fi
done

# 4. Clean old agent-mode session data (keep last 7 days)
if [ -d "$CLAUDE_DIR/local-agent-mode-sessions" ]; then
    find "$CLAUDE_DIR/local-agent-mode-sessions" -maxdepth 1 -type d -mtime +7 \
        ! -path "$CLAUDE_DIR/local-agent-mode-sessions" \
        -exec rm -rf {} + 2>/dev/null || true
    log "Cleaned old agent-mode sessions (older than 7 days)"
fi

# 5. Clean old claude-code-sessions data (keep last 7 days)
if [ -d "$CLAUDE_DIR/claude-code-sessions" ]; then
    find "$CLAUDE_DIR/claude-code-sessions" -maxdepth 1 -type d -mtime +7 \
        ! -path "$CLAUDE_DIR/claude-code-sessions" \
        -exec rm -rf {} + 2>/dev/null || true
    log "Cleaned old claude-code-sessions (older than 7 days)"
fi

# Report
total_size=$(du -sh "$CLAUDE_DIR" 2>/dev/null | cut -f1)
log "Cleanup complete. Total Claude Desktop size: $total_size"
log "=== Done ==="
