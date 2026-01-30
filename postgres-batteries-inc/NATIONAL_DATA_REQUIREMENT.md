# TIGER National Data Loading Requirement

## TL;DR - YES, You Need National Data First

**Short Answer:** Yes, you should load national STATE and COUNTY data before loading state-specific data.

**Why:** State-specific data loading scripts need to know what counties exist in each state to download per-county datasets (EDGES, ADDR, FEATNAMES).

## Current State Analysis

### What's Already Loaded ✅
```
tiger.state_lookup     - 59 rows (states + territories with FIPS codes)
tiger.county_lookup    - 0 rows (EMPTY - this is the problem!)
```

The `state_lookup` table comes pre-populated with the PostGIS TIGER extension. It contains:
- State names
- State abbreviations (TN, CA, NY, etc.)
- State FIPS codes (47 for Tennessee, 06 for California, etc.)

### What's Missing ❌
```
tiger_data.state_all        - Does not exist
tiger_data.county_all       - Does not exist
tiger_data.county_all_lookup - Does not exist
```

These tables contain the actual geographic data and are required for proper geocoding.

## Why National Data is Required

### 1. County Discovery for State Loading

When loading state-specific data, the loader needs to know what counties are in that state:

```bash
# Example: Loading Tennessee EDGES data
# EDGES data is per-county: tl_2024_47001_edges.zip, tl_2024_47003_edges.zip, etc.
# The loader needs to know Tennessee has counties: 001, 003, 005, ..., 189

# Without county data, the loader can't iterate through counties
for county in $(get_state_counties "TN"); do
    load_edges "TN" "$county"  # Loads tl_2024_47${county}_edges.zip
done
```

### 2. Geocoding Lookup Hierarchy

The TIGER geocoder uses a hierarchical lookup:
```
State Lookup (abbrev → FIPS) → County Lookup → Address Data
```

Example geocoding query:
```
"123 Main St, Nashville, TN"
    ↓
1. Resolve "TN" to state FIPS "47" (state_lookup)
2. Resolve "Nashville" to Davidson County "47037" (county_all_lookup)
3. Search for "123 Main St" in Davidson County EDGES/ADDR tables
4. Return coordinates
```

Without `county_all_lookup`, step 2 fails.

### 3. Spatial Relationships

Many geocoding functions use spatial relationships:
```sql
-- Find which county contains this point
SELECT c.name
FROM tiger_data.county_all c
WHERE ST_Contains(c.the_geom, ST_SetSRID(ST_Point(-86.7816, 36.1627), 4269));
```

Without `county_all` geometry data, spatial queries fail.

## What National Data Includes

### STATE Data (~50 MB)
- **File:** `tl_2024_us_state.zip`
- **Table:** `tiger_data.state_all`
- **Contents:**
  - All 50 states + DC + territories
  - State boundaries (geometry)
  - State names, abbreviations, FIPS codes
- **Size:** ~50 MB
- **Load Time:** ~2 minutes

### COUNTY Data (~150 MB)
- **File:** `tl_2024_us_county.zip`
- **Table:** `tiger_data.county_all`
- **Contents:**
  - All 3,200+ US counties
  - County boundaries (geometry)
  - County names, FIPS codes
- **Size:** ~150 MB
- **Load Time:** ~5 minutes

### COUNTY Lookup Table
- **Table:** `tiger_data.county_all_lookup`
- **Contents:**
  - Mapping: state code + county code → county name
  - Used for address parsing
  - Required for geocoding functions
- **Generated from:** `county_all` data

**Total National Data:** ~200 MB, ~7 minutes to load

## Loading Order

### Correct Order ✅
```bash
# 1. Load national data FIRST
docker exec postgres /usr/local/bin/load-tiger-nation.sh

# 2. Then load state data
docker exec postgres /usr/local/bin/load-tiger-data.sh TN
docker exec postgres /usr/local/bin/load-tiger-data.sh CA NY
```

### Incorrect Order ❌
```bash
# This will fail!
docker exec postgres /usr/local/bin/load-tiger-data.sh TN
# Error: Can't determine counties for TN
```

## Implementation in Our Scripts

### Option 1: Automatic Pre-Check (RECOMMENDED)

The state loader script should automatically check for national data and load it if missing:

