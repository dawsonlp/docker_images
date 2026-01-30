# PostgreSQL PostGIS Quick Start

Get up and running with PostgreSQL 18, PostGIS, and pgvector in minutes.

## ⚠️ Security First

**CRITICAL**: You MUST set up passwords before starting. NEVER use default passwords or commit credentials to git.

## Prerequisites

- Docker and Docker Compose installed
- 2GB+ free disk space (more if loading TIGER data)

## 1. Set Up Credentials (REQUIRED)

```bash
cd postgres-postgis

# Copy the example environment file
cp .env.example .env

# Generate a strong password
openssl rand -base64 32

# Edit .env and set the generated password
# Replace CHANGE_ME_TO_STRONG_PASSWORD with your generated password
nano .env  # or vim, code, etc.
```

**Important**:
- Use a password with 16+ characters
- Mix uppercase, lowercase, numbers, special characters
- Never reuse passwords from other systems
- Keep .env file secure and never commit it to git

## 2. Start the Database

```bash
docker compose up -d
```

Wait for the healthcheck to pass (about 30 seconds):
```bash
docker compose ps
```

## 3. Connect to Database

### Using psql (via Docker)
```bash
# Use the username from your .env file (default: postgres)
docker exec -it postgres-postgis psql -U postgres
# It will prompt for the password you set in .env
```

### Using psql (local installation)
```bash
# Use credentials from your .env file
psql -h localhost -U postgres -d postgres
# Enter the password you set in .env when prompted
```

