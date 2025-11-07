#!/usr/bin/env bash

# ═══════════════════════════════════════════════════════════════════════════
# S3 File Reader - Read and Display S3 Object Contents
# ═══════════════════════════════════════════════════════════════════════════
#
# Purpose:
#   Read and display the contents of a file stored in S3 to the console.
#   Supports text files, JSON, and other readable formats.
#
# What it does:
#   1. Validates AWS CLI is installed and configured
#   2. Checks that the specified S3 object exists
#   3. Displays file metadata (size, last modified date)
#   4. Downloads and outputs file contents to stdout
#
# Prerequisites:
#   - AWS CLI installed and configured
#   - Valid AWS credentials with S3 read permissions
#   - Network connectivity to AWS S3
#
# Usage:
#   ./s3-read-file.sh --s3 <key>
#   ./s3-read-file.sh --s3 <key> --bucket <bucket-name>
#   ./s3-read-file.sh --s3 <key> --profile <aws-profile>
#
# Examples:
#   ./s3-read-file.sh --s3 pdf-to-images/dd/example.pdf
#   ./s3-read-file.sh --s3 img-to-ocr/abc/123/result.json --bucket ledgeriq
#   ./s3-read-file.sh --s3 uploads/test.txt --profile dwc_s3
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
    echo -e "${BLUE}ℹ${RESET}  $*"
}

log_success() {
    echo -e "${GREEN}✓${RESET}  $*"
}

log_warning() {
    echo -e "${YELLOW}⚠${RESET}  $*"
}

log_error() {
    echo -e "${RED}✗${RESET}  $*" >&2
}

log_header() {
    echo -e "${BOLD}${CYAN}$*${RESET}"
}

# ═══════════════════════════════════════════════════════════════════════════
# Help Documentation
# ═══════════════════════════════════════════════════════════════════════════

