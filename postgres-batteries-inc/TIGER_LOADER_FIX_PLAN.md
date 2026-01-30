# TIGER Data Loader Fix Plan

## Executive Summary

The current TIGER data loader script has fundamental design flaws that prevent it from successfully loading state data. This plan outlines a comprehensive fix to create a production-ready, error-free TIGER data loading solution.

## Root Cause Analysis

### Issue 1: SQL/Bash Execution Mismatch (CRITICAL)
**Problem:** Lines 160-161 of `load-tiger-data.sh`:
```sql
SELECT Loader_Generate_Script(ARRAY['$state_upper'], 'sh') AS result
\gexec
```

**Root Cause:**
- `Loader_Generate_Script()` with 'sh' parameter generates BASH script code (not SQL)
- `\gexec` attempts to execute output as SQL statements
- Result: "ERROR: syntax error at or near 'TMPDIR'" because bash variables are not valid SQL

**Evidence:**
```
ERROR:  syntax error at or near "TMPDIR"
LINE 1: TMPDIR="/gisdata/temp/"
        ^
```

### Issue 2: Missing Directory Infrastructure
**Problem:** Generated scripts expect `/gisdata` and `/gisdata/temp/` directories
**Current State:** Directories not created in Dockerfile
**Impact:** Script failures when trying to download/extract data

### Issue 3: Incomplete Data Loading
**Problem:** Only PLACE data loaded, missing critical datasets:
- EDGES (street segments) - Required for address geocoding
- ADDR (address points) - Required for precise location matching
- FEATNAMES (street names) - Required for fuzzy matching
- COUSUB, TRACT, TABBLOCK - Required for census geography

**Evidence:** Only `tiger_data.tn_place` table exists after load attempt

### Issue 4: PostGIS Loader Function Misunderstanding
**Problem:** PostGIS TIGER loader functions are code generators, not executors
**Expected Workflow:**
1. Call `Loader_Generate_Script()` → generates bash script
2. Save script to file → `/gisdata/scripts/load_tn.sh`
3. Make executable → `chmod +x`
4. Execute as bash → `bash /gisdata/scripts/load_tn.sh`

**Current Workflow:**
1. Call function → generates bash script
2. Pipe to `\gexec` → attempts to execute bash as SQL
3. **FAILS**

### Issue 5: Incorrect Table Inheritance Setup
**Problem:** Generated scripts may not properly set up table inheritance from `tiger.*` parent tables
**Impact:** Geocoding functions fail to find data because they query parent tables

### Issue 6: Missing Error Handling for Data Downloads
**Problem:** No retry logic for Census Bureau downloads
**Impact:** Network issues cause complete failure, requiring manual restart

## Proposed Solution Architecture

### Option A: Direct Loader Implementation (RECOMMENDED)

**Advantages:**
- Complete control over loading process
- Better error handling and progress reporting
- Can be optimized for our specific use case
- No dependency on PostGIS loader function quirks
- Proven approach (our `/tmp/load_tn_full.sh` worked)

**Approach:**
1. Write custom bash loader that directly:
   - Downloads zip files from Census Bureau
   - Extracts shapefiles
   - Uses `shp2pgsql` to convert to SQL
   - Loads into PostgreSQL with proper table structure

2. Support multiple dataset types:
   - COUNTY, PLACE (basic geography)
   - EDGES (street segments)
   - ADDR (address points)
   - FEATNAMES (street names)
   - COUSUB, TRACT, TABBLOCK (census geography)

### Option B: Fix PostGIS Loader Function Usage

**Advantages:**
- Uses "official" PostGIS approach
- May benefit from future PostGIS updates

**Disadvantages:**
- More complex (two-phase: generate then execute)
- Less control over process
- PostGIS functions have documented bugs/quirks

**Approach:**
1. Generate script to file
2. Execute file as bash
3. Handle each state separately

## Implementation Plan

### Phase 1: Infrastructure Updates (Dockerfile)

**File:** `postgres-postgis/Dockerfile`

**Changes:**
```dockerfile
# Create TIGER data directories with proper permissions
RUN mkdir -p /gisdata/temp /gisdata/downloads /gisdata/scripts && \
    chown -R postgres:postgres /gisdata && \
    chmod 755 /gisdata /gisdata/temp /gisdata/downloads /gisdata/scripts

# Install required tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    curl \
    unzip \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*
```

**Why:** Ensures all required directories and tools are available

