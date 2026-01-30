#!/bin/bash

# TIGER Geocoder Data Loader
# Main entry point for loading TIGER data
# Usage: ./load-tiger-data.sh [OPTIONS] STATE_CODE [STATE_CODE2 ...]

set -e

# Configuration
export POSTGRES_USER="${POSTGRES_USER:-postgres}"
export POSTGRES_DB="${POSTGRES_DB:-postgres}"
TIGER_YEAR="${TIGER_YEAR:-2024}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#############################
# HELPER FUNCTIONS
#############################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Display usage
show_usage() {
    cat <<EOF
TIGER Geocoder Data Loader

Usage:
    $0 [OPTIONS] STATE_CODE [STATE_CODE2 ...]
    $0 --with-nation STATE_CODE [STATE_CODE2 ...]
    $0 --help

Options:
    --with-nation     Automatically load national data if not present
    --help, -h        Show this help message

Arguments:
    STATE_CODE        Two-letter state code (e.g., CA, NY, TX, TN)

Examples:
    $0 TN                          # Load Tennessee (requires national data loaded first)
    $0 --with-nation TN           # Load Tennessee (auto-loads national data if needed)
    $0 CA NY TX                   # Load California, New York, and Texas
    $0 --with-nation CA NY        # Load CA and NY with auto national data

State Codes:
    AL AK AZ AR CA CO CT DE FL GA HI ID IL IN IA KS KY LA ME MD
    MA MI MN MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA RI SC
    SD TN TX UT VT VA WA WV WI WY DC

Data Size per State:
    Small state (RI, DE):          2-3 GB
    Medium state (CO, AZ, TN):     4-6 GB
    Large state (CA, TX, NY, FL):  8-12 GB

Loading Time per State (4 CPU / 8GB RAM):
    Single small state:   30-45 minutes
    Single medium state:  45-60 minutes
    Single large state:   60-90 minutes

Prerequisites:
    National data must be loaded first (STATE and COUNTY tables).
    Use --with-nation flag to load automatically, or run:
      /usr/local/bin/load-tiger-nation.sh

Environment Variables:
    POSTGRES_USER     PostgreSQL username (default: postgres)
    POSTGRES_DB       Database name (default: postgres)
    POSTGRES_PASSWORD PostgreSQL password (required)
    TIGER_YEAR        TIGER data year (default: 2024)

For detailed documentation, see:
    /usr/local/share/doc/postgres-postgis/TIGER_DATA.md
    https://github.com/dawsonlp/docker_images/tree/main/postgres-postgis
EOF
}

# Check PostgreSQL connectivity
check_postgres() {
    if ! pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1; then
        log_error "PostgreSQL is not ready"
        log_error "Please ensure the database is running"
        exit 1
    fi
}

# Check if national data is loaded
check_national_data() {
    local count=$(psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc \
        "SELECT COUNT(*) FROM tiger_data.county_all_lookup LIMIT 1;" 2>/dev/null || echo "0")

    if [ "$count" -gt 0 ]; then
        return 0  # Loaded
    fi
    return 1  # Not loaded
}

# Load national data
load_national_if_needed() {
    if check_national_data; then
        log_info "National data already loaded"
        return 0
    fi

    log_info "National data not found. Loading..."
    if [ -x /usr/local/bin/load-tiger-nation.sh ]; then
        /usr/local/bin/load-tiger-nation.sh
    else
        log_error "National data loader not found"
        log_error "Expected: /usr/local/bin/load-tiger-nation.sh"
        exit 1
    fi
}

# Validate state codes
validate_states() {
    local valid_states="AL AK AZ AR CA CO CT DE FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA RI SC SD TN TX UT VT VA WA WV WI WY DC"

    for state in "$@"; do
        local state_upper=$(echo "$state" | tr '[:lower:]' '[:upper:]')

        if ! echo "$valid_states" | grep -qw "$state_upper"; then
            log_error "Invalid state code: $state"
            log_error "Valid codes: $valid_states"
            exit 1
        fi
    done
}

# Estimate workload
estimate_workload() {
    local states=("$@")
    local count=${#states[@]}

    echo ""
    log_info "=========================================="
    log_info "TIGER Data Loading Estimate"
    log_info "=========================================="
    log_info "States to load: ${count}"
    log_info "States: ${states[*]}"
    log_info ""

    if [ "$count" -eq 1 ]; then
        log_info "Estimated storage: 3-10 GB"
        log_info "Estimated time: 30-90 minutes"
    elif [ "$count" -le 5 ]; then
        log_info "Estimated storage: $((count * 5))-$((count * 10)) GB"
        log_info "Estimated time: $((count / 2 + 1))-$((count * 2)) hours"
    else
        log_info "Estimated storage: $((count * 5))-$((count * 8)) GB"
        log_info "Estimated time: $((count / 2))-$((count * 2)) hours"
    fi

    log_info ""
    log_info "This process will:"
    log_info "  1. Download data from US Census Bureau"
    log_info "  2. Create database tables and indexes"
    log_info "  3. Load data (this is the slow part)"
    log_info "  4. Analyze tables for query optimization"
    log_info "=========================================="
    echo ""
}

# Load states using direct loader
load_states() {
    local states=("$@")

    if [ -x /usr/local/bin/load-tiger-state-direct.sh ]; then
        /usr/local/bin/load-tiger-state-direct.sh "${states[@]}"
    else
        log_error "State data loader not found"
        log_error "Expected: /usr/local/bin/load-tiger-state-direct.sh"
        exit 1
    fi
}

#############################
# MAIN EXECUTION
#############################

main() {
    local start_time=$(date +%s)
    local auto_load_nation=false
    local states=()

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --with-nation)
                auto_load_nation=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                states+=("$1")
                shift
                ;;
        esac
    done

    # Validate we have states
    if [ ${#states[@]} -eq 0 ]; then
        log_error "No state codes provided"
        echo ""
        show_usage
        exit 1
    fi

    # Validate state codes
    validate_states "${states[@]}"

    # Check prerequisites
    check_postgres

    # Handle national data
    if [ "$auto_load_nation" = true ]; then
        load_national_if_needed
    else
        if ! check_national_data; then
            log_error "National data not loaded!"
            log_error ""
            log_error "You must load national data first. Either:"
            log_error "  1. Run: /usr/local/bin/load-tiger-nation.sh"
            log_error "  2. Use: $0 --with-nation ${states[*]}"
            log_error ""
            exit 1
        fi
    fi

    # Show estimate
    estimate_workload "${states[@]}"

    # Confirm for multiple states
    if [ ${#states[@]} -gt 3 ]; then
        read -p "Continue with loading ${#states[@]} states? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            log_info "Aborted by user"
            exit 0
        fi
    fi

    # Load the states
    log_info "Starting state data loading..."
    load_states "${states[@]}"

    # Summary
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local hours=$((duration / 3600))
    local minutes=$(((duration % 3600) / 60))

    echo ""
    log_info "=========================================="
    log_success "TIGER Data Loading Complete!"
    log_info "=========================================="
    log_success "Loaded: ${#states[@]} state(s)"
    log_info "Total time: ${hours}h ${minutes}m"
    log_info "=========================================="
    echo ""
    log_info "You can now test geocoding:"
    log_info "  SELECT * FROM geocode('123 Main St, Nashville, TN', 1);"
    echo ""
}

# Run main
main "$@"