show_help() {
    cat << EOF

${BOLD}${CYAN}📄 S3 File Reader${RESET}

Read and display the contents of a file stored in Amazon S3.

${BOLD}USAGE:${RESET}
    $0 --s3 <key> [OPTIONS]

${BOLD}REQUIRED ARGUMENTS:${RESET}
    --s3 <key>              S3 object key (path within bucket)

${BOLD}OPTIONS:${RESET}
    --bucket <name>         S3 bucket name (default: ${DEFAULT_BUCKET})
    --profile <name>        AWS CLI profile (default: ${DEFAULT_PROFILE})
    --region <region>       AWS region (default: ${DEFAULT_REGION})
    -h, --help              Show this help message

${BOLD}EXAMPLES:${RESET}
    ${CYAN}# Read a JSON file from default bucket${RESET}
    $0 --s3 img-to-ocr/dd/bd967dceba1bc4f4195b2fd91c55c8/result.json

    ${CYAN}# Read a file from a specific bucket${RESET}
    $0 --s3 uploads/document.txt --bucket my-bucket

    ${CYAN}# Use a different AWS profile${RESET}
    $0 --s3 logs/app.log --profile production

    ${CYAN}# Combine all options${RESET}
    $0 --s3 data/file.json --bucket ledgeriq --profile dwc_s3 --region us-west-2

${BOLD}REQUIREMENTS:${RESET}
    - AWS CLI must be installed (https://aws.amazon.com/cli/)
    - AWS credentials must be configured
    - Read permissions for the specified S3 bucket
    - Network connectivity to AWS

${BOLD}OUTPUT:${RESET}
    File metadata is displayed to stderr (colored)
    File contents are displayed to stdout (unformatted)
    This allows piping content to other commands or files

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
# S3 Object Validation
# ═══════════════════════════════════════════════════════════════════════════

validate_s3_object() {
    local bucket="$1"
    local key="$2"
    local profile="$3"
    local region="$4"

    log_info "Checking if object exists: s3://${bucket}/${key}"

    if ! aws s3api head-object \
        --bucket "$bucket" \
        --key "$key" \
        --profile "$profile" \
        --region "$region" \
        &> /dev/null; then
        log_error "Object not found: s3://${bucket}/${key}"
        log_error "Please verify:"
        log_error "  - Bucket name is correct"
        log_error "  - Object key exists"
        log_error "  - AWS profile has read permissions"
        exit 1
    fi

    log_success "Object exists"
}

# ═══════════════════════════════════════════════════════════════════════════
# Get and Display File Metadata
# ═══════════════════════════════════════════════════════════════════════════

display_file_metadata() {
    local bucket="$1"
    local key="$2"
    local profile="$3"
    local region="$4"

    log_info "Fetching file metadata..."

    local metadata
    metadata=$(aws s3api head-object \
        --bucket "$bucket" \
        --key "$key" \
        --profile "$profile" \
        --region "$region" 2>&1)

    if [[ $? -ne 0 ]]; then
        log_error "Failed to fetch metadata"
        return 1
    fi

    # Extract key information
    local size
    local last_modified
    local content_type

    size=$(echo "$metadata" | grep -i '"ContentLength"' | sed 's/.*: \([0-9]*\).*/\1/')
    last_modified=$(echo "$metadata" | grep -i '"LastModified"' | sed 's/.*: "\(.*\)".*/\1/')
    content_type=$(echo "$metadata" | grep -i '"ContentType"' | sed 's/.*: "\(.*\)".*/\1/' || echo "unknown")

    # Format size for human readability
    local human_size
    if [[ -n "$size" && "$size" =~ ^[0-9]+$ ]]; then
        if [[ $size -lt 1024 ]]; then
            human_size="${size} B"
        elif [[ $size -lt 1048576 ]]; then
            human_size="$(( size / 1024 )) KB"
        else
            human_size="$(( size / 1048576 )) MB"
        fi
    else
        human_size="unknown"
    fi

    log_header "═══════════════════════════════════════════════════════════════"
    log_info "Bucket:        ${bucket}"
    log_info "Key:           ${key}"
    log_info "Size:          ${human_size}"
    log_info "Content Type:  ${content_type}"
    log_info "Last Modified: ${last_modified}"
    log_header "═══════════════════════════════════════════════════════════════"
    echo ""  # Add spacing before content
}

# ═══════════════════════════════════════════════════════════════════════════
# Read and Display File Contents
# ═══════════════════════════════════════════════════════════════════════════

read_file_contents() {
    local bucket="$1"
    local key="$2"
    local profile="$3"
    local region="$4"

    log_info "Reading file contents..." >&2
    echo "" >&2  # Add spacing

    # Download to stdout
    if ! aws s3 cp \
        "s3://${bucket}/${key}" \
        - \
        --profile "$profile" \
        --region "$region" \
        --quiet 2>/dev/null; then
        log_error "Failed to read file contents"
        log_error "The file may be binary or inaccessible"
        exit 1
    fi

    echo "" >&2  # Add spacing after content
    log_success "File read successfully" >&2
}

# ═══════════════════════════════════════════════════════════════════════════
# Argument Parsing
# ═══════════════════════════════════════════════════════════════════════════

parse_arguments() {
    # Initialize variables
    S3_KEY=""
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
                S3_KEY="$2"
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
    if [[ -z "$S3_KEY" ]]; then
        log_error "Missing required argument: --s3 <key>"
        log_info "Use --help to see usage"
        exit 1
    fi

    # Normalize S3 key (remove leading slash if present)
    S3_KEY="${S3_KEY#/}"
}

# ═══════════════════════════════════════════════════════════════════════════
# Main Execution
# ═══════════════════════════════════════════════════════════════════════════

main() {
    # Parse command line arguments
    parse_arguments "$@"

    # Display header
    log_header ""
    log_header "📄 S3 File Reader"
    log_header ""

    # Check dependencies
    check_dependencies

    # Validate S3 object exists
    validate_s3_object "$BUCKET" "$S3_KEY" "$PROFILE" "$REGION"

    # Display file metadata
    display_file_metadata "$BUCKET" "$S3_KEY" "$PROFILE" "$REGION"

    # Read and display file contents
    read_file_contents "$BUCKET" "$S3_KEY" "$PROFILE" "$REGION"
}

# Run main function
main "$@"
