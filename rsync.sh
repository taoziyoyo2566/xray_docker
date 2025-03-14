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
    log_info "Usage: $0 [MODE] [OPTIONS]"
    log_info "Modes:"
    log_info "  sync              Default mode - sync from servers to local (if no mode specified)"
    log_info "  restore           Restore mode - restore from local to servers"
    log_info "Options:"
    log_info "  -s|--server       Specify server list, comma separated (required)"
    log_info "  -d|--directory    Specify remote directory path (default: /opt/docker/reality/nodeInfo/)"
    log_info "  -l|--local-dir    Specify local directory (default: /opt/docker/reality/nodeInfo/)"
    log_info "  -b|--backup-dir   Specify local backup directory (default: /opt/docker/reality/nodeInfo_backup)"
    log_info "  -f|--force        Force overwrite without confirmation in restore mode"
    log_info "  -i|--interactive  Ask for confirmation before overwriting each file in restore mode"
    log_info "  -n|--no-backup    Skip creating backup on remote server during restore"
    log_info "  -h|--help         Display this help message"
    log_info ""
    log_info "Examples:"
    log_info "  # Sync configuration from multiple servers to local"
    log_info "  $0 sync -s server1,server2,server3"
    log_info ""
    log_info "  # Basic restore from local to one server"
    log_info "  $0 restore -s server1"
    log_info ""
    log_info "  # Force restore without confirmation, skip remote backup"
    log_info "  $0 restore -s server1 -f -n"
    log_info ""
    log_info "  # Interactive restore with confirmation for each file"
    log_info "  $0 restore -s server1 -i"
    log_info ""
    log_info "  # Sync from specific directory on servers"
    log_info "  $0 sync -s server1,server2 -d /path/to/remote/dir"
    log_info ""
    log_info "  # Restore to custom directory"
    log_info "  $0 restore -s server1 -d /custom/remote/path -l /local/config/path"
}

# Parse command line arguments
# Set default values
MODE="sync"
SERVERS=()
REMOTE_DIR="/opt/docker/reality/nodeInfo/"
LOCAL_DIR="/opt/docker/reality/nodeInfo/"
BACKUP_DIR="/opt/docker/reality/nodeInfo_backup"
FORCE_MODE=0
INTERACTIVE_MODE=0
SKIP_REMOTE_BACKUP=0

# Check if the first argument is a mode
if [[ "$1" == "sync" || "$1" == "restore" ]]; then
    MODE="$1"
    shift
