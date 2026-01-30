#!/bin/bash

# TIGER National Data Loader
# Loads nationwide STATE and COUNTY data required for state-specific geocoding
# This must be run before loading any state-specific data
#
# Usage: ./load-tiger-nation.sh
#
# Size: ~200 MB
# Time: ~7 minutes

set -e

# Configuration
TMPDIR="/gisdata/temp"
DOWNLOADDIR="/gisdata/downloads"
TIGER_YEAR="${TIGER_YEAR:-2024}"
CENSUS_BASE_URL="https://www2.census.gov/geo/tiger/TIGER${TIGER_YEAR}"

# PostgreSQL connection settings
export PGBIN=/usr/lib/postgresql/18/bin
export PGPORT=${PGPORT:-5432}
export PGHOST=${PGHOST:-localhost}
export PGUSER=${POSTGRES_USER:-postgres}
export PGPASSWORD=${POSTGRES_PASSWORD}
export PGDATABASE=${POSTGRES_DB:-postgres}

PSQL="${PGBIN}/psql"
SHP2PGSQL=shp2pgsql

# Download retry settings
MAX_RETRIES=3
RETRY_DELAY=5

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#############################
# HELPER FUNCTIONS
#############################

log_info() {
    echo -e "${BLUE}[$(date +%H:%M:%S)] [INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[$(date +%H:%M:%S)] [SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[$(date +%H:%M:%S)] [WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[$(date +%H:%M:%S)] [ERROR]${NC} $*"
}

# Check if PostgreSQL is ready
check_postgres() {
    log_info "Checking PostgreSQL connection..."
    if ! pg_isready -U "$PGUSER" -d "$PGDATABASE" >/dev/null 2>&1; then
        log_error "PostgreSQL is not ready. Please start the database first."
        exit 1
    fi
    log_success "PostgreSQL is ready"
}

# Download with retry logic
download_with_retry() {
    local url=$1
    local output=$2
    local attempt=1

    while [ $attempt -le $MAX_RETRIES ]; do
        log_info "Download attempt $attempt/$MAX_RETRIES"

        if wget -q --show-progress --timeout=300 -O "$output" "$url" 2>&1; then
            if [ -f "$output" ] && [ -s "$output" ]; then
                log_success "Downloaded successfully"
                return 0
            fi
        fi

        log_warn "Download failed, attempt $attempt/$MAX_RETRIES"
        rm -f "$output"

        if [ $attempt -lt $MAX_RETRIES ]; then
            log_info "Waiting ${RETRY_DELAY}s before retry..."
            sleep $RETRY_DELAY
        fi

        ((attempt++))
    done

    log_error "Failed to download after $MAX_RETRIES attempts: $url"
    return 1
}

# Check if national data is already loaded
check_if_loaded() {
    local state_count=$($PSQL -tAc "SELECT COUNT(*) FROM tiger_data.state_all LIMIT 1;" 2>/dev/null || echo "0")
    local county_count=$($PSQL -tAc "SELECT COUNT(*) FROM tiger_data.county_all_lookup LIMIT 1;" 2>/dev/null || echo "0")

    if [ "$state_count" -gt 0 ] && [ "$county_count" -gt 0 ]; then
        return 0  # Already loaded
    fi
    return 1  # Not loaded
}

#############################
# LOAD STATE DATA
#############################

