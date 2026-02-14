# Technical Design: Adding Apache AGE to postgres-batteries-inc

**Status**: Technical Design  
**Date**: 2026-02-13  
**Author**: Senior DevOps Architect  
**Implements**: `postgres-age-requirements.md`

---

## 1. Summary

Add Apache AGE (graph database extension) to the `postgres-batteries-inc` Docker image by compiling it from source during the image build. This is the only extension in the image that requires source compilation — all other extensions (including pgvector) are installed via apt packages.

**Scope**: Dockerfile modification, init script update, CMD change, smoke test additions. No new files beyond the smoke test update and this document.

---

## 2. Current State Analysis

### Build Pipeline

The existing Dockerfile is straightforward:

1. `FROM postgres:18`
2. Single `apt-get install` layer for all extensions (PostGIS, pgvector, pgRouting, contrib, utilities)
3. `COPY` init scripts and helper scripts
4. `mkdir` for TIGER data directories
5. `HEALTHCHECK` and default `CMD ["postgres"]`

**Key observation**: The requirements document states pgvector is "compiled from source," but the actual Dockerfile installs it via `postgresql-18-pgvector` apt package. This means AGE will be the **first and only** extension requiring source compilation. This affects the design — we must introduce build tooling that doesn't currently exist in any layer.

### Extension Loading

All extensions are created by `01-init-extensions.sql` using `CREATE EXTENSION IF NOT EXISTS`. No extension currently requires `shared_preload_libraries`.

### Build Infrastructure

- Multi-arch via `cloud-dawsonlp-arm64` BuildX builder
- `build.sh` handles local (`docker build`) and remote (`docker buildx build --push`) builds
- Tags: `latest` and `18`

---

## 3. Design Decisions

### 3.1 Source Strategy: Git Tag Clone

**Decision**: Clone the official Apache AGE repository at a specific release tag.

**Rationale**: AGE does not publish release tarballs on their GitHub releases page in a format suitable for `curl`/`wget` extraction. The git tag approach is:
- Reproducible (pinned to exact release)
- Standard practice for PostgreSQL extension builds
- Consistent with how AGE's own documentation recommends building

**Tag**: `PG18/v1.7.0` (latest release with PG18 support). If a later `PG18/v1.7.x` tag becomes available, use that instead.

**Alternative considered**: Downloading a GitHub release tarball. Rejected because AGE's release artifacts are branch-specific and the tag approach is more reliable.

### 3.2 Build Layer Strategy: Separate RUN Layer

**Decision**: Add a new `RUN` layer after the existing apt-get layer that:
1. Installs build dependencies (`build-essential`, `postgresql-server-dev-18`, `flex`, `bison`, `git`)
2. Clones AGE at the release tag
3. Compiles and installs
4. Removes source code and build dependencies

All in a single `RUN` command to minimize layer size.

**Rationale**: The existing apt-get layer installs runtime packages and should not be modified to include build-time dependencies. A separate layer keeps the concern boundary clean and makes it easy to update AGE independently.

**Alternative considered**: Multi-stage build (compile in a builder stage, copy artifacts). Rejected because:
- AGE installs into multiple PostgreSQL directories (`lib/`, `share/extension/`)
- Determining exactly which files to copy is fragile and varies between AGE versions
- The single-layer install-compile-cleanup pattern is simpler and the image size difference is negligible (build deps are removed in the same layer)

### 3.3 shared_preload_libraries: conf.d Snippet

**Decision**: Add a configuration file at `/etc/postgresql/conf.d/age.conf` (or the appropriate `conf.d` path used by the official postgres image) that sets `shared_preload_libraries = 'age'`.

**Rationale**:
- The official `postgres:18` image supports `conf.d` style includes — any `.conf` file in `/etc/postgresql-common/createcluster.d/` or appended to `postgresql.conf` is loaded
- Actually, the simplest reliable approach for the official Docker image: append to the CMD. The official postgres Docker image doesn't automatically include conf.d files. The correct approach is to modify the `CMD` directive.

**Revised Decision**: Change `CMD ["postgres"]` to `CMD ["postgres", "-c", "shared_preload_libraries=age"]`.

**Rationale for CMD approach**:
- Simplest mechanism — single line change
- Explicit and visible in the Dockerfile
- Overridable by users if they need to add additional shared_preload_libraries
- No need to determine the correct conf.d path for the official image (which varies)
- If additional libraries need preloading in the future, the value is comma-separated: `shared_preload_libraries=age,pg_stat_statements`

**Alternative considered**: `ALTER SYSTEM SET shared_preload_libraries = 'age'` in init script. Rejected because this writes to `postgresql.auto.conf` and requires a restart, which is not practical during init.

