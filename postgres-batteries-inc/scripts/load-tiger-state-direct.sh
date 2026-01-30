#!/bin/bash

# TIGER State Data Loader - Using PostGIS Generator Functions
# Loads Census Bureau TIGER/Line data for specific states
# Requires national data to be loaded first (run load-tiger-nation.sh)
#
# Usage: ./load-tiger-state-direct.sh STATE_CODE [STATE_CODE2 ...]
# Example: ./load-tiger-state-direct.sh TN
#          ./load-tiger-state-direct.sh CA NY TX

set -e

# Configuration
SCRIPTDIR="/gisdata/scripts"
TIGER_YEAR="${TIGER_YEAR:-2024}"

# PostgreSQL connection settings
export PGBIN=/usr/lib/postgresql/18/bin
export PGPORT=${PGPORT:-5432}
export PGHOST=${PGHOST:-localhost}
export PGUSER=${POSTGRES_USER:-postgres}
export PGPASSWORD=${POSTGRES_PASSWORD}
export PGDATABASE=${POSTGRES_DB:-postgres}

PSQL="${PGBIN}/psql"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#############################
# HELPER FUNCTIONS
#############################

log_info() { echo -e "${BLUE}[$(date +%H:%M:%S)] [INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[$(date +%H:%M:%S)] [SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[$(date +%H:%M:%S)] [WARN]${NC} $*"; }
log_error() { echo -e "${RED}[$(date +%H:%M:%S)] [ERROR]${NC} $*"; }

# Check prerequisites
check_national_data() {
    log_info "Checking for national data..."

    local county_count=$($PSQL -tAc "SELECT COUNT(*) FROM tiger_data.county_all_lookup LIMIT 1;" 2>/dev/null || echo "0")

    if [ "$county_count" -eq 0 ]; then
        log_error "National data not loaded!"
        log_error ""
        log_error "You must load national STATE and COUNTY data first."
        log_error "Run: /usr/local/bin/load-tiger-nation.sh"
        log_error ""
        exit 1
    fi

    log_success "National data found ($county_count counties)"
}

# Generate and execute loader script for a state
load_state_data() {
    local state=$1
    local state_upper=$(echo "$state" | tr '[:lower:]' '[:upper:]')
    local state_lower=$(echo "$state" | tr '[:upper:]' '[:lower:]')

    log_info "=========================================="
    log_info "Loading TIGER data for: $state_upper"
    log_info "=========================================="

    # Create script directory if it doesn't exist
    mkdir -p "$SCRIPTDIR"

    # Generate the SQL script using PostGIS Loader_Generate_Script function
    local script_file="$SCRIPTDIR/tiger_load_${state_lower}.sql"

    log_info "Generating loader script using PostGIS Loader_Generate_Script()..."

    $PSQL -tA <<EOSQL > "$script_file"
-- Generate TIGER loading script for $state_upper
SELECT Loader_Generate_Script(ARRAY['${state_upper}'], 'sh');
EOSQL

    if [ ! -s "$script_file" ]; then
        log_error "Failed to generate loader script for $state_upper"
        return 1
    fi

    local script_size=$(wc -l < "$script_file")
    log_success "Generated script with $script_size lines"

    # Execute the generated script
    log_info "Executing TIGER data loader script..."
    log_info "This will download and load all TIGER datasets for $state_upper"
    log_info "Expected time: 45-90 minutes depending on state size"
    echo ""

    if ! $PSQL -f "$script_file" 2>&1; then
        log_error "Failed to execute loader script for $state_upper"
        log_error "Script location: $script_file"
        return 1
    fi

    log_success "Completed loading TIGER data for $state_upper"

    # Verify the loaded data
    verify_state_data "$state_lower"

    # Clean up script file
    rm -f "$script_file"

    return 0
}

# Verify loaded data
verify_state_data() {
    local state_lower=$1

    log_info "Verifying loaded data for $state_lower..."

    # Check key tables
    local edges_count=$($PSQL -tAc "SELECT COUNT(*) FROM tiger_data.${state_lower}_edges;" 2>/dev/null || echo "0")
    local addr_count=$($PSQL -tAc "SELECT COUNT(*) FROM tiger_data.${state_lower}_addr;" 2>/dev/null || echo "0")
    local featnames_count=$($PSQL -tAc "SELECT COUNT(*) FROM tiger_data.${state_lower}_featnames;" 2>/dev/null || echo "0")
    local place_count=$($PSQL -tAc "SELECT COUNT(*) FROM tiger_data.${state_lower}_place;" 2>/dev/null || echo "0")

    echo ""
    log_info "Data verification for $(echo $state_lower | tr '[:lower:]' '[:upper:]'):"
    log_info "  EDGES (street segments):  $(printf '%10s' $edges_count)"
    log_info "  ADDR (addresses):         $(printf '%10s' $addr_count)"
    log_info "  FEATNAMES (street names): $(printf '%10s' $featnames_count)"
    log_info "  PLACE (cities/towns):     $(printf '%10s' $place_count)"
    echo ""

    if [ "$edges_count" -eq 0 ] || [ "$addr_count" -eq 0 ]; then
        log_warn "Some critical tables have no data - geocoding may not work properly"
        return 1
    fi

    log_success "Data verification passed"
    return 0
}

#############################
# MAIN EXECUTION
#############################

main() {
    local start_time=$(date +%s)

    if [ $# -eq 0 ]; then
        log_error "No state codes provided"
        echo ""
        echo "Usage: $0 STATE_CODE [STATE_CODE2 ...]"
        echo "Example: $0 TN"
        echo "         $0 CA NY TX"
        exit 1
    fi

    # Check prerequisites
    check_national_data

    # Load each state
    local states=("$@")
    local success_count=0
    local fail_count=0

    for state in "${states[@]}"; do
        if load_state_data "$state"; then
            ((success_count++))
        else
            ((fail_count++))
            log_warn "Failed to load state: $state"
        fi
        echo ""
    done

    # Summary
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local hours=$((duration / 3600))
    local minutes=$(((duration % 3600) / 60))

    echo ""
    log_info "=========================================="
    log_info "TIGER Data Loading Summary"
    log_info "=========================================="
    log_success "Successfully loaded: $success_count state(s)"
    if [ $fail_count -gt 0 ]; then
        log_warn "Failed to load: $fail_count state(s)"
    fi
    log_info "Total time: ${hours}h ${minutes}m"
    log_info "=========================================="
    echo ""

    if [ $fail_count -gt 0 ]; then
        exit 1
    fi

    log_info "You can now test geocoding with queries like:"
    log_info "  SELECT * FROM geocode('123 Main St, Nashville, TN', 1);"
    echo ""
}

# Run main
main "$@"