load_state_data() {
    log_info "=========================================="
    log_info "Loading STATE data (all 50 states + territories)"
    log_info "=========================================="

    local url="${CENSUS_BASE_URL}/STATE/tl_${TIGER_YEAR}_us_state.zip"
    local file="${DOWNLOADDIR}/tl_${TIGER_YEAR}_us_state.zip"

    # Download
    if [ ! -f "$file" ]; then
        if ! download_with_retry "$url" "$file"; then
            log_error "Failed to download STATE data"
            return 1
        fi
    else
        log_info "Using cached file: $(basename "$file")"
    fi

    # Extract
    log_info "Extracting STATE shapefile..."
    rm -rf ${TMPDIR}/*
    if ! unzip -q -o "$file" -d ${TMPDIR}; then
        log_error "Failed to extract STATE data"
        return 1
    fi

    # Create staging schema
    log_info "Creating staging schema..."
    $PSQL -q <<EOSQL
DROP SCHEMA IF EXISTS tiger_staging CASCADE;
CREATE SCHEMA tiger_staging;
EOSQL

    # Create final table
    log_info "Creating state_all table..."
    $PSQL -q <<EOSQL
DROP TABLE IF EXISTS tiger_data.state_all CASCADE;
CREATE TABLE tiger_data.state_all(
    CONSTRAINT pk_state_all PRIMARY KEY (statefp),
    CONSTRAINT uidx_state_all_stusps UNIQUE (stusps),
    CONSTRAINT uidx_state_all_gid UNIQUE (gid)
) INHERITS(tiger.state);
EOSQL

    # Load shapefile to staging
    log_info "Loading shapefile data..."
    cd ${TMPDIR}
    local shp_file=$(ls *.shp 2>/dev/null | head -1)

    if [ -z "$shp_file" ]; then
        log_error "No shapefile found in STATE data"
        return 1
    fi

    if ! ${SHP2PGSQL} -D -c -s 4269 -g the_geom -W "latin1" "$shp_file" tiger_staging.state | $PSQL -q; then
        log_error "Failed to load STATE shapefile"
        return 1
    fi

    # Move from staging to final table
    log_info "Moving data to final table..."
    $PSQL -q <<EOSQL
SELECT loader_load_staged_data(lower('state'), lower('state_all'));
CREATE INDEX tiger_data_state_all_the_geom_gist ON tiger_data.state_all USING gist(the_geom);
VACUUM ANALYZE tiger_data.state_all;
EOSQL

    local count=$($PSQL -tAc "SELECT COUNT(*) FROM tiger_data.state_all;")
    log_success "STATE data loaded: $count states/territories"

    return 0
}

#############################
# LOAD COUNTY DATA
#############################

load_county_data() {
    log_info "=========================================="
    log_info "Loading COUNTY data (all US counties)"
    log_info "=========================================="

    local url="${CENSUS_BASE_URL}/COUNTY/tl_${TIGER_YEAR}_us_county.zip"
    local file="${DOWNLOADDIR}/tl_${TIGER_YEAR}_us_county.zip"

    # Download
    if [ ! -f "$file" ]; then
        if ! download_with_retry "$url" "$file"; then
            log_error "Failed to download COUNTY data"
            return 1
        fi
    else
        log_info "Using cached file: $(basename "$file")"
    fi

    # Extract
    log_info "Extracting COUNTY shapefile..."
    rm -rf ${TMPDIR}/*
    if ! unzip -q -o "$file" -d ${TMPDIR}; then
        log_error "Failed to extract COUNTY data"
        return 1
    fi

    # Create staging schema
    log_info "Creating staging schema..."
    $PSQL -q <<EOSQL
DROP SCHEMA IF EXISTS tiger_staging CASCADE;
CREATE SCHEMA tiger_staging;
EOSQL

    # Create final table
    log_info "Creating county_all table..."
    $PSQL -q <<EOSQL
DROP TABLE IF EXISTS tiger_data.county_all CASCADE;
CREATE TABLE tiger_data.county_all(
    CONSTRAINT pk_tiger_data_county_all PRIMARY KEY (cntyidfp),
    CONSTRAINT uidx_tiger_data_county_all_gid UNIQUE (gid)
) INHERITS(tiger.county);
EOSQL

    # Load shapefile to staging
    log_info "Loading shapefile data..."
    cd ${TMPDIR}
    local shp_file=$(ls *.shp 2>/dev/null | head -1)

    if [ -z "$shp_file" ]; then
        log_error "No shapefile found in COUNTY data"
        return 1
    fi

    if ! ${SHP2PGSQL} -D -c -s 4269 -g the_geom -W "latin1" "$shp_file" tiger_staging.county | $PSQL -q; then
        log_error "Failed to load COUNTY shapefile"
        return 1
    fi

    # Move from staging to final table
    log_info "Moving data to final table..."
    $PSQL -q <<EOSQL
-- Rename geoid column to match expected name
ALTER TABLE tiger_staging.county RENAME geoid TO cntyidfp;

-- Load staged data
SELECT loader_load_staged_data(lower('county'), lower('county_all'));

-- Create indexes
CREATE INDEX tiger_data_county_the_geom_gist
    ON tiger_data.county_all USING gist(the_geom);

CREATE UNIQUE INDEX uidx_tiger_data_county_all_statefp_countyfp
    ON tiger_data.county_all USING btree(statefp, countyfp);

-- Analyze for query optimization
VACUUM ANALYZE tiger_data.county_all;
EOSQL

    local count=$($PSQL -tAc "SELECT COUNT(*) FROM tiger_data.county_all;")
    log_success "COUNTY data loaded: $count counties"

    return 0
}

#############################
# CREATE COUNTY LOOKUP TABLE
#############################

create_county_lookup() {
    log_info "=========================================="
    log_info "Creating county lookup table"
    log_info "=========================================="

    $PSQL -q <<EOSQL
-- Create lookup table
DROP TABLE IF EXISTS tiger_data.county_all_lookup CASCADE;
CREATE TABLE tiger_data.county_all_lookup (
    CONSTRAINT pk_county_all_lookup PRIMARY KEY (st_code, co_code)
) INHERITS (tiger.county_lookup);

-- Populate from state_lookup and county_all
INSERT INTO tiger_data.county_all_lookup(st_code, state, co_code, name)
SELECT
    CAST(s.statefp as integer) as st_code,
    s.abbrev as state,
    CAST(c.countyfp as integer) as co_code,
    c.name
FROM tiger_data.county_all AS c
INNER JOIN tiger.state_lookup AS s ON s.statefp = c.statefp;

-- Create indexes for lookups
CREATE INDEX county_lookup_state_abbrev_idx
    ON tiger_data.county_all_lookup USING btree(state);

CREATE INDEX county_lookup_name_soundex_idx
    ON tiger_data.county_all_lookup USING btree(soundex(name));

-- Analyze
VACUUM ANALYZE tiger_data.county_all_lookup;
EOSQL

    local count=$($PSQL -tAc "SELECT COUNT(*) FROM tiger_data.county_all_lookup;")
    log_success "County lookup table created: $count entries"

    return 0
}

#############################
# VALIDATION
#############################

validate_national_data() {
    log_info "=========================================="
    log_info "Validating national data"
    log_info "=========================================="

    $PSQL <<EOSQL
SELECT
    'States/Territories' as dataset,
    COUNT(*)::text as count
FROM tiger_data.state_all

UNION ALL

SELECT
    'Counties' as dataset,
    COUNT(*)::text as count
FROM tiger_data.county_all

UNION ALL

SELECT
    'County Lookup Entries' as dataset,
    COUNT(*)::text as count
FROM tiger_data.county_all_lookup;
EOSQL

    # Verify key states
    log_info ""
    log_info "Sample data verification:"
    $PSQL <<EOSQL
SELECT
    abbrev as state,
    statefp as fips,
    name as state_name
FROM tiger.state_lookup
WHERE abbrev IN ('CA', 'NY', 'TX', 'FL', 'TN')
ORDER BY abbrev;
EOSQL

    log_success "Validation complete"
}

#############################
# MAIN EXECUTION
#############################

main() {
    local start_time=$(date +%s)

    echo ""
    log_info "=========================================="
    log_info "TIGER National Data Loader"
    log_info "=========================================="
    log_info ""
    log_info "This loads nationwide STATE and COUNTY data"
    log_info "Required before loading state-specific data"
    log_info ""
    log_info "Estimated size: ~200 MB"
    log_info "Estimated time: ~7 minutes"
    log_info "=========================================="
    echo ""

    # Pre-flight checks
    check_postgres

    # Check if already loaded
    if check_if_loaded; then
        log_warn "National data appears to be already loaded"
        log_info "To reload, drop tables first:"
        log_info "  DROP TABLE tiger_data.state_all CASCADE;"
        log_info "  DROP TABLE tiger_data.county_all CASCADE;"
        log_info "  DROP TABLE tiger_data.county_all_lookup CASCADE;"
        exit 0
    fi

    # Create directories
    log_info "Creating directories..."
    mkdir -p "$TMPDIR" "$DOWNLOADDIR"
    cd /gisdata

    # Load data
    if ! load_state_data; then
        log_error "Failed to load STATE data"
        exit 1
    fi

    if ! load_county_data; then
        log_error "Failed to load COUNTY data"
        exit 1
    fi

    if ! create_county_lookup; then
        log_error "Failed to create county lookup"
        exit 1
    fi

    # Validate
    validate_national_data

    # Calculate duration
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))

    echo ""
    log_info "=========================================="
    log_success "National Data Load Complete!"
    log_info "=========================================="
    log_info "Duration: ${minutes}m ${seconds}s"
    log_info ""
    log_info "You can now load state-specific data:"
    log_info "  /usr/local/bin/load-tiger-data.sh TN"
    log_info "  /usr/local/bin/load-tiger-data.sh CA NY TX"
    log_info "=========================================="
    echo ""
}

# Run main function
main "$@"
