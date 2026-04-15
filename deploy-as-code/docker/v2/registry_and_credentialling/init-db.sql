-- Create databases
CREATE DATABASE kratos;
CREATE DATABASE hydra;

-- Create users
CREATE USER kratos WITH PASSWORD '<KRATOS_DB_PASSWORD>';
CREATE USER hydra WITH PASSWORD '<HYDRA_DB_PASSWORD>';

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE kratos TO kratos;
GRANT ALL PRIVILEGES ON DATABASE hydra TO hydra;

-- PostgreSQL 15+ revoked default CREATE on public schema; restore it per-db.
\c kratos
GRANT ALL ON SCHEMA public TO kratos;
\c hydra
GRANT ALL ON SCHEMA public TO hydra;
