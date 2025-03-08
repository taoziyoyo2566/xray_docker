#!/bin/bash
set -o pipefail

# Define fixed log file name
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
LOGFILE="${LOG_DIR}/user_config_$(date '+%Y%m%d').log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Log functions, redirect output to log file and standard error, add timestamp
log_info() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a "$LOGFILE" >&2
}

log_error() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOGFILE" >&2
}

# Function to display help information, using log_info
show_help() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -s|--server       Set server (required)"
    echo "  -d|--directory    Specify directory identifier (required)"
    echo "  -f|--force        Force overwrite files without user confirmation"
    echo "  -to|--target      Create configuration for target server based on spt server config"
    echo "  -h|--help         Display help information"
    echo ""
    echo "Example:"
    echo "  $0 -s spt -d me"
    echo "  $0 -s spt -d me -to custom"
}

# Function to generate a random port number greater than 20000
generate_random_port() {
    while true; do
        port=$((20000 + RANDOM % 45536))
        if [ "$port" -le 65535 ] && ! is_port_in_use "$port"; then
            echo "$port"
            return
        fi
    done
}

# Check if port is in use
is_port_in_use() {
    local port=$1
    if netstat -tuln | grep -q -E "[:.]$port\s"; then
        return 0  # Port is in use
    else
        return 1  # Port is not in use
    fi
}

# Function to generate a random 8-character alphanumeric string
generate_random_id() {
    tr -dc 'A-Z0-9' </dev/urandom | head -c 8
}

# Function to calculate the expiration date one year from today
calculate_expiration_date() {
    date -d "+100 year" +%Y%m%d
}