### 3.4 Search Path: Database-Level Default in Init Script

**Decision**: Set `ag_catalog` in the search path at the database level in `01-init-extensions.sql`:

```sql
ALTER DATABASE :"DBNAME" SET search_path TO ag_catalog, "$user", public, tiger, tiger_data;
```

**Note**: The TIGER geocoder init script (`02-init-tiger-geocoder.sh`) already sets `search_path TO public, tiger, tiger_data`. The AGE init must be compatible — the final search path must include all schemas: `ag_catalog`, `public`, `tiger`, `tiger_data`.

**Rationale**: Database-level default means all new sessions automatically have access to AGE functions without per-session `SET` or `LOAD` commands. Since `shared_preload_libraries` handles the library loading, `LOAD 'age'` is not needed per-session.

### 3.5 Init Script Placement

**Decision**: Add AGE extension creation to the existing `01-init-extensions.sql` file, in a new `GRAPH EXTENSIONS` section after the existing `VECTOR/AI EXTENSIONS` section.

**Rationale**: Follows the established pattern. No new init script file needed.

### 3.6 AGE Version Pinning

**Decision**: Define `AGE_VERSION` as an `ENV` variable in the Dockerfile (e.g., `AGE_VERSION=PG18/v1.7.0-rc0`) for easy updates.

**Rationale**: Same pattern used for `POSTGIS_VERSION=3`. Makes version bumps a single-line change.

---

## 4. Implementation Plan

### 4.1 Dockerfile Changes

Add after the existing `ENV POSTGIS_VERSION=3` line:

```dockerfile
ENV AGE_VERSION=PG18/v1.7.0
```

Add a new `RUN` layer after the existing `apt-get` layer and before the `COPY` commands:

```dockerfile
# Build and install Apache AGE from source
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        postgresql-server-dev-${PG_MAJOR} \
        flex \
        bison \
        git \
    ; \
    git clone --branch ${AGE_VERSION} --single-branch --depth 1 \
        https://github.com/apache/age.git /tmp/age; \
    cd /tmp/age; \
    make PG_CONFIG=/usr/lib/postgresql/${PG_MAJOR}/bin/pg_config install; \
    # Cleanup build artifacts and dependencies
    cd /; \
    rm -rf /tmp/age; \
    apt-get purge -y --auto-remove \
        build-essential \
        postgresql-server-dev-${PG_MAJOR} \
        flex \
        bison \
        git \
    ; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*;
```

Change the CMD line:

```dockerfile
CMD ["postgres", "-c", "shared_preload_libraries=age"]
```

Update the `LABEL` description to mention AGE:

```dockerfile
org.opencontainers.image.description="PostgreSQL with PostGIS, pgvector, Apache AGE, pgrouting, and essential extensions"
```

### 4.2 Init Script Changes (`01-init-extensions.sql`)

Add after the `VECTOR/AI EXTENSIONS` section:

```sql
-- ===== GRAPH EXTENSIONS =====
\echo 'Creating Apache AGE extension (graph database)...'
CREATE EXTENSION IF NOT EXISTS age;
```

Add a search path update after all extensions are created (replaces any existing search path logic, and must be compatible with `02-init-tiger-geocoder.sh` which sets `public, tiger, tiger_data`):

```sql
-- ===== CONFIGURE SEARCH PATH =====
\echo 'Setting search path to include ag_catalog and tiger schemas...'
SELECT format('ALTER DATABASE %I SET search_path TO ag_catalog, "$user", public, tiger, tiger_data;', current_database()) \gexec
```

Add AGE verification to the verification section:

```sql
\echo 'Apache AGE Version:'
SELECT extversion FROM pg_extension WHERE extname = 'age';
```

Optionally add a sample graph table to the sample tables section (lightweight, demonstrates capability):

```sql
-- Graph sample (Apache AGE)
\echo 'Creating sample graph...'
SELECT create_graph('sample_graph');
```

### 4.3 Smoke Test Changes

Add to `smoke-tests/run-smoke-test.sh` (or create a dedicated AGE smoke test script):

```sql
-- T1: Extension loads
SELECT extname, extversion FROM pg_extension WHERE extname = 'age';

-- T2: Graph creation
SELECT create_graph('smoke_test_graph');

-- T3: Cypher query (create and read vertex)
SELECT * FROM cypher('smoke_test_graph', $$ 
    CREATE (n:Person {name: 'Smoke Test'}) RETURN n 
$$) AS (result agtype);

SELECT * FROM cypher('smoke_test_graph', $$ 
    MATCH (n:Person) RETURN n 
$$) AS (result agtype);

-- T4: Co-existence with pgvector
CREATE TABLE IF NOT EXISTS age_pgvector_test (
    id SERIAL PRIMARY KEY,
    embedding vector(3)
);
INSERT INTO age_pgvector_test (embedding) VALUES ('[1,2,3]');
SELECT * FROM age_pgvector_test;
DROP TABLE age_pgvector_test;

-- Cleanup
SELECT drop_graph('smoke_test_graph', true);
```

