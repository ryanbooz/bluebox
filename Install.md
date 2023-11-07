## Requirements
Using the **bluebox** database dump file currently requires PostgreSQL 12+ with PostGIS installed and available. Many hosted solutions from AWS, Azure, or GCP (to name a few), should offer a database ready to use with these requirements.

The easiest way to do this locally is to use the official PostGIS Docker image.

With Docker installed and running, the following command will get an image up and running quickly for you to restore the database to.

> Adjust the port and password to your liking.

```bash
docker run -d --name bluebox -p 5432:5432 -e POSTGRES_PASSWORD=password postgis/postgis
```

Alternatively, you can use the **bluebox** Docker image which includes a few other extensions and `pg_stat_statements` ready to go.

```bash
docker run -d --name bluebox -p 5432:5432 -e POSTGRES_PASSWORD=password ryanbooz/bluebox
```

## Restoring the database dump file
Once you have a running container, you can use `psql` or your IDE of choice to create a new, empty database (I call it `bluebox`) and then restore the database to. For any `psql` command below, ensure you modify the host, port, or password as needed.

> If you do not yet have `psql` and `pg_restore` installed on your machine, you can follow the directions [from this article](https://www.red-gate.com/simple-talk/databases/postgresql/postgresql-basics-getting-started-with-psql/) to get the tools installed. If you have PostgreSQL 16 already installed on your computer, you likely already have the necessary tools.

`psql -h localhost -U postgres -c 'CREATE DATABASE bluebox;'`

Next, use `pg_restore` to restore the dump file into the newly created database.

`pg_restore -h localhost -U postgres -d bluebox bluebox_v0.2.dump`

Finally, update the statistics in the database, which are not carried over in a dump.

`psql -h localhost -U postgres -d bluebox -c 'ANALYZE;'`

You can now log into your **bluebox** PostgreSQL database and begin exploring.