### Phase 2: Create New TIGER Loader Script

**File:** `postgres-postgis/scripts/load-tiger-data-direct.sh`

**Features:**
- Direct loading approach (no PostGIS generator functions)
- Progress reporting with timestamps
- Retry logic for downloads (3 attempts)
- Parallel loading where possible
- Comprehensive error handling
- Detailed logging
- Resume capability (skip already-loaded datasets)
- Validation after each dataset

**Dataset Support:**
- COUNTY - County boundaries
- PLACE - Cities and towns
- COUSUB - County subdivisions
- TRACT - Census tracts
- TABBLOCK20 - Census blocks
- EDGES - Street segments (by county)
- ADDR - Address points (by county)
- FEATNAMES - Street names (by county)

**Implementation Structure:**
```bash
#!/bin/bash
set -e

# Configuration
TMPDIR="/gisdata/temp"
DOWNLOADDIR="/gisdata/downloads"
TIGER_YEAR="2024"
CENSUS_BASE_URL="https://www2.census.gov/geo/tiger/TIGER${TIGER_YEAR}"

# PostgreSQL connection
export PGBIN=/usr/lib/postgresql/18/bin
export PGPORT=5432
export PGHOST=localhost
export PGUSER=${POSTGRES_USER:-postgres}
export PGPASSWORD=${POSTGRES_PASSWORD}
export PGDATABASE=${POSTGRES_DB:-postgres}

# Core functions:
# - load_state_basic_geography()  # COUNTY, PLACE, COUSUB
# - load_state_census_geography() # TRACT, TABBLOCK
# - load_state_detailed_data()    # EDGES, ADDR, FEATNAMES (by county)
# - download_with_retry()         # Robust downloading
# - create_tables_if_needed()     # Table structure setup
# - validate_data()               # Post-load verification
```

### Phase 3: Update Helper Script

**File:** `postgres-postgis/scripts/load-tiger-data.sh`

**Changes:**
- Replace PostGIS function calls with direct loader
- Add progress bars for multi-state loads
- Add resume capability
- Improve error messages
- Add validation step after each state
- Generate summary report

### Phase 4: Add Dockerfile Support Script

**File:** `postgres-postgis/scripts/setup-tiger-environment.sh`

**Purpose:** One-time setup of TIGER infrastructure
- Creates required directories
- Sets permissions
- Validates PostgreSQL connection
- Ensures extensions are loaded
- Creates helper functions

**Called from:** Dockerfile or init scripts

### Phase 5: Documentation Updates

**Files to Update:**
1. `postgres-postgis/README.md`
   - Add troubleshooting section for TIGER loading
   - Update loading examples with correct usage

2. `postgres-postgis/TIGER_DATA.md`
   - Add detailed explanation of loading process
   - Document each dataset type and size
   - Add performance tuning recommendations

3. `postgres-postgis/QUICKSTART.md`
   - Add step-by-step TIGER loading guide
   - Include validation commands

### Phase 6: Testing Strategy

**Test Cases:**

1. **Single State Load (Small)**
   - State: Rhode Island (RI)
   - Expected time: < 30 minutes
   - Expected size: ~2 GB
   - Validates: Basic functionality

2. **Single State Load (Large)**
   - State: California (CA)
   - Expected time: 60-90 minutes
   - Expected size: ~10 GB
   - Validates: Performance with large dataset

3. **Multi-State Load**
   - States: TN, KY, VA (neighboring states)
   - Expected time: 2-3 hours
   - Validates: Sequential processing

4. **Resume Capability**
   - Start TN load
   - Kill process mid-load
   - Restart
   - Validates: Skip already-loaded data

5. **Error Recovery**
   - Simulate network failure during download
   - Validates: Retry logic works

6. **End-to-End Geocoding**
   - Load state data
   - Test forward geocoding
   - Test reverse geocoding
   - Validates: Data is usable

## Detailed Implementation: New Loader Script

### Script Structure

