# Security Best Practices

**CRITICAL**: This document outlines essential security practices for deploying PostgreSQL with PostGIS and pgvector in production.

## Password Management

### NEVER Hardcode Passwords

**DO NOT** hardcode passwords in:
- Docker Compose files
- Dockerfiles
- Configuration files committed to git
- Scripts or application code
- Documentation or README files

### Use Environment Variables and .env Files

1. **Copy the example file**:
   ```bash
   cp .env.example .env
   ```

2. **Generate strong passwords**:
   ```bash
   # Linux/macOS
   openssl rand -base64 32

   # Or use a password manager
   # Recommended: 1Password, Bitwarden, LastPass
   ```

3. **Edit .env with strong passwords**:
   - Minimum 16 characters
   - Mix of uppercase, lowercase, numbers, special characters
   - Different password for each service
   - Never reuse passwords from other systems

4. **Verify .env is in .gitignore**:
   ```bash
   # This should show .env in the gitignore
   cat .gitignore | grep .env
   ```

### Password Requirements

**Production Minimum Requirements**:
- Length: 20+ characters
- Complexity: Uppercase, lowercase, numbers, special characters
- Uniqueness: Different for each environment and service
- Rotation: Change every 90 days

**Example Strong Password**:
```bash
# Generate a strong password
openssl rand -base64 32
# Output: kJ8vN3xQ2mR9tY6wE4sF1aH7bL5cP0dZ8gT4uV2n=
```

**BAD Examples** (NEVER use these):
- ❌ `postgres`
- ❌ `password`
- ❌ `admin`
- ❌ `123456`
- ❌ `Password123`

## Environment-Specific Security

### Development
- Use .env file (never committed)
- Strong passwords even in development
- Separate from production credentials
- Document setup in README

### Testing
- Use .env file in test directory
- Different passwords than development/production
- Can be regenerated for each test run
- Consider ephemeral credentials

### Production

**DO NOT use .env files in production**. Use proper secrets management:

#### AWS
```bash
# Store secrets in AWS Secrets Manager
aws secretsmanager create-secret \
  --name postgres/production/password \
  --secret-string "$(openssl rand -base64 32)"

# Retrieve in application
aws secretsmanager get-secret-value \
  --secret-id postgres/production/password \
  --query SecretString \
  --output text
```

#### Kubernetes
```bash
# Create secret
kubectl create secret generic postgres-credentials \
  --from-literal=username=postgres \
  --from-literal=password="$(openssl rand -base64 32)"

# Use in pod
env:
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: postgres-credentials
      key: password
```

#### Docker Swarm
```bash
# Create secret
echo "$(openssl rand -base64 32)" | docker secret create postgres_password -

# Use in service
docker service create \
  --secret postgres_password \
  --env POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password \
  dawsonlp/postgres-postgis:latest
```

## Connection Security

### SSL/TLS Configuration

**Production MUST use SSL/TLS**:

1. **Generate certificates**:
   ```bash
   # Self-signed for development (use proper CA in production)
   openssl req -new -x509 -days 365 -nodes \
     -text -out server.crt \
     -keyout server.key \
     -subj "/CN=postgres.yourdomain.com"

   chmod 600 server.key
   ```

2. **Configure PostgreSQL**:
   ```sql
   ALTER SYSTEM SET ssl = on;
   ALTER SYSTEM SET ssl_cert_file = '/path/to/server.crt';
   ALTER SYSTEM SET ssl_key_file = '/path/to/server.key';
   SELECT pg_reload_conf();
   ```

3. **Require SSL for connections**:
   ```sql
   ALTER USER postgres REQUIRE SSL;
   ```

4. **Client connection**:
   ```bash
   psql "postgresql://postgres@host:5432/postgres?sslmode=require"
   ```

### Network Isolation

1. **Use private networks**:
   ```yaml
   # docker-compose.yml
   networks:
     postgres-network:
       internal: true  # No external access
   ```

2. **Restrict host binding**:
   ```yaml
   ports:
     - "127.0.0.1:5432:5432"  # Only localhost access
   ```

3. **Firewall rules** (AWS Security Groups, iptables):
   ```bash
   # Only allow from application servers
   iptables -A INPUT -p tcp --dport 5432 -s 10.0.1.0/24 -j ACCEPT
   iptables -A INPUT -p tcp --dport 5432 -j DROP
   ```

## Access Control

### Principle of Least Privilege

1. **Create role-specific users**:
   ```sql
   -- Read-only user for reporting
   CREATE USER reporting_user WITH PASSWORD 'strong_password';
   GRANT CONNECT ON DATABASE mydb TO reporting_user;
   GRANT SELECT ON ALL TABLES IN SCHEMA public TO reporting_user;

   -- Application user with limited permissions
   CREATE USER app_user WITH PASSWORD 'strong_password';
   GRANT CONNECT ON DATABASE mydb TO app_user;
   GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_user;
   ```