```bash
load_state() {
    local state=$1

    # Check if national data is loaded
    if ! has_national_data; then
        log_warn "National data not found. Loading automatically..."
        load_national_data || exit 1
    fi

    # Now load state data
    load_state_data "$state"
}

has_national_data() {
    local count=$($PSQL -tAc "SELECT COUNT(*) FROM tiger_data.county_all_lookup LIMIT 1;" 2>/dev/null)
    [ "$count" -gt 0 ]
}
```

**Advantages:**
- User-friendly: "just works"
- Can't forget the step
- One-time overhead

### Option 2: Explicit Requirement

Require users to explicitly load national data first:

```bash
# User must run these commands in order
./load-tiger-nation.sh
./load-tiger-data.sh TN
```

**Advantages:**
- Clear separation of concerns
- User understands the two-phase process
- Can skip if already loaded

### Option 3: Combined Script

Single script that detects and loads both:

```bash
./load-tiger-data.sh --with-nation TN
```

**Advantages:**
- Single command
- Explicit about what's happening

## Recommendation for Our Fix

### Phase 0: National Data Loader (NEW)

**File:** `postgres-postgis/scripts/load-tiger-nation.sh`

```bash
#!/bin/bash
# Load nationwide STATE and COUNTY data
# This must be run before loading any state-specific data

set -e

log_info "Loading TIGER National Data"
log_info "This is a one-time setup that takes ~7 minutes"

# Check if already loaded
if [ $($PSQL -tAc "SELECT COUNT(*) FROM tiger_data.county_all_lookup LIMIT 1;" 2>/dev/null || echo "0") -gt 0 ]; then
    log_info "National data already loaded. Skipping."
    exit 0
fi

# Load STATE data
load_state_data() {
    log_info "Loading STATE data..."

    download_with_retry \
        "https://www2.census.gov/geo/tiger/TIGER2024/STATE/tl_2024_us_state.zip" \
        "/gisdata/downloads/tl_2024_us_state.zip"

    unzip -q -o /gisdata/downloads/tl_2024_us_state.zip -d /gisdata/temp/

    $PSQL <<EOSQL
DROP SCHEMA IF EXISTS tiger_staging CASCADE;
CREATE SCHEMA tiger_staging;

CREATE TABLE tiger_data.state_all(
    CONSTRAINT pk_state_all PRIMARY KEY (statefp),
    CONSTRAINT uidx_state_all_stusps UNIQUE (stusps),
    CONSTRAINT uidx_state_all_gid UNIQUE (gid)
) INHERITS(tiger.state);
EOSQL

    cd /gisdata/temp/
    $SHP2PGSQL -D -c -s 4269 -g the_geom -W "latin1" \
        tl_2024_us_state.dbf tiger_staging.state | $PSQL -q

    $PSQL <<EOSQL
SELECT loader_load_staged_data(lower('state'), lower('state_all'));
CREATE INDEX tiger_data_state_all_the_geom_gist ON tiger_data.state_all USING gist(the_geom);
VACUUM ANALYZE tiger_data.state_all;
EOSQL

    log_success "STATE data loaded (50 states + territories)"
}

# Load COUNTY data
load_county_data() {
    log_info "Loading COUNTY data..."

    download_with_retry \
        "https://www2.census.gov/geo/tiger/TIGER2024/COUNTY/tl_2024_us_county.zip" \
        "/gisdata/downloads/tl_2024_us_county.zip"

    unzip -q -o /gisdata/downloads/tl_2024_us_county.zip -d /gisdata/temp/

    $PSQL <<EOSQL
DROP SCHEMA IF EXISTS tiger_staging CASCADE;
CREATE SCHEMA tiger_staging;

CREATE TABLE tiger_data.county_all(
    CONSTRAINT pk_tiger_data_county_all PRIMARY KEY (cntyidfp),
    CONSTRAINT uidx_tiger_data_county_all_gid UNIQUE (gid)
) INHERITS(tiger.county);
EOSQL

    cd /gisdata/temp/
    $SHP2PGSQL -D -c -s 4269 -g the_geom -W "latin1" \
        tl_2024_us_county.dbf tiger_staging.county | $PSQL -q

    $PSQL <<EOSQL
ALTER TABLE tiger_staging.county RENAME geoid TO cntyidfp;
SELECT loader_load_staged_data(lower('county'), lower('county_all'));

CREATE INDEX tiger_data_county_the_geom_gist ON tiger_data.county_all USING gist(the_geom);
CREATE UNIQUE INDEX uidx_tiger_data_county_all_statefp_countyfp
    ON tiger_data.county_all USING btree(statefp, countyfp);

-- Create and populate county lookup table
CREATE TABLE tiger_data.county_all_lookup (
    CONSTRAINT pk_county_all_lookup PRIMARY KEY (st_code, co_code)
) INHERITS (tiger.county_lookup);

INSERT INTO tiger_data.county_all_lookup(st_code, state, co_code, name)
SELECT
    CAST(s.statefp as integer),
    s.abbrev,
    CAST(c.countyfp as integer),
    c.name
FROM tiger_data.county_all AS c
INNER JOIN tiger.state_lookup AS s ON s.statefp = c.statefp;

VACUUM ANALYZE tiger_data.county_all;
VACUUM ANALYZE tiger_data.county_all_lookup;
EOSQL

    local county_count=$($PSQL -tAc "SELECT COUNT(*) FROM tiger_data.county_all;")
    log_success "COUNTY data loaded ($county_count counties)"
}

# Main execution
load_state_data
load_county_data

log_success "National data loading complete!"
log_info "You can now load state-specific data with: load-tiger-data.sh [STATE]"
```

