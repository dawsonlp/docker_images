# PostgreSQL Batteries-Included

[![Docker Hub](https://img.shields.io/badge/docker-dawsonlp%2Fpostgres--batteries--inc-blue)](https://hub.docker.com/r/dawsonlp/postgres-batteries-inc)

PostgreSQL 18 with PostGIS, pgvector, pgRouting, and 15+ essential extensions pre-installed.

## Quick Start

```bash
# Pull and run
docker run -d --name postgres -p 5432:5432 \
  -e POSTGRES_PASSWORD=postgres \
  dawsonlp/postgres-batteries-inc:latest

# Connect
psql -h localhost -U postgres
```

Or with Docker Compose:

```bash
# Set password and start
export POSTGRES_PASSWORD=your_secure_password
docker compose up -d
```

## Available Tags

| Tag | PostgreSQL | Description |
|-----|------------|-------------|
| `latest`, `18` | 18 | Latest stable |

## Included Extensions

### Spatial & Routing
| Extension | Description |
|-----------|-------------|
| **PostGIS** | Spatial database with geometry, geography, raster |
| **PostGIS Topology** | Topological data management |
| **PostGIS TIGER Geocoder** | US address geocoding |
| **pgRouting** | Graph algorithms, shortest path routing |

### Vector & AI
| Extension | Description |
|-----------|-------------|
| **pgvector** | Vector similarity search for AI embeddings |

### Full-Text Search
| Extension | Description |
|-----------|-------------|
| **pg_trgm** | Trigram similarity for fuzzy matching |
| **fuzzystrmatch** | Fuzzy string matching (soundex, metaphone) |
| **unaccent** | Remove accents for text normalization |

### Utility
| Extension | Description |
|-----------|-------------|
| **uuid-ossp** | UUID generation |
| **pgcrypto** | Cryptographic functions |
| **hstore** | Key-value storage |
| **citext** | Case-insensitive text |
| **ltree** | Hierarchical data (tree structures) |

### Analytics & Indexing
| Extension | Description |
|-----------|-------------|
| **tablefunc** | Crosstab/pivot tables |
| **intarray** | Integer array functions |
| **btree_gin** | GIN index for common types |
| **btree_gist** | GiST index for common types |
| **pg_stat_statements** | Query performance monitoring |

## Usage Examples

### Vector Similarity Search (AI)

```sql
-- Create table with embeddings
CREATE TABLE documents (
    id SERIAL PRIMARY KEY,
    content TEXT,
    embedding vector(1536)  -- OpenAI dimension
);

-- Find similar documents
SELECT * FROM documents
ORDER BY embedding <-> '[0.1, 0.2, ...]'::vector
LIMIT 10;
```

### Spatial Queries (PostGIS)

```sql
-- Find locations within 1km
SELECT * FROM locations
WHERE ST_DWithin(
    point::geography,
    ST_MakePoint(-122.4194, 37.7749)::geography,
    1000
);
```

### Full-Text Search

```sql
-- Create searchable table
CREATE TABLE articles (
    id SERIAL PRIMARY KEY,
    title TEXT,
    body TEXT,
    search_vector TSVECTOR GENERATED ALWAYS AS (
        to_tsvector('english', title || ' ' || body)
    ) STORED
);

CREATE INDEX ON articles USING GIN(search_vector);

-- Search
SELECT * FROM articles
WHERE search_vector @@ plainto_tsquery('english', 'search terms');
```

### Graph Routing (pgRouting)

```sql
-- Shortest path between nodes
SELECT * FROM pgr_dijkstra(
    'SELECT id, source, target, cost FROM roads',
    1,    -- start node
    100   -- end node
);
```

### Fuzzy Matching

```sql
-- Trigram similarity
SELECT * FROM companies
WHERE name % 'Microsft'  -- typo-tolerant
ORDER BY similarity(name, 'Microsft') DESC;
```

## Sample Tables

The image creates sample tables for demonstration:

- `sample_vectors` - Vector embeddings with IVFFlat index
- `sample_locations` - Spatial data with GiST indexes
- `sample_documents` - Full-text search with weighted fields
- `sample_roads` - Graph network for routing

## TIGER Geocoder

US address geocoding is available. Load TIGER data:

```bash
# Load national data (required first)
docker exec postgres load-tiger-nation.sh

# Load state data
docker exec postgres load-tiger-state-direct.sh TX
```

Then geocode:

```sql
SELECT * FROM geocode('1600 Pennsylvania Ave, Washington, DC');
```

## Configuration

Set these environment variables before running `docker compose up`:

| Variable | Default | Description |
|----------|---------|-------------|
| `POSTGRES_USER` | `postgres` | Database user |
| `POSTGRES_PASSWORD` | **(required)** | User password - must be set |
| `POSTGRES_DB` | `postgres` | Default database |

**Example:**
```bash
export POSTGRES_PASSWORD=your_secure_password
docker compose up -d
```

Or create a `.env` file (not committed to git):
```bash
POSTGRES_PASSWORD=your_secure_password
```

## Data Persistence

```yaml
# PostgreSQL 18+ uses version-specific subdirectories
volumes:
  - postgres-data:/var/lib/postgresql
```

## Building

```bash
# Build and push
chmod +x build.sh
./build.sh

# Build locally only
./build.sh --local
```

## Smoke Tests

```bash
cd smoke-tests
chmod +x run-smoke-test.sh
./run-smoke-test.sh
```

## Health Check

```bash
docker inspect --format='{{.State.Health.Status}}' postgres-batteries-inc
```

## License

PostgreSQL License