2. **Disable superuser for applications**:
   ```sql
   -- Never use postgres superuser in applications
   -- Create app-specific users with only needed permissions
   ```

3. **Restrict pg_hba.conf**:
   ```conf
   # Only allow SSL connections from specific hosts
   hostssl all all 10.0.1.0/24 md5
   ```

## Database Security

### Row-Level Security (RLS)

```sql
-- Enable RLS
ALTER TABLE sensitive_data ENABLE ROW LEVEL SECURITY;

-- Create policy
CREATE POLICY user_data_policy ON sensitive_data
  USING (user_id = current_user_id());
```

### Audit Logging

```sql
-- Enable logging
ALTER SYSTEM SET log_connections = on;
ALTER SYSTEM SET log_disconnections = on;
ALTER SYSTEM SET log_statement = 'all';
SELECT pg_reload_conf();
```

### Regular Updates

```bash
# Rebuild images monthly for security patches
docker pull postgres:18
docker buildx build --platform linux/amd64,linux/arm64 \
  -t dawsonlp/postgres-postgis:$(date +%Y%m%d) \
  --push .
```

## Container Security

### Run as Non-Root

The official postgres image already runs as the `postgres` user (not root) inside the container. Verify:

```bash
docker exec postgres-postgis whoami
# Should output: postgres
```

### Read-Only Filesystem

For additional security, mount non-data volumes as read-only:

```yaml
volumes:
  - postgres-data:/var/lib/postgresql/data  # Read-write (required)
  - ./config:/etc/postgresql:ro             # Read-only
```

### Resource Limits

Prevent DoS attacks with resource limits:

```yaml
deploy:
  resources:
    limits:
      cpus: '2'
      memory: 4G
    reservations:
      cpus: '1'
      memory: 2G
```

## Backup Security

### Encrypt Backups

```bash
# Encrypted backup
pg_dump -U postgres mydb | \
  openssl enc -aes-256-cbc -salt -pbkdf2 -out backup.sql.enc

# Encrypted restore
openssl enc -d -aes-256-cbc -pbkdf2 -in backup.sql.enc | \
  psql -U postgres mydb
```

### Secure Backup Storage

- Store backups in encrypted storage (AWS S3 with encryption)
- Use separate credentials for backup access
- Enable versioning to prevent accidental deletion
- Test restore procedures regularly

## Compliance Considerations

### HIPAA
- Encrypt data at rest and in transit
- Enable audit logging
- Implement access controls
- Regular security assessments

### PCI-DSS
- Network isolation
- Encryption (SSL/TLS)
- Access logging and monitoring
- Regular security testing

### GDPR
- Data encryption
- Access controls
- Audit trails
- Right to erasure capabilities

## Security Checklist

Before deploying to production:

- [ ] Strong, unique passwords for all services
- [ ] Passwords stored in secrets manager (not .env)
- [ ] SSL/TLS enabled and enforced
- [ ] Firewall rules configured
- [ ] Non-superuser application accounts
- [ ] Row-level security policies where needed
- [ ] Audit logging enabled
- [ ] Regular backup schedule
- [ ] Backup encryption enabled
- [ ] Resource limits configured
- [ ] Security groups/network policies configured
- [ ] Monitoring and alerting set up
- [ ] Incident response plan documented
- [ ] Regular security updates scheduled

## Incident Response

If credentials are compromised:

1. **Immediately rotate passwords**:
   ```sql
   ALTER USER postgres WITH PASSWORD 'new_strong_password';
   ```

2. **Revoke existing sessions**:
   ```sql
   SELECT pg_terminate_backend(pid)
   FROM pg_stat_activity
   WHERE usename = 'compromised_user';
   ```

3. **Review audit logs**:
   ```sql
   -- Check for unauthorized access
   SELECT * FROM pg_stat_activity;
   ```

4. **Update secrets in secrets manager**
5. **Redeploy applications with new credentials**
6. **Document incident and lessons learned**

## Additional Resources

- [PostgreSQL Security Documentation](https://www.postgresql.org/docs/current/security.html)
- [OWASP Database Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Database_Security_Cheat_Sheet.html)
- [CIS PostgreSQL Benchmark](https://www.cisecurity.org/benchmark/postgresql)
- [Docker Security Best Practices](https://docs.docker.com/engine/security/)

## Reporting Security Issues

If you discover a security vulnerability:
1. **DO NOT** open a public GitHub issue
2. Email: security@yourdomain.com (replace with actual contact)
3. Include detailed description and reproduction steps
4. Allow reasonable time for response before public disclosure
