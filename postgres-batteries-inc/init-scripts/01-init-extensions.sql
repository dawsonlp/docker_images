-- PostgreSQL Batteries-Included: Extension Initialization
-- This script runs automatically during first container startup

\echo '=========================================='
\echo 'PostgreSQL Batteries-Included Setup'
\echo '=========================================='
\echo ''

-- ===== SPATIAL EXTENSIONS =====
\echo 'Creating PostGIS extension...'
CREATE EXTENSION IF NOT EXISTS postgis;

\echo 'Creating PostGIS Topology extension...'
CREATE EXTENSION IF NOT EXISTS postgis_topology;

\echo 'Creating PostGIS Raster extension...'
CREATE EXTENSION IF NOT EXISTS postgis_raster;

\echo 'Creating pgRouting extension...'
CREATE EXTENSION IF NOT EXISTS pgrouting;

-- ===== VECTOR/AI EXTENSIONS =====
\echo 'Creating pgvector extension...'
CREATE EXTENSION IF NOT EXISTS vector;

-- ===== GRAPH EXTENSIONS =====
\echo 'Creating Apache AGE extension (graph database)...'
CREATE EXTENSION IF NOT EXISTS age;

-- ===== FULL-TEXT SEARCH EXTENSIONS =====
\echo 'Creating fuzzystrmatch extension...'
CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;

\echo 'Creating pg_trgm extension (trigram similarity)...'
CREATE EXTENSION IF NOT EXISTS pg_trgm;

\echo 'Creating unaccent extension (text normalization)...'
CREATE EXTENSION IF NOT EXISTS unaccent;

-- ===== TIGER GEOCODER =====
\echo 'Creating PostGIS TIGER geocoder extension...'
CREATE EXTENSION IF NOT EXISTS postgis_tiger_geocoder;

-- ===== UTILITY EXTENSIONS =====
\echo 'Creating uuid-ossp extension...'
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

\echo 'Creating pgcrypto extension...'
CREATE EXTENSION IF NOT EXISTS pgcrypto;

\echo 'Creating hstore extension (key-value)...'
CREATE EXTENSION IF NOT EXISTS hstore;

\echo 'Creating citext extension (case-insensitive text)...'
CREATE EXTENSION IF NOT EXISTS citext;

\echo 'Creating ltree extension (hierarchical data)...'
CREATE EXTENSION IF NOT EXISTS ltree;

-- ===== ANALYTICS EXTENSIONS =====
\echo 'Creating tablefunc extension (crosstab/pivot)...'
CREATE EXTENSION IF NOT EXISTS tablefunc;

\echo 'Creating intarray extension...'
CREATE EXTENSION IF NOT EXISTS intarray;

-- ===== INDEXING EXTENSIONS =====
\echo 'Creating btree_gin extension...'
CREATE EXTENSION IF NOT EXISTS btree_gin;

\echo 'Creating btree_gist extension...'
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ===== PERFORMANCE MONITORING =====
\echo 'Creating pg_stat_statements extension...'
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- ===== CONFIGURE SEARCH PATH =====
\echo 'Setting search path to include ag_catalog and tiger schemas...'
SELECT format('ALTER DATABASE %I SET search_path TO ag_catalog, "$user", public, tiger, tiger_data;', current_database()) \gexec

-- ===== VERIFY INSTALLATION =====
\echo ''
\echo '=========================================='
\echo 'Installed Extensions'
\echo '=========================================='
SELECT extname, extversion FROM pg_extension ORDER BY extname;

-- ===== VERSION INFO =====
\echo ''
\echo 'PostGIS Version:'
SELECT PostGIS_Full_Version();

\echo ''
\echo 'pgRouting Version:'
SELECT pgr_version();

\echo ''
\echo 'pgvector Version:'
SELECT extversion FROM pg_extension WHERE extname = 'vector';

