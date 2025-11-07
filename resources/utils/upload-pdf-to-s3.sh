#!/usr/bin/env bash
#──────────────────────────────────────────────────────────────────────────────
# 📤 Upload PDF to S3
#──────────────────────────────────────────────────────────────────────────────
# Description:
#   Uploads a PDF file to the LedgerIQ S3 bucket for processing.
#
# Usage:
#   ./upload-pdf-to-s3.sh <pdf-file> [options]
#   ./upload-pdf-to-s3.sh receipt.pdf
#   ./upload-pdf-to-s3.sh receipt.pdf --path custom/path/
#   ./upload-pdf-to-s3.sh receipt.pdf --bucket other-bucket
#
# Arguments:
#   pdf-file          Path to the PDF file to upload (required)
#
# Options:
#   --path PATH       S3 path prefix (default: uploads/)
#   --bucket BUCKET   S3 bucket name (default: ledgeriq)
#   --profile PROFILE AWS profile to use (default: dwc_s3)
#   --help            Display this help message
#
# Example:
#   ./upload-pdf-to-s3.sh ~/Documents/receipt-2024-01.pdf
#   # Uploads to: s3://ledgeriq/uploads/receipt-2024-01.pdf
#
#   ./upload-pdf-to-s3.sh invoice.pdf --path invoices/2024/
#   # Uploads to: s3://ledgeriq/invoices/2024/invoice.pdf
#
# Environment:
#   AWS_PROFILE       Can be set instead of using --profile flag
#
# Requirements:
#   - AWS CLI installed and configured
#   - Valid AWS credentials for profile 'dwc_s3'
#   - Read access to the local PDF file
#   - Write access to the S3 bucket
#──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

#──────────────────────────────────────────────────────────────────────────────
# 🎨 Colors and Formatting
#──────────────────────────────────────────────────────────────────────────────

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly RESET='\033[0m'

#──────────────────────────────────────────────────────────────────────────────
# 📋 Default Configuration
#──────────────────────────────────────────────────────────────────────────────

DEFAULT_BUCKET="ledgeriq"
DEFAULT_PATH="uploads/"
DEFAULT_PROFILE="dwc_s3"

#──────────────────────────────────────────────────────────────────────────────
# 🛠️ Helper Functions
#──────────────────────────────────────────────────────────────────────────────

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
    echo -e "\n${BOLD}${CYAN}$*${RESET}"
}

show_help() {
    cat << EOF

${BOLD}📤 Upload PDF to S3${RESET}

${BOLD}USAGE:${RESET}
    $(basename "$0") <pdf-file> [options]

${BOLD}ARGUMENTS:${RESET}
    ${CYAN}pdf-file${RESET}          Path to the PDF file to upload (required)

${BOLD}OPTIONS:${RESET}
    ${CYAN}--path${RESET} PATH       S3 path prefix (default: uploads/)
    ${CYAN}--bucket${RESET} BUCKET   S3 bucket name (default: ledgeriq)
    ${CYAN}--profile${RESET} PROFILE AWS profile to use (default: dwc_s3)
    ${CYAN}--help${RESET}            Display this help message

${BOLD}EXAMPLES:${RESET}
    # Upload to default location (s3://ledgeriq/uploads/)
    $(basename "$0") receipt.pdf

    # Upload to custom path
    $(basename "$0") receipt.pdf --path invoices/2024/

    # Upload to different bucket
    $(basename "$0") receipt.pdf --bucket other-bucket

    # Combine options
    $(basename "$0") receipt.pdf --path docs/ --profile prod

${BOLD}REQUIREMENTS:${RESET}
    • AWS CLI installed and configured
    • Valid AWS credentials for profile '${DEFAULT_PROFILE}'
    • Read access to the local PDF file
    • Write access to the S3 bucket

${BOLD}OUTPUT:${RESET}
    Returns the full S3 URI of the uploaded file:
    s3://ledgeriq/uploads/filename.pdf

EOF
}

check_dependencies() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install it first:"
        echo "  https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        exit 1
    fi
}

