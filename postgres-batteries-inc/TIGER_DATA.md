# TIGER Geocoder Data Loading Guide

Complete guide for loading US Census TIGER/Line data for address geocoding.

## Table of Contents

- [Overview](#overview)
- [Two-Phase Loading Process](#two-phase-loading-process)
- [Quick Start](#quick-start)
- [Detailed Instructions](#detailed-instructions)
- [Data Size & Time Estimates](#data-size--time-estimates)
- [Production Deployment](#production-deployment)
- [Troubleshooting](#troubleshooting)
- [Performance Tuning](#performance-tuning)
- [Updates and Maintenance](#updates-and-maintenance)

## Overview

### What is TIGER Data?

TIGER (Topologically Integrated Geographic Encoding and Referencing) data is the US Census Bureau's geographic and cartographic data. It includes:

- **Street segments** (EDGES) - Every street in the US
- **Address points** (ADDR) - Individual address locations
- **Administrative boundaries** - States, counties, cities
- **Census geography** - Tracts, blocks, subdivisions

### Why Two Phases?

State-specific data (EDGES, ADDR, FEATNAMES) is organized **by county**. The loader needs national STATE and COUNTY data to:
1. Map state codes to FIPS codes (TN → 47)
2. Identify counties in each state (Tennessee has 95 counties)
3. Download per-county files (\`tl_2024_47001_edges.zip\`, \`tl_2024_47003_edges.zip\`, etc.)

Without national data, the loader cannot determine which counties to load.

## Two-Phase Loading Process

### Phase 1: National Data (Required, One-Time)

**What it loads:**
- \`tiger_data.state_all\` - All US states and territories
- \`tiger_data.county_all\` - All US counties (~3,200)
- \`tiger_data.county_all_lookup\` - County name/code mappings

**Size:** ~200 MB
**Time:** ~7 minutes
**Frequency:** Once per database

\`\`\`bash
docker exec postgres /usr/local/bin/load-tiger-nation.sh
\`\`\`

### Phase 2: State Data (Per State)

**What it loads per state:**
- County boundaries
- Places (cities/towns)
- County subdivisions
- Census tracts and blocks
- **Street segments** (EDGES) - Required for geocoding
- **Address points** (ADDR) - Required for address matching
- **Street names** (FEATNAMES) - Required for fuzzy matching

**Size:** 2-12 GB per state
**Time:** 30-90 minutes per state
**Frequency:** Per state needed

\`\`\`bash
# Single state
docker exec postgres /usr/local/bin/load-tiger-data.sh TN

# Multiple states
docker exec postgres /usr/local/bin/load-tiger-data.sh CA NY TX
\`\`\`

## Quick Start

### Development (Single State)

\`\`\`bash
# All-in-one command (auto-loads national data if needed)
docker exec postgres /usr/local/bin/load-tiger-data.sh --with-nation TN

# Wait 30-60 minutes...

# Test geocoding
docker exec postgres psql -U postgres -c \
  "SELECT * FROM geocode('123 Main St, Nashville, TN', 1);"
\`\`\`

For complete step-by-step instructions and troubleshooting, see the full documentation above.