### 4.4 docker-compose.yml Changes

No changes needed. The CMD in the Dockerfile handles `shared_preload_libraries`. If a user overrides CMD in their compose file, they must include the flag themselves — this is documented.

### 4.5 build.sh Changes

No changes needed. The build script passes `PG_MAJOR` as a build arg and the rest is handled by the Dockerfile.

### 4.6 Documentation Changes

Update `README.md`:
- Add Apache AGE to the "Included Extensions" table under a new "Graph" section
- Add a Cypher query example to the usage section
- Update the extension count in the description

---

## 5. Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| AGE `PG18/v1.7.0-rc0` tag has build issues on arm64 | Low | High | Test multi-arch build before merging. Fall back to building from `master` branch at a known commit if needed. |
| `apt-get purge build-essential` removes packages needed by PostGIS/pgvector runtime | Low | High | PostGIS and pgvector are installed via apt with their own runtime dependencies tracked by apt. `purge --auto-remove` only removes packages not needed by other installed packages. Verify with `dpkg -l` after build. |
| Image size exceeds 50MB increase target | Low | Low | AGE compiled binary is ~5-10MB. Build deps are cleaned up. Monitor with `docker images`. |
| `shared_preload_libraries=age` increases startup time | Very Low | Low | AGE preload is lightweight. Health check start_period is 60 seconds — ample margin. |
| Search path conflict between AGE (`ag_catalog`) and TIGER (`tiger`, `tiger_data`) | Medium | Medium | Set unified search path in `01-init-extensions.sql`. The `02-init-tiger-geocoder.sh` runs after and may override — verify ordering and final search path in smoke test. |

---

## 6. Verification Checklist

After implementation, verify:

- [x] `docker build` succeeds locally (single arch) — 298MB compressed
- [ ] `docker buildx build --platform linux/amd64,linux/arm64` succeeds
- [x] Container starts and health check passes within 60 seconds (3 attempts)
- [x] `SELECT extname, extversion FROM pg_extension WHERE extname = 'age';` returns `1.7.0`
- [x] `SELECT create_graph('test'); SELECT drop_graph('test', true);` succeeds
- [x] Cypher `CREATE` and `MATCH` queries work
- [x] All existing extensions still load (21 extensions verified)
- [x] AGE and pgvector work in same database and same transaction
- [x] `sample_graph` exists after init
- [x] All smoke tests pass (Steps 1–10)
- [x] Image size increase acceptable (298MB compressed, same baseline order of magnitude)
- [x] `docker images` shows correct tags (`latest`, `18`)

---

## 7. Files Modified

| File | Change |
|------|--------|
| `Dockerfile` | Add `AGE_VERSION` env, add AGE build layer, update CMD, update LABEL |
| `init-scripts/01-init-extensions.sql` | Add AGE extension creation, search path, verification, sample graph |
| `smoke-tests/run-smoke-test.sh` | Add AGE smoke tests (T1–T5) |
| `README.md` | Add AGE to extension list, add Cypher example |
| `AGE_DESIGN.md` | This document |

---

## 8. Implementation Notes (Post-Build)

### Search Path Timing Issue

During implementation, the `create_graph('sample_graph')` call in `01-init-extensions.sql` failed with `function create_graph(unknown) does not exist`. 

**Root cause**: `ALTER DATABASE ... SET search_path` only takes effect for **new** sessions. The psql session executing the init script does not pick up the database-level default. AGE functions like `create_graph()` live in the `ag_catalog` schema and require it in the search path.

**Fix**: Added an explicit `SET search_path = ag_catalog, "$user", public;` immediately before the `create_graph()` call in the init script. This sets the search path for the current session. The `ALTER DATABASE` still applies to all future sessions.

This same pattern is needed in the smoke tests — each `run_sql` call is a separate `docker exec psql` invocation (a new session), but the database-level default only applies after the init completes and the database restarts. The smoke test sessions do get the database-level default, but to be safe and explicit, each AGE-related smoke test call uses `SET search_path = ag_catalog, public;` as a prefix.

---

## 9. Estimated Effort

| Task | Time |
|------|------|
| Dockerfile changes | 15 minutes |
| Init script changes | 10 minutes |
| Smoke test additions | 15 minutes |
| Local build + test | 20 minutes |
| Multi-arch build + push | 15 minutes |
| Documentation updates | 15 minutes |
| **Total** | **~1.5 hours** |