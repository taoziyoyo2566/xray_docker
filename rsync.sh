#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status
set -o pipefail  # Return value of a pipeline is the status of the last command

# Define log related paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
LOGFILE="${LOG_DIR}/rsync_$(date '+%Y%m%d').log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Logging functions
log_info() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a "$LOGFILE" >&2
}

log_error() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOGFILE" >&2
}

# Display help information
show_help() {
    log_info "Usage: $0 -s server1,server2,server3"
    log_info "Options:"
    log_info "  -s|--server       Specify source server list, comma separated (required)"
    log_info "  -d|--directory    Specify remote directory path to sync (default: /opt/docker/reality/nodeInfo/)"
    log_info "  -l|--local-dir    Specify local destination directory (default: /opt/docker/reality/nodeInfo/)"
    log_info "  -b|--backup-dir   Specify local backup directory (default: /opt/docker/reality/nodeInfo_backup)"
    log_info "  -h|--help         Display this help message"
}

# Parse command line arguments
# Set default values
SOURCE_SERVERS=()
SOURCE_DIR="/opt/docker/reality/nodeInfo/"
LOCAL_DIR="/opt/docker/reality/nodeInfo/"
BACKUP_DIR="/opt/docker/reality/nodeInfo_backup"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -s|--server)
            IFS=',' read -ra SOURCE_SERVERS <<< "$2"
            shift 2
            ;;
        -d|--directory)
            SOURCE_DIR="$2"
            shift 2
            ;;
        -l|--local-dir)
            LOCAL_DIR="$2"
            shift 2
            ;;
        -b|--backup-dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Check if server list was provided
if [ ${#SOURCE_SERVERS[@]} -eq 0 ]; then
    log_error "Please specify source server list using -s option, e.g.: $0 -s server1,server2,server3"
    exit 1
fi

# Define SSH parameters
SSH_KEY="$HOME/.ssh/id_rsa"
SSH_OPTS="-o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -i $SSH_KEY"

# Basic checks
if ! command -v rsync >/dev/null 2>&1; then
    log_error "rsync is not installed locally. Please install rsync first."
    exit 1
fi

if [ ! -f "$SSH_KEY" ]; then
    log_error "SSH key file does not exist: $SSH_KEY"
    exit 1
fi

# Ensure local directories exist
mkdir -p "$LOCAL_DIR" "$BACKUP_DIR"

# Clean log files older than 30 days
find "$LOG_DIR" -name "rsync_*.log" -mtime +30 -delete

# Create local backup
log_info "Creating local backup..."
BACKUP_NAME="nodeInfo_$(date '+%Y%m%d_%H%M%S').tar.gz"
if [ -d "$LOCAL_DIR" ] && [ "$(ls -A "$LOCAL_DIR" 2>/dev/null)" ]; then
    log_info "Creating local backup: $BACKUP_NAME"
    if ! tar --exclude='*/log/*' -czf "$BACKUP_DIR/$BACKUP_NAME" -C "$(dirname "$LOCAL_DIR")" "$(basename "$LOCAL_DIR")"; then
        log_error "Failed to create local backup"
    fi
else
    log_info "Local directory is empty or does not exist, skipping backup"
fi

# Loop through each source server for synchronization
for SERVER in "${SOURCE_SERVERS[@]}"; do
    log_info "Starting to sync data from $SERVER..."

    # Check remote server connectivity and rsync
    if ! ssh $SSH_OPTS "$SERVER" "command -v rsync &>/dev/null"; then
        log_error "Cannot connect to server $SERVER or rsync is not installed on the server"
        continue
    fi

    # Check if source directory exists
    if ! ssh $SSH_OPTS "$SERVER" "[ -d \"$SOURCE_DIR\" ]"; then
        log_error "Source directory does not exist on server $SERVER: $SOURCE_DIR"
        continue
    fi

    # First perform rsync dry-run to check files that will be updated
    log_info "Checking files to be updated from $SERVER..."
    rsync -ainv --timeout=30 -e "ssh $SSH_OPTS" \
        --exclude="*/log/*" \
        "$SERVER:$SOURCE_DIR" "$LOCAL_DIR" 2>&1 | grep -v "^$" | tee -a "$LOGFILE"

    # Use rsync to synchronize files, with optimization parameters
    if rsync -avz --timeout=30 -e "ssh $SSH_OPTS" \
        --exclude="*/log/*" \
        --checksum \
        "$SERVER:$SOURCE_DIR" "$LOCAL_DIR" 2>&1 | tee -a "$LOGFILE"; then
        log_info "Successfully synced from $SERVER"
    else
        log_error "Failed to sync from $SERVER"
    fi
done

# Clean up old backups
log_info "Cleaning up backups older than 30 days..."
find "$BACKUP_DIR" -name '*.tar.gz' -mtime +30 -delete

log_info "Sync task completed!"