fi

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -s|--server)
            IFS=',' read -ra SERVERS <<< "$2"
            shift 2
            ;;
        -d|--directory)
            REMOTE_DIR="$2"
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
        -f|--force)
            FORCE_MODE=1
            shift
            ;;
        -i|--interactive)
            INTERACTIVE_MODE=1
            shift
            ;;
        -n|--no-backup)
            SKIP_REMOTE_BACKUP=1
            shift
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
if [ ${#SERVERS[@]} -eq 0 ]; then
    log_error "Please specify server list using -s option, e.g.: $0 $MODE -s server1,server2,server3"
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

# Clean log files older than 30 days
find "$LOG_DIR" -name "rsync_*.log" -mtime +30 -delete

# Function to sync data from servers to local
sync_from_servers() {
    # Ensure local directories exist
    mkdir -p "$LOCAL_DIR" "$BACKUP_DIR"

    # Loop through each source server for synchronization
    for SERVER in "${SERVERS[@]}"; do
        log_info "Starting to sync data from $SERVER..."

        # Check remote server connectivity and rsync
        if ! ssh $SSH_OPTS "$SERVER" "command -v rsync &>/dev/null"; then
            log_error "Cannot connect to server $SERVER or rsync is not installed on the server"
            continue
        fi

        # Check if source directory exists
        if ! ssh $SSH_OPTS "$SERVER" "[ -d \"$REMOTE_DIR\" ]"; then
            log_error "Source directory does not exist on server $SERVER: $REMOTE_DIR"
            continue
        fi

        # First perform rsync dry-run to check files that will be updated
        log_info "Checking files to be updated from $SERVER..."
        rsync -ainv --timeout=30 -e "ssh $SSH_OPTS" \
            --exclude="*/log/*" \
            "$SERVER:$REMOTE_DIR" "$LOCAL_DIR" 2>&1 | grep -v "^$" | tee -a "$LOGFILE"

        # Use rsync to synchronize files, with optimization parameters
        if rsync -avz --timeout=30 -e "ssh $SSH_OPTS" \
            --exclude="*/log/*" \
            --checksum \
            "$SERVER:$REMOTE_DIR" "$LOCAL_DIR" 2>&1 | tee -a "$LOGFILE"; then
            log_info "Successfully synced from $SERVER"
        else
            log_error "Failed to sync from $SERVER"
        fi
    done

    # Clean up old backups
    log_info "Cleaning up backups older than 30 days..."
    find "$BACKUP_DIR" -name '*.tar.gz' -mtime +30 -delete
}

# Function to restore data from local to servers
restore_to_servers() {
    # Check if local directory exists and is not empty
    if [ ! -d "$LOCAL_DIR" ] || [ ! "$(ls -A "$LOCAL_DIR" 2>/dev/null)" ]; then
        log_error "Local directory $LOCAL_DIR does not exist or is empty. Nothing to restore."
        exit 1
    fi

    log_info "Starting to restore configuration to servers..."

    # Loop through each target server for restoration
    for SERVER in "${SERVERS[@]}"; do
        log_info "Preparing to restore data to $SERVER..."

        # Check remote server connectivity and rsync
        if ! ssh $SSH_OPTS "$SERVER" "command -v rsync &>/dev/null"; then
            log_error "Cannot connect to server $SERVER or rsync is not installed on the server"
            continue
        fi

        # Create remote directory if it doesn't exist
        # Remove trailing slash for consistency
        REMOTE_DIR_CLEAN=${REMOTE_DIR%/}
        ssh $SSH_OPTS "$SERVER" "mkdir -p \"$REMOTE_DIR_CLEAN\"" || {
            log_error "Failed to create remote directory on $SERVER: $REMOTE_DIR_CLEAN"
            continue
        }
        
        # Identify directories related to this server
        log_info "Looking for configuration directories related to $SERVER..."
        # Find directories containing the server name
        SERVER_DIRS=$(find "$LOCAL_DIR" -type d -name "*_${SERVER}*" -o -name "*_${SERVER^^}*" -o -name "*_${SERVER,,}*")
        
        if [ -z "$SERVER_DIRS" ]; then
            log_info "No specific directories found for server $SERVER. Will look for directories containing matching node names..."
            # Also look for directories containing nodeInfo files with the server's name
            SERVER_DIRS=$(find "$LOCAL_DIR" -name "nodeInfo-${SERVER}*.json" -o -name "nodeInfo-${SERVER^^}*.json" -o -name "nodeInfo-${SERVER,,}*.json" | xargs -r dirname)
        fi
        
        if [ -z "$SERVER_DIRS" ]; then
            log_error "No configuration directories found for server $SERVER. Skipping..."
            continue
        fi
        
        log_info "Found server-specific directories to restore:"
        echo "$SERVER_DIRS" | tee -a "$LOGFILE"
        
        # Backup remote directory before overwriting
        if [ $SKIP_REMOTE_BACKUP -eq 0 ]; then
            REMOTE_BACKUP="nodeInfo_backup_$(date '+%Y%m%d_%H%M%S')"
            log_info "Creating backup on remote server before restoration..."
            
            # Remove trailing slash from remote directory path
            REMOTE_DIR_CLEAN=${REMOTE_DIR%/}
            REMOTE_PARENT=$(dirname "$REMOTE_DIR_CLEAN")
            
            if ssh $SSH_OPTS "$SERVER" "[ -d \"$REMOTE_DIR_CLEAN\" ] && [ \"\$(ls -A \"$REMOTE_DIR_CLEAN\" 2>/dev/null)\" ] && \
                mkdir -p \"$REMOTE_PARENT/$REMOTE_BACKUP\" && \
                rsync -avz --exclude=\"*/log/*\" \"$REMOTE_DIR_CLEAN/\" \"$REMOTE_PARENT/$REMOTE_BACKUP/\""; then
                log_info "Successfully created backup on $SERVER"
            else
                log_info "Remote directory is empty or backup creation failed on $SERVER, continuing with restore"
            fi
        else
            log_info "Skipping remote backup as requested with -n option"
        fi
        
        # First perform rsync dry-run to check files that will be updated
        log_info "Checking files to be updated on $SERVER..."
        
        # Restore only server-specific directories
        for DIR in $SERVER_DIRS; do
            DIR_NAME=$(basename "$DIR")
            log_info "Checking directory $DIR_NAME for server $SERVER..."
            
            # Remove trailing slash from REMOTE_DIR if present
            REMOTE_DIR_CLEAN=${REMOTE_DIR%/}
            
            rsync -ainv --timeout=30 -e "ssh $SSH_OPTS" \
                --exclude="*/log" --exclude="*/log/*" \
                "$DIR/" "$SERVER:$REMOTE_DIR_CLEAN/$DIR_NAME/" 2>&1 | grep -v "^$" | tee -a "$LOGFILE"
                
            # Use rsync to restore files for this directory with preserved permissions
            if rsync -avz --timeout=30 -e "ssh $SSH_OPTS" \
                --exclude="*/log" --exclude="*/log/*" \
                --perms --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r \
                --checksum \
                "$DIR/" "$SERVER:$REMOTE_DIR_CLEAN/$DIR_NAME/" 2>&1 | tee -a "$LOGFILE"; then
                log_info "Successfully restored $DIR_NAME to $SERVER"
            else
                log_error "Failed to restore $DIR_NAME to $SERVER"
            fi
        done
    done
}

# Function to create local backup
create_local_backup() {
    # Ensure local directories exist
    mkdir -p "$LOCAL_DIR" "$BACKUP_DIR"
    
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
}

# Main execution based on mode
if [ "$MODE" == "sync" ]; then
    log_info "Running in SYNC mode (from servers to local)"
    # Create backup before syncing from servers
    create_local_backup
    sync_from_servers
elif [ "$MODE" == "restore" ]; then
    log_info "Running in RESTORE mode (from local to servers)"
    # No need for local backup in restore mode
    restore_to_servers
else
    log_error "Unknown mode: $MODE"
    show_help
    exit 1
fi

log_info "$MODE task completed!"