validate_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        log_error "File not found: ${file}"
        exit 1
    fi

    if [[ ! -r "$file" ]]; then
        log_error "File not readable: ${file}"
        exit 1
    fi

    # Check if file is a PDF (by extension)
    if [[ ! "$file" =~ \.pdf$ ]] && [[ ! "$file" =~ \.PDF$ ]]; then
        log_warning "File does not have .pdf extension: ${file}"
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Upload cancelled"
            exit 0
        fi
    fi
}

format_bytes() {
    local bytes=$1
    if ((bytes < 1024)); then
        echo "${bytes} B"
    elif ((bytes < 1048576)); then
        echo "$((bytes / 1024)) KB"
    elif ((bytes < 1073741824)); then
        echo "$((bytes / 1048576)) MB"
    else
        echo "$((bytes / 1073741824)) GB"
    fi
}

#──────────────────────────────────────────────────────────────────────────────
# 📝 Argument Parsing
#──────────────────────────────────────────────────────────────────────────────

PDF_FILE=""
S3_PATH="$DEFAULT_PATH"
S3_BUCKET="$DEFAULT_BUCKET"
AWS_PROFILE="$DEFAULT_PROFILE"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_help
            exit 0
            ;;
        --path)
            S3_PATH="$2"
            shift 2
            ;;
        --bucket)
            S3_BUCKET="$2"
            shift 2
            ;;
        --profile)
            AWS_PROFILE="$2"
            shift 2
            ;;
        -*)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            if [[ -z "$PDF_FILE" ]]; then
                PDF_FILE="$1"
            else
                log_error "Multiple files specified. Only one file can be uploaded at a time."
                exit 1
            fi
            shift
            ;;
    esac
done

#──────────────────────────────────────────────────────────────────────────────
# ✅ Validation
#──────────────────────────────────────────────────────────────────────────────

if [[ -z "$PDF_FILE" ]]; then
    log_error "No PDF file specified"
    echo ""
    echo "Usage: $(basename "$0") <pdf-file> [options]"
    echo "Use --help for more information"
    exit 1
fi

check_dependencies
validate_file "$PDF_FILE"

# Normalize S3 path (ensure trailing slash)
if [[ -n "$S3_PATH" ]] && [[ ! "$S3_PATH" =~ /$ ]]; then
    S3_PATH="${S3_PATH}/"
fi

# Remove leading slash if present
S3_PATH="${S3_PATH#/}"

#──────────────────────────────────────────────────────────────────────────────
# 📤 Upload Process
#──────────────────────────────────────────────────────────────────────────────

log_header "📤 Uploading PDF to S3"

# Get file info
FILE_NAME=$(basename "$PDF_FILE")
FILE_SIZE=$(stat -f%z "$PDF_FILE" 2>/dev/null || stat -c%s "$PDF_FILE" 2>/dev/null)
FORMATTED_SIZE=$(format_bytes "$FILE_SIZE")

# Construct S3 URI
S3_KEY="${S3_PATH}${FILE_NAME}"
S3_URI="s3://${S3_BUCKET}/${S3_KEY}"

# Display upload info
log_info "File:    ${BOLD}${FILE_NAME}${RESET}"
log_info "Size:    ${FORMATTED_SIZE}"
log_info "Bucket:  ${S3_BUCKET}"
log_info "Path:    ${S3_PATH}"
log_info "Profile: ${AWS_PROFILE}"
echo ""
log_info "Destination: ${CYAN}${S3_URI}${RESET}"
echo ""

# Perform upload
log_info "Uploading..."

if aws s3 cp "$PDF_FILE" "$S3_URI" \
    --profile "$AWS_PROFILE" \
    --content-type "application/pdf" \
    --no-progress 2>&1; then

    echo ""
    log_success "Upload complete!"
    echo ""
    echo -e "${BOLD}S3 URI:${RESET} ${GREEN}${S3_URI}${RESET}"
    echo ""

    # Output for scripting (clean format on stdout)
    echo "$S3_URI"

    exit 0
else
    echo ""
    log_error "Upload failed"
    echo ""
    log_warning "Troubleshooting:"
    echo "  • Verify AWS profile '${AWS_PROFILE}' is configured"
    echo "  • Check AWS credentials: aws configure list --profile ${AWS_PROFILE}"
    echo "  • Verify S3 bucket exists: aws s3 ls s3://${S3_BUCKET}/ --profile ${AWS_PROFILE}"
    echo "  • Check IAM permissions for s3:PutObject"
    exit 1
fi
