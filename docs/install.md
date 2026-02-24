# Installation

## Quick Start

The easiest way to run a fully functional version of Bluebox with any currently supported version of PostgreSQL is by using the [Bluebox Docker](https://github.com/ryanbooz/bluebox-docker) project. Clone the repo, run `start.sh`, and you're ready to go.

If you'd rather set things up manually, read on.

## Requirements

- PostgreSQL 13+ with PostGIS installed and available
- Many hosted solutions from AWS, Azure, or GCP should offer a database ready to use with these requirements
- Locally, the easiest option is the official PostGIS Docker image

## Option 1: PostGIS Docker image

With Docker installed and running, the following command will get an image up and running quickly. Adjust the port and password to your liking.

```bash
docker run -d --name bluebox -p 5432:5432 -e POSTGRES_PASSWORD=password postgis/postgis
```

## Option 2: Bluebox Docker image

Alternatively, you can use the Bluebox Docker image which includes a few other extensions and `pg_stat_statements` ready to go. This image is the one used in the [Bluebox Docker project](https://github.com/ryanbooz/bluebox-docker), so it will also create the `bluebox` database automatically.

```bash
docker run -d --name bluebox -p 5432:5432 -e POSTGRES_PASSWORD=password ghcr.io/ryanbooz/bluebox-postgres:latest
```

## Restoring the database dump file

If you choose to run your own Postgres container with PostGIS, you can use `psql` or your IDE of choice to create a new, empty database and then restore the data. For any `psql` command below, modify the host, port, or password as needed.

> If you do not yet have `psql` and `pg_restore` installed on your machine, you can follow the directions [from this article](https://www.red-gate.com/simple-talk/databases/postgresql/postgresql-basics-getting-started-with-psql/) to get the tools installed. If you have PostgreSQL already installed on your computer, you likely already have the necessary tools.

**First, unzip the data file before proceeding.**

### Step 1: Create the database

```bash
psql -h localhost -U postgres -c 'CREATE DATABASE bluebox;'
```

### Step 2: Restore schema and data

```bash
psql -h localhost -U postgres -d bluebox -f bluebox_schema.sql -f bluebox_data.sql
```

### Step 3: Update the local statistics

Statistics are not carried over in a dump, so update them after restoring.

```bash
psql -h localhost -U postgres -d bluebox -c 'ANALYZE;'
```

### Step 4: Generate sample rental data

The dump files don't contain sample rental data because it increases the size of the repository quickly and is easy to generate with the included stored procedures.

The `bluebox.generate_rental_history()` procedure can create up to one year of rental data at a time. To generate rental data for the last twelve months:

```bash
psql -h localhost -U postgres -d bluebox -c "CALL bluebox.generate_rental_history(now()-'12 months'::interval, now());"
```

### Step 5: Login and explore

You can now log into your Bluebox PostgreSQL database and begin exploring. Use an IDE like DBeaver or the included `psql` command line tool for querying your data.