### Using pgAdmin (Optional)
If you started pgAdmin (it's in docker-compose.yml):

Open http://localhost:5050 in your browser:
- Email: Value from `PGADMIN_DEFAULT_EMAIL` in your .env
- Password: Value from `PGADMIN_DEFAULT_PASSWORD` in your .env

Add server in pgAdmin:
- Host: `postgres` (or `host.docker.internal` from host)
- Port: `5432`
- Username: Value from `POSTGRES_USER` in your .env
- Password: Value from `POSTGRES_PASSWORD` in your .env

## 4. Verify Installation

```sql
-- Check PostgreSQL version
SELECT version();

-- List installed extensions
\dx

-- Verify PostGIS
SELECT PostGIS_Full_Version();

-- Verify pgvector
SELECT * FROM pg_extension WHERE extname = 'vector';
```

You should see:
- `postgis`
- `postgis_topology`
- `postgis_tiger_geocoder`
- `vector`
- `fuzzystrmatch`
- `pg_trgm`

## 5. Try It Out

### Spatial Query Example

```sql
-- Create a table with spatial data
CREATE TABLE cities (
    id SERIAL PRIMARY KEY,
    name TEXT,
    location GEOMETRY(Point, 4326)
);

-- Insert some cities
INSERT INTO cities (name, location) VALUES
    ('San Francisco', ST_SetSRID(ST_MakePoint(-122.4194, 37.7749), 4326)),
    ('Los Angeles', ST_SetSRID(ST_MakePoint(-118.2437, 34.0522), 4326)),
    ('New York', ST_SetSRID(ST_MakePoint(-74.0060, 40.7128), 4326)),
    ('Chicago', ST_SetSRID(ST_MakePoint(-87.6298, 41.8781), 4326));

-- Find the distance between San Francisco and other cities (in meters)
SELECT
    c2.name,
    ROUND(ST_Distance(c1.location::geography, c2.location::geography) / 1609.34) AS miles
FROM cities c1, cities c2
WHERE c1.name = 'San Francisco' AND c2.name != 'San Francisco'
ORDER BY miles;

-- Find cities within 100 miles of San Francisco
SELECT
    c2.name,
    ROUND(ST_Distance(c1.location::geography, c2.location::geography) / 1609.34) AS miles
FROM cities c1, cities c2
WHERE c1.name = 'San Francisco'
  AND ST_DWithin(c1.location::geography, c2.location::geography, 160934)  -- 100 miles in meters
  AND c2.name != 'San Francisco';
```

### Vector Search Example

```sql
-- Create a table for document embeddings
CREATE TABLE documents (
    id SERIAL PRIMARY KEY,
    title TEXT,
    content TEXT,
    embedding vector(3)  -- Using 3 dimensions for demo (real use: 1536 for OpenAI)
);

-- Insert sample documents with embeddings
INSERT INTO documents (title, content, embedding) VALUES
    ('PostgreSQL Guide', 'Learn about databases', '[1, 0.5, 0.2]'),
    ('PostGIS Tutorial', 'Spatial database features', '[0.9, 0.6, 0.3]'),
    ('Vector Search', 'Using pgvector for AI', '[0.2, 0.8, 0.9]'),
    ('Machine Learning', 'AI and embeddings', '[0.3, 0.7, 0.8]');

-- Create an index for vector similarity search
CREATE INDEX ON documents USING ivfflat (embedding vector_cosine_ops) WITH (lists = 2);

-- Find similar documents using cosine similarity
SELECT
    title,
    content,
    1 - (embedding <=> '[1, 0.5, 0.2]'::vector) AS similarity
FROM documents
ORDER BY embedding <=> '[1, 0.5, 0.2]'::vector
LIMIT 3;
```

### Geocoding Example (requires TIGER data)

```sql
-- Forward geocoding (address to coordinates)
SELECT
    rating,
    lon,
    lat,
    full_address
FROM geocode_address('1600 Pennsylvania Avenue NW, Washington, DC');

-- Reverse geocoding (coordinates to address)
SELECT
    street_number,
    street_name,
    city,
    state,
    zip,
    full_address
FROM reverse_geocode_point(-77.0365, 38.8977);
```

**Note**: Geocoding requires TIGER data to be loaded. See README.md for instructions.

## 6. Load TIGER Data (Optional)

TIGER geocoder provides US address data but increases database size significantly.

**Important**: TIGER data loading is a two-phase process:
1. Load national data (required, once)
2. Load state-specific data (per state needed)

### Quick Start (All-in-One)

```bash
# Load national data + Tennessee in one command
docker exec postgres-postgis /usr/local/bin/load-tiger-data.sh --with-nation TN
```

### Step-by-Step Approach

```bash
# Phase 1: Load national data (one-time, ~7 minutes, ~200 MB)
docker exec postgres-postgis /usr/local/bin/load-tiger-nation.sh

# Phase 2: Load state data (per state, 30-90 minutes, 3-10 GB each)
docker exec postgres-postgis /usr/local/bin/load-tiger-data.sh TN

# Load multiple states
docker exec postgres-postgis /usr/local/bin/load-tiger-data.sh CA NY TX
```

### Check Loading Status

```sql
-- Check national data
SELECT COUNT(*) as states FROM tiger_data.state_all;      -- Should be ~56
SELECT COUNT(*) as counties FROM tiger_data.county_all;   -- Should be ~3,200

-- Check Tennessee data (after loading TN)
SELECT COUNT(*) as places FROM tiger_data.tn_county;      -- Should be 95
SELECT COUNT(*) as edges FROM tiger_data.tn_edges;        -- Should be ~1.8M
SELECT COUNT(*) as addresses FROM tiger_data.tn_addr;     -- Should be ~2.7M
```

### Test Geocoding

After loading Tennessee data:

```sql
-- Forward geocoding (address to coordinates)
SELECT * FROM geocode('123 Main St, Nashville, TN', 1);

-- Using helper function
SELECT rating, lon, lat, full_address
FROM geocode_address('123 Main St, Nashville, TN');
```

## Common Tasks

### Backup Database
```bash
docker exec postgres-postgis pg_dump -U postgres postgres > backup.sql
```

### Restore Database
```bash
docker exec -i postgres-postgis psql -U postgres postgres < backup.sql
```

### View Logs
```bash
docker logs postgres-postgis
```

### Stop Database
```bash
docker compose down
```

### Remove All Data
```bash
docker compose down -v
```

## Next Steps

- Read the full [README.md](README.md) for advanced usage
- Check [PostGIS documentation](https://postgis.net/docs/) for spatial functions
- Check [pgvector documentation](https://github.com/pgvector/pgvector) for vector operations
- Explore TIGER geocoder functions for address matching

## Troubleshooting

### Can't connect to database
```bash
# Check if container is running
docker compose ps

# Check logs for errors
docker logs postgres-postgis

# Verify healthcheck
docker inspect postgres-postgis | grep -A 10 Health
```

### Extensions not available
```sql
-- Verify extensions are installed
SELECT * FROM pg_available_extensions
WHERE name IN ('postgis', 'vector', 'postgis_tiger_geocoder');

-- If missing, recreate container
docker compose down -v
docker compose up -d
```

### Performance is slow
```sql
-- Update statistics
ANALYZE;

-- Check query plans
EXPLAIN ANALYZE <your query>;

-- Increase shared memory in docker-compose.yml
shm_size: 512mb
```

## Production Checklist

Before deploying to production:

- [ ] Change default passwords
- [ ] Configure SSL/TLS
- [ ] Set up automated backups
- [ ] Configure resource limits
- [ ] Set up monitoring
- [ ] Review PostgreSQL configuration
- [ ] Test failover procedures
- [ ] Document connection strings
- [ ] Set up log aggregation

## Support

For issues and questions:
- GitHub: [docker_images repository](https://github.com/dawsonlp/docker_images)
- PostgreSQL docs: https://www.postgresql.org/docs/
- PostGIS docs: https://postgis.net/docs/