\echo ''
\echo 'Apache AGE Version:'
SELECT extversion FROM pg_extension WHERE extname = 'age';

-- ===== SAMPLE TABLES =====
\echo ''
\echo 'Creating sample demonstration tables...'

-- Vector embeddings table
CREATE TABLE IF NOT EXISTS sample_vectors (
    id SERIAL PRIMARY KEY,
    content TEXT NOT NULL,
    embedding vector(1536),  -- OpenAI ada-002 dimension
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE sample_vectors IS 'Sample table for vector similarity search (AI embeddings)';

-- Create vector index (IVFFlat for approximate nearest neighbor)
CREATE INDEX IF NOT EXISTS sample_vectors_embedding_idx
    ON sample_vectors USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);

-- Spatial data table
CREATE TABLE IF NOT EXISTS sample_locations (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    point GEOMETRY(Point, 4326),
    area GEOMETRY(Polygon, 4326),
    tags TEXT[],
    metadata HSTORE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE sample_locations IS 'Sample table for spatial data with PostGIS';

-- Create spatial indexes
CREATE INDEX IF NOT EXISTS sample_locations_point_idx
    ON sample_locations USING GIST (point);

CREATE INDEX IF NOT EXISTS sample_locations_area_idx
    ON sample_locations USING GIST (area);

-- Full-text search table
CREATE TABLE IF NOT EXISTS sample_documents (
    id SERIAL PRIMARY KEY,
    title CITEXT NOT NULL,  -- Case-insensitive
    body TEXT NOT NULL,
    search_vector TSVECTOR GENERATED ALWAYS AS (
        setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(body, '')), 'B')
    ) STORED,
    category LTREE,  -- Hierarchical category
    tags TEXT[],
    created_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE sample_documents IS 'Sample table for full-text search with weighted fields';

-- Full-text search index
CREATE INDEX IF NOT EXISTS sample_documents_search_idx
    ON sample_documents USING GIN (search_vector);

-- Trigram index for fuzzy search on title
CREATE INDEX IF NOT EXISTS sample_documents_title_trgm_idx
    ON sample_documents USING GIN (title gin_trgm_ops);

-- Category hierarchy index
CREATE INDEX IF NOT EXISTS sample_documents_category_idx
    ON sample_documents USING GIST (category);

-- Routing network table (for pgRouting)
CREATE TABLE IF NOT EXISTS sample_roads (
    id SERIAL PRIMARY KEY,
    name TEXT,
    source INTEGER,
    target INTEGER,
    cost DOUBLE PRECISION,
    reverse_cost DOUBLE PRECISION,
    geom GEOMETRY(LineString, 4326)
);

COMMENT ON TABLE sample_roads IS 'Sample table for graph routing with pgRouting';

CREATE INDEX IF NOT EXISTS sample_roads_geom_idx
    ON sample_roads USING GIST (geom);

-- Graph sample (Apache AGE)
\echo 'Creating sample graph...'
SET search_path = ag_catalog, "$user", public;
SELECT create_graph('sample_graph');

\echo ''
\echo '=========================================='
\echo 'Database initialization completed!'
\echo '=========================================='
\echo ''
\echo 'Quick Reference:'
\echo '  - Vector search: SELECT * FROM sample_vectors ORDER BY embedding <-> query_vector LIMIT 10;'
\echo '  - Spatial query: SELECT * FROM sample_locations WHERE ST_DWithin(point, ST_MakePoint(lon, lat)::geography, 1000);'
\echo '  - Full-text search: SELECT * FROM sample_documents WHERE search_vector @@ plainto_tsquery(''search terms'');'
\echo '  - Routing: SELECT * FROM pgr_dijkstra(''SELECT id, source, target, cost FROM sample_roads'', start_id, end_id);'
\echo '  - Graph (Cypher): SELECT * FROM cypher(''sample_graph'', $$ MATCH (n) RETURN n $$) AS (result agtype);'
\echo ''
