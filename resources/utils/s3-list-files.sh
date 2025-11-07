#!/usr/bin/env bash

# ═══════════════════════════════════════════════════════════════════════════
# S3 Directory Lister - Recursively List S3 Objects
# ═══════════════════════════════════════════════════════════════════════════
#
# Purpose:
#   Recursively list all files within an S3 directory (prefix) and display
#   their full S3 URIs.
#
# What it does:
#   1. Validates AWS CLI is installed and configured
#   2. Lists all objects under the specified S3 prefix/path
#   3. Displays full S3 URIs (s3://bucket/key) for each object
#   4. Shows file count and total size summary
#   5. Provides friendly feedback if no files are found
#
# Prerequisites:
#   - AWS CLI installed and configured
#   - Valid AWS credentials with S3 read permissions
#   - Network connectivity to AWS S3
#
# Usage:
#   ./s3-list-files.sh --s3 <path>
#   ./s3-list-files.sh --s3 <path> --bucket <bucket-name>
#   ./s3-list-files.sh --s3 <path> --profile <aws-profile>
#
# Examples:
#   ./s3-list-files.sh --s3 pdf-to-images/
#   ./s3-list-files.sh --s3 img-to-ocr/dd/ --bucket ledgeriq
#   ./s3-list-files.sh --s3 uploads/ --profile dwc_s3
#
# Author: LedgerIQ Team
# Date: 2025-11-07
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════
# Color Definitions
# ═══════════════════════════════════════════════════════════════════════════

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly RESET='\033[0m'

# ═══════════════════════════════════════════════════════════════════════════
# Default Configuration
# ═══════════════════════════════════════════════════════════════════════════

DEFAULT_BUCKET="ledgeriq"
DEFAULT_PROFILE="dwc_s3"
DEFAULT_REGION="us-west-2"

# ═══════════════════════════════════════════════════════════════════════════
# Logging Functions
# ═══════════════════════════════════════════════════════════════════════════

log_info() {
    echo -e "${BLUE}ℹ${RESET}  $*" >&2
}

log_success() {
    echo -e "${GREEN}✓${RESET}  $*" >&2
}

log_warning() {
    echo -e "${YELLOW}⚠${RESET}  $*" >&2
}

log_error() {
    echo -e "${RED}✗${RESET}  $*" >&2
}

log_header() {
    echo -e "${BOLD}${CYAN}$*${RESET}" >&2
}

# ═══════════════════════════════════════════════════════════════════════════
# Help Documentation
# ═══════════════════════════════════════════════════════════════════════════