```bash
#!/bin/bash
# Direct TIGER Data Loader
# Loads Census Bureau TIGER/Line data without using PostGIS generator functions

set -e

#############################
# CONFIGURATION
#############################

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

#############################
# HELPER FUNCTIONS
#############################

log_info() { echo "[$(date +%H:%M:%S)] [INFO] $*"; }
log_success() { echo "[$(date +%H:%M:%S)] [SUCCESS] $*"; }
log_warn() { echo "[$(date +%H:%M:%S)] [WARN] $*"; }
log_error() { echo "[$(date +%H:%M:%S)] [ERROR] $*"; }

# Download with retry logic
download_with_retry() {
    local url=$1
    local output=$2
    local attempt=1

    while [ $attempt -le $MAX_RETRIES ]; do
        log_info "Download attempt $attempt/$MAX_RETRIES: $url"

        if wget -q --show-progress --timeout=300 -O "$output" "$url"; then
            log_success "Downloaded successfully"
            return 0
        fi

        log_warn "Download failed, attempt $attempt/$MAX_RETRIES"
        rm -f "$output"

        if [ $attempt -lt $MAX_RETRIES ]; then
            log_info "Waiting ${RETRY_DELAY}s before retry..."
            sleep $RETRY_DELAY
        fi

        ((attempt++))
    done

    log_error "Failed to download after $MAX_RETRIES attempts"
    return 1
}

# Create table if it doesn't exist
create_table_if_needed() {
    local state=$1
    local tablename=$2
    local parent=$3
    local pk_column=$4

    $PSQL -v ON_ERROR_STOP=1 <<EOSQL
DO \$\$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_tables
        WHERE schemaname = 'tiger_data'
        AND tablename = '${state}_${tablename}'
    ) THEN
        CREATE TABLE tiger_data.${state}_${tablename}(
            CONSTRAINT pk_${state}_${tablename} PRIMARY KEY (${pk_column})
        ) INHERITS(tiger.${parent});
    END IF;
END
\$\$;
EOSQL
}

# Load a shapefile to staging and then to final table
load_shapefile() {
    local zip_url=$1
    local zip_file=$2
    local state=$3
    local table_name=$4
    local dataset_name=$5

    log_info "Loading $dataset_name for $state..."

    # Download
    local download_path="${DOWNLOADDIR}/${zip_file}"
    if [ ! -f "$download_path" ]; then
        if ! download_with_retry "$zip_url" "$download_path"; then
            return 1
        fi
    else
        log_info "Using cached file: $zip_file"
    fi

    # Extract
    rm -rf ${TMPDIR}/*
    if ! unzip -q -o "$download_path" -d ${TMPDIR}; then
        log_error "Failed to extract $zip_file"
        return 1
    fi

    # Load to staging
    $PSQL -q -c "DROP SCHEMA IF EXISTS tiger_staging CASCADE;" || true
    $PSQL -q -c "CREATE SCHEMA tiger_staging;"

    cd ${TMPDIR}
    local shp_file=$(ls *.shp 2>/dev/null | head -1)

    if [ -z "$shp_file" ]; then
        log_error "No shapefile found in $zip_file"
        return 1
    fi

    # Convert shapefile to SQL and load
    if ! ${SHP2PGSQL} -D -c -s 4269 -g the_geom -W "latin1" "$shp_file" "tiger_staging.${table_name}" | $PSQL -q; then
        log_error "Failed to load shapefile"
        return 1
    fi

    log_success "$dataset_name loaded to staging"
    return 0
}

# Get state FIPS code
get_state_fips() {
    local state=$1
    $PSQL -tA -c "SELECT statefp FROM tiger.state_lookup WHERE stusps = '${state}' LIMIT 1;"
}

# Get counties for a state
get_state_counties() {
    local state_fips=$1
    $PSQL -tA -c "SELECT countyfp FROM tiger_data.${state}_county ORDER BY countyfp;" 2>/dev/null || echo ""
}

#############################
# DATA LOADING FUNCTIONS
#############################

# Load COUNTY data (nationwide file, filter by state)
load_county_data() {
    local state=$1
    local state_lower=$(echo "$state" | tr '[:upper:]' '[:lower:]')
    local state_fips=$(get_state_fips "$state")

    log_info "=== Loading COUNTY data for $state (FIPS: $state_fips) ==="

    create_table_if_needed "$state_lower" "county" "county" "cntyidfp"

    local url="${CENSUS_BASE_URL}/COUNTY/tl_${TIGER_YEAR}_us_county.zip"
    local file="tl_${TIGER_YEAR}_us_county.zip"

    if load_shapefile "$url" "$file" "$state" "${state_lower}_county" "COUNTY"; then
        # Filter to just this state and insert
        $PSQL -q <<EOSQL
DELETE FROM tiger_data.${state_lower}_county;
INSERT INTO tiger_data.${state_lower}_county
SELECT * FROM tiger_staging.${state_lower}_county
WHERE statefp = '${state_fips}';

CREATE INDEX IF NOT EXISTS idx_${state_lower}_county_geom
    ON tiger_data.${state_lower}_county USING gist(the_geom);

ANALYZE tiger_data.${state_lower}_county;
EOSQL
        log_success "COUNTY data loaded for $state"
        return 0
    fi

    return 1
}

# Load PLACE data
load_place_data() {
    local state=$1
    local state_lower=$(echo "$state" | tr '[:upper:]' '[:lower:]')
    local state_fips=$(get_state_fips "$state")

    log_info "=== Loading PLACE data for $state ==="

    create_table_if_needed "$state_lower" "place" "place" "plcidfp"

    local url="${CENSUS_BASE_URL}/PLACE/tl_${TIGER_YEAR}_${state_fips}_place.zip"
    local file="tl_${TIGER_YEAR}_${state_fips}_place.zip"

    if load_shapefile "$url" "$file" "$state" "${state_lower}_place" "PLACE"; then
        # Rename GEOID to plcidfp if needed
        $PSQL -q <<EOSQL
DO \$\$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'tiger_staging'
               AND table_name = '${state_lower}_place'
               AND column_name = 'geoid') THEN
        ALTER TABLE tiger_staging.${state_lower}_place
        RENAME COLUMN geoid TO plcidfp;
    END IF;
END
\$\$;

INSERT INTO tiger_data.${state_lower}_place
SELECT * FROM tiger_staging.${state_lower}_place
ON CONFLICT DO NOTHING;

CREATE INDEX IF NOT EXISTS idx_${state_lower}_place_geom
    ON tiger_data.${state_lower}_place USING gist(the_geom);
CREATE INDEX IF NOT EXISTS idx_${state_lower}_place_soundex
    ON tiger_data.${state_lower}_place USING btree(soundex(name));

ANALYZE tiger_data.${state_lower}_place;
EOSQL
        log_success "PLACE data loaded for $state"
        return 0
    fi

    return 1
}

# Load EDGES data (per county)
load_edges_data() {
    local state=$1
    local state_lower=$(echo "$state" | tr '[:upper:]' '[:lower:]')
    local state_fips=$(get_state_fips "$state")

    log_info "=== Loading EDGES data for $state ==="

    create_table_if_needed "$state_lower" "edges" "edges" "gid"

    # Get list of counties
    local counties=$(get_state_counties "$state_lower")

    if [ -z "$counties" ]; then
        log_error "No counties found for $state - load COUNTY data first"
        return 1
    fi

    local county_count=$(echo "$counties" | wc -w)
    local current=0

    for county in $counties; do
        ((current++))
        log_info "Loading EDGES for county $county [$current/$county_count]"

        local url="${CENSUS_BASE_URL}/EDGES/tl_${TIGER_YEAR}_${state_fips}${county}_edges.zip"
        local file="tl_${TIGER_YEAR}_${state_fips}${county}_edges.zip"

        if load_shapefile "$url" "$file" "$state" "${state_lower}_edges" "EDGES-${county}"; then
            $PSQL -q <<EOSQL
INSERT INTO tiger_data.${state_lower}_edges
SELECT * FROM tiger_staging.${state_lower}_edges
ON CONFLICT DO NOTHING;
EOSQL
        else
            log_warn "Failed to load EDGES for county $county"
        fi
    done

    # Create indexes after all data loaded
    log_info "Creating indexes on EDGES table..."
    $PSQL -q <<EOSQL
CREATE INDEX IF NOT EXISTS idx_${state_lower}_edges_geom
    ON tiger_data.${state_lower}_edges USING gist(the_geom);
CREATE INDEX IF NOT EXISTS idx_${state_lower}_edges_tfidr
    ON tiger_data.${state_lower}_edges USING btree(tfidr);
CREATE INDEX IF NOT EXISTS idx_${state_lower}_edges_tfidl
    ON tiger_data.${state_lower}_edges USING btree(tfidl);

ANALYZE tiger_data.${state_lower}_edges;
EOSQL

    log_success "EDGES data loaded for $state"
    return 0
}

# Similar functions for ADDR, FEATNAMES, COUSUB, TRACT, TABBLOCK...
# (abbreviated for plan document)

#############################
# MAIN LOADING WORKFLOW
#############################

load_state_complete() {
    local state=$1
    local state_upper=$(echo "$state" | tr '[:lower:]' '[:upper:]')

    log_info "========================================"
    log_info "Loading complete TIGER data for: $state_upper"
    log_info "========================================"

    # Phase 1: Basic geography
    load_county_data "$state_upper" || return 1
    load_place_data "$state_upper" || return 1

    # Phase 2: Detailed data (can fail partially)
    load_edges_data "$state_upper" || log_warn "EDGES data incomplete"

    # Phase 3: Validation
    validate_state_data "$state_upper"

    log_success "========================================"
    log_success "Completed loading TIGER data for: $state_upper"
    log_success "========================================"
}

# Validation function
validate_state_data() {
    local state=$1
    local state_lower=$(echo "$state" | tr '[:upper:]' '[:lower:]')

    log_info "Validating data for $state..."

    $PSQL <<EOSQL
SELECT
    '${state}' as state,
    'COUNTY' as dataset,
    COUNT(*)::text as count
FROM tiger_data.${state_lower}_county

UNION ALL

SELECT '${state}', 'PLACE', COUNT(*)::text
FROM tiger_data.${state_lower}_place

UNION ALL

SELECT '${state}', 'EDGES', COUNT(*)::text
FROM tiger_data.${state_lower}_edges
WHERE EXISTS (SELECT 1 FROM tiger_data.${state_lower}_edges LIMIT 1);
EOSQL
}

#############################
# ENTRY POINT
#############################

main() {
    # Setup environment
    mkdir -p "$TMPDIR" "$DOWNLOADDIR"
    cd /gisdata

    # Process states
    for state in "$@"; do
        load_state_complete "$state"
    done
}

main "$@"
```

