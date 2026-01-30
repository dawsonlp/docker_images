#!/bin/bash
set -e

# This script initializes TIGER geocoder data for US addresses
# By default, it only sets up the tables and structure
# To load actual data, set TIGER_STATES environment variable

echo "Initializing TIGER geocoder..."

# The TIGER geocoder tables are created by the postgis_tiger_geocoder extension
# This script provides additional setup and optional data loading

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Grant permissions for TIGER geocoder
    GRANT USAGE ON SCHEMA tiger TO PUBLIC;
    GRANT SELECT ON ALL TABLES IN SCHEMA tiger TO PUBLIC;
    
    -- Create tiger_data schema (will be populated later with TIGER data)
    CREATE SCHEMA IF NOT EXISTS tiger_data;
    GRANT USAGE ON SCHEMA tiger_data TO PUBLIC;
    GRANT SELECT ON ALL TABLES IN SCHEMA tiger_data TO PUBLIC;

    -- Set search path to include tiger schemas
    ALTER DATABASE "$POSTGRES_DB" SET search_path TO public, tiger, tiger_data;

    -- Create helper functions for geocoding
    CREATE OR REPLACE FUNCTION geocode_address(
        address_input TEXT
    ) RETURNS TABLE (
        rating INTEGER,
        lon DOUBLE PRECISION,
        lat DOUBLE PRECISION,
        full_address TEXT
    ) AS \$\$
    BEGIN
        RETURN QUERY
        SELECT
            (g.geo).rating,
            ST_X((g.geo).geomout)::DOUBLE PRECISION AS lon,
            ST_Y((g.geo).geomout)::DOUBLE PRECISION AS lat,
            (g.geo).address AS full_address
        FROM geocode(address_input, 1) AS g;
    END;
    \$\$ LANGUAGE plpgsql;

    -- Create reverse geocoding helper
    CREATE OR REPLACE FUNCTION reverse_geocode_point(
        longitude DOUBLE PRECISION,
        latitude DOUBLE PRECISION
    ) RETURNS TABLE (
        street_number TEXT,
        street_name TEXT,
        city TEXT,
        state TEXT,
        zip TEXT,
        full_address TEXT
    ) AS \$\$
    BEGIN
        RETURN QUERY
        SELECT
            (rg.address).streetNumber::TEXT,
            (rg.address).streetName::TEXT,
            (rg.address).location::TEXT,
            (rg.address).stateAbbrev::TEXT,
            (rg.address).zip::TEXT,
            (rg.address).streetNumber || ' ' ||
            (rg.address).streetName || ', ' ||
            (rg.address).location || ', ' ||
            (rg.address).stateAbbrev || ' ' ||
            (rg.address).zip AS full_address
        FROM reverse_geocode(ST_SetSRID(ST_MakePoint(longitude, latitude), 4326), true) AS rg;
    END;
    \$\$ LANGUAGE plpgsql;

    \echo 'TIGER geocoder structure initialized successfully!'
    \echo ''
    \echo 'To load TIGER data for specific states, you can:'
    \echo '1. Use the Loader_Generate_Nation_Script() function to generate load scripts'
    \echo '2. Set TIGER_STATES environment variable (e.g., CA,NY,TX) and rebuild'
    \echo '3. Manually load data using the tiger data loader functions'
    \echo ''
    \echo 'Example: SELECT Loader_Generate_Nation_Script(sh);'
EOSQL

# Note: TIGER data is NOT loaded automatically due to size (20-100GB+)
# and time (30min - 6 hours) requirements

echo ""
echo "=========================================="
echo "TIGER Geocoder Setup Complete"
echo "=========================================="
echo ""
echo "TIGER geocoder structure is ready, but NO DATA is loaded yet."
echo ""
echo "To load US address data, run after container is ready:"
echo "  docker compose exec postgres /usr/local/bin/load-tiger-data.sh CA NY TX"
echo ""
echo "Or for help:"
echo "  docker compose exec postgres /usr/local/bin/load-tiger-data.sh --help"
echo ""
echo "For detailed instructions, see TIGER_DATA.md"
echo "=========================================="
echo ""

echo "TIGER geocoder initialization completed!"