### Updated State Loader

**File:** `postgres-postgis/scripts/load-tiger-data.sh`

Add automatic check:

```bash
# Check for national data
check_national_data() {
    log_info "Checking for national data..."

    local county_count=$($PSQL -tAc "SELECT COUNT(*) FROM tiger_data.county_all_lookup LIMIT 1;" 2>/dev/null || echo "0")

    if [ "$county_count" -eq 0 ]; then
        log_error "National data not loaded!"
        log_error ""
        log_error "You must load national STATE and COUNTY data first."
        log_error "Run: /usr/local/bin/load-tiger-nation.sh"
        log_error ""
        log_error "Or use: load-tiger-data.sh --with-nation [STATE]"
        exit 1
    fi

    log_success "National data found ($county_count counties)"
}
```

## User Documentation

Update README.md with clear instructions:

```markdown
## Loading TIGER Data

### Step 1: Load National Data (One-Time, ~7 minutes, ~200 MB)

This loads nationwide STATE and COUNTY data. Required before loading any state-specific data.

```bash
docker exec postgres /usr/local/bin/load-tiger-nation.sh
```

### Step 2: Load State Data (Per-State, 30-90 minutes, 3-10 GB each)

After national data is loaded, you can load data for specific states:

```bash
# Single state
docker exec postgres /usr/local/bin/load-tiger-data.sh TN

# Multiple states
docker exec postgres /usr/local/bin/load-tiger-data.sh CA NY TX

# Automatically load national data if needed
docker exec postgres /usr/local/bin/load-tiger-data.sh --with-nation TN
```

### Quick Start (All-In-One)

```bash
# Load national + Tennessee in one command
docker exec postgres /usr/local/bin/load-tiger-data.sh --with-nation TN
```

## Verification

After loading, verify data is present:

```sql
-- Check national data
SELECT COUNT(*) FROM tiger_data.state_all;      -- Should be ~56 (states + territories)
SELECT COUNT(*) FROM tiger_data.county_all;     -- Should be ~3,200+ (all US counties)

-- Check Tennessee data
SELECT COUNT(*) FROM tiger_data.tn_place;       -- Should be ~500
SELECT COUNT(*) FROM tiger_data.tn_edges;       -- Should be ~1.8M
SELECT COUNT(*) FROM tiger_data.tn_addr;        -- Should be ~2.7M
```
```

## Summary

1. **National data IS required** - Load it first
2. **Size is reasonable** - Only ~200 MB and 7 minutes
3. **One-time operation** - Load once, use for all states
4. **Should be automatic** - Script should check and load if needed
5. **Update the fix plan** - Add Phase 0 for national data

The updated implementation plan should include:
- Phase 0: National data loader script
- Phase 1: Dockerfile updates (including national data support)
- Phase 2: State loader with automatic national data check
- Phase 3: Documentation with clear two-phase process