# Get the existing directory path by directory identifier
get_existing_directory() {
    local dir_identifier="$1"
    local server="$2"
    
    # Find matching directories
    local matching_dirs=($(find . -maxdepth 1 -type d -name "client_${server}_${dir_identifier}_*" | sort -r))
    
    if [ ${#matching_dirs[@]} -gt 0 ]; then
        echo "${matching_dirs[0]}"
        return 0
    else
        return 1
    fi
}

# Create new directory (if needed)
create_directory() {
    local server="$1"
    local dir_identifier="$2"
    local date_part=$(date +%Y%m%d%H%M)
    
    local dir_name="client_${server}_${dir_identifier}_${date_part}"
    mkdir -p "$dir_name"
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create target directory: $dir_name"
        exit 1
    fi
    log_info "Directory created: $dir_name"
    echo "$dir_name"
}

# Add users
add_users() {
    local users="$1"
    local target_dir="$2"
    local server="$3"
    local force_overwrite="$4"
    
    IFS=',' read -ra USER_ARRAY <<< "$users"
    for user in "${USER_ARRAY[@]}"; do
        # Remove possible spaces
        user=$(echo "$user" | xargs)
        if [ -z "$user" ]; then
            log_error "Username cannot be empty"
            continue
        fi
        
        local target_file="${target_dir}/${user}.json"
        if [ -f "$target_file" ] && [ "$force_overwrite" != "true" ]; then
            read -p "File $target_file already exists. Overwrite? (y/n): " choice
            if [[ ! "$choice" =~ ^[Yy]$ ]]; then
                log_info "Skipping file: $target_file"
                continue
            fi
        fi
        
        port=$(generate_random_port)
        id=$(generate_random_id)
        expiration=$(calculate_expiration_date)
        
        # Generate JSON file, removed r field
        cat > "$target_file" <<EOF
{
  "u": "$user",
  "p": "$port",
  "i": "$id",
  "e": "$expiration",
  "s": "$server"
}
EOF
        if [ $? -eq 0 ]; then
            log_info "File generated: $target_file"
        else
            log_error "Failed to generate file: $target_file"
        fi
    done
}

# Delete users
delete_users() {
    local users="$1"
    local target_dir="$2"
    
    IFS=',' read -ra USER_ARRAY <<< "$users"
    for user in "${USER_ARRAY[@]}"; do
        # Remove possible spaces
        user=$(echo "$user" | xargs)
        if [ -z "$user" ]; then
            log_error "Username cannot be empty"
            continue
        fi
        
        local target_file="${target_dir}/${user}.json"
        if [ -f "$target_file" ]; then
            read -p "Are you sure you want to delete $target_file? (y/n): " choice
            if [[ "$choice" =~ ^[Yy]$ ]]; then
                rm "$target_file"
                if [ $? -eq 0 ]; then
                    log_info "File deleted: $target_file"
                else
                    log_error "Failed to delete file: $target_file"
                fi
            else
                log_info "Canceled deletion of $target_file"
            fi
        else
            log_error "File not found: $target_file"
        fi
    done
}

# Modify user configuration
modify_user() {
    local user="$1"
    local target_dir="$2"
    local server="$3"
    
    # Remove possible spaces
    user=$(echo "$user" | xargs)
    if [ -z "$user" ]; then
        log_error "Username cannot be empty"
        return 1
    fi
    
    local target_file="${target_dir}/${user}.json"
    if [ ! -f "$target_file" ]; then
        log_error "File does not exist: $target_file"
        return 1
    fi
    
    # Read current configuration
    local current_port=$(jq -r '.p' "$target_file")
    local current_id=$(jq -r '.i' "$target_file")
    local current_expiration=$(jq -r '.e' "$target_file")
    
    echo "Current configuration:"
    echo "Port(p): $current_port"
    echo "ID(i): $current_id"
    echo "Expiry Date(e): $current_expiration"
    echo ""
    
    # Ask whether to modify each field
    read -p "Modify port? Current: $current_port (y/n): " modify_port
    if [[ "$modify_port" =~ ^[Yy]$ ]]; then
        read -p "Enter new port (leave empty for random): " new_port
        if [ -z "$new_port" ]; then
            new_port=$(generate_random_port)
        else
            # Validate port format
            if ! [[ "$new_port" =~ ^[0-9]{5}$ ]] || [ "$new_port" -le 20000 ]; then
                log_error "Port must be a 5-digit number greater than 20000"
                new_port=$(generate_random_port)
                log_info "Using randomly generated port: $new_port"
            fi
        fi
        current_port=$new_port
    fi
    
    read -p "Modify ID? Current: $current_id (y/n): " modify_id
    if [[ "$modify_id" =~ ^[Yy]$ ]]; then
        read -p "Enter new ID (leave empty for random): " new_id
        if [ -z "$new_id" ]; then
            new_id=$(generate_random_id)
        else
            # Validate ID format
            if ! [[ "$new_id" =~ ^[A-Z0-9]{8}$ ]]; then
                log_error "ID must be 8 uppercase letters and numbers"
                new_id=$(generate_random_id)
                log_info "Using randomly generated ID: $new_id"
            fi
        fi
        current_id=$new_id
    fi
    
    read -p "Modify expiry date? Current: $current_expiration (y/n): " modify_expiration
    if [[ "$modify_expiration" =~ ^[Yy]$ ]]; then
        read -p "Enter new expiry date (format YYYYMMDD, empty for default): " new_expiration
        if [ -z "$new_expiration" ]; then
            new_expiration=$(calculate_expiration_date)
        else
            # Validate date format
            if ! date -d "$new_expiration" &>/dev/null; then
                log_error "Invalid date format"
                new_expiration=$(calculate_expiration_date)
                log_info "Using default expiry date: $new_expiration"
            fi
        fi
        current_expiration=$new_expiration
    fi
    
    # Generate new JSON file, removed r field
    cat > "$target_file" <<EOF
{
  "u": "$user",
  "p": "$current_port",
  "i": "$current_id",
  "e": "$current_expiration",
  "s": "$server"
}
EOF
    
    if [ $? -eq 0 ]; then
        log_info "File updated: $target_file"
        echo "Configuration updated for: $target_file"
    else
        log_error "Failed to update file: $target_file"
    fi
}

# List all users in the directory
list_users() {
    local target_dir="$1"
    
    echo "User configurations in directory $target_dir:"
    echo "----------------------------------------"
    
    local files=("$target_dir"/*.json)
    if [ ${#files[@]} -eq 0 ] || [ ! -f "${files[0]}" ]; then
        echo "No configuration files found"
        return
    fi
    
    printf "%-15s %-10s %-10s %-12s %-10s\n" "Username" "Port" "ID" "Expiry Date" "Server"
    echo "----------------------------------------"
    
    for file in "$target_dir"/*.json; do
        if [ -f "$file" ]; then
            local user=$(basename "$file" .json)
            local port=$(jq -r '.p' "$file")
            local id=$(jq -r '.i' "$file")
            local expiration=$(jq -r '.e' "$file")
            local server=$(jq -r '.s' "$file")
            
            printf "%-15s %-10s %-10s %-12s %-10s\n" "$user" "$port" "$id" "$expiration" "$server"
        fi
    done
    
    echo "----------------------------------------"
    echo "Total: ${#files[@]} user configurations"
}

# Copy configuration from spt to target server
copy_to_target_server() {
    local source_server="spt"
    local target_server="$1"
    local dir_identifier="$2"
    local force_overwrite="$3"
    
    # Get the existing source directory
    local source_dir
    if ! source_dir=$(get_existing_directory "$dir_identifier" "$source_server"); then
        log_error "No source directory found for server '$source_server' with identifier '$dir_identifier'"
        return 1
    fi
    
    # Create target directory with new server name
    local date_part=$(date +%Y%m%d%H%M)
    local target_dir="client_${target_server}_${dir_identifier}_${date_part}"
    mkdir -p "$target_dir"
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create target directory: $target_dir"
        return 1
    fi
    log_info "Target directory created: $target_dir"
    
    # Copy and modify all user configurations
    local count=0
    for file in "$source_dir"/*.json; do
        if [ -f "$file" ]; then
            local user=$(basename "$file" .json)
            local target_file="${target_dir}/${user}.json"
            
            if [ -f "$target_file" ] && [ "$force_overwrite" != "true" ]; then
                read -p "File $target_file already exists. Overwrite? (y/n): " choice
                if [[ ! "$choice" =~ ^[Yy]$ ]]; then
                    log_info "Skipping file: $target_file"
                    continue
                fi
            fi
            
            # Read configuration from source file
            local port=$(jq -r '.p' "$file")
            local id=$(jq -r '.i' "$file")
            local expiration=$(jq -r '.e' "$file")
            
            # Generate new configuration with target server
            cat > "$target_file" <<EOF
{
  "u": "$user",
  "p": "$port",
  "i": "$id",
  "e": "$expiration",
  "s": "$target_server"
}
EOF
            
            if [ $? -eq 0 ]; then
                log_info "File generated: $target_file (copied from $file)"
                ((count++))
            else
                log_error "Failed to generate file: $target_file"
            fi
        fi
    done
    
    log_info "Successfully copied $count configurations from '$source_server' to '$target_server'"
    echo "Successfully copied $count configurations from '$source_server' to '$target_server'"
    echo "New configurations are in: $target_dir"
    
    return 0
}

# Interactive menu function
show_menu() {
    echo ""
    echo "=========================================="
    echo "       User Configuration System"
    echo "=========================================="
    echo "1. Add User"
    echo "2. Delete User"
    echo "3. Modify User"
    echo "4. List All Users"
    echo "5. Copy to Target Server"
    echo "0. Exit"
    echo "=========================================="
    read -p "Select operation [0-5]: " choice
    echo ""
    
    return "$choice"
}

# Main function
main() {
    # Initialize variables
    local server=""
    local dir_identifier=""
    local force_overwrite=false
    local target_server=""
    
    # Parse command line arguments
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -s|--server)
                server="$2"
                shift 2
                ;;
            -d|--directory)
                dir_identifier="$2"
                shift 2
                ;;
            -f|--force)
                force_overwrite=true
                shift
                ;;
            -to|--target)
                target_server="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown parameter: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Check required parameters
    if [ -z "$server" ]; then
        log_error "Server must be specified (-s|--server)"
        show_help
        exit 1
    fi
    
    if [ -z "$dir_identifier" ]; then
        log_error "Directory identifier must be specified (-d|--directory)"
        show_help
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &>/dev/null; then
        log_error "jq is not installed, please install jq first"
        exit 1
    fi
    
    # If target server specified and source is spt, copy configurations
    if [ -n "$target_server" ] && [ "$server" = "spt" ]; then
        log_info "Copying configurations from 'spt' to '$target_server'"
        copy_to_target_server "$target_server" "$dir_identifier" "$force_overwrite"
        exit $?
    fi
    
    # Find or create directory
    local target_dir
    if ! target_dir=$(get_existing_directory "$dir_identifier" "$server"); then
        log_info "No matching directory found, creating new directory"
        target_dir=$(create_directory "$server" "$dir_identifier")
    else
        log_info "Using existing directory: $target_dir"
    fi
    
    # Interactive menu loop
    while true; do
        show_menu
        choice=$?
        
        case "$choice" in
            0)  # Exit
                log_info "Exit program"
                break
                ;;
            1)  # Add users
                read -p "Enter usernames to add (separate multiple with commas): " users
                if [ -n "$users" ]; then
                    add_users "$users" "$target_dir" "$server" "$force_overwrite"
                else
                    log_error "Username cannot be empty"
                fi
                ;;
            2)  # Delete users
                read -p "Enter usernames to delete (separate multiple with commas): " users
                if [ -n "$users" ]; then
                    delete_users "$users" "$target_dir"
                else
                    log_error "Username cannot be empty"
                fi
                ;;
            3)  # Modify user
                read -p "Enter username to modify: " user
                if [ -n "$user" ]; then
                    if [[ "$user" == *","* ]]; then
                        log_error "Modification only supports one username at a time"
                    else
                        modify_user "$user" "$target_dir" "$server"
                    fi
                else
                    log_error "Username cannot be empty"
                fi
                ;;
            4)  # List all users
                list_users "$target_dir"
                ;;
            5)  # Copy to target server
                read -p "Enter target server name: " new_target
                if [ -n "$new_target" ]; then
                    if [ "$server" = "spt" ]; then
                        copy_to_target_server "$new_target" "$dir_identifier" "$force_overwrite"
                    else
                        log_error "Source server must be 'spt' to use this feature"
                    fi
                else
                    log_error "Target server name cannot be empty"
                fi
                ;;
            *)
                log_error "Invalid selection: $choice"
                ;;
        esac
    done
}

# Execute main function
main "$@"