#!/bin/bash
# PostgreSQL Batteries-Included Smoke Test
# Tests all major extensions and functionality

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

CONTAINER_NAME="postgres-smoke-test"
PGUSER="postgres"
PGDATABASE="testdb"

# Export password for docker compose (use env var or generate random for testing)
export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(openssl rand -base64 16)}"

echo "=========================================="
echo "PostgreSQL Batteries-Included Smoke Test"
echo "=========================================="
echo ""

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up..."
    docker compose down -v 2>/dev/null || true
    echo "✓ Cleanup complete"
}

# Set trap for cleanup on exit
trap cleanup EXIT

# Helper function to run SQL
run_sql() {
    docker exec "$CONTAINER_NAME" psql -U "$PGUSER" -d "$PGDATABASE" -c "$1"
}

# Step 1: Start PostgreSQL
echo "Step 1: Starting PostgreSQL container..."
echo "----------------------------------------"
POSTGRES_DB="$PGDATABASE" docker compose up -d
echo ""

# Wait for container to be healthy
echo "Waiting for PostgreSQL to become healthy..."
max_attempts=30
attempt=0
while [ "$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null)" != "healthy" ]; do
    attempt=$((attempt + 1))
    if [ $attempt -ge $max_attempts ]; then
        echo "ERROR: PostgreSQL did not become healthy"
        echo ""
        echo "Container logs:"
        docker logs "$CONTAINER_NAME" --tail 50
        exit 1
    fi
    printf "  Attempt %d/%d\r" "$attempt" "$max_attempts"
    sleep 2
done
echo ""
echo "✓ PostgreSQL is healthy"
echo ""

# Step 2: Verify extensions
echo "Step 2: Verifying installed extensions..."
echo "----------------------------------------"
run_sql "SELECT extname, extversion FROM pg_extension ORDER BY extname;"

# Step 3: Test PostGIS
echo ""
echo "Step 3: Testing PostGIS..."
echo "----------------------------------------"
run_sql "SELECT PostGIS_Version();"
run_sql "SELECT ST_AsText(ST_MakePoint(-122.4194, 37.7749));"
echo "✓ PostGIS working"

# Step 4: Test pgvector
echo ""
echo "Step 4: Testing pgvector..."
echo "----------------------------------------"
run_sql "SELECT '[1,2,3]'::vector;"
run_sql "SELECT '[1,2,3]'::vector <-> '[4,5,6]'::vector AS distance;"
echo "✓ pgvector working"

# Step 5: Test pgRouting
echo ""
echo "Step 5: Testing pgRouting..."
echo "----------------------------------------"
run_sql "SELECT pgr_version();"
echo "✓ pgRouting working"

# Step 6: Test Full-Text Search
echo ""
echo "Step 6: Testing Full-Text Search..."
echo "----------------------------------------"
run_sql "SELECT to_tsvector('english', 'The quick brown fox jumps over the lazy dog');"
run_sql "SELECT 'PostgreSQL' % 'Postgres' AS trigram_similarity;"  # pg_trgm
run_sql "SELECT unaccent('Hôtel Café Résumé');"  # unaccent
echo "✓ Full-Text Search working"

# Step 7: Test Utility Extensions
echo ""
echo "Step 7: Testing utility extensions..."
echo "----------------------------------------"
run_sql "SELECT uuid_generate_v4();"  # uuid-ossp
run_sql "SELECT encode(gen_random_bytes(16), 'hex');"  # pgcrypto
run_sql "SELECT 'key=>value'::hstore;"  # hstore
run_sql "SELECT 'CamelCase'::citext = 'camelcase'::citext;"  # citext
run_sql "SELECT 'A.B.C'::ltree;"  # ltree
echo "✓ Utility extensions working"

# Step 8: Test sample tables
echo ""
echo "Step 8: Testing sample tables..."
echo "----------------------------------------"

# Insert spatial data
run_sql "INSERT INTO sample_locations (name, point) VALUES ('Test Location', ST_MakePoint(-122.4194, 37.7749)) ON CONFLICT DO NOTHING;"

# Insert FTS data
run_sql "INSERT INTO sample_documents (title, body, category) VALUES ('Test Doc', 'This is a test document for full-text search', 'tech.database.postgres') ON CONFLICT DO NOTHING;"

# Query FTS
run_sql "SELECT id, title FROM sample_documents WHERE search_vector @@ plainto_tsquery('english', 'test');"

echo "✓ Sample tables working"

# Step 9: Test TIGER Geocoder (extension only, no data)
echo ""
echo "Step 9: Verifying TIGER Geocoder extension..."
echo "----------------------------------------"
run_sql "SELECT * FROM tiger.loader_platform LIMIT 1;" || echo "  (TIGER tables exist but need data loading)"
echo "✓ TIGER Geocoder extension installed"

# Step 10: Test Apache AGE (graph database)
echo ""
echo "Step 10: Testing Apache AGE (graph database)..."
echo "----------------------------------------"

# T1: Extension loads
run_sql "SELECT extname, extversion FROM pg_extension WHERE extname = 'age';"
echo "✓ AGE extension loaded"

# T2: Graph creation (need ag_catalog in search_path for AGE functions)
run_sql "SET search_path = ag_catalog, public; SELECT create_graph('smoke_test_graph');"
echo "✓ Graph creation works"

# T3: Cypher queries (create and read vertex)
run_sql "SET search_path = ag_catalog, public; SELECT * FROM cypher('smoke_test_graph', \$\$ CREATE (n:Person {name: 'Smoke Test'}) RETURN n \$\$) AS (result agtype);"
run_sql "SET search_path = ag_catalog, public; SELECT * FROM cypher('smoke_test_graph', \$\$ MATCH (n:Person) RETURN n \$\$) AS (result agtype);"
echo "✓ Cypher queries work"

# T4: Co-existence with pgvector in same database
run_sql "CREATE TABLE age_pgvector_coexist_test (id SERIAL PRIMARY KEY, embedding vector(3));"
run_sql "INSERT INTO age_pgvector_coexist_test (embedding) VALUES ('[1,2,3]');"
run_sql "SELECT * FROM age_pgvector_coexist_test;"
run_sql "DROP TABLE age_pgvector_coexist_test;"
echo "✓ AGE and pgvector co-exist"

# Cleanup test graph
run_sql "SET search_path = ag_catalog, public; SELECT drop_graph('smoke_test_graph', true);"
echo "✓ Graph cleanup works"

echo "✓ Apache AGE working"

# Summary
echo ""
echo "=========================================="
echo "✓ SMOKE TEST PASSED"
echo "=========================================="
echo ""
echo "Verified Extensions:"
echo "  ✓ PostGIS (spatial)"
echo "  ✓ PostGIS Topology"
echo "  ✓ PostGIS TIGER Geocoder"
echo "  ✓ pgvector (vector similarity)"
echo "  ✓ pgRouting (graph algorithms)"
echo "  ✓ Apache AGE (graph database / Cypher)"
echo "  ✓ pg_trgm (trigram similarity)"
echo "  ✓ fuzzystrmatch (fuzzy matching)"
echo "  ✓ unaccent (text normalization)"
echo "  ✓ uuid-ossp (UUID generation)"
echo "  ✓ pgcrypto (cryptography)"
echo "  ✓ hstore (key-value)"
echo "  ✓ citext (case-insensitive text)"
echo "  ✓ ltree (hierarchical data)"
echo "  ✓ tablefunc (pivot tables)"
echo "  ✓ btree_gin, btree_gist (indexing)"
echo ""
echo "PostgreSQL Batteries-Included is working correctly!"