show_help() {
    cat << EOF

${BOLD}${CYAN}📂 S3 Directory Lister${RESET}

Recursively list all files within an S3 directory and display their full paths.

${BOLD}USAGE:${RESET}
    $0 --s3 <path> [OPTIONS]

${BOLD}REQUIRED ARGUMENTS:${RESET}
    --s3 <path>             S3 prefix/path (directory within bucket)
                           Trailing slash optional

${BOLD}OPTIONS:${RESET}
    --bucket <name>         S3 bucket name (default: ${DEFAULT_BUCKET})
    --profile <name>        AWS CLI profile (default: ${DEFAULT_PROFILE})
    --region <region>       AWS region (default: ${DEFAULT_REGION})
    -h, --help              Show this help message

${BOLD}EXAMPLES:${RESET}
    ${CYAN}# List all files in pdf-to-images directory${RESET}
    $0 --s3 pdf-to-images/

    ${CYAN}# List files in a specific subdirectory${RESET}
    $0 --s3 img-to-ocr/dd/bd967dceba1bc4f4195b2fd91c55c8/

    ${CYAN}# Use a different bucket${RESET}
    $0 --s3 logs/ --bucket my-bucket

    ${CYAN}# Use a different AWS profile${RESET}
    $0 --s3 uploads/ --profile production

    ${CYAN}# Combine all options${RESET}
    $0 --s3 data/ --bucket ledgeriq --profile dwc_s3 --region us-west-2

${BOLD}REQUIREMENTS:${RESET}
    - AWS CLI must be installed (https://aws.amazon.com/cli/)
    - AWS credentials must be configured
    - List permissions for the specified S3 bucket
    - Network connectivity to AWS

${BOLD}OUTPUT:${RESET}
    File paths are displayed to stdout (one per line)
    Metadata and summaries are displayed to stderr (colored)
    This allows piping file paths to other commands

    ${CYAN}Example output format:${RESET}
    s3://ledgeriq/pdf-to-images/dd/file1.jpg
    s3://ledgeriq/pdf-to-images/dd/file2.jpg
    s3://ledgeriq/pdf-to-images/dd/file3.jpg

EOF
}

# ═══════════════════════════════════════════════════════════════════════════
# Dependency Checking
# ═══════════════════════════════════════════════════════════════════════════

check_dependencies() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install it first:"
        log_error "  https://aws.amazon.com/cli/"
        exit 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# Format File Size for Human Readability
# ═══════════════════════════════════════════════════════════════════════════

format_size() {
    local size=$1

    if [[ $size -lt 1024 ]]; then
        echo "${size} B"
    elif [[ $size -lt 1048576 ]]; then
        echo "$(awk "BEGIN {printf \"%.1f\", $size/1024}") KB"
    elif [[ $size -lt 1073741824 ]]; then
        echo "$(awk "BEGIN {printf \"%.1f\", $size/1048576}") MB"
    else
        echo "$(awk "BEGIN {printf \"%.2f\", $size/1073741824}") GB"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# List S3 Objects Recursively
# ═══════════════════════════════════════════════════════════════════════════

list_s3_objects() {
    local bucket="$1"
    local prefix="$2"
    local profile="$3"
    local region="$4"

    log_info "Searching for files in: s3://${bucket}/${prefix}"
    echo "" >&2

    # List objects and capture output
    local list_output
    list_output=$(aws s3api list-objects-v2 \
        --bucket "$bucket" \
        --prefix "$prefix" \
        --profile "$profile" \
        --region "$region" \
        2>&1)

    if [[ $? -ne 0 ]]; then
        log_error "Failed to list objects in s3://${bucket}/${prefix}"
        log_error "AWS CLI error:"
        echo "$list_output" >&2
        exit 1
    fi

    # Check if any objects were found
    local object_count
    object_count=$(echo "$list_output" | grep -c '"Key":' || true)

    if [[ $object_count -eq 0 ]]; then
        log_header "═══════════════════════════════════════════════════════════════"
        log_warning "No files found in s3://${bucket}/${prefix}"
        log_info "Possible reasons:"
        log_info "  • The directory is empty"
        log_info "  • The path doesn't exist"
        log_info "  • You don't have permissions to list objects"
        log_info "  • The prefix/path may be misspelled"
        log_header "═══════════════════════════════════════════════════════════════"
        return 0
    fi

    # Parse and display objects
    local total_size=0
    local file_count=0

    log_header "═══════════════════════════════════════════════════════════════"
    log_success "Found ${object_count} file(s)"
    log_header "═══════════════════════════════════════════════════════════════"
    echo "" >&2

    # Extract keys and sizes, then output
    while IFS= read -r line; do
        if [[ $line =~ \"Key\":[[:space:]]*\"([^\"]+)\" ]]; then
            local key="${BASH_REMATCH[1]}"

            # Output the full S3 URI to stdout
            echo "s3://${bucket}/${key}"

            ((file_count++))
        elif [[ $line =~ \"Size\":[[:space:]]*([0-9]+) ]]; then
            local size="${BASH_REMATCH[1]}"
            ((total_size+=size))
        fi
    done <<< "$list_output"

    # Display summary
    echo "" >&2
    log_header "═══════════════════════════════════════════════════════════════"
    log_info "Total files:  ${file_count}"
    log_info "Total size:   $(format_size $total_size)"
    log_info "Location:     s3://${bucket}/${prefix}"
    log_header "═══════════════════════════════════════════════════════════════"
    log_success "Listing complete"
}

# ═══════════════════════════════════════════════════════════════════════════
# Argument Parsing
# ═══════════════════════════════════════════════════════════════════════════

parse_arguments() {
    # Initialize variables
    S3_PATH=""
    BUCKET="$DEFAULT_BUCKET"
    PROFILE="$DEFAULT_PROFILE"
    REGION="$DEFAULT_REGION"

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            --s3)
                if [[ -z "${2-}" ]]; then
                    log_error "Missing value for --s3"
                    exit 1
                fi
                S3_PATH="$2"
                shift 2
                ;;
            --bucket)
                if [[ -z "${2-}" ]]; then
                    log_error "Missing value for --bucket"
                    exit 1
                fi
                BUCKET="$2"
                shift 2
                ;;
            --profile)
                if [[ -z "${2-}" ]]; then
                    log_error "Missing value for --profile"
                    exit 1
                fi
                PROFILE="$2"
                shift 2
                ;;
            --region)
                if [[ -z "${2-}" ]]; then
                    log_error "Missing value for --region"
                    exit 1
                fi
                REGION="$2"
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                log_info "Use --help to see available options"
                exit 1
                ;;
            *)
                log_error "Unexpected argument: $1"
                log_info "Use --help to see usage"
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$S3_PATH" ]]; then
        log_error "Missing required argument: --s3 <path>"
        log_info "Use --help to see usage"
        exit 1
    fi

    # Normalize S3 path (remove leading slash if present)
    S3_PATH="${S3_PATH#/}"

    # Add trailing slash if not present (for prefix matching)
    if [[ ! "$S3_PATH" =~ /$ ]] && [[ -n "$S3_PATH" ]]; then
        S3_PATH="${S3_PATH}/"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# Main Execution
# ═══════════════════════════════════════════════════════════════════════════

main() {
    # Parse command line arguments
    parse_arguments "$@"

    # Display header
    log_header ""
    log_header "📂 S3 Directory Lister"
    log_header ""

    # Check dependencies
    check_dependencies

    # List S3 objects
    list_s3_objects "$BUCKET" "$S3_PATH" "$PROFILE" "$REGION"
}

# Run main function
main "$@"