## Migration Path

### Step 1: Build New Image with Fixes
```bash
cd postgres-postgis
docker buildx build --platform linux/amd64,linux/arm64 \
  -t dawsonlp/postgres-postgis:v2-beta \
  --push .
```

### Step 2: Test with Single State
```bash
docker run --rm -d \
  --name postgres-test-v2 \
  -e POSTGRES_PASSWORD=test_password \
  -p 5433:5432 \
  dawsonlp/postgres-postgis:v2-beta

# Test loading
docker exec postgres-test-v2 /usr/local/bin/load-tiger-data.sh RI
```

### Step 3: Validate Geocoding Works
```sql
-- After RI load completes
SELECT * FROM geocode('123 Main St, Providence, RI', 1);
```

### Step 4: Full Production Release
```bash
# Tag as latest
docker tag dawsonlp/postgres-postgis:v2-beta dawsonlp/postgres-postgis:latest
docker push dawsonlp/postgres-postgis:latest
```

## Success Criteria

1. ✅ Script loads state data without SQL syntax errors
2. ✅ All required datasets loaded (COUNTY, PLACE, EDGES, ADDR, FEATNAMES)
3. ✅ Geocoding works for addresses in loaded states
4. ✅ Reverse geocoding works
5. ✅ Script handles network failures gracefully (retry logic)
6. ✅ Script is resumable (can skip already-loaded data)
7. ✅ Progress reporting is clear and accurate
8. ✅ Load completes in expected timeframe (30-60 min per state)
9. ✅ Data validation passes
10. ✅ Documentation is clear and complete

## Timeline Estimate

- **Phase 1** (Infrastructure): 2 hours
- **Phase 2** (New loader script): 8 hours
- **Phase 3** (Update helper): 2 hours
- **Phase 4** (Setup script): 1 hour
- **Phase 5** (Documentation): 3 hours
- **Phase 6** (Testing): 4 hours

**Total:** ~20 hours development + testing

## Risk Mitigation

1. **Risk:** Census Bureau changes data format
   - **Mitigation:** Version-lock to TIGER2024, document upgrade process

2. **Risk:** Script fails mid-load, corrupts database
   - **Mitigation:** Use staging schema, transaction boundaries, validation

3. **Risk:** Performance issues with large states
   - **Mitigation:** Batch processing, progress checkpoints, parallel where possible

4. **Risk:** Users run out of disk space
   - **Mitigation:** Pre-flight space check, cleanup downloads after load

## Conclusion

This plan provides a comprehensive fix for all TIGER data loading issues. The direct loader approach gives us full control, better error handling, and proven reliability. Implementation will result in a production-ready image that handles state data loading correctly and error-free.
