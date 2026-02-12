## Quick Start
The easiest way to run a fully functional version of Bluebox with any currently supported version of Postgres, is by using the [Bluebox Docker](https://github.com/ryanbooz/bluebox-docker) project! No "installation" necessary!

No... seriously... that's really the easiest way to do it. Why do all the stuff below if you don't have to. Clone the [Bluebox Docker repo](https://github.com/ryanbooz/bluebox-docker), type `start.sh` at the command line, and you're ready to roll!

Well, if you really want to do it manually, more power to you. 😃

## Requirements
Using the **bluebox** database dump file currently requires PostgreSQL 13+ with PostGIS installed and available. Many hosted solutions from AWS, Azure, or GCP (to name a few), should offer a database ready to use with these requirements.

The easiest way to do this locally is to use the official PostGIS Docker image.

With Docker installed and running, the following command will get an image up and running quickly for you to restore the database to.

> Adjust the port and password to your liking.

```bash
docker run -d --name bluebox -p 5432:5432 -e POSTGRES_PASSWORD=password postgis/postgis
```

Alternatively, you can use the **bluebox** Docker image which includes a few other extensions and `pg_stat_statements` ready to go. This image is the one used in the [Bluebox Docker project](https://github.com/ryanbooz/bluebox-docker), so it will also create the `bluebox` database automatically and fill it with some data, etc.

```bash
docker run -d --name bluebox -p 5432:5432 -e POSTGRES_PASSWORD=password ghcr.io/ryanbooz/bluebox-postgres:latest
```

## Restoring the database dump file
If you choose to run your own Postgres container with PostGIS, you can use `psql` or your IDE of choice to create a new, empty database (I call it `bluebox`) and then restore the database to. For any `psql` command below, ensure you modify the host, port, or password as needed.

> If you do not yet have `psql` and `pg_restore` installed on your machine, you can follow the directions [from this article](https://www.red-gate.com/simple-talk/databases/postgresql/postgresql-basics-getting-started-with-psql/) to get the tools installed. If you have PostgreSQL already installed on your computer, you likely already have the necessary tools.

**First, you will need to unzip the data file to restore data into the sample database. Once that file is unzipped, you can proceed.**

### Step 1: Create the database

`psql -h localhost -U postgres -c 'CREATE DATABASE bluebox;'`

### Step 2: Restore schema and data
Next, use `psql` to restore the schema and data files into the newly created database.

`psql -h localhost -U postgres -d bluebox -f bluebox_schema.sql -f bluebox_data.sql`

### Step 3: Update thh local statistics
Finally, update the statistics in the database, which are not carried over in a dump.

`psql -h localhost -U postgres -d bluebox -c 'ANALYZE;'`

### Step 4: Generate sample rental data
This scripts don't contain sample rental data because it increases the size of the repository
quickly and is easy to create your own with the included stored procedures.

The `bluebox.generate_rental_history()` procedure can create up to one year of rental data at a time. To
generate rental data for the last twelve months, try the following:

`psql -h localhost -U postgres -d bluebox -c "CALL bluebox.generate_rental_history(now()-'12 months'::interval, now());"`

### Step 5: Login and explore!
You can now log into your **bluebox** PostgreSQL database and begin exploring. Use an IDE like DBeaver
or the included `psql` command line tool for querying your data.

