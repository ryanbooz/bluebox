--
-- PostgreSQL database dump
--

-- Dumped from database version 16.0 (Debian 16.0-1.pgdg110+1)
-- Dumped by pg_dump version 16.4 (Ubuntu 16.4-1.pgdg20.04+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: convert; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA convert;


--
-- Name: SCHEMA convert; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA convert IS 'Contains functions created by convert extension. Helpful conversion functions for speed, distance, area, power, and travel time.';


--
-- Name: pg_cron; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION pg_cron; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_cron IS 'Job scheduler for PostgreSQL';


--
-- Name: dd; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA dd;


--
-- Name: SCHEMA dd; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA dd IS 'Schema for Data Dictionary objects.  See https://github.com/rustprooflabs/pgdd';


--
-- Name: osm_seattle; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA osm_seattle;


--
-- Name: SCHEMA osm_seattle; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA osm_seattle IS 'Schema populated by PgOSM Flex.  SELECT * FROM osm_seattle.pgosm_flex; for details.';


--
-- Name: osm_spokane; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA osm_spokane;


--
-- Name: SCHEMA osm_spokane; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA osm_spokane IS 'Schema populated by PgOSM Flex.  SELECT * FROM osm_spokane.pgosm_flex; for details.';


--
-- Name: osm_wa; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA osm_wa;


--
-- Name: SCHEMA osm_wa; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA osm_wa IS 'Schema populated by PgOSM Flex.  SELECT * FROM osm_wa.pgosm_flex; for details.';


--
-- Name: pgosm; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA pgosm;


--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

-- *not* creating schema, since initdb creates it


--
-- Name: routing; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA routing;


--
-- Name: tiger; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA tiger;


--
-- Name: tiger_data; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA tiger_data;


--
-- Name: topology; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA topology;


--
-- Name: SCHEMA topology; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA topology IS 'PostGIS Topology schema';


--
-- Name: fuzzystrmatch; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS fuzzystrmatch WITH SCHEMA public;


--
-- Name: EXTENSION fuzzystrmatch; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION fuzzystrmatch IS 'determine similarities and distance between strings';


--
-- Name: pg_stat_statements; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA public;


--
-- Name: EXTENSION pg_stat_statements; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_stat_statements IS 'track planning and execution statistics of all SQL statements executed';


--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry and geography spatial types and functions';


--
-- Name: postgis_raster; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis_raster WITH SCHEMA public;


--
-- Name: EXTENSION postgis_raster; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis_raster IS 'PostGIS raster types and functions';


--
-- Name: postgis_tiger_geocoder; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis_tiger_geocoder WITH SCHEMA tiger;


--
-- Name: EXTENSION postgis_tiger_geocoder; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis_tiger_geocoder IS 'PostGIS tiger geocoder and reverse geocoder';


--
-- Name: postgis_topology; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis_topology WITH SCHEMA topology;


--
-- Name: EXTENSION postgis_topology; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis_topology IS 'PostGIS topology spatial types and functions';


--
-- Name: append_data_finish(boolean); Type: PROCEDURE; Schema: osm_seattle; Owner: -
--

CREATE PROCEDURE osm_seattle.append_data_finish(IN skip_nested boolean DEFAULT false)
    LANGUAGE plpgsql
    AS $_$
 BEGIN

    REFRESH MATERIALIZED VIEW osm_seattle.vplace_polygon_subdivide;

    IF $1 = False THEN
        RAISE NOTICE 'Populating nested place table';
        CALL osm_seattle.populate_place_polygon_nested();
        RAISE NOTICE 'Calculating nesting of place polygons';
        CALL osm_seattle.build_nested_admin_polygons();

    END IF;


END $_$;


--
-- Name: PROCEDURE append_data_finish(IN skip_nested boolean); Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON PROCEDURE osm_seattle.append_data_finish(IN skip_nested boolean) IS 'Finalizes PgOSM Flex after osm2pgsql-replication.  Refreshes materialized view and (optionally) processes the place_polygon_nested data.';


--
-- Name: append_data_start(); Type: PROCEDURE; Schema: osm_seattle; Owner: -
--

CREATE PROCEDURE osm_seattle.append_data_start()
    LANGUAGE plpgsql
    AS $$

 BEGIN

    RAISE NOTICE 'Truncating table osm_seattle.place_polygon_nested;';
    TRUNCATE TABLE osm_seattle.place_polygon_nested;

END $$;


--
-- Name: PROCEDURE append_data_start(); Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON PROCEDURE osm_seattle.append_data_start() IS 'Prepares PgOSM Flex database for running osm2pgsql in append mode.  Removes records from place_polygon_nested if they existed.';


--
-- Name: build_nested_admin_polygons(bigint); Type: PROCEDURE; Schema: osm_seattle; Owner: -
--

CREATE PROCEDURE osm_seattle.build_nested_admin_polygons(IN batch_row_limit bigint DEFAULT 100)
    LANGUAGE plpgsql
    AS $_$
 DECLARE
     rows_to_update BIGINT;
 BEGIN

 SELECT  COUNT(*) INTO rows_to_update
     FROM osm_seattle.place_polygon_nested r
     WHERE nest_level IS NULL
 ;
 RAISE NOTICE 'Rows to update: %', rows_to_update;
 RAISE NOTICE 'Updating in batches of % rows', $1;

 FOR counter IN 1..rows_to_update by $1 LOOP

    DROP TABLE IF EXISTS places_for_nesting;
    CREATE TEMP TABLE places_for_nesting AS
    SELECT p.osm_id
        FROM osm_seattle.place_polygon_nested p
        WHERE p.name IS NOT NULL
            AND (admin_level IS NOT NULL
                OR osm_type IN ('boundary', 'admin_level', 'suburb',
                             'neighbourhood')
                )
    ;
    CREATE UNIQUE INDEX tmp_ix_places_for_nesting
        ON places_for_nesting (osm_id);


    DROP TABLE IF EXISTS place_batch;
    CREATE TEMP TABLE place_batch AS
    SELECT p.osm_id, t.nest_level, t.name_path, t.osm_id_path, t.admin_level_path
        FROM osm_seattle.place_polygon p
        INNER JOIN LATERAL (
            SELECT COUNT(i.osm_id) AS nest_level,
                    ARRAY_AGG(i.name ORDER BY COALESCE(i.admin_level::INT, 99::INT) ASC) AS name_path,
                    ARRAY_AGG(i.osm_id ORDER BY COALESCE(i.admin_level::INT, 99::INT) ASC) AS osm_id_path,
                    ARRAY_AGG(COALESCE(i.admin_level::INT, 99::INT) ORDER BY i.admin_level ASC) AS admin_level_path
                FROM osm_seattle.place_polygon i
                WHERE ST_Within(p.geom, i.geom)
                    AND EXISTS (
                            SELECT 1 FROM places_for_nesting include
                                WHERE i.osm_id = include.osm_id
                        )
                    AND i.name IS NOT NULL
               ) t ON True
        WHERE EXISTS (
                SELECT 1 FROM osm_seattle.place_polygon_nested miss
                    WHERE miss.nest_level IS NULL
                    AND p.osm_id = miss.osm_id
        )
        AND EXISTS (
                SELECT 1 FROM places_for_nesting include
                    WHERE p.osm_id = include.osm_id
            )
    LIMIT $1
    ;

    UPDATE osm_seattle.place_polygon_nested n 
        SET nest_level = t.nest_level,
            name_path = t.name_path,
            osm_id_path = t.osm_id_path,
            admin_level_path = t.admin_level_path
        FROM place_batch t
        WHERE n.osm_id = t.osm_id
        ;
    COMMIT;
    END LOOP;

    DROP TABLE IF EXISTS place_batch;
    DROP TABLE IF EXISTS places_for_nesting;

    -- With all nested paths calculated the innermost value can be determined.
    WITH calc_inner AS (
    SELECT a.osm_id
        FROM osm_seattle.place_polygon_nested a
        WHERE a.row_innermost -- Start with per row check...
            -- If an osm_id is found in any other path, cannot be innermost
            AND NOT EXISTS (
            SELECT 1
                FROM osm_seattle.place_polygon_nested i
                WHERE a.osm_id <> i.osm_id
                    AND a.osm_id = ANY(osm_id_path)
        )
    )
    UPDATE osm_seattle.place_polygon_nested n
        SET innermost = True
        FROM calc_inner i
        WHERE n.osm_id = i.osm_id
    ;
END $_$;


--
-- Name: PROCEDURE build_nested_admin_polygons(IN batch_row_limit bigint); Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON PROCEDURE osm_seattle.build_nested_admin_polygons(IN batch_row_limit bigint) IS 'Warning: Expensive procedure!  Use to populate the osm_seattle.place_polygon_nested table. This procedure is not ran as part of SQL script automatically due to excessive run time on large regions.';


--
-- Name: populate_place_polygon_nested(); Type: PROCEDURE; Schema: osm_seattle; Owner: -
--

CREATE PROCEDURE osm_seattle.populate_place_polygon_nested()
    LANGUAGE sql
    AS $$


    INSERT INTO osm_seattle.place_polygon_nested (osm_id, name, osm_type, admin_level, geom)
    SELECT p.osm_id, p.name, p.osm_type,
            COALESCE(p.admin_level::INT, 99) AS admin_level,
            geom
        FROM osm_seattle.place_polygon p
        WHERE (p.boundary = 'administrative'
                OR p.osm_type IN   ('neighborhood', 'city', 'suburb', 'town', 'admin_level', 'locality')
           )
            AND p.name IS NOT NULL
            AND NOT EXISTS (
                SELECT osm_id
                    FROM osm_seattle.place_polygon_nested n
                    WHERE n.osm_id = p.osm_id
                )
    ;

$$;


--
-- Name: append_data_finish(boolean); Type: PROCEDURE; Schema: osm_spokane; Owner: -
--

CREATE PROCEDURE osm_spokane.append_data_finish(IN skip_nested boolean DEFAULT false)
    LANGUAGE plpgsql
    AS $_$
 BEGIN

    REFRESH MATERIALIZED VIEW osm_spokane.vplace_polygon_subdivide;

    IF $1 = False THEN
        RAISE NOTICE 'Populating nested place table';
        CALL osm_spokane.populate_place_polygon_nested();
        RAISE NOTICE 'Calculating nesting of place polygons';
        CALL osm_spokane.build_nested_admin_polygons();

    END IF;


END $_$;


--
-- Name: PROCEDURE append_data_finish(IN skip_nested boolean); Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON PROCEDURE osm_spokane.append_data_finish(IN skip_nested boolean) IS 'Finalizes PgOSM Flex after osm2pgsql-replication.  Refreshes materialized view and (optionally) processes the place_polygon_nested data.';


--
-- Name: append_data_start(); Type: PROCEDURE; Schema: osm_spokane; Owner: -
--

CREATE PROCEDURE osm_spokane.append_data_start()
    LANGUAGE plpgsql
    AS $$

 BEGIN

    RAISE NOTICE 'Truncating table osm_spokane.place_polygon_nested;';
    TRUNCATE TABLE osm_spokane.place_polygon_nested;

END $$;


--
-- Name: PROCEDURE append_data_start(); Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON PROCEDURE osm_spokane.append_data_start() IS 'Prepares PgOSM Flex database for running osm2pgsql in append mode.  Removes records from place_polygon_nested if they existed.';


--
-- Name: build_nested_admin_polygons(bigint); Type: PROCEDURE; Schema: osm_spokane; Owner: -
--

CREATE PROCEDURE osm_spokane.build_nested_admin_polygons(IN batch_row_limit bigint DEFAULT 100)
    LANGUAGE plpgsql
    AS $_$
 DECLARE
     rows_to_update BIGINT;
 BEGIN

 SELECT  COUNT(*) INTO rows_to_update
     FROM osm_spokane.place_polygon_nested r
     WHERE nest_level IS NULL
 ;
 RAISE NOTICE 'Rows to update: %', rows_to_update;
 RAISE NOTICE 'Updating in batches of % rows', $1;

 FOR counter IN 1..rows_to_update by $1 LOOP

    DROP TABLE IF EXISTS places_for_nesting;
    CREATE TEMP TABLE places_for_nesting AS
    SELECT p.osm_id
        FROM osm_spokane.place_polygon_nested p
        WHERE p.name IS NOT NULL
            AND (admin_level IS NOT NULL
                OR osm_type IN ('boundary', 'admin_level', 'suburb',
                             'neighbourhood')
                )
    ;
    CREATE UNIQUE INDEX tmp_ix_places_for_nesting
        ON places_for_nesting (osm_id);


    DROP TABLE IF EXISTS place_batch;
    CREATE TEMP TABLE place_batch AS
    SELECT p.osm_id, t.nest_level, t.name_path, t.osm_id_path, t.admin_level_path
        FROM osm_spokane.place_polygon p
        INNER JOIN LATERAL (
            SELECT COUNT(i.osm_id) AS nest_level,
                    ARRAY_AGG(i.name ORDER BY COALESCE(i.admin_level::INT, 99::INT) ASC) AS name_path,
                    ARRAY_AGG(i.osm_id ORDER BY COALESCE(i.admin_level::INT, 99::INT) ASC) AS osm_id_path,
                    ARRAY_AGG(COALESCE(i.admin_level::INT, 99::INT) ORDER BY i.admin_level ASC) AS admin_level_path
                FROM osm_spokane.place_polygon i
                WHERE ST_Within(p.geom, i.geom)
                    AND EXISTS (
                            SELECT 1 FROM places_for_nesting include
                                WHERE i.osm_id = include.osm_id
                        )
                    AND i.name IS NOT NULL
               ) t ON True
        WHERE EXISTS (
                SELECT 1 FROM osm_spokane.place_polygon_nested miss
                    WHERE miss.nest_level IS NULL
                    AND p.osm_id = miss.osm_id
        )
        AND EXISTS (
                SELECT 1 FROM places_for_nesting include
                    WHERE p.osm_id = include.osm_id
            )
    LIMIT $1
    ;

    UPDATE osm_spokane.place_polygon_nested n 
        SET nest_level = t.nest_level,
            name_path = t.name_path,
            osm_id_path = t.osm_id_path,
            admin_level_path = t.admin_level_path
        FROM place_batch t
        WHERE n.osm_id = t.osm_id
        ;
    COMMIT;
    END LOOP;

    DROP TABLE IF EXISTS place_batch;
    DROP TABLE IF EXISTS places_for_nesting;

    -- With all nested paths calculated the innermost value can be determined.
    WITH calc_inner AS (
    SELECT a.osm_id
        FROM osm_spokane.place_polygon_nested a
        WHERE a.row_innermost -- Start with per row check...
            -- If an osm_id is found in any other path, cannot be innermost
            AND NOT EXISTS (
            SELECT 1
                FROM osm_spokane.place_polygon_nested i
                WHERE a.osm_id <> i.osm_id
                    AND a.osm_id = ANY(osm_id_path)
        )
    )
    UPDATE osm_spokane.place_polygon_nested n
        SET innermost = True
        FROM calc_inner i
        WHERE n.osm_id = i.osm_id
    ;
END $_$;


--
-- Name: PROCEDURE build_nested_admin_polygons(IN batch_row_limit bigint); Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON PROCEDURE osm_spokane.build_nested_admin_polygons(IN batch_row_limit bigint) IS 'Warning: Expensive procedure!  Use to populate the osm_spokane.place_polygon_nested table. This procedure is not ran as part of SQL script automatically due to excessive run time on large regions.';


--
-- Name: populate_place_polygon_nested(); Type: PROCEDURE; Schema: osm_spokane; Owner: -
--

CREATE PROCEDURE osm_spokane.populate_place_polygon_nested()
    LANGUAGE sql
    AS $$


    INSERT INTO osm_spokane.place_polygon_nested (osm_id, name, osm_type, admin_level, geom)
    SELECT p.osm_id, p.name, p.osm_type,
            COALESCE(p.admin_level::INT, 99) AS admin_level,
            geom
        FROM osm_spokane.place_polygon p
        WHERE (p.boundary = 'administrative'
                OR p.osm_type IN   ('neighborhood', 'city', 'suburb', 'town', 'admin_level', 'locality')
           )
            AND p.name IS NOT NULL
            AND NOT EXISTS (
                SELECT osm_id
                    FROM osm_spokane.place_polygon_nested n
                    WHERE n.osm_id = p.osm_id
                )
    ;

$$;


--
-- Name: append_data_finish(boolean); Type: PROCEDURE; Schema: osm_wa; Owner: -
--

CREATE PROCEDURE osm_wa.append_data_finish(IN skip_nested boolean DEFAULT false)
    LANGUAGE plpgsql
    AS $_$
 BEGIN

    REFRESH MATERIALIZED VIEW osm_wa.vplace_polygon_subdivide;

    IF $1 = False THEN
        RAISE NOTICE 'Populating nested place table';
        CALL osm_wa.populate_place_polygon_nested();
        RAISE NOTICE 'Calculating nesting of place polygons';
        CALL osm_wa.build_nested_admin_polygons();

    END IF;


END $_$;


--
-- Name: PROCEDURE append_data_finish(IN skip_nested boolean); Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON PROCEDURE osm_wa.append_data_finish(IN skip_nested boolean) IS 'Finalizes PgOSM Flex after osm2pgsql-replication.  Refreshes materialized view and (optionally) processes the place_polygon_nested data.';


--
-- Name: append_data_start(); Type: PROCEDURE; Schema: osm_wa; Owner: -
--

CREATE PROCEDURE osm_wa.append_data_start()
    LANGUAGE plpgsql
    AS $$

 BEGIN

    RAISE NOTICE 'Truncating table osm_wa.place_polygon_nested;';
    TRUNCATE TABLE osm_wa.place_polygon_nested;

END $$;


--
-- Name: PROCEDURE append_data_start(); Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON PROCEDURE osm_wa.append_data_start() IS 'Prepares PgOSM Flex database for running osm2pgsql in append mode.  Removes records from place_polygon_nested if they existed.';


--
-- Name: build_nested_admin_polygons(bigint); Type: PROCEDURE; Schema: osm_wa; Owner: -
--

CREATE PROCEDURE osm_wa.build_nested_admin_polygons(IN batch_row_limit bigint DEFAULT 100)
    LANGUAGE plpgsql
    AS $_$
 DECLARE
     rows_to_update BIGINT;
 BEGIN

 SELECT  COUNT(*) INTO rows_to_update
     FROM osm_wa.place_polygon_nested r
     WHERE nest_level IS NULL
 ;
 RAISE NOTICE 'Rows to update: %', rows_to_update;
 RAISE NOTICE 'Updating in batches of % rows', $1;

 FOR counter IN 1..rows_to_update by $1 LOOP

    DROP TABLE IF EXISTS places_for_nesting;
    CREATE TEMP TABLE places_for_nesting AS
    SELECT p.osm_id
        FROM osm_wa.place_polygon_nested p
        WHERE p.name IS NOT NULL
            AND (admin_level IS NOT NULL
                OR osm_type IN ('boundary', 'admin_level', 'suburb',
                             'neighbourhood')
                )
    ;
    CREATE UNIQUE INDEX tmp_ix_places_for_nesting
        ON places_for_nesting (osm_id);


    DROP TABLE IF EXISTS place_batch;
    CREATE TEMP TABLE place_batch AS
    SELECT p.osm_id, t.nest_level, t.name_path, t.osm_id_path, t.admin_level_path
        FROM osm_wa.place_polygon p
        INNER JOIN LATERAL (
            SELECT COUNT(i.osm_id) AS nest_level,
                    ARRAY_AGG(i.name ORDER BY COALESCE(i.admin_level::INT, 99::INT) ASC) AS name_path,
                    ARRAY_AGG(i.osm_id ORDER BY COALESCE(i.admin_level::INT, 99::INT) ASC) AS osm_id_path,
                    ARRAY_AGG(COALESCE(i.admin_level::INT, 99::INT) ORDER BY i.admin_level ASC) AS admin_level_path
                FROM osm_wa.place_polygon i
                WHERE ST_Within(p.geom, i.geom)
                    AND EXISTS (
                            SELECT 1 FROM places_for_nesting include
                                WHERE i.osm_id = include.osm_id
                        )
                    AND i.name IS NOT NULL
               ) t ON True
        WHERE EXISTS (
                SELECT 1 FROM osm_wa.place_polygon_nested miss
                    WHERE miss.nest_level IS NULL
                    AND p.osm_id = miss.osm_id
        )
        AND EXISTS (
                SELECT 1 FROM places_for_nesting include
                    WHERE p.osm_id = include.osm_id
            )
    LIMIT $1
    ;

    UPDATE osm_wa.place_polygon_nested n 
        SET nest_level = t.nest_level,
            name_path = t.name_path,
            osm_id_path = t.osm_id_path,
            admin_level_path = t.admin_level_path
        FROM place_batch t
        WHERE n.osm_id = t.osm_id
        ;
    COMMIT;
    END LOOP;

    DROP TABLE IF EXISTS place_batch;
    DROP TABLE IF EXISTS places_for_nesting;

    -- With all nested paths calculated the innermost value can be determined.
    WITH calc_inner AS (
    SELECT a.osm_id
        FROM osm_wa.place_polygon_nested a
        WHERE a.row_innermost -- Start with per row check...
            -- If an osm_id is found in any other path, cannot be innermost
            AND NOT EXISTS (
            SELECT 1
                FROM osm_wa.place_polygon_nested i
                WHERE a.osm_id <> i.osm_id
                    AND a.osm_id = ANY(osm_id_path)
        )
    )
    UPDATE osm_wa.place_polygon_nested n
        SET innermost = True
        FROM calc_inner i
        WHERE n.osm_id = i.osm_id
    ;
END $_$;


--
-- Name: PROCEDURE build_nested_admin_polygons(IN batch_row_limit bigint); Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON PROCEDURE osm_wa.build_nested_admin_polygons(IN batch_row_limit bigint) IS 'Warning: Expensive procedure!  Use to populate the osm_wa.place_polygon_nested table. This procedure is not ran as part of SQL script automatically due to excessive run time on large regions.';


--
-- Name: populate_place_polygon_nested(); Type: PROCEDURE; Schema: osm_wa; Owner: -
--

CREATE PROCEDURE osm_wa.populate_place_polygon_nested()
    LANGUAGE sql
    AS $$


    INSERT INTO osm_wa.place_polygon_nested (osm_id, name, osm_type, admin_level, geom)
    SELECT p.osm_id, p.name, p.osm_type,
            COALESCE(p.admin_level::INT, 99) AS admin_level,
            geom
        FROM osm_wa.place_polygon p
        WHERE (p.boundary = 'administrative'
                OR p.osm_type IN   ('neighborhood', 'city', 'suburb', 'town', 'admin_level', 'locality')
           )
            AND p.name IS NOT NULL
            AND NOT EXISTS (
                SELECT osm_id
                    FROM osm_wa.place_polygon_nested n
                    WHERE n.osm_id = p.osm_id
                )
    ;

$$;


--
-- Name: complete_recent_rentals(interval); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.complete_recent_rentals(IN min_interval interval DEFAULT '96:00:00'::interval)
    LANGUAGE plpgsql
    AS $$
 DECLARE 
	rid int;
    close_pct_lower int = 10;
    close_pct_upper int = 20;
    -- In seconds to get some additional randomness in the rental end time
    close_interval_lower int = 57600; -- 16 hours
    close_interval_upper int = 345600; -- 96 hours
 BEGIN
    
	CREATE TEMPORARY TABLE IF NOT exists tmp_open_rentals (
		rental_id int
	);

	INSERT INTO tmp_open_rentals 
	SELECT rental_id FROM rental WHERE upper(rental_period) IS NULL 
		AND lower(rental_period) > now()-min_interval;


	ANALYZE tmp_open_rentals;
	-- sample 0.01% of the rows from available customers for the given day 
	-- loop over them and
 	IF EXISTS (SELECT 1 FROM tmp_open_rentals) THEN 
        -- we close out somewhere between 10 and 20 percent of the rentals each time.
		FOR rid IN (SELECT rental_id FROM tmp_open_rentals TABLESAMPLE bernoulli(random_between(close_pct_lower,close_pct_upper,1)))
	 	LOOP
		 	-- update the rental end period to be between 16 hours and 4 days from initial rental.
		 	UPDATE rental SET rental_period = tstzrange(lower(rental_period), (lower(rental_period) + (random_between(close_interval_lower,close_interval_upper)::TEXT || ' seconds')::INTERVAL))
		 	WHERE rental_id = rid;
			 
			COMMIT;
		
            -- create the payment for the completed rental
			CALL insert_single_payment(rid);
			
	 	end LOOP;
	END IF;
 END;
$$;


--
-- Name: generate_new_rental(); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.generate_new_rental()
    LANGUAGE plpgsql
    AS $$
 DECLARE cus record;
	c_inv int;
	a_inv int[];
	rental_start timestamptz;
    rental_range tstzrange;
	cust_percent float4 = .01;
 BEGIN

	CREATE TEMPORARY TABLE tmp_av_customer(LIKE customer INCLUDING ALL);
	CREATE TEMPORARY TABLE tmp_av_inventory (LIKE inventory INCLUDING ALL);

	CREATE INDEX tmp_av_inventory_id ON tmp_av_inventory (inventory_id);

	rental_start = now();
	rental_range = tstzrange(now(),now()+'5 minutes'::INTERVAL); 
	
	IF EXISTS (SELECT 1 FROM public.holiday WHERE holiday_date::timestamptz <@ rental_range) THEN 
		SELECT pct INTO cust_percent FROM random_between(.015,.025,3) x(pct);
	END IF;
	
    -- Get a list of inventory that is currently on loan as of the rental_start day
    -- For new rentals this is a bit faulty as the "rental_start" is a single timestamp
    -- but the start time 
    WITH outstanding_rentals AS (
        SELECT rental_id, inventory_id FROM rental
        WHERE rental_period @> rental_range
    ),
    -- get a list of inventory that is available
    available_inventory AS (
        INSERT INTO tmp_av_inventory
        SELECT i.* FROM inventory i
            LEFT JOIN outstanding_rentals o using(inventory_id)
        WHERE o.inventory_id IS NULL
    )
    -- get a list of customers that do not currently have a video on loan
    -- as of this time
    INSERT INTO tmp_av_customer
    SELECT c.* FROM customer c
        LEFT JOIN outstanding_rentals o using(customer_id)
    WHERE o.customer_id IS NULL;
        
    ANALYZE tmp_av_inventory;
    -- sample 0.01% of the rows from available customers for the given day 
    -- loop over them and
    FOR cus IN (SELECT customer_id, store_id FROM tmp_av_customer TABLESAMPLE bernoulli(cust_percent))
    LOOP
        -- This is not efficient on larger tables. For a small table like this
        -- using 'random()' to order is faster and easier than a multi-step search
        SELECT inventory_id INTO c_inv FROM tmp_av_inventory 
            WHERE inventory_id NOT IN (SELECT UNNEST(a_inv))
            ORDER BY random()
            LIMIT 1;
        
        --RAISE NOTICE 'customer_id: %, inventory_id: %, a_inv: %',cus.customer_id, c_inv, a_inv;
        
        INSERT INTO rental (rental_period, inventory_id, customer_id, staff_id)
        SELECT tstzrange((rental_start + trunc(random() * 300) * '1 second'::INTERVAL),NULL) rental_period,
            ai.inventory_id,
            cus.customer_id,
            1 staff_id 
        FROM tmp_av_inventory ai
            LEFT JOIN staff s ON ai.store_id = s.store_id
        WHERE ai.inventory_id = c_inv;
            
        COMMIT;
    
        -- keep a list of inventory that is has been used from the 
        -- available inventory temp table so that we don't reuse it on this run.
        a_inv := array_append(a_inv, c_inv);
        
    end LOOP;
 END;
$$;


--
-- Name: generate_rental_history(timestamp with time zone, timestamp with time zone); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.generate_rental_history(IN data_start timestamp with time zone, IN data_end timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
 DECLARE cus record;
	c_inv int;
	a_inv int[];
	rental_start timestamptz;
    rental_nextday timestamptz;
	sqlstr TEXT;
	cust_percent int = 0.1;
 BEGIN
	 
	IF data_start > data_end THEN
		RAISE EXCEPTION 'End date must be after start date!';
	END IF;
	
	IF (data_end-data_start) > '365 days'::INTERVAL THEN
		RAISE EXCEPTION 'You can only do one year at time! %', (data_end-data_start);
	END IF;

    CREATE TEMPORARY TABLE tmp_av_customer(LIKE customer INCLUDING ALL);
	CREATE TEMPORARY TABLE tmp_av_inventory (LIKE inventory INCLUDING ALL);

	CREATE INDEX tmp_av_inventory_id ON tmp_av_inventory (inventory_id);

	rental_start = data_start;

	WHILE rental_start <= data_end THEN
	LOOP -- daily LOOP FOR rentals
		-- this is used during the INSERT and pulled out here for visibility
		rental_nextday = rental_start + '1 day'::INTERVAL;
		
		-- RAISE NOTICE 'rental_start: %', rental_start;
		-- RAISE NOTICE 'data_end: %', data_end;	
	
        -- If this date falls on a holiday, increase rentals by some percentage
		IF EXISTS (SELECT 1 FROM public.holiday WHERE holiday_date::timestamptz <@ tstzrange(rental_start,rental_nextday)) THEN 
			SELECT pct INTO cust_percent FROM random_between(.015,.025,3) x(pct);
		END IF;
	
		-- Get a list of inventory that is currently on loan as of the rental_start day
		WITH outstanding_rentals AS (
			SELECT * FROM rental
			WHERE rental_period @> rental_start
		),
		-- get a list of inventory that is available
		available_inventory AS (
			INSERT INTO tmp_av_inventory
			SELECT i.* FROM inventory i
				LEFT JOIN outstanding_rentals o using(inventory_id)
			WHERE o.inventory_id IS NULL
		)
		-- get a list of customers that do not currently have a video on loan
		-- as of today
		INSERT INTO tmp_av_customer
		SELECT c.* FROM customer c
		 	LEFT JOIN outstanding_rentals o using(customer_id)
		WHERE o.customer_id IS NULL;
		 
		ANALYZE tmp_av_inventory;
		-- sample rows from available customers for the given day 
		-- loop over them and
	 	FOR cus IN (SELECT customer_id, store_id FROM tmp_av_customer TABLESAMPLE bernoulli(cust_percent))
	 	LOOP
		 	-- This is not efficient on larger tables. For a small table like this
		 	-- using 'random()' to order is faster and easier than a multi-step search
		 	SELECT inventory_id INTO c_inv FROM tmp_av_inventory 
		 		WHERE inventory_id NOT IN (SELECT UNNEST(a_inv))
		 		ORDER BY random()
		 		LIMIT 1;
		 	
		 	--RAISE NOTICE 'customer_id: %, inventory_id: %, a_inv: %',cus.customer_id, c_inv, a_inv;
		 	
		 	INSERT INTO rental (rental_period, inventory_id, customer_id, staff_id)
		 	SELECT tstzrange((rental_start + trunc(random() * 1440) * '1 minute'::INTERVAL),(rental_nextday + trunc(random() * 4320) * '1 minute'::INTERVAL)) rental_period,
				ai.inventory_id,
				cus.customer_id,
--				timestamptz(rental_nextday + trunc(random() * 4320) * '1 minute'::INTERVAL) return_date,
				1 staff_id 
			FROM tmp_av_inventory ai
				LEFT JOIN staff s ON ai.store_id = s.store_id
			WHERE ai.inventory_id = c_inv;
			 
			COMMIT;
		
			a_inv := array_append(a_inv, c_inv);
			
	 	end LOOP;
	 
        -- Truncate the temp tables and start again with the next day
	    TRUNCATE tmp_av_customer;
		TRUNCATE tmp_av_inventory; 

        -- Create payments for all of these new rentals because they are in the past.
		CALL insert_payments(rental_start::date);
	
        -- Increment the date and move on until we've reached the
        -- end date for historical rentals.
		rental_start = rental_nextday;
		
		--RAISE NOTICE 'Next day: %', rental_start;
	
	end LOOP; -- WHILE LOOP

 END;
$$;


--
-- Name: insert_payments(date, real); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.insert_payments(IN rd date, IN rental_rate_daily real DEFAULT 1.99)
    LANGUAGE plpgsql
    AS $$	
 BEGIN 
	WITH payment_info AS (
		SELECT rental_id, rental_period, GREATEST(CEILING(EXTRACT(epoch from (upper(rental_period)-lower(rental_period)))/3600/24),1) rental_days,
			inventory_id, customer_id, staff_id, upper(rental_period) AS payment_date
		FROM rental r
			INNER JOIN inventory i USING(inventory_id)
			INNER JOIN film f USING(film_id)
		WHERE lower(rental_period) > rd AND lower(rental_period) <= rd+'1 day'::INTERVAL
	)
	INSERT INTO payment (customer_id, staff_id, rental_id, amount, payment_date)
	SELECT customer_id, staff_id, rental_id, rental_days*rental_rate_daily AS amount, payment_date
		FROM payment_info;
	
	END;
$$;


--
-- Name: insert_single_payment(integer, real); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.insert_single_payment(IN rid integer, IN rental_rate_daily real DEFAULT 1.99)
    LANGUAGE plpgsql
    AS $$	
 BEGIN 
	WITH payment_info AS (
		SELECT rental_id, rental_period, GREATEST(CEILING(EXTRACT(epoch from (upper(rental_period)-lower(rental_period)))/3600/24),1) rental_days,
			inventory_id, customer_id, staff_id, upper(rental_period) AS payment_date
		FROM rental r
			INNER JOIN inventory i USING(inventory_id)
			INNER JOIN film f USING(film_id)
		WHERE r.rental_id = rid
	)
	INSERT INTO payment (customer_id, staff_id, rental_id, amount, payment_date)
	SELECT customer_id, staff_id, rental_id, rental_days*rental_rate_daily AS amount, payment_date
		FROM payment_info;
	
	END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: amenity_line; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.amenity_line (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    name text,
    housenumber text,
    street text,
    city text,
    state text,
    postcode text,
    address text NOT NULL,
    wheelchair text,
    wheelchair_desc text,
    geom public.geometry(LineString,3857) NOT NULL
);


--
-- Name: TABLE amenity_line; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.amenity_line IS 'OpenStreetMap amenity lines - all lines with an amenity tag.  Some amenity tags are pulled into other tables (e.g. infrastructure, shop, and traffic layers) and duplicated again here. This is currently intentional but may change in the future. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/amenity.lua';


--
-- Name: COLUMN amenity_line.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_line.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN amenity_line.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_line.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN amenity_line.osm_subtype; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_line.osm_subtype IS 'Further describes osm_type for amenities.';


--
-- Name: COLUMN amenity_line.name; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_line.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN amenity_line.housenumber; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_line.housenumber IS 'Value from addr:housenumber tag';


--
-- Name: COLUMN amenity_line.street; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_line.street IS 'Value from addr:street tag';


--
-- Name: COLUMN amenity_line.city; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_line.city IS 'Value from addr:city tag';


--
-- Name: COLUMN amenity_line.state; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_line.state IS 'Value from addr:state tag';


--
-- Name: COLUMN amenity_line.postcode; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_line.postcode IS 'Value from addr:postcode tag';


--
-- Name: COLUMN amenity_line.address; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_line.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN amenity_line.wheelchair; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_line.wheelchair IS 'Indicates if feature is wheelchair accessible. Values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';


--
-- Name: COLUMN amenity_line.wheelchair_desc; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_line.wheelchair_desc IS 'Value from wheelchair:description Per https://wiki.openstreetmap.org/wiki/Key:wheelchair:description';


--
-- Name: COLUMN amenity_line.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_line.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: amenity_point; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.amenity_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    name text,
    housenumber text,
    street text,
    city text,
    state text,
    postcode text,
    address text NOT NULL,
    wheelchair text,
    wheelchair_desc text,
    geom public.geometry(Point,3857) NOT NULL
);


--
-- Name: TABLE amenity_point; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.amenity_point IS 'OpenStreetMap amenity points - all points with an amenity tag.  Some amenity tags are pulled into other tables (e.g. infrastructure, shop, and traffic layers) and duplicated again here. This is currently intentional but may change in the future. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/amenity.lua';


--
-- Name: COLUMN amenity_point.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN amenity_point.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_point.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN amenity_point.osm_subtype; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_point.osm_subtype IS 'Further describes osm_type for amenities.';


--
-- Name: COLUMN amenity_point.name; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN amenity_point.housenumber; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_point.housenumber IS 'Value from addr:housenumber tag';


--
-- Name: COLUMN amenity_point.street; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_point.street IS 'Value from addr:street tag';


--
-- Name: COLUMN amenity_point.city; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_point.city IS 'Value from addr:city tag';


--
-- Name: COLUMN amenity_point.state; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_point.state IS 'Value from addr:state tag';


--
-- Name: COLUMN amenity_point.postcode; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_point.postcode IS 'Value from addr:postcode tag';


--
-- Name: COLUMN amenity_point.address; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_point.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN amenity_point.wheelchair; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_point.wheelchair IS 'Indicates if feature is wheelchair accessible. Values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';


--
-- Name: COLUMN amenity_point.wheelchair_desc; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_point.wheelchair_desc IS 'Value from wheelchair:description Per https://wiki.openstreetmap.org/wiki/Key:wheelchair:description';


--
-- Name: COLUMN amenity_point.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: amenity_polygon; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.amenity_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    name text,
    housenumber text,
    street text,
    city text,
    state text,
    postcode text,
    address text NOT NULL,
    wheelchair text,
    wheelchair_desc text,
    geom public.geometry(MultiPolygon,3857) NOT NULL
);


--
-- Name: TABLE amenity_polygon; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.amenity_polygon IS 'OpenStreetMap amenity polygons - all polygons with an amenity tag.  Some amenity tags are pulled into other tables (e.g. infrastructure, shop, and traffic layers) and duplicated again here. This is currently intentional but may change in the future. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/amenity.lua';


--
-- Name: COLUMN amenity_polygon.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN amenity_polygon.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_polygon.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN amenity_polygon.osm_subtype; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_polygon.osm_subtype IS 'Further describes osm_type for amenities.';


--
-- Name: COLUMN amenity_polygon.name; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN amenity_polygon.housenumber; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_polygon.housenumber IS 'Value from addr:housenumber tag';


--
-- Name: COLUMN amenity_polygon.street; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_polygon.street IS 'Value from addr:street tag';


--
-- Name: COLUMN amenity_polygon.city; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_polygon.city IS 'Value from addr:city tag';


--
-- Name: COLUMN amenity_polygon.state; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_polygon.state IS 'Value from addr:state tag';


--
-- Name: COLUMN amenity_polygon.postcode; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_polygon.postcode IS 'Value from addr:postcode tag';


--
-- Name: COLUMN amenity_polygon.address; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_polygon.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN amenity_polygon.wheelchair; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_polygon.wheelchair IS 'Indicates if feature is wheelchair accessible. Values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';


--
-- Name: COLUMN amenity_polygon.wheelchair_desc; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_polygon.wheelchair_desc IS 'Value from wheelchair:description Per https://wiki.openstreetmap.org/wiki/Key:wheelchair:description';


--
-- Name: COLUMN amenity_polygon.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.amenity_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: building_point; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.building_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    name text,
    levels integer,
    height numeric,
    housenumber text,
    street text,
    city text,
    state text,
    postcode text,
    address text NOT NULL,
    wheelchair text,
    wheelchair_desc text,
    operator text,
    geom public.geometry(Point,3857) NOT NULL
);


--
-- Name: TABLE building_point; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.building_point IS 'OpenStreetMap building points - all points with a building tag.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/building.lua';


--
-- Name: COLUMN building_point.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.building_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN building_point.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.building_point.osm_type IS 'Values: building, building_part, office or address. All but address described in osm_subtype.  Value is address if addr:* tags exist with no other major keys to group it in a more specific layer.  See address_only_building() in building_helpers.lua';


--
-- Name: COLUMN building_point.osm_subtype; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.building_point.osm_subtype IS 'Further describes osm_type for building, building_part, and office.';


--
-- Name: COLUMN building_point.name; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.building_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN building_point.levels; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.building_point.levels IS 'Number (#) of levels in the building.';


--
-- Name: COLUMN building_point.height; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.building_point.height IS 'Building height.  Should be in meters (m) but is not enforced.  Please fix data in OpenStreetMap.org if incorrect values are discovered.';


--
-- Name: COLUMN building_point.housenumber; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.building_point.housenumber IS 'Value from addr:housenumber tag';


--
-- Name: COLUMN building_point.street; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.building_point.street IS 'Value from addr:street tag';


--
-- Name: COLUMN building_point.city; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.building_point.city IS 'Value from addr:city tag';


--
-- Name: COLUMN building_point.state; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.building_point.state IS 'Value from addr:state tag';


--
-- Name: COLUMN building_point.postcode; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.building_point.postcode IS 'Value from addr:postcode tag';


--
-- Name: COLUMN building_point.address; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.building_point.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN building_point.wheelchair; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.building_point.wheelchair IS 'Indicates if building is wheelchair accessible. Values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';


--
-- Name: COLUMN building_point.wheelchair_desc; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.building_point.wheelchair_desc IS 'Value from wheelchair:description Per https://wiki.openstreetmap.org/wiki/Key:wheelchair:description';


--
-- Name: COLUMN building_point.operator; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.building_point.operator IS 'Entity in charge of operations. https://wiki.openstreetmap.org/wiki/Key:operator';


--
-- Name: COLUMN building_point.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.building_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: building_polygon; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.building_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    name text,
    levels integer,
    height numeric,
    housenumber text,
    street text,
    city text,
    state text,
    postcode text,
    address text NOT NULL,
    wheelchair text,
    wheelchair_desc text,
    operator text,
    geom public.geometry(MultiPolygon,3857) NOT NULL
);


--
-- Name: TABLE building_polygon; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.building_polygon IS 'OpenStreetMap building polygons - all polygons with a building tag.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/building.lua';


--
-- Name: COLUMN building_polygon.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.building_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN building_polygon.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.building_polygon.osm_type IS 'Values: building, building_part, office or address. All but address described in osm_subtype.  Value is address if addr:* tags exist with no other major keys to group it in a more specific layer.  See address_only_building() in building_helpers.lua';


--
-- Name: COLUMN building_polygon.osm_subtype; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.building_polygon.osm_subtype IS 'Further describes osm_type for building, building_part, and office.';


--
-- Name: COLUMN building_polygon.name; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.building_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN building_polygon.levels; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.building_polygon.levels IS 'Number (#) of levels in the building.';


--
-- Name: COLUMN building_polygon.height; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.building_polygon.height IS 'Building height.  Should be in meters (m) but is not enforced.  Please fix data in OpenStreetMap.org if incorrect values are discovered.';


--
-- Name: COLUMN building_polygon.housenumber; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.building_polygon.housenumber IS 'Value from addr:housenumber tag';


--
-- Name: COLUMN building_polygon.street; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.building_polygon.street IS 'Value from addr:street tag';


--
-- Name: COLUMN building_polygon.city; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.building_polygon.city IS 'Value from addr:city tag';


--
-- Name: COLUMN building_polygon.state; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.building_polygon.state IS 'Value from addr:state tag';


--
-- Name: COLUMN building_polygon.postcode; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.building_polygon.postcode IS 'Value from addr:postcode tag';


--
-- Name: COLUMN building_polygon.address; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.building_polygon.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN building_polygon.wheelchair; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.building_polygon.wheelchair IS 'Indicates if building is wheelchair accessible. Values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';


--
-- Name: COLUMN building_polygon.wheelchair_desc; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.building_polygon.wheelchair_desc IS 'Value from wheelchair:description Per https://wiki.openstreetmap.org/wiki/Key:wheelchair:description';


--
-- Name: COLUMN building_polygon.operator; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.building_polygon.operator IS 'Entity in charge of operations. https://wiki.openstreetmap.org/wiki/Key:operator';


--
-- Name: COLUMN building_polygon.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.building_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: indoor_line; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.indoor_line (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    layer integer,
    level text,
    room text,
    entrance text,
    door text,
    capacity text,
    highway text,
    geom public.geometry(LineString,3857) NOT NULL
);


--
-- Name: TABLE indoor_line; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.indoor_line IS 'OpenStreetMap indoor related lines. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging - Generated by osm2pgsql Flex output using pgosm-flex/flex-config/indoor.lua';


--
-- Name: COLUMN indoor_line.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.indoor_line.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN indoor_line.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.indoor_line.osm_type IS 'Value from indoor tag. https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN indoor_line.name; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.indoor_line.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN indoor_line.layer; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.indoor_line.layer IS 'Indoor data should prefer using level over layer.  Layer is included as a fallback. Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN indoor_line.level; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.indoor_line.level IS 'Indoor Vertical ordering layer (Z) to handle crossing/overlapping features. https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_line.room; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.indoor_line.room IS 'Represents an indoor room or area. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_line.entrance; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.indoor_line.entrance IS 'Represents an exterior entrance. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_line.door; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.indoor_line.door IS 'Represents an indoor door. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_line.capacity; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.indoor_line.capacity IS 'Occupant capacity. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_line.highway; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.indoor_line.highway IS 'Indoor highways, e.g. stairs, escalators, hallways. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_line.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.indoor_line.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: indoor_point; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.indoor_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    layer integer,
    level text,
    room text,
    entrance text,
    door text,
    capacity text,
    highway text,
    geom public.geometry(Point,3857) NOT NULL
);


--
-- Name: TABLE indoor_point; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.indoor_point IS 'OpenStreetMap indoor related points. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging - Generated by osm2pgsql Flex output using pgosm-flex/flex-config/indoor.lua';


--
-- Name: COLUMN indoor_point.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.indoor_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN indoor_point.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.indoor_point.osm_type IS 'Value from indoor tag. https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN indoor_point.name; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.indoor_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN indoor_point.layer; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.indoor_point.layer IS 'Indoor data should prefer using level over layer.  Layer is included as a fallback. Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN indoor_point.level; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.indoor_point.level IS 'Indoor Vertical ordering layer (Z) to handle crossing/overlapping features. https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_point.room; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.indoor_point.room IS 'Represents an indoor room or area. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_point.entrance; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.indoor_point.entrance IS 'Represents an exterior entrance. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_point.door; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.indoor_point.door IS 'Represents an indoor door. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_point.capacity; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.indoor_point.capacity IS 'Occupant capacity. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_point.highway; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.indoor_point.highway IS 'Indoor highways, e.g. stairs, escalators, hallways. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_point.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.indoor_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: indoor_polygon; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.indoor_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    layer integer,
    level text,
    room text,
    entrance text,
    door text,
    capacity text,
    highway text,
    geom public.geometry(MultiPolygon,3857) NOT NULL
);


--
-- Name: TABLE indoor_polygon; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.indoor_polygon IS 'OpenStreetMap indoor related polygons. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging - Generated by osm2pgsql Flex output using pgosm-flex/flex-config/indoor.lua';


--
-- Name: COLUMN indoor_polygon.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.indoor_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN indoor_polygon.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.indoor_polygon.osm_type IS 'Value from indoor tag. https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN indoor_polygon.name; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.indoor_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN indoor_polygon.layer; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.indoor_polygon.layer IS 'Indoor data should prefer using level over layer.  Layer is included as a fallback. Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN indoor_polygon.level; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.indoor_polygon.level IS 'Indoor Vertical ordering layer (Z) to handle crossing/overlapping features. https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_polygon.room; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.indoor_polygon.room IS 'Represents an indoor room or area. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_polygon.entrance; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.indoor_polygon.entrance IS 'Represents an exterior entrance. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_polygon.door; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.indoor_polygon.door IS 'Represents an indoor door. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_polygon.capacity; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.indoor_polygon.capacity IS 'Occupant capacity. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_polygon.highway; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.indoor_polygon.highway IS 'Indoor highways, e.g. stairs, escalators, hallways. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_polygon.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.indoor_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: infrastructure_line; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.infrastructure_line (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    name text,
    ele integer,
    height numeric,
    operator text,
    material text,
    geom public.geometry(LineString,3857) NOT NULL
);


--
-- Name: COLUMN infrastructure_line.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.infrastructure_line.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer. Value from key stored in osm_subtype.';


--
-- Name: COLUMN infrastructure_line.osm_subtype; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.infrastructure_line.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: infrastructure_point; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.infrastructure_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    name text,
    ele integer,
    height numeric,
    operator text,
    material text,
    geom public.geometry(Point,3857) NOT NULL
);


--
-- Name: TABLE infrastructure_point; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.infrastructure_point IS 'OpenStreetMap infrastructure layer.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/infrasturcture.lua';


--
-- Name: COLUMN infrastructure_point.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.infrastructure_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN infrastructure_point.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.infrastructure_point.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer. Value from key stored in osm_subtype.';


--
-- Name: COLUMN infrastructure_point.osm_subtype; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.infrastructure_point.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: COLUMN infrastructure_point.name; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.infrastructure_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN infrastructure_point.ele; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.infrastructure_point.ele IS 'Elevation in meters';


--
-- Name: COLUMN infrastructure_point.height; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.infrastructure_point.height IS 'Object height.  Should be in meters (m) but is not enforced.  Please fix data in OpenStreetMap.org if incorrect values are discovered.';


--
-- Name: COLUMN infrastructure_point.operator; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.infrastructure_point.operator IS 'Entity in charge of operations. https://wiki.openstreetmap.org/wiki/Key:operator';


--
-- Name: COLUMN infrastructure_point.material; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.infrastructure_point.material IS 'Describes the main material of a physical feature.  https://wiki.openstreetmap.org/wiki/Key:material';


--
-- Name: COLUMN infrastructure_point.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.infrastructure_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: infrastructure_polygon; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.infrastructure_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    name text,
    ele integer,
    height numeric,
    operator text,
    material text,
    geom public.geometry(MultiPolygon,3857) NOT NULL
);


--
-- Name: COLUMN infrastructure_polygon.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.infrastructure_polygon.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer. Value from key stored in osm_subtype.';


--
-- Name: COLUMN infrastructure_polygon.osm_subtype; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.infrastructure_polygon.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: landuse_point; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.landuse_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    geom public.geometry(Point,3857) NOT NULL
);


--
-- Name: TABLE landuse_point; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.landuse_point IS 'OpenStreetMap landuse points - all points with a landuse tag.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/landuse.lua';


--
-- Name: COLUMN landuse_point.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.landuse_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN landuse_point.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.landuse_point.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN landuse_point.name; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.landuse_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN landuse_point.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.landuse_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: landuse_polygon; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.landuse_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    geom public.geometry(MultiPolygon,3857) NOT NULL
);


--
-- Name: TABLE landuse_polygon; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.landuse_polygon IS 'OpenStreetMap landuse polygons - all polygons with a landuse tag.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/landuse.lua';


--
-- Name: COLUMN landuse_polygon.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.landuse_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN landuse_polygon.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.landuse_polygon.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN landuse_polygon.name; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.landuse_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN landuse_polygon.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.landuse_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: leisure_point; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.leisure_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    geom public.geometry(Point,3857) NOT NULL
);


--
-- Name: TABLE leisure_point; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.leisure_point IS 'OpenStreetMap leisure points - all points with a leisure tag.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/leisure.lua';


--
-- Name: COLUMN leisure_point.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.leisure_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN leisure_point.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.leisure_point.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN leisure_point.name; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.leisure_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN leisure_point.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.leisure_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: leisure_polygon; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.leisure_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    geom public.geometry(MultiPolygon,3857) NOT NULL
);


--
-- Name: TABLE leisure_polygon; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.leisure_polygon IS 'OpenStreetMap leisure polygons - all polygons with a leisure tag.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/leisure.lua';


--
-- Name: COLUMN leisure_polygon.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.leisure_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN leisure_polygon.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.leisure_polygon.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN leisure_polygon.name; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.leisure_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN leisure_polygon.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.leisure_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: natural_line; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.natural_line (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    ele integer,
    geom public.geometry(LineString,3857) NOT NULL
);


--
-- Name: TABLE natural_line; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.natural_line IS 'OpenStreetMap natural lines, e.g. cliffs, tree row, etc.. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/natural.lua';


--
-- Name: COLUMN natural_line.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.natural_line.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN natural_line.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.natural_line.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN natural_line.name; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.natural_line.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN natural_line.ele; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.natural_line.ele IS 'Elevation in meters';


--
-- Name: COLUMN natural_line.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.natural_line.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: natural_point; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.natural_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    ele integer,
    geom public.geometry(Point,3857) NOT NULL
);


--
-- Name: TABLE natural_point; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.natural_point IS 'OpenStreetMap natural points, e.g. trees, peaks, etc..  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/natural.lua';


--
-- Name: COLUMN natural_point.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.natural_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN natural_point.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.natural_point.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN natural_point.name; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.natural_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN natural_point.ele; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.natural_point.ele IS 'Elevation in meters';


--
-- Name: COLUMN natural_point.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.natural_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: natural_polygon; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.natural_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    ele integer,
    geom public.geometry(MultiPolygon,3857) NOT NULL
);


--
-- Name: TABLE natural_polygon; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.natural_polygon IS 'OpenStreetMap natural polygons, e.g. woods, grass, etc.. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/natural.lua';


--
-- Name: COLUMN natural_polygon.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.natural_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN natural_polygon.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.natural_polygon.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN natural_polygon.name; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.natural_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN natural_polygon.ele; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.natural_polygon.ele IS 'Elevation in meters';


--
-- Name: COLUMN natural_polygon.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.natural_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: pgosm_flex; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.pgosm_flex (
    id bigint NOT NULL,
    imported timestamp with time zone DEFAULT now() NOT NULL,
    osm_date date NOT NULL,
    region text NOT NULL,
    layerset text,
    srid text NOT NULL,
    pgosm_flex_version text NOT NULL,
    osm2pgsql_version text NOT NULL,
    language text NOT NULL,
    import_mode jsonb,
    import_status text DEFAULT 'Initializing'::text NOT NULL,
    input_file text
);


--
-- Name: TABLE pgosm_flex; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.pgosm_flex IS 'Provides meta information on the PgOSM-Flex project including version and SRID used during the import. One row per import.';


--
-- Name: COLUMN pgosm_flex.imported; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.pgosm_flex.imported IS 'Indicates when the import was ran.';


--
-- Name: COLUMN pgosm_flex.osm_date; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.pgosm_flex.osm_date IS 'Indicates the date of the OpenStreetMap data loaded.  Recommended to set PGOSM_DATE env var at runtime, otherwise defaults to the date PgOSM-Flex was run.';


--
-- Name: COLUMN pgosm_flex.region; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.pgosm_flex.region IS 'Region specified at run time via --region and --subregion values.  When using --input-file without region/subregion, this defaults to the input filename.';


--
-- Name: COLUMN pgosm_flex.layerset; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.pgosm_flex.layerset IS 'PgOSM Flex layerset used for the import style.';


--
-- Name: COLUMN pgosm_flex.srid; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.pgosm_flex.srid IS 'SRID of imported data.';


--
-- Name: COLUMN pgosm_flex.pgosm_flex_version; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.pgosm_flex.pgosm_flex_version IS 'Version of PgOSM-Flex used to generate schema.';


--
-- Name: COLUMN pgosm_flex.osm2pgsql_version; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.pgosm_flex.osm2pgsql_version IS 'Version of osm2pgsql used to load data.';


--
-- Name: COLUMN pgosm_flex.language; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.pgosm_flex.language IS 'Preferred language specified at run time via env var PGOSM_LANGUAGE.  Empty string when not defined.';


--
-- Name: COLUMN pgosm_flex.import_status; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.pgosm_flex.import_status IS 'Status of the import. Starts as initialized, tracks status during imports and final success/failure.';


--
-- Name: COLUMN pgosm_flex.input_file; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.pgosm_flex.input_file IS 'Tracks explicit file defined when --input-file is used.  NULL when --input-file not used.';


--
-- Name: pgosm_flex_id_seq; Type: SEQUENCE; Schema: osm_seattle; Owner: -
--

ALTER TABLE osm_seattle.pgosm_flex ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME osm_seattle.pgosm_flex_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: place_line; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.place_line (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    boundary text,
    admin_level integer,
    name text,
    geom public.geometry(LineString,3857) NOT NULL
);


--
-- Name: TABLE place_line; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.place_line IS 'OpenStreetMap named places and administrative boundaries. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/place.lua';


--
-- Name: COLUMN place_line.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.place_line.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN place_line.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.place_line.osm_type IS 'Values from place if a place tag exists.  If no place tag, values boundary or admin_level indicate the source of the feature.';


--
-- Name: COLUMN place_line.boundary; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.place_line.boundary IS 'Value from boundary tag.  https://wiki.openstreetmap.org/wiki/Boundaries';


--
-- Name: COLUMN place_line.admin_level; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.place_line.admin_level IS 'Value from admin_level if it exists as integer value. Meaning of admin_level changes by region, see: https://wiki.openstreetmap.org/wiki/Key:admin_level';


--
-- Name: COLUMN place_line.name; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.place_line.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN place_line.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.place_line.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: place_point; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.place_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    boundary text,
    admin_level integer,
    name text,
    geom public.geometry(Point,3857) NOT NULL
);


--
-- Name: TABLE place_point; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.place_point IS 'OpenStreetMap named places and administrative boundaries. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/place.lua';


--
-- Name: COLUMN place_point.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.place_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN place_point.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.place_point.osm_type IS 'Values from place if a place tag exists.  If no place tag, values boundary or admin_level indicate the source of the feature.';


--
-- Name: COLUMN place_point.boundary; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.place_point.boundary IS 'Value from boundary tag.  https://wiki.openstreetmap.org/wiki/Boundaries';


--
-- Name: COLUMN place_point.admin_level; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.place_point.admin_level IS 'Value from admin_level if it exists as integer value. Meaning of admin_level changes by region, see: https://wiki.openstreetmap.org/wiki/Key:admin_level';


--
-- Name: COLUMN place_point.name; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.place_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN place_point.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.place_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: place_polygon; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.place_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    boundary text,
    admin_level integer,
    name text,
    member_ids jsonb,
    geom public.geometry(MultiPolygon,3857) NOT NULL
);


--
-- Name: TABLE place_polygon; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.place_polygon IS 'OpenStreetMap named places and administrative boundaries.  Contains relations and the polygon parts making up the relations. Members of relations are removed to avoid duplication. Generated by PgOSM Flex using pgosm-flex/flex-config/place.lua';


--
-- Name: COLUMN place_polygon.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.place_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN place_polygon.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.place_polygon.osm_type IS 'Values from place if a place tag exists.  If no place tag, values boundary or admin_level indicate the source of the feature.';


--
-- Name: COLUMN place_polygon.boundary; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.place_polygon.boundary IS 'Value from boundary tag.  https://wiki.openstreetmap.org/wiki/Boundaries';


--
-- Name: COLUMN place_polygon.admin_level; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.place_polygon.admin_level IS 'Value from admin_level if it exists as integer value. Meaning of admin_level changes by region, see: https://wiki.openstreetmap.org/wiki/Key:admin_level';


--
-- Name: COLUMN place_polygon.name; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.place_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN place_polygon.member_ids; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.place_polygon.member_ids IS 'Member IDs making up the full relation.  NULL if not a relation.  Used to create improved osm_seattle.vplace_polygon.';


--
-- Name: COLUMN place_polygon.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.place_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: place_polygon_nested; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.place_polygon_nested (
    osm_id bigint NOT NULL,
    name text NOT NULL,
    osm_type text NOT NULL,
    admin_level integer NOT NULL,
    nest_level bigint,
    name_path text[],
    osm_id_path bigint[],
    admin_level_path integer[],
    row_innermost boolean GENERATED ALWAYS AS (
CASE
    WHEN (osm_id_path[array_length(osm_id_path, 1)] = osm_id) THEN true
    ELSE false
END) STORED NOT NULL,
    innermost boolean DEFAULT false NOT NULL,
    geom public.geometry NOT NULL
);


--
-- Name: TABLE place_polygon_nested; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.place_polygon_nested IS 'Provides hierarchy of administrative polygons.  Built on top of osm_seattle.vplace_polygon. Artifact of PgOSM-Flex (place.sql).';


--
-- Name: COLUMN place_polygon_nested.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.place_polygon_nested.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN place_polygon_nested.name; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.place_polygon_nested.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN place_polygon_nested.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.place_polygon_nested.osm_type IS 'Values from place if a place tag exists.  If no place tag, values boundary or admin_level indicate the source of the feature.';


--
-- Name: COLUMN place_polygon_nested.admin_level; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.place_polygon_nested.admin_level IS 'Value from admin_level if it exists.  Defaults to 99 if not.';


--
-- Name: COLUMN place_polygon_nested.nest_level; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.place_polygon_nested.nest_level IS 'How many polygons is the current polygon nested within.  1 indicates polygon with no containing polygon.';


--
-- Name: COLUMN place_polygon_nested.name_path; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.place_polygon_nested.name_path IS 'Array of names of the current polygon (last) and all containing polygons.';


--
-- Name: COLUMN place_polygon_nested.osm_id_path; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.place_polygon_nested.osm_id_path IS 'Array of osm_id for the current polygon (last) and all containing polygons.';


--
-- Name: COLUMN place_polygon_nested.admin_level_path; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.place_polygon_nested.admin_level_path IS 'Array of admin_level values for the current polygon (last) and all containing polygons.';


--
-- Name: COLUMN place_polygon_nested.row_innermost; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.place_polygon_nested.row_innermost IS 'Indicates if the osm_id is the most inner ID of the current row.  Used to calculated innermost after all nesting paths have been calculated.';


--
-- Name: COLUMN place_polygon_nested.innermost; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.place_polygon_nested.innermost IS 'Indicates this row is the innermost admin level of the current data set and does **not** itself contain another admin polygon.  Calculated by procedure osm_seattle.build_nested_admin_polygons() defined in pgosm-flex/flex-config/place.sql.';


--
-- Name: COLUMN place_polygon_nested.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.place_polygon_nested.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: poi_line; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.poi_line (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text NOT NULL,
    name text,
    housenumber text,
    street text,
    city text,
    state text,
    postcode text,
    address text NOT NULL,
    operator text,
    geom public.geometry(LineString,3857) NOT NULL
);


--
-- Name: TABLE poi_line; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.poi_line IS 'OpenStreetMap Points of Interest (POI) (lines).  pois, amenities, tourism, some man_made objects, etc. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/poi.lua';


--
-- Name: COLUMN poi_line.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_line.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN poi_line.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_line.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer. Value from key stored in osm_subtype.';


--
-- Name: COLUMN poi_line.osm_subtype; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_line.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: COLUMN poi_line.name; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_line.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN poi_line.housenumber; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_line.housenumber IS 'Value from addr:housenumber tag';


--
-- Name: COLUMN poi_line.street; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_line.street IS 'Value from addr:street tag';


--
-- Name: COLUMN poi_line.city; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_line.city IS 'Value from addr:city tag';


--
-- Name: COLUMN poi_line.state; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_line.state IS 'Value from addr:state tag';


--
-- Name: COLUMN poi_line.postcode; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_line.postcode IS 'Value from addr:postcode tag';


--
-- Name: COLUMN poi_line.address; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_line.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN poi_line.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_line.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: poi_point; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.poi_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text NOT NULL,
    name text,
    housenumber text,
    street text,
    city text,
    state text,
    postcode text,
    address text NOT NULL,
    operator text,
    geom public.geometry(Point,3857) NOT NULL
);


--
-- Name: TABLE poi_point; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.poi_point IS 'OpenStreetMap Points of Interest (POI) (points).  pois, amenities, tourism, some man_made objects, etc. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/poi.lua';


--
-- Name: COLUMN poi_point.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN poi_point.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_point.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer. Value from key stored in osm_subtype.';


--
-- Name: COLUMN poi_point.osm_subtype; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_point.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: COLUMN poi_point.name; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN poi_point.housenumber; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_point.housenumber IS 'Value from addr:housenumber tag';


--
-- Name: COLUMN poi_point.street; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_point.street IS 'Value from addr:street tag';


--
-- Name: COLUMN poi_point.city; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_point.city IS 'Value from addr:city tag';


--
-- Name: COLUMN poi_point.state; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_point.state IS 'Value from addr:state tag';


--
-- Name: COLUMN poi_point.postcode; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_point.postcode IS 'Value from addr:postcode tag';


--
-- Name: COLUMN poi_point.address; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_point.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN poi_point.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: poi_polygon; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.poi_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text NOT NULL,
    name text,
    housenumber text,
    street text,
    city text,
    state text,
    postcode text,
    address text NOT NULL,
    operator text,
    member_ids jsonb,
    geom public.geometry(MultiPolygon,3857) NOT NULL
);


--
-- Name: TABLE poi_polygon; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.poi_polygon IS 'OpenStreetMap Points of Interest (POI) (polygons).  pois, amenities, tourism, some man_made objects, etc. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/poi.lua';


--
-- Name: COLUMN poi_polygon.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN poi_polygon.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_polygon.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer. Value from key stored in osm_subtype.';


--
-- Name: COLUMN poi_polygon.osm_subtype; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_polygon.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: COLUMN poi_polygon.name; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN poi_polygon.housenumber; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_polygon.housenumber IS 'Value from addr:housenumber tag';


--
-- Name: COLUMN poi_polygon.street; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_polygon.street IS 'Value from addr:street tag';


--
-- Name: COLUMN poi_polygon.city; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_polygon.city IS 'Value from addr:city tag';


--
-- Name: COLUMN poi_polygon.state; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_polygon.state IS 'Value from addr:state tag';


--
-- Name: COLUMN poi_polygon.postcode; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_polygon.postcode IS 'Value from addr:postcode tag';


--
-- Name: COLUMN poi_polygon.address; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_polygon.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN poi_polygon.member_ids; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_polygon.member_ids IS 'Member IDs making up the full relation.  NULL if not a relation.';


--
-- Name: COLUMN poi_polygon.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.poi_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: public_transport_line; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.public_transport_line (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    public_transport text NOT NULL,
    layer integer NOT NULL,
    name text,
    ref text,
    operator text,
    network text,
    surface text,
    bus text,
    shelter text,
    bench text,
    lit text,
    wheelchair text,
    wheelchair_desc text,
    member_ids jsonb,
    geom public.geometry(MultiLineString,3857) NOT NULL
);


--
-- Name: TABLE public_transport_line; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.public_transport_line IS 'OpenStreetMap public transport lines - all lines with a public_transport tag and others defined on https://wiki.openstreetmap.org/wiki/Public_transport.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/public_transport.lua';


--
-- Name: COLUMN public_transport_line.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_line.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN public_transport_line.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_line.osm_type IS 'Key indicating type of public transport feature if detail exists, falls back to public_transport tag. e.g. highway, bus, train, etc';


--
-- Name: COLUMN public_transport_line.osm_subtype; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_line.osm_subtype IS 'Value describing osm_type key, e.g. osm_type = "highway", osm_subtype = "bus_stop".';


--
-- Name: COLUMN public_transport_line.public_transport; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_line.public_transport IS 'Value from public_transport key, or "other" for additional 1st level keys defined in public_transport.lua';


--
-- Name: COLUMN public_transport_line.layer; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_line.layer IS 'Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN public_transport_line.name; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_line.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN public_transport_line.ref; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_line.ref IS 'Reference number or code. Best ref option determined by helpers.get_ref(). https://wiki.openstreetmap.org/wiki/Key:ref';


--
-- Name: COLUMN public_transport_line.operator; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_line.operator IS 'Entity in charge of operations. https://wiki.openstreetmap.org/wiki/Key:operator';


--
-- Name: COLUMN public_transport_line.network; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_line.network IS 'Route, system or operator. Usage of network key is widely varied. See https://wiki.openstreetmap.org/wiki/Key:network';


--
-- Name: COLUMN public_transport_line.wheelchair; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_line.wheelchair IS 'Indicates if feature is wheelchair accessible. Expected values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';


--
-- Name: COLUMN public_transport_line.wheelchair_desc; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_line.wheelchair_desc IS 'Value from wheelchair:description Per https://wiki.openstreetmap.org/wiki/Key:wheelchair:description';


--
-- Name: COLUMN public_transport_line.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_line.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: public_transport_point; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.public_transport_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    public_transport text NOT NULL,
    layer integer NOT NULL,
    name text,
    ref text,
    operator text,
    network text,
    surface text,
    bus text,
    shelter text,
    bench text,
    lit text,
    wheelchair text,
    wheelchair_desc text,
    geom public.geometry(Point,3857) NOT NULL
);


--
-- Name: TABLE public_transport_point; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.public_transport_point IS 'OpenStreetMap public transport points - all points with a public_transport tag and others defined on https://wiki.openstreetmap.org/wiki/Public_transport.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/public_transport.lua';


--
-- Name: COLUMN public_transport_point.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN public_transport_point.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_point.osm_type IS 'Key indicating type of public transport feature if detail exists, falls back to public_transport tag. e.g. highway, bus, train, etc';


--
-- Name: COLUMN public_transport_point.osm_subtype; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_point.osm_subtype IS 'Value describing osm_type key, e.g. osm_type = "highway", osm_subtype = "bus_stop".';


--
-- Name: COLUMN public_transport_point.public_transport; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_point.public_transport IS 'Value from public_transport key, or "other" for additional 1st level keys defined in public_transport.lua';


--
-- Name: COLUMN public_transport_point.layer; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_point.layer IS 'Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN public_transport_point.name; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN public_transport_point.ref; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_point.ref IS 'Reference number or code. Best ref option determined by helpers.get_ref(). https://wiki.openstreetmap.org/wiki/Key:ref';


--
-- Name: COLUMN public_transport_point.operator; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_point.operator IS 'Entity in charge of operations. https://wiki.openstreetmap.org/wiki/Key:operator';


--
-- Name: COLUMN public_transport_point.network; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_point.network IS 'Route, system or operator. Usage of network key is widely varied. See https://wiki.openstreetmap.org/wiki/Key:network';


--
-- Name: COLUMN public_transport_point.wheelchair; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_point.wheelchair IS 'Indicates if feature is wheelchair accessible. Expected values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';


--
-- Name: COLUMN public_transport_point.wheelchair_desc; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_point.wheelchair_desc IS 'Value from wheelchair:description Per https://wiki.openstreetmap.org/wiki/Key:wheelchair:description';


--
-- Name: COLUMN public_transport_point.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: public_transport_polygon; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.public_transport_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    public_transport text NOT NULL,
    layer integer NOT NULL,
    name text,
    ref text,
    operator text,
    network text,
    surface text,
    bus text,
    shelter text,
    bench text,
    lit text,
    wheelchair text,
    wheelchair_desc text,
    member_ids jsonb,
    geom public.geometry(MultiPolygon,3857) NOT NULL
);


--
-- Name: TABLE public_transport_polygon; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.public_transport_polygon IS 'OpenStreetMap public transport polygons - all polygons with a public_transport tag and others defined on https://wiki.openstreetmap.org/wiki/Public_transport.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/public_transport.lua';


--
-- Name: COLUMN public_transport_polygon.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN public_transport_polygon.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_polygon.osm_type IS 'Key indicating type of public transport feature if detail exists, falls back to public_transport tag. e.g. highway, bus, train, etc';


--
-- Name: COLUMN public_transport_polygon.osm_subtype; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_polygon.osm_subtype IS 'Value describing osm_type key, e.g. osm_type = "highway", osm_subtype = "bus_stop".';


--
-- Name: COLUMN public_transport_polygon.public_transport; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_polygon.public_transport IS 'Value from public_transport key, or "other" for additional 1st level keys defined in public_transport.lua';


--
-- Name: COLUMN public_transport_polygon.layer; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_polygon.layer IS 'Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN public_transport_polygon.name; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN public_transport_polygon.ref; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_polygon.ref IS 'Reference number or code. Best ref option determined by helpers.get_ref(). https://wiki.openstreetmap.org/wiki/Key:ref';


--
-- Name: COLUMN public_transport_polygon.operator; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_polygon.operator IS 'Entity in charge of operations. https://wiki.openstreetmap.org/wiki/Key:operator';


--
-- Name: COLUMN public_transport_polygon.network; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_polygon.network IS 'Route, system or operator. Usage of network key is widely varied. See https://wiki.openstreetmap.org/wiki/Key:network';


--
-- Name: COLUMN public_transport_polygon.wheelchair; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_polygon.wheelchair IS 'Indicates if feature is wheelchair accessible. Expected values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';


--
-- Name: COLUMN public_transport_polygon.wheelchair_desc; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_polygon.wheelchair_desc IS 'Value from wheelchair:description Per https://wiki.openstreetmap.org/wiki/Key:wheelchair:description';


--
-- Name: COLUMN public_transport_polygon.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.public_transport_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: road_line; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.road_line (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    ref text,
    maxspeed integer,
    oneway smallint,
    layer integer NOT NULL,
    tunnel text,
    bridge text,
    major boolean NOT NULL,
    route_foot boolean,
    route_cycle boolean,
    route_motor boolean,
    access text,
    member_ids jsonb,
    geom public.geometry(MultiLineString,3857) NOT NULL
);


--
-- Name: TABLE road_line; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.road_line IS 'OpenStreetMap roads, full layer.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/road.lua';


--
-- Name: COLUMN road_line.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.road_line.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN road_line.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.road_line.osm_type IS 'Value from "highway" key from OpenStreetMap data.  e.g. motorway, residential, service, footway, etc.';


--
-- Name: COLUMN road_line.name; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.road_line.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN road_line.ref; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.road_line.ref IS 'Reference number or code. Best ref option determined by helpers.get_ref(). https://wiki.openstreetmap.org/wiki/Key:ref';


--
-- Name: COLUMN road_line.maxspeed; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.road_line.maxspeed IS 'Maximum posted speed limit in kilometers per hour (km/hr).  Units not enforced by OpenStreetMap.  Please fix values in MPH in OpenStreetMap.org to either the value in km/hr OR with the suffix "mph" so it can be properly converted.  See https://wiki.openstreetmap.org/wiki/Key:maxspeed';


--
-- Name: COLUMN road_line.oneway; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.road_line.oneway IS 'Used for calculating costs for routing with one-way controls.  0 indicates 2-way traffic is allowed (or assumed).  1 indicates travel is allowed forward only, -1 indicates travel is allowed reverse only. Values reversible and alternating result in NULL.  See https://wiki.openstreetmap.org/wiki/Key:oneway';


--
-- Name: COLUMN road_line.layer; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.road_line.layer IS 'Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN road_line.tunnel; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.road_line.tunnel IS 'If empty, assume not a tunnel.  If not empty, check value for details.';


--
-- Name: COLUMN road_line.bridge; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.road_line.bridge IS 'If empty, assume not a bridge.  If not empty, check value for details.';


--
-- Name: COLUMN road_line.major; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.road_line.major IS 'Indicates feature is a "major" road, classification handled by helpers.major_road().';


--
-- Name: COLUMN road_line.route_foot; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.road_line.route_foot IS 'Best guess if the segment is route-able for foot traffic. If access is no or private, set to false. WARNING: This does not indicate that this method of travel is safe OR allowed!';


--
-- Name: COLUMN road_line.route_cycle; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.road_line.route_cycle IS 'Best guess if the segment is route-able for bicycle traffic. If access is no or private, set to false. WARNING: This does not indicate that this method of travel is safe OR allowed!';


--
-- Name: COLUMN road_line.route_motor; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.road_line.route_motor IS 'Best guess if the segment is route-able for motorized traffic. If access is no or private, set to false. WARNING: This does not indicate that this method of travel is safe OR allowed!';


--
-- Name: COLUMN road_line.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.road_line.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: road_point; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.road_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    ref text,
    maxspeed integer,
    oneway smallint,
    layer integer NOT NULL,
    tunnel text,
    bridge text,
    access text,
    geom public.geometry(Point,3857) NOT NULL
);


--
-- Name: TABLE road_point; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.road_point IS 'OpenStreetMap road points.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/road.lua';


--
-- Name: COLUMN road_point.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.road_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN road_point.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.road_point.osm_type IS 'Value from "highway" key from OpenStreetMap data.  e.g. motorway, residential, service, footway, etc.';


--
-- Name: COLUMN road_point.name; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.road_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN road_point.ref; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.road_point.ref IS 'Reference number or code. Best ref option determined by helpers.get_ref(). https://wiki.openstreetmap.org/wiki/Key:ref';


--
-- Name: COLUMN road_point.maxspeed; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.road_point.maxspeed IS 'Maximum posted speed limit in kilometers per hour (km/hr).  Units not enforced by OpenStreetMap.  Please fix values in MPH in OpenStreetMap.org to either the value in km/hr OR with the suffix "mph" so it can be properly converted.  See https://wiki.openstreetmap.org/wiki/Key:maxspeed';


--
-- Name: COLUMN road_point.oneway; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.road_point.oneway IS 'Used for calculating costs for routing with one-way controls.  0 indicates 2-way traffic is allowed (or assumed).  1 indicates travel is allowed forward only, -1 indicates travel is allowed reverse only. Values reversible and alternating result in NULL.  See https://wiki.openstreetmap.org/wiki/Key:oneway';


--
-- Name: COLUMN road_point.layer; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.road_point.layer IS 'Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN road_point.tunnel; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.road_point.tunnel IS 'If empty, assume not a tunnel.  If not empty, check value for details.';


--
-- Name: COLUMN road_point.bridge; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.road_point.bridge IS 'If empty, assume not a bridge.  If not empty, check value for details.';


--
-- Name: COLUMN road_point.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.road_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: road_polygon; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.road_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    ref text,
    maxspeed integer,
    layer integer NOT NULL,
    tunnel text,
    bridge text,
    major boolean NOT NULL,
    route_foot boolean,
    route_cycle boolean,
    route_motor boolean,
    access text,
    member_ids jsonb,
    geom public.geometry(MultiPolygon,3857) NOT NULL
);


--
-- Name: COLUMN road_polygon.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.road_polygon.osm_type IS 'Value from "highway" key from OpenStreetMap data.  e.g. motorway, residential, service, footway, etc.';


--
-- Name: COLUMN road_polygon.ref; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.road_polygon.ref IS 'Reference number or code. Best ref option determined by helpers.get_ref(). https://wiki.openstreetmap.org/wiki/Key:ref';


--
-- Name: shop_point; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.shop_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text NOT NULL,
    name text,
    housenumber text,
    street text,
    city text,
    state text,
    postcode text,
    address text NOT NULL,
    phone text,
    wheelchair text,
    wheelchair_desc text,
    operator text,
    brand text,
    website text,
    geom public.geometry(Point,3857) NOT NULL
);


--
-- Name: TABLE shop_point; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.shop_point IS 'OpenStreetMap shop related points.   Generated by osm2pgsql Flex output using pgosm-flex/flex-config/shop.lua';


--
-- Name: COLUMN shop_point.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN shop_point.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_point.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer. Value from key stored in osm_subtype.';


--
-- Name: COLUMN shop_point.osm_subtype; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_point.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: COLUMN shop_point.name; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN shop_point.housenumber; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_point.housenumber IS 'Value from addr:housenumber tag';


--
-- Name: COLUMN shop_point.street; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_point.street IS 'Value from addr:street tag';


--
-- Name: COLUMN shop_point.city; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_point.city IS 'Value from addr:city tag';


--
-- Name: COLUMN shop_point.state; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_point.state IS 'Value from addr:state tag';


--
-- Name: COLUMN shop_point.postcode; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_point.postcode IS 'Value from addr:postcode tag';


--
-- Name: COLUMN shop_point.address; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_point.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN shop_point.phone; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_point.phone IS 'Phone number associated with the feature. https://wiki.openstreetmap.org/wiki/Key:phone';


--
-- Name: COLUMN shop_point.wheelchair; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_point.wheelchair IS 'Indicates if feature is wheelchair accessible. Values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';


--
-- Name: COLUMN shop_point.wheelchair_desc; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_point.wheelchair_desc IS 'Value from wheelchair:description Per https://wiki.openstreetmap.org/wiki/Key:wheelchair:description';


--
-- Name: COLUMN shop_point.operator; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_point.operator IS 'Entity in charge of operations. https://wiki.openstreetmap.org/wiki/Key:operator';


--
-- Name: COLUMN shop_point.brand; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_point.brand IS 'Identity of product, service or business. https://wiki.openstreetmap.org/wiki/Key:brand';


--
-- Name: COLUMN shop_point.website; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_point.website IS 'Official website for the feature.  https://wiki.openstreetmap.org/wiki/Key:website';


--
-- Name: COLUMN shop_point.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: shop_polygon; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.shop_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text NOT NULL,
    name text,
    housenumber text,
    street text,
    city text,
    state text,
    postcode text,
    address text NOT NULL,
    phone text,
    wheelchair text,
    wheelchair_desc text,
    operator text,
    brand text,
    website text,
    geom public.geometry(MultiPolygon,3857) NOT NULL
);


--
-- Name: TABLE shop_polygon; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.shop_polygon IS 'OpenStreetMap shop related polygons. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/shop.lua';


--
-- Name: COLUMN shop_polygon.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN shop_polygon.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_polygon.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer. Value from key stored in osm_subtype.';


--
-- Name: COLUMN shop_polygon.osm_subtype; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_polygon.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: COLUMN shop_polygon.name; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN shop_polygon.housenumber; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_polygon.housenumber IS 'Value from addr:housenumber tag';


--
-- Name: COLUMN shop_polygon.street; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_polygon.street IS 'Value from addr:street tag';


--
-- Name: COLUMN shop_polygon.city; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_polygon.city IS 'Value from addr:city tag';


--
-- Name: COLUMN shop_polygon.state; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_polygon.state IS 'Value from addr:state tag';


--
-- Name: COLUMN shop_polygon.postcode; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_polygon.postcode IS 'Value from addr:postcode tag';


--
-- Name: COLUMN shop_polygon.address; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_polygon.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN shop_polygon.phone; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_polygon.phone IS 'Phone number associated with the feature. https://wiki.openstreetmap.org/wiki/Key:phone';


--
-- Name: COLUMN shop_polygon.wheelchair; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_polygon.wheelchair IS 'Indicates if feature is wheelchair accessible. Values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';


--
-- Name: COLUMN shop_polygon.wheelchair_desc; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_polygon.wheelchair_desc IS 'Value from wheelchair:description Per https://wiki.openstreetmap.org/wiki/Key:wheelchair:description';


--
-- Name: COLUMN shop_polygon.operator; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_polygon.operator IS 'Entity in charge of operations. https://wiki.openstreetmap.org/wiki/Key:operator';


--
-- Name: COLUMN shop_polygon.brand; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_polygon.brand IS 'Identity of product, service or business. https://wiki.openstreetmap.org/wiki/Key:brand';


--
-- Name: COLUMN shop_polygon.website; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_polygon.website IS 'Official website for the feature.  https://wiki.openstreetmap.org/wiki/Key:website';


--
-- Name: COLUMN shop_polygon.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.shop_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: tags; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.tags (
    geom_type character(1) NOT NULL,
    osm_id bigint NOT NULL,
    tags jsonb,
    osm_url text GENERATED ALWAYS AS (((('https://www.openstreetmap.org/'::text ||
CASE
    WHEN (geom_type = 'N'::bpchar) THEN 'node'::text
    WHEN (geom_type = 'W'::bpchar) THEN 'way'::text
    ELSE 'relation'::text
END) || '/'::text) || (osm_id)::text)) STORED NOT NULL
);


--
-- Name: TABLE tags; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.tags IS 'OpenStreetMap tag data for all objects in source file.  Key/value data stored in tags column in JSONB format.';


--
-- Name: COLUMN tags.geom_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.tags.geom_type IS 'Type of geometry. N(ode), W(ay) or R(elation).  Unique along with osm_id';


--
-- Name: COLUMN tags.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.tags.osm_id IS 'OpenStreetMap ID. Unique along with geometry type (geom_type).';


--
-- Name: COLUMN tags.tags; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.tags.tags IS 'Stores unaltered key/value pairs from OpenStreetMap.  A few tags are dropped by Lua script though most are preserved.';


--
-- Name: COLUMN tags.osm_url; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.tags.osm_url IS 'Calculated URL to object in OpenStreetMap.org.  Paths are split based on N(ode), W(ay) and R(elation).  See definition of generated column for full details.';


--
-- Name: traffic_line; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.traffic_line (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    geom public.geometry(LineString,3857) NOT NULL
);


--
-- Name: TABLE traffic_line; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.traffic_line IS 'OpenStreetMap traffic related lines.  Primarily "highway" tags but includes multiple.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/traffic.lua';


--
-- Name: COLUMN traffic_line.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.traffic_line.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN traffic_line.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.traffic_line.osm_type IS 'Value of the main key associated with traffic details.  If osm_subtype IS NULL then key = "highway" or key = "noexit".  Otherwise the main key is the value stored in osm_type while osm_subtype has the value for the main key.';


--
-- Name: COLUMN traffic_line.osm_subtype; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.traffic_line.osm_subtype IS 'Value of the non-main key(s) associated with traffic details. See osm_type column for the key associated with this value. NULL when the main key = "highway" or key = "noexit".';


--
-- Name: COLUMN traffic_line.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.traffic_line.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: traffic_point; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.traffic_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    geom public.geometry(Point,3857) NOT NULL
);


--
-- Name: TABLE traffic_point; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.traffic_point IS 'OpenStreetMap traffic related points.  Primarily "highway" tags but includes multiple.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/traffic.lua';


--
-- Name: COLUMN traffic_point.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.traffic_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN traffic_point.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.traffic_point.osm_type IS 'Value of the main key associated with traffic details.  If osm_subtype IS NULL then key = "highway" or key = "noexit".  Otherwise the main key is the value stored in osm_type while osm_subtype has the value for the main key.';


--
-- Name: COLUMN traffic_point.osm_subtype; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.traffic_point.osm_subtype IS 'Value of the non-main key(s) associated with traffic details. See osm_type column for the key associated with this value. NULL when the main key = "highway" or key = "noexit".';


--
-- Name: COLUMN traffic_point.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.traffic_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: traffic_polygon; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.traffic_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    geom public.geometry(MultiPolygon,3857) NOT NULL
);


--
-- Name: TABLE traffic_polygon; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.traffic_polygon IS 'OpenStreetMap traffic related polygons.  Primarily "highway" tags but includes multiple.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/traffic.lua';


--
-- Name: COLUMN traffic_polygon.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.traffic_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN traffic_polygon.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.traffic_polygon.osm_type IS 'Value of the main key associated with traffic details.  If osm_subtype IS NULL then key = "highway".  Otherwise the main key is the value stored in osm_type while osm_subtype has the value for the main key.';


--
-- Name: COLUMN traffic_polygon.osm_subtype; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.traffic_polygon.osm_subtype IS 'Value of the non-main key(s) associated with traffic details. See osm_type column for the key associated with this value. NULL when the main key = "highway".';


--
-- Name: COLUMN traffic_polygon.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.traffic_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: vplace_polygon_subdivide; Type: MATERIALIZED VIEW; Schema: osm_seattle; Owner: -
--

CREATE MATERIALIZED VIEW osm_seattle.vplace_polygon_subdivide AS
 SELECT osm_id,
    public.st_subdivide(geom) AS geom
   FROM osm_seattle.place_polygon
  WITH NO DATA;


--
-- Name: MATERIALIZED VIEW vplace_polygon_subdivide; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON MATERIALIZED VIEW osm_seattle.vplace_polygon_subdivide IS 'Subdivided geometry from osm_seattle.vplace_polygon.  Multiple rows per osm_id, one for each subdivided geometry.';


--
-- Name: COLUMN vplace_polygon_subdivide.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.vplace_polygon_subdivide.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.  Duplicated in this view!';


--
-- Name: COLUMN vplace_polygon_subdivide.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.vplace_polygon_subdivide.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: water_line; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.water_line (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text NOT NULL,
    name text,
    layer integer NOT NULL,
    tunnel text,
    bridge text,
    boat text,
    member_ids jsonb,
    geom public.geometry(MultiLineString,3857) NOT NULL
);


--
-- Name: TABLE water_line; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.water_line IS 'OpenStreetMap water / waterway related lines.  Includes combination of "natural" and "waterway" keys.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/water.lua';


--
-- Name: COLUMN water_line.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.water_line.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN water_line.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.water_line.osm_type IS 'Indicates the key (natural/waterway) providing the source for the detail';


--
-- Name: COLUMN water_line.osm_subtype; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.water_line.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: COLUMN water_line.name; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.water_line.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN water_line.layer; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.water_line.layer IS 'Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN water_line.tunnel; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.water_line.tunnel IS 'If empty, assume not a tunnel.  If not empty, check value for details.';


--
-- Name: COLUMN water_line.bridge; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.water_line.bridge IS 'If empty, assume not a bridge.  If not empty, check value for details.';


--
-- Name: COLUMN water_line.boat; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.water_line.boat IS 'Access details for boat travel.  https://wiki.openstreetmap.org/wiki/Key:boat';


--
-- Name: COLUMN water_line.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.water_line.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: water_point; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.water_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text NOT NULL,
    name text,
    layer integer NOT NULL,
    tunnel text,
    bridge text,
    boat text,
    geom public.geometry(Point,3857) NOT NULL
);


--
-- Name: TABLE water_point; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.water_point IS 'OpenStreetMap water / waterway related points.  Includes combination of "natural" and "waterway" keys.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/water.lua';


--
-- Name: COLUMN water_point.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.water_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN water_point.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.water_point.osm_type IS 'Indicates the key (natural/waterway) providing the source for the detail';


--
-- Name: COLUMN water_point.osm_subtype; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.water_point.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: COLUMN water_point.name; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.water_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN water_point.layer; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.water_point.layer IS 'Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN water_point.tunnel; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.water_point.tunnel IS 'If empty, assume not a tunnel.  If not empty, check value for details.';


--
-- Name: COLUMN water_point.bridge; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.water_point.bridge IS 'If empty, assume not a bridge.  If not empty, check value for details.';


--
-- Name: COLUMN water_point.boat; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.water_point.boat IS 'Access details for boat travel.  https://wiki.openstreetmap.org/wiki/Key:boat';


--
-- Name: COLUMN water_point.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.water_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: water_polygon; Type: TABLE; Schema: osm_seattle; Owner: -
--

CREATE TABLE osm_seattle.water_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text NOT NULL,
    name text,
    layer integer NOT NULL,
    tunnel text,
    bridge text,
    boat text,
    member_ids jsonb,
    geom public.geometry(MultiPolygon,3857) NOT NULL
);


--
-- Name: TABLE water_polygon; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON TABLE osm_seattle.water_polygon IS 'OpenStreetMap water / waterway related polygons.  Includes combination of "natural" and "waterway" keys.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/water.lua';


--
-- Name: COLUMN water_polygon.osm_id; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.water_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN water_polygon.osm_type; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.water_polygon.osm_type IS 'Indicates the key (natural/waterway) providing the source for the detail';


--
-- Name: COLUMN water_polygon.osm_subtype; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.water_polygon.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: COLUMN water_polygon.name; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.water_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN water_polygon.layer; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.water_polygon.layer IS 'Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN water_polygon.tunnel; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.water_polygon.tunnel IS 'If empty, assume not a tunnel.  If not empty, check value for details.';


--
-- Name: COLUMN water_polygon.bridge; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.water_polygon.bridge IS 'If empty, assume not a bridge.  If not empty, check value for details.';


--
-- Name: COLUMN water_polygon.boat; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.water_polygon.boat IS 'Access details for boat travel.  https://wiki.openstreetmap.org/wiki/Key:boat';


--
-- Name: COLUMN water_polygon.geom; Type: COMMENT; Schema: osm_seattle; Owner: -
--

COMMENT ON COLUMN osm_seattle.water_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: amenity_line; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.amenity_line (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    name text,
    housenumber text,
    street text,
    city text,
    state text,
    postcode text,
    address text NOT NULL,
    wheelchair text,
    wheelchair_desc text,
    geom public.geometry(LineString,3857) NOT NULL
);


--
-- Name: TABLE amenity_line; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.amenity_line IS 'OpenStreetMap amenity lines - all lines with an amenity tag.  Some amenity tags are pulled into other tables (e.g. infrastructure, shop, and traffic layers) and duplicated again here. This is currently intentional but may change in the future. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/amenity.lua';


--
-- Name: COLUMN amenity_line.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_line.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN amenity_line.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_line.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN amenity_line.osm_subtype; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_line.osm_subtype IS 'Further describes osm_type for amenities.';


--
-- Name: COLUMN amenity_line.name; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_line.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN amenity_line.housenumber; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_line.housenumber IS 'Value from addr:housenumber tag';


--
-- Name: COLUMN amenity_line.street; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_line.street IS 'Value from addr:street tag';


--
-- Name: COLUMN amenity_line.city; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_line.city IS 'Value from addr:city tag';


--
-- Name: COLUMN amenity_line.state; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_line.state IS 'Value from addr:state tag';


--
-- Name: COLUMN amenity_line.postcode; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_line.postcode IS 'Value from addr:postcode tag';


--
-- Name: COLUMN amenity_line.address; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_line.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN amenity_line.wheelchair; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_line.wheelchair IS 'Indicates if feature is wheelchair accessible. Values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';


--
-- Name: COLUMN amenity_line.wheelchair_desc; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_line.wheelchair_desc IS 'Value from wheelchair:description Per https://wiki.openstreetmap.org/wiki/Key:wheelchair:description';


--
-- Name: COLUMN amenity_line.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_line.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: amenity_point; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.amenity_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    name text,
    housenumber text,
    street text,
    city text,
    state text,
    postcode text,
    address text NOT NULL,
    wheelchair text,
    wheelchair_desc text,
    geom public.geometry(Point,3857) NOT NULL
);


--
-- Name: TABLE amenity_point; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.amenity_point IS 'OpenStreetMap amenity points - all points with an amenity tag.  Some amenity tags are pulled into other tables (e.g. infrastructure, shop, and traffic layers) and duplicated again here. This is currently intentional but may change in the future. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/amenity.lua';


--
-- Name: COLUMN amenity_point.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN amenity_point.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_point.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN amenity_point.osm_subtype; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_point.osm_subtype IS 'Further describes osm_type for amenities.';


--
-- Name: COLUMN amenity_point.name; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN amenity_point.housenumber; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_point.housenumber IS 'Value from addr:housenumber tag';


--
-- Name: COLUMN amenity_point.street; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_point.street IS 'Value from addr:street tag';


--
-- Name: COLUMN amenity_point.city; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_point.city IS 'Value from addr:city tag';


--
-- Name: COLUMN amenity_point.state; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_point.state IS 'Value from addr:state tag';


--
-- Name: COLUMN amenity_point.postcode; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_point.postcode IS 'Value from addr:postcode tag';


--
-- Name: COLUMN amenity_point.address; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_point.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN amenity_point.wheelchair; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_point.wheelchair IS 'Indicates if feature is wheelchair accessible. Values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';


--
-- Name: COLUMN amenity_point.wheelchair_desc; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_point.wheelchair_desc IS 'Value from wheelchair:description Per https://wiki.openstreetmap.org/wiki/Key:wheelchair:description';


--
-- Name: COLUMN amenity_point.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: amenity_polygon; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.amenity_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    name text,
    housenumber text,
    street text,
    city text,
    state text,
    postcode text,
    address text NOT NULL,
    wheelchair text,
    wheelchair_desc text,
    geom public.geometry(MultiPolygon,3857) NOT NULL
);


--
-- Name: TABLE amenity_polygon; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.amenity_polygon IS 'OpenStreetMap amenity polygons - all polygons with an amenity tag.  Some amenity tags are pulled into other tables (e.g. infrastructure, shop, and traffic layers) and duplicated again here. This is currently intentional but may change in the future. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/amenity.lua';


--
-- Name: COLUMN amenity_polygon.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN amenity_polygon.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_polygon.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN amenity_polygon.osm_subtype; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_polygon.osm_subtype IS 'Further describes osm_type for amenities.';


--
-- Name: COLUMN amenity_polygon.name; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN amenity_polygon.housenumber; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_polygon.housenumber IS 'Value from addr:housenumber tag';


--
-- Name: COLUMN amenity_polygon.street; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_polygon.street IS 'Value from addr:street tag';


--
-- Name: COLUMN amenity_polygon.city; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_polygon.city IS 'Value from addr:city tag';


--
-- Name: COLUMN amenity_polygon.state; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_polygon.state IS 'Value from addr:state tag';


--
-- Name: COLUMN amenity_polygon.postcode; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_polygon.postcode IS 'Value from addr:postcode tag';


--
-- Name: COLUMN amenity_polygon.address; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_polygon.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN amenity_polygon.wheelchair; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_polygon.wheelchair IS 'Indicates if feature is wheelchair accessible. Values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';


--
-- Name: COLUMN amenity_polygon.wheelchair_desc; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_polygon.wheelchair_desc IS 'Value from wheelchair:description Per https://wiki.openstreetmap.org/wiki/Key:wheelchair:description';


--
-- Name: COLUMN amenity_polygon.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.amenity_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: building_point; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.building_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    name text,
    levels integer,
    height numeric,
    housenumber text,
    street text,
    city text,
    state text,
    postcode text,
    address text NOT NULL,
    wheelchair text,
    wheelchair_desc text,
    operator text,
    geom public.geometry(Point,3857) NOT NULL
);


--
-- Name: TABLE building_point; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.building_point IS 'OpenStreetMap building points - all points with a building tag.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/building.lua';


--
-- Name: COLUMN building_point.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.building_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN building_point.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.building_point.osm_type IS 'Values: building, building_part, office or address. All but address described in osm_subtype.  Value is address if addr:* tags exist with no other major keys to group it in a more specific layer.  See address_only_building() in building_helpers.lua';


--
-- Name: COLUMN building_point.osm_subtype; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.building_point.osm_subtype IS 'Further describes osm_type for building, building_part, and office.';


--
-- Name: COLUMN building_point.name; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.building_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN building_point.levels; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.building_point.levels IS 'Number (#) of levels in the building.';


--
-- Name: COLUMN building_point.height; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.building_point.height IS 'Building height.  Should be in meters (m) but is not enforced.  Please fix data in OpenStreetMap.org if incorrect values are discovered.';


--
-- Name: COLUMN building_point.housenumber; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.building_point.housenumber IS 'Value from addr:housenumber tag';


--
-- Name: COLUMN building_point.street; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.building_point.street IS 'Value from addr:street tag';


--
-- Name: COLUMN building_point.city; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.building_point.city IS 'Value from addr:city tag';


--
-- Name: COLUMN building_point.state; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.building_point.state IS 'Value from addr:state tag';


--
-- Name: COLUMN building_point.postcode; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.building_point.postcode IS 'Value from addr:postcode tag';


--
-- Name: COLUMN building_point.address; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.building_point.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN building_point.wheelchair; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.building_point.wheelchair IS 'Indicates if building is wheelchair accessible. Values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';


--
-- Name: COLUMN building_point.wheelchair_desc; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.building_point.wheelchair_desc IS 'Value from wheelchair:description Per https://wiki.openstreetmap.org/wiki/Key:wheelchair:description';


--
-- Name: COLUMN building_point.operator; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.building_point.operator IS 'Entity in charge of operations. https://wiki.openstreetmap.org/wiki/Key:operator';


--
-- Name: COLUMN building_point.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.building_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: building_polygon; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.building_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    name text,
    levels integer,
    height numeric,
    housenumber text,
    street text,
    city text,
    state text,
    postcode text,
    address text NOT NULL,
    wheelchair text,
    wheelchair_desc text,
    operator text,
    geom public.geometry(MultiPolygon,3857) NOT NULL
);


--
-- Name: TABLE building_polygon; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.building_polygon IS 'OpenStreetMap building polygons - all polygons with a building tag.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/building.lua';


--
-- Name: COLUMN building_polygon.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.building_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN building_polygon.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.building_polygon.osm_type IS 'Values: building, building_part, office or address. All but address described in osm_subtype.  Value is address if addr:* tags exist with no other major keys to group it in a more specific layer.  See address_only_building() in building_helpers.lua';


--
-- Name: COLUMN building_polygon.osm_subtype; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.building_polygon.osm_subtype IS 'Further describes osm_type for building, building_part, and office.';


--
-- Name: COLUMN building_polygon.name; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.building_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN building_polygon.levels; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.building_polygon.levels IS 'Number (#) of levels in the building.';


--
-- Name: COLUMN building_polygon.height; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.building_polygon.height IS 'Building height.  Should be in meters (m) but is not enforced.  Please fix data in OpenStreetMap.org if incorrect values are discovered.';


--
-- Name: COLUMN building_polygon.housenumber; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.building_polygon.housenumber IS 'Value from addr:housenumber tag';


--
-- Name: COLUMN building_polygon.street; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.building_polygon.street IS 'Value from addr:street tag';


--
-- Name: COLUMN building_polygon.city; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.building_polygon.city IS 'Value from addr:city tag';


--
-- Name: COLUMN building_polygon.state; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.building_polygon.state IS 'Value from addr:state tag';


--
-- Name: COLUMN building_polygon.postcode; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.building_polygon.postcode IS 'Value from addr:postcode tag';


--
-- Name: COLUMN building_polygon.address; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.building_polygon.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN building_polygon.wheelchair; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.building_polygon.wheelchair IS 'Indicates if building is wheelchair accessible. Values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';


--
-- Name: COLUMN building_polygon.wheelchair_desc; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.building_polygon.wheelchair_desc IS 'Value from wheelchair:description Per https://wiki.openstreetmap.org/wiki/Key:wheelchair:description';


--
-- Name: COLUMN building_polygon.operator; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.building_polygon.operator IS 'Entity in charge of operations. https://wiki.openstreetmap.org/wiki/Key:operator';


--
-- Name: COLUMN building_polygon.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.building_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: indoor_line; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.indoor_line (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    layer integer,
    level text,
    room text,
    entrance text,
    door text,
    capacity text,
    highway text,
    geom public.geometry(LineString,3857) NOT NULL
);


--
-- Name: TABLE indoor_line; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.indoor_line IS 'OpenStreetMap indoor related lines. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging - Generated by osm2pgsql Flex output using pgosm-flex/flex-config/indoor.lua';


--
-- Name: COLUMN indoor_line.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.indoor_line.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN indoor_line.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.indoor_line.osm_type IS 'Value from indoor tag. https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN indoor_line.name; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.indoor_line.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN indoor_line.layer; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.indoor_line.layer IS 'Indoor data should prefer using level over layer.  Layer is included as a fallback. Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN indoor_line.level; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.indoor_line.level IS 'Indoor Vertical ordering layer (Z) to handle crossing/overlapping features. https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_line.room; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.indoor_line.room IS 'Represents an indoor room or area. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_line.entrance; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.indoor_line.entrance IS 'Represents an exterior entrance. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_line.door; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.indoor_line.door IS 'Represents an indoor door. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_line.capacity; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.indoor_line.capacity IS 'Occupant capacity. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_line.highway; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.indoor_line.highway IS 'Indoor highways, e.g. stairs, escalators, hallways. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_line.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.indoor_line.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: indoor_point; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.indoor_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    layer integer,
    level text,
    room text,
    entrance text,
    door text,
    capacity text,
    highway text,
    geom public.geometry(Point,3857) NOT NULL
);


--
-- Name: TABLE indoor_point; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.indoor_point IS 'OpenStreetMap indoor related points. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging - Generated by osm2pgsql Flex output using pgosm-flex/flex-config/indoor.lua';


--
-- Name: COLUMN indoor_point.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.indoor_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN indoor_point.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.indoor_point.osm_type IS 'Value from indoor tag. https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN indoor_point.name; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.indoor_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN indoor_point.layer; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.indoor_point.layer IS 'Indoor data should prefer using level over layer.  Layer is included as a fallback. Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN indoor_point.level; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.indoor_point.level IS 'Indoor Vertical ordering layer (Z) to handle crossing/overlapping features. https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_point.room; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.indoor_point.room IS 'Represents an indoor room or area. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_point.entrance; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.indoor_point.entrance IS 'Represents an exterior entrance. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_point.door; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.indoor_point.door IS 'Represents an indoor door. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_point.capacity; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.indoor_point.capacity IS 'Occupant capacity. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_point.highway; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.indoor_point.highway IS 'Indoor highways, e.g. stairs, escalators, hallways. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_point.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.indoor_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: indoor_polygon; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.indoor_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    layer integer,
    level text,
    room text,
    entrance text,
    door text,
    capacity text,
    highway text,
    geom public.geometry(MultiPolygon,3857) NOT NULL
);


--
-- Name: TABLE indoor_polygon; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.indoor_polygon IS 'OpenStreetMap indoor related polygons. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging - Generated by osm2pgsql Flex output using pgosm-flex/flex-config/indoor.lua';


--
-- Name: COLUMN indoor_polygon.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.indoor_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN indoor_polygon.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.indoor_polygon.osm_type IS 'Value from indoor tag. https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN indoor_polygon.name; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.indoor_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN indoor_polygon.layer; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.indoor_polygon.layer IS 'Indoor data should prefer using level over layer.  Layer is included as a fallback. Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN indoor_polygon.level; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.indoor_polygon.level IS 'Indoor Vertical ordering layer (Z) to handle crossing/overlapping features. https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_polygon.room; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.indoor_polygon.room IS 'Represents an indoor room or area. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_polygon.entrance; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.indoor_polygon.entrance IS 'Represents an exterior entrance. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_polygon.door; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.indoor_polygon.door IS 'Represents an indoor door. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_polygon.capacity; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.indoor_polygon.capacity IS 'Occupant capacity. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_polygon.highway; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.indoor_polygon.highway IS 'Indoor highways, e.g. stairs, escalators, hallways. See https://wiki.openstreetmap.org/wiki/Indoor_Mapping#Tagging';


--
-- Name: COLUMN indoor_polygon.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.indoor_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: infrastructure_line; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.infrastructure_line (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    name text,
    ele integer,
    height numeric,
    operator text,
    material text,
    geom public.geometry(LineString,3857) NOT NULL
);


--
-- Name: COLUMN infrastructure_line.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.infrastructure_line.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer. Value from key stored in osm_subtype.';


--
-- Name: COLUMN infrastructure_line.osm_subtype; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.infrastructure_line.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: infrastructure_point; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.infrastructure_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    name text,
    ele integer,
    height numeric,
    operator text,
    material text,
    geom public.geometry(Point,3857) NOT NULL
);


--
-- Name: TABLE infrastructure_point; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.infrastructure_point IS 'OpenStreetMap infrastructure layer.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/infrasturcture.lua';


--
-- Name: COLUMN infrastructure_point.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.infrastructure_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN infrastructure_point.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.infrastructure_point.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer. Value from key stored in osm_subtype.';


--
-- Name: COLUMN infrastructure_point.osm_subtype; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.infrastructure_point.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: COLUMN infrastructure_point.name; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.infrastructure_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN infrastructure_point.ele; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.infrastructure_point.ele IS 'Elevation in meters';


--
-- Name: COLUMN infrastructure_point.height; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.infrastructure_point.height IS 'Object height.  Should be in meters (m) but is not enforced.  Please fix data in OpenStreetMap.org if incorrect values are discovered.';


--
-- Name: COLUMN infrastructure_point.operator; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.infrastructure_point.operator IS 'Entity in charge of operations. https://wiki.openstreetmap.org/wiki/Key:operator';


--
-- Name: COLUMN infrastructure_point.material; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.infrastructure_point.material IS 'Describes the main material of a physical feature.  https://wiki.openstreetmap.org/wiki/Key:material';


--
-- Name: COLUMN infrastructure_point.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.infrastructure_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: infrastructure_polygon; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.infrastructure_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    name text,
    ele integer,
    height numeric,
    operator text,
    material text,
    geom public.geometry(MultiPolygon,3857) NOT NULL
);


--
-- Name: COLUMN infrastructure_polygon.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.infrastructure_polygon.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer. Value from key stored in osm_subtype.';


--
-- Name: COLUMN infrastructure_polygon.osm_subtype; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.infrastructure_polygon.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: landuse_point; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.landuse_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    geom public.geometry(Point,3857) NOT NULL
);


--
-- Name: TABLE landuse_point; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.landuse_point IS 'OpenStreetMap landuse points - all points with a landuse tag.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/landuse.lua';


--
-- Name: COLUMN landuse_point.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.landuse_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN landuse_point.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.landuse_point.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN landuse_point.name; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.landuse_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN landuse_point.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.landuse_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: landuse_polygon; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.landuse_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    geom public.geometry(MultiPolygon,3857) NOT NULL
);


--
-- Name: TABLE landuse_polygon; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.landuse_polygon IS 'OpenStreetMap landuse polygons - all polygons with a landuse tag.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/landuse.lua';


--
-- Name: COLUMN landuse_polygon.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.landuse_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN landuse_polygon.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.landuse_polygon.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN landuse_polygon.name; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.landuse_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN landuse_polygon.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.landuse_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: leisure_point; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.leisure_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    geom public.geometry(Point,3857) NOT NULL
);


--
-- Name: TABLE leisure_point; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.leisure_point IS 'OpenStreetMap leisure points - all points with a leisure tag.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/leisure.lua';


--
-- Name: COLUMN leisure_point.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.leisure_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN leisure_point.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.leisure_point.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN leisure_point.name; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.leisure_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN leisure_point.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.leisure_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: leisure_polygon; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.leisure_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    geom public.geometry(MultiPolygon,3857) NOT NULL
);


--
-- Name: TABLE leisure_polygon; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.leisure_polygon IS 'OpenStreetMap leisure polygons - all polygons with a leisure tag.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/leisure.lua';


--
-- Name: COLUMN leisure_polygon.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.leisure_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN leisure_polygon.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.leisure_polygon.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN leisure_polygon.name; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.leisure_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN leisure_polygon.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.leisure_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: natural_line; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.natural_line (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    ele integer,
    geom public.geometry(LineString,3857) NOT NULL
);


--
-- Name: TABLE natural_line; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.natural_line IS 'OpenStreetMap natural lines, e.g. cliffs, tree row, etc.. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/natural.lua';


--
-- Name: COLUMN natural_line.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.natural_line.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN natural_line.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.natural_line.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN natural_line.name; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.natural_line.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN natural_line.ele; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.natural_line.ele IS 'Elevation in meters';


--
-- Name: COLUMN natural_line.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.natural_line.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: natural_point; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.natural_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    ele integer,
    geom public.geometry(Point,3857) NOT NULL
);


--
-- Name: TABLE natural_point; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.natural_point IS 'OpenStreetMap natural points, e.g. trees, peaks, etc..  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/natural.lua';


--
-- Name: COLUMN natural_point.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.natural_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN natural_point.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.natural_point.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN natural_point.name; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.natural_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN natural_point.ele; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.natural_point.ele IS 'Elevation in meters';


--
-- Name: COLUMN natural_point.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.natural_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: natural_polygon; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.natural_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    ele integer,
    geom public.geometry(MultiPolygon,3857) NOT NULL
);


--
-- Name: TABLE natural_polygon; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.natural_polygon IS 'OpenStreetMap natural polygons, e.g. woods, grass, etc.. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/natural.lua';


--
-- Name: COLUMN natural_polygon.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.natural_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN natural_polygon.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.natural_polygon.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN natural_polygon.name; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.natural_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN natural_polygon.ele; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.natural_polygon.ele IS 'Elevation in meters';


--
-- Name: COLUMN natural_polygon.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.natural_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: pgosm_flex; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.pgosm_flex (
    id bigint NOT NULL,
    imported timestamp with time zone DEFAULT now() NOT NULL,
    osm_date date NOT NULL,
    region text NOT NULL,
    layerset text,
    srid text NOT NULL,
    pgosm_flex_version text NOT NULL,
    osm2pgsql_version text NOT NULL,
    language text NOT NULL,
    import_mode jsonb,
    import_status text DEFAULT 'Initializing'::text NOT NULL,
    input_file text
);


--
-- Name: TABLE pgosm_flex; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.pgosm_flex IS 'Provides meta information on the PgOSM-Flex project including version and SRID used during the import. One row per import.';


--
-- Name: COLUMN pgosm_flex.imported; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.pgosm_flex.imported IS 'Indicates when the import was ran.';


--
-- Name: COLUMN pgosm_flex.osm_date; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.pgosm_flex.osm_date IS 'Indicates the date of the OpenStreetMap data loaded.  Recommended to set PGOSM_DATE env var at runtime, otherwise defaults to the date PgOSM-Flex was run.';


--
-- Name: COLUMN pgosm_flex.region; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.pgosm_flex.region IS 'Region specified at run time via --region and --subregion values.  When using --input-file without region/subregion, this defaults to the input filename.';


--
-- Name: COLUMN pgosm_flex.layerset; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.pgosm_flex.layerset IS 'PgOSM Flex layerset used for the import style.';


--
-- Name: COLUMN pgosm_flex.srid; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.pgosm_flex.srid IS 'SRID of imported data.';


--
-- Name: COLUMN pgosm_flex.pgosm_flex_version; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.pgosm_flex.pgosm_flex_version IS 'Version of PgOSM-Flex used to generate schema.';


--
-- Name: COLUMN pgosm_flex.osm2pgsql_version; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.pgosm_flex.osm2pgsql_version IS 'Version of osm2pgsql used to load data.';


--
-- Name: COLUMN pgosm_flex.language; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.pgosm_flex.language IS 'Preferred language specified at run time via env var PGOSM_LANGUAGE.  Empty string when not defined.';


--
-- Name: COLUMN pgosm_flex.import_status; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.pgosm_flex.import_status IS 'Status of the import. Starts as initialized, tracks status during imports and final success/failure.';


--
-- Name: COLUMN pgosm_flex.input_file; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.pgosm_flex.input_file IS 'Tracks explicit file defined when --input-file is used.  NULL when --input-file not used.';


--
-- Name: pgosm_flex_id_seq; Type: SEQUENCE; Schema: osm_spokane; Owner: -
--

ALTER TABLE osm_spokane.pgosm_flex ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME osm_spokane.pgosm_flex_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: place_line; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.place_line (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    boundary text,
    admin_level integer,
    name text,
    geom public.geometry(LineString,3857) NOT NULL
);


--
-- Name: TABLE place_line; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.place_line IS 'OpenStreetMap named places and administrative boundaries. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/place.lua';


--
-- Name: COLUMN place_line.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.place_line.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN place_line.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.place_line.osm_type IS 'Values from place if a place tag exists.  If no place tag, values boundary or admin_level indicate the source of the feature.';


--
-- Name: COLUMN place_line.boundary; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.place_line.boundary IS 'Value from boundary tag.  https://wiki.openstreetmap.org/wiki/Boundaries';


--
-- Name: COLUMN place_line.admin_level; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.place_line.admin_level IS 'Value from admin_level if it exists as integer value. Meaning of admin_level changes by region, see: https://wiki.openstreetmap.org/wiki/Key:admin_level';


--
-- Name: COLUMN place_line.name; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.place_line.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN place_line.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.place_line.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: place_point; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.place_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    boundary text,
    admin_level integer,
    name text,
    geom public.geometry(Point,3857) NOT NULL
);


--
-- Name: TABLE place_point; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.place_point IS 'OpenStreetMap named places and administrative boundaries. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/place.lua';


--
-- Name: COLUMN place_point.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.place_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN place_point.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.place_point.osm_type IS 'Values from place if a place tag exists.  If no place tag, values boundary or admin_level indicate the source of the feature.';


--
-- Name: COLUMN place_point.boundary; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.place_point.boundary IS 'Value from boundary tag.  https://wiki.openstreetmap.org/wiki/Boundaries';


--
-- Name: COLUMN place_point.admin_level; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.place_point.admin_level IS 'Value from admin_level if it exists as integer value. Meaning of admin_level changes by region, see: https://wiki.openstreetmap.org/wiki/Key:admin_level';


--
-- Name: COLUMN place_point.name; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.place_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN place_point.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.place_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: place_polygon; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.place_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    boundary text,
    admin_level integer,
    name text,
    member_ids jsonb,
    geom public.geometry(MultiPolygon,3857) NOT NULL
);


--
-- Name: TABLE place_polygon; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.place_polygon IS 'OpenStreetMap named places and administrative boundaries.  Contains relations and the polygon parts making up the relations. Members of relations are removed to avoid duplication. Generated by PgOSM Flex using pgosm-flex/flex-config/place.lua';


--
-- Name: COLUMN place_polygon.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.place_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN place_polygon.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.place_polygon.osm_type IS 'Values from place if a place tag exists.  If no place tag, values boundary or admin_level indicate the source of the feature.';


--
-- Name: COLUMN place_polygon.boundary; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.place_polygon.boundary IS 'Value from boundary tag.  https://wiki.openstreetmap.org/wiki/Boundaries';


--
-- Name: COLUMN place_polygon.admin_level; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.place_polygon.admin_level IS 'Value from admin_level if it exists as integer value. Meaning of admin_level changes by region, see: https://wiki.openstreetmap.org/wiki/Key:admin_level';


--
-- Name: COLUMN place_polygon.name; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.place_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN place_polygon.member_ids; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.place_polygon.member_ids IS 'Member IDs making up the full relation.  NULL if not a relation.  Used to create improved osm_spokane.vplace_polygon.';


--
-- Name: COLUMN place_polygon.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.place_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: place_polygon_nested; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.place_polygon_nested (
    osm_id bigint NOT NULL,
    name text NOT NULL,
    osm_type text NOT NULL,
    admin_level integer NOT NULL,
    nest_level bigint,
    name_path text[],
    osm_id_path bigint[],
    admin_level_path integer[],
    row_innermost boolean GENERATED ALWAYS AS (
CASE
    WHEN (osm_id_path[array_length(osm_id_path, 1)] = osm_id) THEN true
    ELSE false
END) STORED NOT NULL,
    innermost boolean DEFAULT false NOT NULL,
    geom public.geometry NOT NULL
);


--
-- Name: TABLE place_polygon_nested; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.place_polygon_nested IS 'Provides hierarchy of administrative polygons.  Built on top of osm_spokane.vplace_polygon. Artifact of PgOSM-Flex (place.sql).';


--
-- Name: COLUMN place_polygon_nested.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.place_polygon_nested.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN place_polygon_nested.name; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.place_polygon_nested.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN place_polygon_nested.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.place_polygon_nested.osm_type IS 'Values from place if a place tag exists.  If no place tag, values boundary or admin_level indicate the source of the feature.';


--
-- Name: COLUMN place_polygon_nested.admin_level; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.place_polygon_nested.admin_level IS 'Value from admin_level if it exists.  Defaults to 99 if not.';


--
-- Name: COLUMN place_polygon_nested.nest_level; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.place_polygon_nested.nest_level IS 'How many polygons is the current polygon nested within.  1 indicates polygon with no containing polygon.';


--
-- Name: COLUMN place_polygon_nested.name_path; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.place_polygon_nested.name_path IS 'Array of names of the current polygon (last) and all containing polygons.';


--
-- Name: COLUMN place_polygon_nested.osm_id_path; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.place_polygon_nested.osm_id_path IS 'Array of osm_id for the current polygon (last) and all containing polygons.';


--
-- Name: COLUMN place_polygon_nested.admin_level_path; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.place_polygon_nested.admin_level_path IS 'Array of admin_level values for the current polygon (last) and all containing polygons.';


--
-- Name: COLUMN place_polygon_nested.row_innermost; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.place_polygon_nested.row_innermost IS 'Indicates if the osm_id is the most inner ID of the current row.  Used to calculated innermost after all nesting paths have been calculated.';


--
-- Name: COLUMN place_polygon_nested.innermost; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.place_polygon_nested.innermost IS 'Indicates this row is the innermost admin level of the current data set and does **not** itself contain another admin polygon.  Calculated by procedure osm_spokane.build_nested_admin_polygons() defined in pgosm-flex/flex-config/place.sql.';


--
-- Name: COLUMN place_polygon_nested.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.place_polygon_nested.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: poi_line; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.poi_line (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text NOT NULL,
    name text,
    housenumber text,
    street text,
    city text,
    state text,
    postcode text,
    address text NOT NULL,
    operator text,
    geom public.geometry(LineString,3857) NOT NULL
);


--
-- Name: TABLE poi_line; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.poi_line IS 'OpenStreetMap Points of Interest (POI) (lines).  pois, amenities, tourism, some man_made objects, etc. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/poi.lua';


--
-- Name: COLUMN poi_line.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_line.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN poi_line.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_line.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer. Value from key stored in osm_subtype.';


--
-- Name: COLUMN poi_line.osm_subtype; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_line.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: COLUMN poi_line.name; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_line.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN poi_line.housenumber; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_line.housenumber IS 'Value from addr:housenumber tag';


--
-- Name: COLUMN poi_line.street; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_line.street IS 'Value from addr:street tag';


--
-- Name: COLUMN poi_line.city; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_line.city IS 'Value from addr:city tag';


--
-- Name: COLUMN poi_line.state; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_line.state IS 'Value from addr:state tag';


--
-- Name: COLUMN poi_line.postcode; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_line.postcode IS 'Value from addr:postcode tag';


--
-- Name: COLUMN poi_line.address; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_line.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN poi_line.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_line.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: poi_point; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.poi_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text NOT NULL,
    name text,
    housenumber text,
    street text,
    city text,
    state text,
    postcode text,
    address text NOT NULL,
    operator text,
    geom public.geometry(Point,3857) NOT NULL
);


--
-- Name: TABLE poi_point; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.poi_point IS 'OpenStreetMap Points of Interest (POI) (points).  pois, amenities, tourism, some man_made objects, etc. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/poi.lua';


--
-- Name: COLUMN poi_point.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN poi_point.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_point.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer. Value from key stored in osm_subtype.';


--
-- Name: COLUMN poi_point.osm_subtype; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_point.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: COLUMN poi_point.name; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN poi_point.housenumber; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_point.housenumber IS 'Value from addr:housenumber tag';


--
-- Name: COLUMN poi_point.street; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_point.street IS 'Value from addr:street tag';


--
-- Name: COLUMN poi_point.city; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_point.city IS 'Value from addr:city tag';


--
-- Name: COLUMN poi_point.state; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_point.state IS 'Value from addr:state tag';


--
-- Name: COLUMN poi_point.postcode; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_point.postcode IS 'Value from addr:postcode tag';


--
-- Name: COLUMN poi_point.address; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_point.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN poi_point.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: poi_polygon; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.poi_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text NOT NULL,
    name text,
    housenumber text,
    street text,
    city text,
    state text,
    postcode text,
    address text NOT NULL,
    operator text,
    member_ids jsonb,
    geom public.geometry(MultiPolygon,3857) NOT NULL
);


--
-- Name: TABLE poi_polygon; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.poi_polygon IS 'OpenStreetMap Points of Interest (POI) (polygons).  pois, amenities, tourism, some man_made objects, etc. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/poi.lua';


--
-- Name: COLUMN poi_polygon.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN poi_polygon.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_polygon.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer. Value from key stored in osm_subtype.';


--
-- Name: COLUMN poi_polygon.osm_subtype; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_polygon.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: COLUMN poi_polygon.name; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN poi_polygon.housenumber; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_polygon.housenumber IS 'Value from addr:housenumber tag';


--
-- Name: COLUMN poi_polygon.street; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_polygon.street IS 'Value from addr:street tag';


--
-- Name: COLUMN poi_polygon.city; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_polygon.city IS 'Value from addr:city tag';


--
-- Name: COLUMN poi_polygon.state; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_polygon.state IS 'Value from addr:state tag';


--
-- Name: COLUMN poi_polygon.postcode; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_polygon.postcode IS 'Value from addr:postcode tag';


--
-- Name: COLUMN poi_polygon.address; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_polygon.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN poi_polygon.member_ids; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_polygon.member_ids IS 'Member IDs making up the full relation.  NULL if not a relation.';


--
-- Name: COLUMN poi_polygon.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.poi_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: public_transport_line; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.public_transport_line (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    public_transport text NOT NULL,
    layer integer NOT NULL,
    name text,
    ref text,
    operator text,
    network text,
    surface text,
    bus text,
    shelter text,
    bench text,
    lit text,
    wheelchair text,
    wheelchair_desc text,
    member_ids jsonb,
    geom public.geometry(MultiLineString,3857) NOT NULL
);


--
-- Name: TABLE public_transport_line; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.public_transport_line IS 'OpenStreetMap public transport lines - all lines with a public_transport tag and others defined on https://wiki.openstreetmap.org/wiki/Public_transport.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/public_transport.lua';


--
-- Name: COLUMN public_transport_line.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_line.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN public_transport_line.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_line.osm_type IS 'Key indicating type of public transport feature if detail exists, falls back to public_transport tag. e.g. highway, bus, train, etc';


--
-- Name: COLUMN public_transport_line.osm_subtype; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_line.osm_subtype IS 'Value describing osm_type key, e.g. osm_type = "highway", osm_subtype = "bus_stop".';


--
-- Name: COLUMN public_transport_line.public_transport; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_line.public_transport IS 'Value from public_transport key, or "other" for additional 1st level keys defined in public_transport.lua';


--
-- Name: COLUMN public_transport_line.layer; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_line.layer IS 'Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN public_transport_line.name; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_line.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN public_transport_line.ref; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_line.ref IS 'Reference number or code. Best ref option determined by helpers.get_ref(). https://wiki.openstreetmap.org/wiki/Key:ref';


--
-- Name: COLUMN public_transport_line.operator; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_line.operator IS 'Entity in charge of operations. https://wiki.openstreetmap.org/wiki/Key:operator';


--
-- Name: COLUMN public_transport_line.network; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_line.network IS 'Route, system or operator. Usage of network key is widely varied. See https://wiki.openstreetmap.org/wiki/Key:network';


--
-- Name: COLUMN public_transport_line.wheelchair; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_line.wheelchair IS 'Indicates if feature is wheelchair accessible. Expected values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';


--
-- Name: COLUMN public_transport_line.wheelchair_desc; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_line.wheelchair_desc IS 'Value from wheelchair:description Per https://wiki.openstreetmap.org/wiki/Key:wheelchair:description';


--
-- Name: COLUMN public_transport_line.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_line.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: public_transport_point; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.public_transport_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    public_transport text NOT NULL,
    layer integer NOT NULL,
    name text,
    ref text,
    operator text,
    network text,
    surface text,
    bus text,
    shelter text,
    bench text,
    lit text,
    wheelchair text,
    wheelchair_desc text,
    geom public.geometry(Point,3857) NOT NULL
);


--
-- Name: TABLE public_transport_point; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.public_transport_point IS 'OpenStreetMap public transport points - all points with a public_transport tag and others defined on https://wiki.openstreetmap.org/wiki/Public_transport.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/public_transport.lua';


--
-- Name: COLUMN public_transport_point.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN public_transport_point.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_point.osm_type IS 'Key indicating type of public transport feature if detail exists, falls back to public_transport tag. e.g. highway, bus, train, etc';


--
-- Name: COLUMN public_transport_point.osm_subtype; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_point.osm_subtype IS 'Value describing osm_type key, e.g. osm_type = "highway", osm_subtype = "bus_stop".';


--
-- Name: COLUMN public_transport_point.public_transport; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_point.public_transport IS 'Value from public_transport key, or "other" for additional 1st level keys defined in public_transport.lua';


--
-- Name: COLUMN public_transport_point.layer; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_point.layer IS 'Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN public_transport_point.name; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN public_transport_point.ref; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_point.ref IS 'Reference number or code. Best ref option determined by helpers.get_ref(). https://wiki.openstreetmap.org/wiki/Key:ref';


--
-- Name: COLUMN public_transport_point.operator; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_point.operator IS 'Entity in charge of operations. https://wiki.openstreetmap.org/wiki/Key:operator';


--
-- Name: COLUMN public_transport_point.network; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_point.network IS 'Route, system or operator. Usage of network key is widely varied. See https://wiki.openstreetmap.org/wiki/Key:network';


--
-- Name: COLUMN public_transport_point.wheelchair; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_point.wheelchair IS 'Indicates if feature is wheelchair accessible. Expected values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';


--
-- Name: COLUMN public_transport_point.wheelchair_desc; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_point.wheelchair_desc IS 'Value from wheelchair:description Per https://wiki.openstreetmap.org/wiki/Key:wheelchair:description';


--
-- Name: COLUMN public_transport_point.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: public_transport_polygon; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.public_transport_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    public_transport text NOT NULL,
    layer integer NOT NULL,
    name text,
    ref text,
    operator text,
    network text,
    surface text,
    bus text,
    shelter text,
    bench text,
    lit text,
    wheelchair text,
    wheelchair_desc text,
    member_ids jsonb,
    geom public.geometry(MultiPolygon,3857) NOT NULL
);


--
-- Name: TABLE public_transport_polygon; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.public_transport_polygon IS 'OpenStreetMap public transport polygons - all polygons with a public_transport tag and others defined on https://wiki.openstreetmap.org/wiki/Public_transport.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/public_transport.lua';


--
-- Name: COLUMN public_transport_polygon.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN public_transport_polygon.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_polygon.osm_type IS 'Key indicating type of public transport feature if detail exists, falls back to public_transport tag. e.g. highway, bus, train, etc';


--
-- Name: COLUMN public_transport_polygon.osm_subtype; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_polygon.osm_subtype IS 'Value describing osm_type key, e.g. osm_type = "highway", osm_subtype = "bus_stop".';


--
-- Name: COLUMN public_transport_polygon.public_transport; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_polygon.public_transport IS 'Value from public_transport key, or "other" for additional 1st level keys defined in public_transport.lua';


--
-- Name: COLUMN public_transport_polygon.layer; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_polygon.layer IS 'Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN public_transport_polygon.name; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN public_transport_polygon.ref; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_polygon.ref IS 'Reference number or code. Best ref option determined by helpers.get_ref(). https://wiki.openstreetmap.org/wiki/Key:ref';


--
-- Name: COLUMN public_transport_polygon.operator; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_polygon.operator IS 'Entity in charge of operations. https://wiki.openstreetmap.org/wiki/Key:operator';


--
-- Name: COLUMN public_transport_polygon.network; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_polygon.network IS 'Route, system or operator. Usage of network key is widely varied. See https://wiki.openstreetmap.org/wiki/Key:network';


--
-- Name: COLUMN public_transport_polygon.wheelchair; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_polygon.wheelchair IS 'Indicates if feature is wheelchair accessible. Expected values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';


--
-- Name: COLUMN public_transport_polygon.wheelchair_desc; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_polygon.wheelchair_desc IS 'Value from wheelchair:description Per https://wiki.openstreetmap.org/wiki/Key:wheelchair:description';


--
-- Name: COLUMN public_transport_polygon.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.public_transport_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: road_line; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.road_line (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    ref text,
    maxspeed integer,
    oneway smallint,
    layer integer NOT NULL,
    tunnel text,
    bridge text,
    major boolean NOT NULL,
    route_foot boolean,
    route_cycle boolean,
    route_motor boolean,
    access text,
    member_ids jsonb,
    geom public.geometry(MultiLineString,3857) NOT NULL
);


--
-- Name: TABLE road_line; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.road_line IS 'OpenStreetMap roads, full layer.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/road.lua';


--
-- Name: COLUMN road_line.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.road_line.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN road_line.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.road_line.osm_type IS 'Value from "highway" key from OpenStreetMap data.  e.g. motorway, residential, service, footway, etc.';


--
-- Name: COLUMN road_line.name; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.road_line.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN road_line.ref; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.road_line.ref IS 'Reference number or code. Best ref option determined by helpers.get_ref(). https://wiki.openstreetmap.org/wiki/Key:ref';


--
-- Name: COLUMN road_line.maxspeed; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.road_line.maxspeed IS 'Maximum posted speed limit in kilometers per hour (km/hr).  Units not enforced by OpenStreetMap.  Please fix values in MPH in OpenStreetMap.org to either the value in km/hr OR with the suffix "mph" so it can be properly converted.  See https://wiki.openstreetmap.org/wiki/Key:maxspeed';


--
-- Name: COLUMN road_line.oneway; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.road_line.oneway IS 'Used for calculating costs for routing with one-way controls.  0 indicates 2-way traffic is allowed (or assumed).  1 indicates travel is allowed forward only, -1 indicates travel is allowed reverse only. Values reversible and alternating result in NULL.  See https://wiki.openstreetmap.org/wiki/Key:oneway';


--
-- Name: COLUMN road_line.layer; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.road_line.layer IS 'Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN road_line.tunnel; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.road_line.tunnel IS 'If empty, assume not a tunnel.  If not empty, check value for details.';


--
-- Name: COLUMN road_line.bridge; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.road_line.bridge IS 'If empty, assume not a bridge.  If not empty, check value for details.';


--
-- Name: COLUMN road_line.major; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.road_line.major IS 'Indicates feature is a "major" road, classification handled by helpers.major_road().';


--
-- Name: COLUMN road_line.route_foot; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.road_line.route_foot IS 'Best guess if the segment is route-able for foot traffic. If access is no or private, set to false. WARNING: This does not indicate that this method of travel is safe OR allowed!';


--
-- Name: COLUMN road_line.route_cycle; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.road_line.route_cycle IS 'Best guess if the segment is route-able for bicycle traffic. If access is no or private, set to false. WARNING: This does not indicate that this method of travel is safe OR allowed!';


--
-- Name: COLUMN road_line.route_motor; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.road_line.route_motor IS 'Best guess if the segment is route-able for motorized traffic. If access is no or private, set to false. WARNING: This does not indicate that this method of travel is safe OR allowed!';


--
-- Name: COLUMN road_line.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.road_line.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: road_point; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.road_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    ref text,
    maxspeed integer,
    oneway smallint,
    layer integer NOT NULL,
    tunnel text,
    bridge text,
    access text,
    geom public.geometry(Point,3857) NOT NULL
);


--
-- Name: TABLE road_point; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.road_point IS 'OpenStreetMap road points.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/road.lua';


--
-- Name: COLUMN road_point.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.road_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN road_point.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.road_point.osm_type IS 'Value from "highway" key from OpenStreetMap data.  e.g. motorway, residential, service, footway, etc.';


--
-- Name: COLUMN road_point.name; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.road_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN road_point.ref; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.road_point.ref IS 'Reference number or code. Best ref option determined by helpers.get_ref(). https://wiki.openstreetmap.org/wiki/Key:ref';


--
-- Name: COLUMN road_point.maxspeed; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.road_point.maxspeed IS 'Maximum posted speed limit in kilometers per hour (km/hr).  Units not enforced by OpenStreetMap.  Please fix values in MPH in OpenStreetMap.org to either the value in km/hr OR with the suffix "mph" so it can be properly converted.  See https://wiki.openstreetmap.org/wiki/Key:maxspeed';


--
-- Name: COLUMN road_point.oneway; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.road_point.oneway IS 'Used for calculating costs for routing with one-way controls.  0 indicates 2-way traffic is allowed (or assumed).  1 indicates travel is allowed forward only, -1 indicates travel is allowed reverse only. Values reversible and alternating result in NULL.  See https://wiki.openstreetmap.org/wiki/Key:oneway';


--
-- Name: COLUMN road_point.layer; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.road_point.layer IS 'Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN road_point.tunnel; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.road_point.tunnel IS 'If empty, assume not a tunnel.  If not empty, check value for details.';


--
-- Name: COLUMN road_point.bridge; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.road_point.bridge IS 'If empty, assume not a bridge.  If not empty, check value for details.';


--
-- Name: COLUMN road_point.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.road_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: road_polygon; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.road_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    ref text,
    maxspeed integer,
    layer integer NOT NULL,
    tunnel text,
    bridge text,
    major boolean NOT NULL,
    route_foot boolean,
    route_cycle boolean,
    route_motor boolean,
    access text,
    member_ids jsonb,
    geom public.geometry(MultiPolygon,3857) NOT NULL
);


--
-- Name: COLUMN road_polygon.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.road_polygon.osm_type IS 'Value from "highway" key from OpenStreetMap data.  e.g. motorway, residential, service, footway, etc.';


--
-- Name: COLUMN road_polygon.ref; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.road_polygon.ref IS 'Reference number or code. Best ref option determined by helpers.get_ref(). https://wiki.openstreetmap.org/wiki/Key:ref';


--
-- Name: shop_point; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.shop_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text NOT NULL,
    name text,
    housenumber text,
    street text,
    city text,
    state text,
    postcode text,
    address text NOT NULL,
    phone text,
    wheelchair text,
    wheelchair_desc text,
    operator text,
    brand text,
    website text,
    geom public.geometry(Point,3857) NOT NULL
);


--
-- Name: TABLE shop_point; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.shop_point IS 'OpenStreetMap shop related points.   Generated by osm2pgsql Flex output using pgosm-flex/flex-config/shop.lua';


--
-- Name: COLUMN shop_point.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN shop_point.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_point.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer. Value from key stored in osm_subtype.';


--
-- Name: COLUMN shop_point.osm_subtype; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_point.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: COLUMN shop_point.name; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN shop_point.housenumber; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_point.housenumber IS 'Value from addr:housenumber tag';


--
-- Name: COLUMN shop_point.street; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_point.street IS 'Value from addr:street tag';


--
-- Name: COLUMN shop_point.city; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_point.city IS 'Value from addr:city tag';


--
-- Name: COLUMN shop_point.state; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_point.state IS 'Value from addr:state tag';


--
-- Name: COLUMN shop_point.postcode; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_point.postcode IS 'Value from addr:postcode tag';


--
-- Name: COLUMN shop_point.address; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_point.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN shop_point.phone; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_point.phone IS 'Phone number associated with the feature. https://wiki.openstreetmap.org/wiki/Key:phone';


--
-- Name: COLUMN shop_point.wheelchair; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_point.wheelchair IS 'Indicates if feature is wheelchair accessible. Values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';


--
-- Name: COLUMN shop_point.wheelchair_desc; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_point.wheelchair_desc IS 'Value from wheelchair:description Per https://wiki.openstreetmap.org/wiki/Key:wheelchair:description';


--
-- Name: COLUMN shop_point.operator; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_point.operator IS 'Entity in charge of operations. https://wiki.openstreetmap.org/wiki/Key:operator';


--
-- Name: COLUMN shop_point.brand; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_point.brand IS 'Identity of product, service or business. https://wiki.openstreetmap.org/wiki/Key:brand';


--
-- Name: COLUMN shop_point.website; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_point.website IS 'Official website for the feature.  https://wiki.openstreetmap.org/wiki/Key:website';


--
-- Name: COLUMN shop_point.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: shop_polygon; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.shop_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text NOT NULL,
    name text,
    housenumber text,
    street text,
    city text,
    state text,
    postcode text,
    address text NOT NULL,
    phone text,
    wheelchair text,
    wheelchair_desc text,
    operator text,
    brand text,
    website text,
    geom public.geometry(MultiPolygon,3857) NOT NULL
);


--
-- Name: TABLE shop_polygon; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.shop_polygon IS 'OpenStreetMap shop related polygons. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/shop.lua';


--
-- Name: COLUMN shop_polygon.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN shop_polygon.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_polygon.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer. Value from key stored in osm_subtype.';


--
-- Name: COLUMN shop_polygon.osm_subtype; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_polygon.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: COLUMN shop_polygon.name; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN shop_polygon.housenumber; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_polygon.housenumber IS 'Value from addr:housenumber tag';


--
-- Name: COLUMN shop_polygon.street; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_polygon.street IS 'Value from addr:street tag';


--
-- Name: COLUMN shop_polygon.city; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_polygon.city IS 'Value from addr:city tag';


--
-- Name: COLUMN shop_polygon.state; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_polygon.state IS 'Value from addr:state tag';


--
-- Name: COLUMN shop_polygon.postcode; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_polygon.postcode IS 'Value from addr:postcode tag';


--
-- Name: COLUMN shop_polygon.address; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_polygon.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN shop_polygon.phone; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_polygon.phone IS 'Phone number associated with the feature. https://wiki.openstreetmap.org/wiki/Key:phone';


--
-- Name: COLUMN shop_polygon.wheelchair; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_polygon.wheelchair IS 'Indicates if feature is wheelchair accessible. Values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';


--
-- Name: COLUMN shop_polygon.wheelchair_desc; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_polygon.wheelchair_desc IS 'Value from wheelchair:description Per https://wiki.openstreetmap.org/wiki/Key:wheelchair:description';


--
-- Name: COLUMN shop_polygon.operator; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_polygon.operator IS 'Entity in charge of operations. https://wiki.openstreetmap.org/wiki/Key:operator';


--
-- Name: COLUMN shop_polygon.brand; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_polygon.brand IS 'Identity of product, service or business. https://wiki.openstreetmap.org/wiki/Key:brand';


--
-- Name: COLUMN shop_polygon.website; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_polygon.website IS 'Official website for the feature.  https://wiki.openstreetmap.org/wiki/Key:website';


--
-- Name: COLUMN shop_polygon.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.shop_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: tags; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.tags (
    geom_type character(1) NOT NULL,
    osm_id bigint NOT NULL,
    tags jsonb,
    osm_url text GENERATED ALWAYS AS (((('https://www.openstreetmap.org/'::text ||
CASE
    WHEN (geom_type = 'N'::bpchar) THEN 'node'::text
    WHEN (geom_type = 'W'::bpchar) THEN 'way'::text
    ELSE 'relation'::text
END) || '/'::text) || (osm_id)::text)) STORED NOT NULL
);


--
-- Name: TABLE tags; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.tags IS 'OpenStreetMap tag data for all objects in source file.  Key/value data stored in tags column in JSONB format.';


--
-- Name: COLUMN tags.geom_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.tags.geom_type IS 'Type of geometry. N(ode), W(ay) or R(elation).  Unique along with osm_id';


--
-- Name: COLUMN tags.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.tags.osm_id IS 'OpenStreetMap ID. Unique along with geometry type (geom_type).';


--
-- Name: COLUMN tags.tags; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.tags.tags IS 'Stores unaltered key/value pairs from OpenStreetMap.  A few tags are dropped by Lua script though most are preserved.';


--
-- Name: COLUMN tags.osm_url; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.tags.osm_url IS 'Calculated URL to object in OpenStreetMap.org.  Paths are split based on N(ode), W(ay) and R(elation).  See definition of generated column for full details.';


--
-- Name: traffic_line; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.traffic_line (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    geom public.geometry(LineString,3857) NOT NULL
);


--
-- Name: TABLE traffic_line; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.traffic_line IS 'OpenStreetMap traffic related lines.  Primarily "highway" tags but includes multiple.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/traffic.lua';


--
-- Name: COLUMN traffic_line.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.traffic_line.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN traffic_line.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.traffic_line.osm_type IS 'Value of the main key associated with traffic details.  If osm_subtype IS NULL then key = "highway" or key = "noexit".  Otherwise the main key is the value stored in osm_type while osm_subtype has the value for the main key.';


--
-- Name: COLUMN traffic_line.osm_subtype; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.traffic_line.osm_subtype IS 'Value of the non-main key(s) associated with traffic details. See osm_type column for the key associated with this value. NULL when the main key = "highway" or key = "noexit".';


--
-- Name: COLUMN traffic_line.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.traffic_line.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: traffic_point; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.traffic_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    geom public.geometry(Point,3857) NOT NULL
);


--
-- Name: TABLE traffic_point; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.traffic_point IS 'OpenStreetMap traffic related points.  Primarily "highway" tags but includes multiple.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/traffic.lua';


--
-- Name: COLUMN traffic_point.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.traffic_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN traffic_point.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.traffic_point.osm_type IS 'Value of the main key associated with traffic details.  If osm_subtype IS NULL then key = "highway" or key = "noexit".  Otherwise the main key is the value stored in osm_type while osm_subtype has the value for the main key.';


--
-- Name: COLUMN traffic_point.osm_subtype; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.traffic_point.osm_subtype IS 'Value of the non-main key(s) associated with traffic details. See osm_type column for the key associated with this value. NULL when the main key = "highway" or key = "noexit".';


--
-- Name: COLUMN traffic_point.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.traffic_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: traffic_polygon; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.traffic_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    geom public.geometry(MultiPolygon,3857) NOT NULL
);


--
-- Name: TABLE traffic_polygon; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.traffic_polygon IS 'OpenStreetMap traffic related polygons.  Primarily "highway" tags but includes multiple.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/traffic.lua';


--
-- Name: COLUMN traffic_polygon.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.traffic_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN traffic_polygon.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.traffic_polygon.osm_type IS 'Value of the main key associated with traffic details.  If osm_subtype IS NULL then key = "highway".  Otherwise the main key is the value stored in osm_type while osm_subtype has the value for the main key.';


--
-- Name: COLUMN traffic_polygon.osm_subtype; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.traffic_polygon.osm_subtype IS 'Value of the non-main key(s) associated with traffic details. See osm_type column for the key associated with this value. NULL when the main key = "highway".';


--
-- Name: COLUMN traffic_polygon.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.traffic_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: vplace_polygon_subdivide; Type: MATERIALIZED VIEW; Schema: osm_spokane; Owner: -
--

CREATE MATERIALIZED VIEW osm_spokane.vplace_polygon_subdivide AS
 SELECT osm_id,
    public.st_subdivide(geom) AS geom
   FROM osm_spokane.place_polygon
  WITH NO DATA;


--
-- Name: MATERIALIZED VIEW vplace_polygon_subdivide; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON MATERIALIZED VIEW osm_spokane.vplace_polygon_subdivide IS 'Subdivided geometry from osm_spokane.vplace_polygon.  Multiple rows per osm_id, one for each subdivided geometry.';


--
-- Name: COLUMN vplace_polygon_subdivide.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.vplace_polygon_subdivide.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.  Duplicated in this view!';


--
-- Name: COLUMN vplace_polygon_subdivide.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.vplace_polygon_subdivide.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: water_line; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.water_line (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text NOT NULL,
    name text,
    layer integer NOT NULL,
    tunnel text,
    bridge text,
    boat text,
    member_ids jsonb,
    geom public.geometry(MultiLineString,3857) NOT NULL
);


--
-- Name: TABLE water_line; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.water_line IS 'OpenStreetMap water / waterway related lines.  Includes combination of "natural" and "waterway" keys.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/water.lua';


--
-- Name: COLUMN water_line.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.water_line.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN water_line.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.water_line.osm_type IS 'Indicates the key (natural/waterway) providing the source for the detail';


--
-- Name: COLUMN water_line.osm_subtype; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.water_line.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: COLUMN water_line.name; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.water_line.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN water_line.layer; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.water_line.layer IS 'Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN water_line.tunnel; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.water_line.tunnel IS 'If empty, assume not a tunnel.  If not empty, check value for details.';


--
-- Name: COLUMN water_line.bridge; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.water_line.bridge IS 'If empty, assume not a bridge.  If not empty, check value for details.';


--
-- Name: COLUMN water_line.boat; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.water_line.boat IS 'Access details for boat travel.  https://wiki.openstreetmap.org/wiki/Key:boat';


--
-- Name: COLUMN water_line.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.water_line.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: water_point; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.water_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text NOT NULL,
    name text,
    layer integer NOT NULL,
    tunnel text,
    bridge text,
    boat text,
    geom public.geometry(Point,3857) NOT NULL
);


--
-- Name: TABLE water_point; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.water_point IS 'OpenStreetMap water / waterway related points.  Includes combination of "natural" and "waterway" keys.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/water.lua';


--
-- Name: COLUMN water_point.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.water_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN water_point.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.water_point.osm_type IS 'Indicates the key (natural/waterway) providing the source for the detail';


--
-- Name: COLUMN water_point.osm_subtype; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.water_point.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: COLUMN water_point.name; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.water_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN water_point.layer; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.water_point.layer IS 'Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN water_point.tunnel; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.water_point.tunnel IS 'If empty, assume not a tunnel.  If not empty, check value for details.';


--
-- Name: COLUMN water_point.bridge; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.water_point.bridge IS 'If empty, assume not a bridge.  If not empty, check value for details.';


--
-- Name: COLUMN water_point.boat; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.water_point.boat IS 'Access details for boat travel.  https://wiki.openstreetmap.org/wiki/Key:boat';


--
-- Name: COLUMN water_point.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.water_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: water_polygon; Type: TABLE; Schema: osm_spokane; Owner: -
--

CREATE TABLE osm_spokane.water_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text NOT NULL,
    name text,
    layer integer NOT NULL,
    tunnel text,
    bridge text,
    boat text,
    member_ids jsonb,
    geom public.geometry(MultiPolygon,3857) NOT NULL
);


--
-- Name: TABLE water_polygon; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON TABLE osm_spokane.water_polygon IS 'OpenStreetMap water / waterway related polygons.  Includes combination of "natural" and "waterway" keys.  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/water.lua';


--
-- Name: COLUMN water_polygon.osm_id; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.water_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN water_polygon.osm_type; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.water_polygon.osm_type IS 'Indicates the key (natural/waterway) providing the source for the detail';


--
-- Name: COLUMN water_polygon.osm_subtype; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.water_polygon.osm_subtype IS 'Value detail describing the key (osm_type).';


--
-- Name: COLUMN water_polygon.name; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.water_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN water_polygon.layer; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.water_polygon.layer IS 'Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN water_polygon.tunnel; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.water_polygon.tunnel IS 'If empty, assume not a tunnel.  If not empty, check value for details.';


--
-- Name: COLUMN water_polygon.bridge; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.water_polygon.bridge IS 'If empty, assume not a bridge.  If not empty, check value for details.';


--
-- Name: COLUMN water_polygon.boat; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.water_polygon.boat IS 'Access details for boat travel.  https://wiki.openstreetmap.org/wiki/Key:boat';


--
-- Name: COLUMN water_polygon.geom; Type: COMMENT; Schema: osm_spokane; Owner: -
--

COMMENT ON COLUMN osm_spokane.water_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: amenity_line; Type: TABLE; Schema: osm_wa; Owner: -
--

CREATE TABLE osm_wa.amenity_line (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    name text,
    housenumber text,
    street text,
    city text,
    state text,
    postcode text,
    address text NOT NULL,
    wheelchair text,
    wheelchair_desc text,
    geom public.geometry(LineString,3857) NOT NULL
);


--
-- Name: TABLE amenity_line; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON TABLE osm_wa.amenity_line IS 'OpenStreetMap amenity lines - all lines with an amenity tag.  Some amenity tags are pulled into other tables (e.g. infrastructure, shop, and traffic layers) and duplicated again here. This is currently intentional but may change in the future. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/amenity.lua';


--
-- Name: COLUMN amenity_line.osm_id; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_line.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN amenity_line.osm_type; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_line.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN amenity_line.osm_subtype; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_line.osm_subtype IS 'Further describes osm_type for amenities.';


--
-- Name: COLUMN amenity_line.name; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_line.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN amenity_line.housenumber; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_line.housenumber IS 'Value from addr:housenumber tag';


--
-- Name: COLUMN amenity_line.street; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_line.street IS 'Value from addr:street tag';


--
-- Name: COLUMN amenity_line.city; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_line.city IS 'Value from addr:city tag';


--
-- Name: COLUMN amenity_line.state; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_line.state IS 'Value from addr:state tag';


--
-- Name: COLUMN amenity_line.postcode; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_line.postcode IS 'Value from addr:postcode tag';


--
-- Name: COLUMN amenity_line.address; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_line.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN amenity_line.wheelchair; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_line.wheelchair IS 'Indicates if feature is wheelchair accessible. Values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';


--
-- Name: COLUMN amenity_line.wheelchair_desc; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_line.wheelchair_desc IS 'Value from wheelchair:description Per https://wiki.openstreetmap.org/wiki/Key:wheelchair:description';


--
-- Name: COLUMN amenity_line.geom; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_line.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: amenity_point; Type: TABLE; Schema: osm_wa; Owner: -
--

CREATE TABLE osm_wa.amenity_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    name text,
    housenumber text,
    street text,
    city text,
    state text,
    postcode text,
    address text NOT NULL,
    wheelchair text,
    wheelchair_desc text,
    geom public.geometry(Point,3857) NOT NULL
);


--
-- Name: TABLE amenity_point; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON TABLE osm_wa.amenity_point IS 'OpenStreetMap amenity points - all points with an amenity tag.  Some amenity tags are pulled into other tables (e.g. infrastructure, shop, and traffic layers) and duplicated again here. This is currently intentional but may change in the future. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/amenity.lua';


--
-- Name: COLUMN amenity_point.osm_id; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN amenity_point.osm_type; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_point.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN amenity_point.osm_subtype; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_point.osm_subtype IS 'Further describes osm_type for amenities.';


--
-- Name: COLUMN amenity_point.name; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN amenity_point.housenumber; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_point.housenumber IS 'Value from addr:housenumber tag';


--
-- Name: COLUMN amenity_point.street; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_point.street IS 'Value from addr:street tag';


--
-- Name: COLUMN amenity_point.city; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_point.city IS 'Value from addr:city tag';


--
-- Name: COLUMN amenity_point.state; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_point.state IS 'Value from addr:state tag';


--
-- Name: COLUMN amenity_point.postcode; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_point.postcode IS 'Value from addr:postcode tag';


--
-- Name: COLUMN amenity_point.address; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_point.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN amenity_point.wheelchair; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_point.wheelchair IS 'Indicates if feature is wheelchair accessible. Values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';


--
-- Name: COLUMN amenity_point.wheelchair_desc; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_point.wheelchair_desc IS 'Value from wheelchair:description Per https://wiki.openstreetmap.org/wiki/Key:wheelchair:description';


--
-- Name: COLUMN amenity_point.geom; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: amenity_polygon; Type: TABLE; Schema: osm_wa; Owner: -
--

CREATE TABLE osm_wa.amenity_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    osm_subtype text,
    name text,
    housenumber text,
    street text,
    city text,
    state text,
    postcode text,
    address text NOT NULL,
    wheelchair text,
    wheelchair_desc text,
    geom public.geometry(MultiPolygon,3857) NOT NULL
);


--
-- Name: TABLE amenity_polygon; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON TABLE osm_wa.amenity_polygon IS 'OpenStreetMap amenity polygons - all polygons with an amenity tag.  Some amenity tags are pulled into other tables (e.g. infrastructure, shop, and traffic layers) and duplicated again here. This is currently intentional but may change in the future. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/amenity.lua';


--
-- Name: COLUMN amenity_polygon.osm_id; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN amenity_polygon.osm_type; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_polygon.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN amenity_polygon.osm_subtype; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_polygon.osm_subtype IS 'Further describes osm_type for amenities.';


--
-- Name: COLUMN amenity_polygon.name; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN amenity_polygon.housenumber; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_polygon.housenumber IS 'Value from addr:housenumber tag';


--
-- Name: COLUMN amenity_polygon.street; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_polygon.street IS 'Value from addr:street tag';


--
-- Name: COLUMN amenity_polygon.city; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_polygon.city IS 'Value from addr:city tag';


--
-- Name: COLUMN amenity_polygon.state; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_polygon.state IS 'Value from addr:state tag';


--
-- Name: COLUMN amenity_polygon.postcode; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_polygon.postcode IS 'Value from addr:postcode tag';


--
-- Name: COLUMN amenity_polygon.address; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_polygon.address IS 'Address combined from address parts in helpers.get_address().';


--
-- Name: COLUMN amenity_polygon.wheelchair; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_polygon.wheelchair IS 'Indicates if feature is wheelchair accessible. Values:  yes, no, limited.  Per https://wiki.openstreetmap.org/wiki/Key:wheelchair';


--
-- Name: COLUMN amenity_polygon.wheelchair_desc; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_polygon.wheelchair_desc IS 'Value from wheelchair:description Per https://wiki.openstreetmap.org/wiki/Key:wheelchair:description';


--
-- Name: COLUMN amenity_polygon.geom; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.amenity_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: natural_line; Type: TABLE; Schema: osm_wa; Owner: -
--

CREATE TABLE osm_wa.natural_line (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    ele integer,
    geom public.geometry(LineString,3857) NOT NULL
);


--
-- Name: TABLE natural_line; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON TABLE osm_wa.natural_line IS 'OpenStreetMap natural lines, e.g. cliffs, tree row, etc.. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/natural.lua';


--
-- Name: COLUMN natural_line.osm_id; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.natural_line.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN natural_line.osm_type; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.natural_line.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN natural_line.name; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.natural_line.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN natural_line.ele; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.natural_line.ele IS 'Elevation in meters';


--
-- Name: COLUMN natural_line.geom; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.natural_line.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: natural_point; Type: TABLE; Schema: osm_wa; Owner: -
--

CREATE TABLE osm_wa.natural_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    ele integer,
    geom public.geometry(Point,3857) NOT NULL
);


--
-- Name: TABLE natural_point; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON TABLE osm_wa.natural_point IS 'OpenStreetMap natural points, e.g. trees, peaks, etc..  Generated by osm2pgsql Flex output using pgosm-flex/flex-config/natural.lua';


--
-- Name: COLUMN natural_point.osm_id; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.natural_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN natural_point.osm_type; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.natural_point.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN natural_point.name; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.natural_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN natural_point.ele; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.natural_point.ele IS 'Elevation in meters';


--
-- Name: COLUMN natural_point.geom; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.natural_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: natural_polygon; Type: TABLE; Schema: osm_wa; Owner: -
--

CREATE TABLE osm_wa.natural_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    ele integer,
    geom public.geometry(MultiPolygon,3857) NOT NULL
);


--
-- Name: TABLE natural_polygon; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON TABLE osm_wa.natural_polygon IS 'OpenStreetMap natural polygons, e.g. woods, grass, etc.. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/natural.lua';


--
-- Name: COLUMN natural_polygon.osm_id; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.natural_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN natural_polygon.osm_type; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.natural_polygon.osm_type IS 'Stores the OpenStreetMap key that included this feature in the layer.';


--
-- Name: COLUMN natural_polygon.name; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.natural_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN natural_polygon.ele; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.natural_polygon.ele IS 'Elevation in meters';


--
-- Name: COLUMN natural_polygon.geom; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.natural_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: pgosm_flex; Type: TABLE; Schema: osm_wa; Owner: -
--

CREATE TABLE osm_wa.pgosm_flex (
    id bigint NOT NULL,
    imported timestamp with time zone DEFAULT now() NOT NULL,
    osm_date date NOT NULL,
    region text NOT NULL,
    layerset text,
    srid text NOT NULL,
    pgosm_flex_version text NOT NULL,
    osm2pgsql_version text NOT NULL,
    language text NOT NULL,
    import_mode jsonb,
    import_status text DEFAULT 'Initializing'::text NOT NULL,
    input_file text
);


--
-- Name: TABLE pgosm_flex; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON TABLE osm_wa.pgosm_flex IS 'Provides meta information on the PgOSM-Flex project including version and SRID used during the import. One row per import.';


--
-- Name: COLUMN pgosm_flex.imported; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.pgosm_flex.imported IS 'Indicates when the import was ran.';


--
-- Name: COLUMN pgosm_flex.osm_date; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.pgosm_flex.osm_date IS 'Indicates the date of the OpenStreetMap data loaded.  Recommended to set PGOSM_DATE env var at runtime, otherwise defaults to the date PgOSM-Flex was run.';


--
-- Name: COLUMN pgosm_flex.region; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.pgosm_flex.region IS 'Region specified at run time via --region and --subregion values.  When using --input-file without region/subregion, this defaults to the input filename.';


--
-- Name: COLUMN pgosm_flex.layerset; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.pgosm_flex.layerset IS 'PgOSM Flex layerset used for the import style.';


--
-- Name: COLUMN pgosm_flex.srid; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.pgosm_flex.srid IS 'SRID of imported data.';


--
-- Name: COLUMN pgosm_flex.pgosm_flex_version; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.pgosm_flex.pgosm_flex_version IS 'Version of PgOSM-Flex used to generate schema.';


--
-- Name: COLUMN pgosm_flex.osm2pgsql_version; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.pgosm_flex.osm2pgsql_version IS 'Version of osm2pgsql used to load data.';


--
-- Name: COLUMN pgosm_flex.language; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.pgosm_flex.language IS 'Preferred language specified at run time via env var PGOSM_LANGUAGE.  Empty string when not defined.';


--
-- Name: COLUMN pgosm_flex.import_status; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.pgosm_flex.import_status IS 'Status of the import. Starts as initialized, tracks status during imports and final success/failure.';


--
-- Name: COLUMN pgosm_flex.input_file; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.pgosm_flex.input_file IS 'Tracks explicit file defined when --input-file is used.  NULL when --input-file not used.';


--
-- Name: pgosm_flex_id_seq; Type: SEQUENCE; Schema: osm_wa; Owner: -
--

ALTER TABLE osm_wa.pgosm_flex ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME osm_wa.pgosm_flex_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: place_line; Type: TABLE; Schema: osm_wa; Owner: -
--

CREATE TABLE osm_wa.place_line (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    boundary text,
    admin_level integer,
    name text,
    geom public.geometry(LineString,3857) NOT NULL
);


--
-- Name: TABLE place_line; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON TABLE osm_wa.place_line IS 'OpenStreetMap named places and administrative boundaries. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/place.lua';


--
-- Name: COLUMN place_line.osm_id; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.place_line.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN place_line.osm_type; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.place_line.osm_type IS 'Values from place if a place tag exists.  If no place tag, values boundary or admin_level indicate the source of the feature.';


--
-- Name: COLUMN place_line.boundary; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.place_line.boundary IS 'Value from boundary tag.  https://wiki.openstreetmap.org/wiki/Boundaries';


--
-- Name: COLUMN place_line.admin_level; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.place_line.admin_level IS 'Value from admin_level if it exists as integer value. Meaning of admin_level changes by region, see: https://wiki.openstreetmap.org/wiki/Key:admin_level';


--
-- Name: COLUMN place_line.name; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.place_line.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN place_line.geom; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.place_line.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: place_point; Type: TABLE; Schema: osm_wa; Owner: -
--

CREATE TABLE osm_wa.place_point (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    boundary text,
    admin_level integer,
    name text,
    geom public.geometry(Point,3857) NOT NULL
);


--
-- Name: TABLE place_point; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON TABLE osm_wa.place_point IS 'OpenStreetMap named places and administrative boundaries. Generated by osm2pgsql Flex output using pgosm-flex/flex-config/place.lua';


--
-- Name: COLUMN place_point.osm_id; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.place_point.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN place_point.osm_type; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.place_point.osm_type IS 'Values from place if a place tag exists.  If no place tag, values boundary or admin_level indicate the source of the feature.';


--
-- Name: COLUMN place_point.boundary; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.place_point.boundary IS 'Value from boundary tag.  https://wiki.openstreetmap.org/wiki/Boundaries';


--
-- Name: COLUMN place_point.admin_level; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.place_point.admin_level IS 'Value from admin_level if it exists as integer value. Meaning of admin_level changes by region, see: https://wiki.openstreetmap.org/wiki/Key:admin_level';


--
-- Name: COLUMN place_point.name; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.place_point.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN place_point.geom; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.place_point.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: place_polygon; Type: TABLE; Schema: osm_wa; Owner: -
--

CREATE TABLE osm_wa.place_polygon (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    boundary text,
    admin_level integer,
    name text,
    member_ids jsonb,
    geom public.geometry(MultiPolygon,3857) NOT NULL
);


--
-- Name: TABLE place_polygon; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON TABLE osm_wa.place_polygon IS 'OpenStreetMap named places and administrative boundaries.  Contains relations and the polygon parts making up the relations. Members of relations are removed to avoid duplication. Generated by PgOSM Flex using pgosm-flex/flex-config/place.lua';


--
-- Name: COLUMN place_polygon.osm_id; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.place_polygon.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN place_polygon.osm_type; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.place_polygon.osm_type IS 'Values from place if a place tag exists.  If no place tag, values boundary or admin_level indicate the source of the feature.';


--
-- Name: COLUMN place_polygon.boundary; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.place_polygon.boundary IS 'Value from boundary tag.  https://wiki.openstreetmap.org/wiki/Boundaries';


--
-- Name: COLUMN place_polygon.admin_level; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.place_polygon.admin_level IS 'Value from admin_level if it exists as integer value. Meaning of admin_level changes by region, see: https://wiki.openstreetmap.org/wiki/Key:admin_level';


--
-- Name: COLUMN place_polygon.name; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.place_polygon.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN place_polygon.member_ids; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.place_polygon.member_ids IS 'Member IDs making up the full relation.  NULL if not a relation.  Used to create improved osm_wa.vplace_polygon.';


--
-- Name: COLUMN place_polygon.geom; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.place_polygon.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: place_polygon_nested; Type: TABLE; Schema: osm_wa; Owner: -
--

CREATE TABLE osm_wa.place_polygon_nested (
    osm_id bigint NOT NULL,
    name text NOT NULL,
    osm_type text NOT NULL,
    admin_level integer NOT NULL,
    nest_level bigint,
    name_path text[],
    osm_id_path bigint[],
    admin_level_path integer[],
    row_innermost boolean GENERATED ALWAYS AS (
CASE
    WHEN (osm_id_path[array_length(osm_id_path, 1)] = osm_id) THEN true
    ELSE false
END) STORED NOT NULL,
    innermost boolean DEFAULT false NOT NULL,
    geom public.geometry NOT NULL
);


--
-- Name: TABLE place_polygon_nested; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON TABLE osm_wa.place_polygon_nested IS 'Provides hierarchy of administrative polygons.  Built on top of osm_wa.vplace_polygon. Artifact of PgOSM-Flex (place.sql).';


--
-- Name: COLUMN place_polygon_nested.osm_id; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.place_polygon_nested.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN place_polygon_nested.name; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.place_polygon_nested.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN place_polygon_nested.osm_type; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.place_polygon_nested.osm_type IS 'Values from place if a place tag exists.  If no place tag, values boundary or admin_level indicate the source of the feature.';


--
-- Name: COLUMN place_polygon_nested.admin_level; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.place_polygon_nested.admin_level IS 'Value from admin_level if it exists.  Defaults to 99 if not.';


--
-- Name: COLUMN place_polygon_nested.nest_level; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.place_polygon_nested.nest_level IS 'How many polygons is the current polygon nested within.  1 indicates polygon with no containing polygon.';


--
-- Name: COLUMN place_polygon_nested.name_path; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.place_polygon_nested.name_path IS 'Array of names of the current polygon (last) and all containing polygons.';


--
-- Name: COLUMN place_polygon_nested.osm_id_path; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.place_polygon_nested.osm_id_path IS 'Array of osm_id for the current polygon (last) and all containing polygons.';


--
-- Name: COLUMN place_polygon_nested.admin_level_path; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.place_polygon_nested.admin_level_path IS 'Array of admin_level values for the current polygon (last) and all containing polygons.';


--
-- Name: COLUMN place_polygon_nested.row_innermost; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.place_polygon_nested.row_innermost IS 'Indicates if the osm_id is the most inner ID of the current row.  Used to calculated innermost after all nesting paths have been calculated.';


--
-- Name: COLUMN place_polygon_nested.innermost; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.place_polygon_nested.innermost IS 'Indicates this row is the innermost admin level of the current data set and does **not** itself contain another admin polygon.  Calculated by procedure osm_wa.build_nested_admin_polygons() defined in pgosm-flex/flex-config/place.sql.';


--
-- Name: COLUMN place_polygon_nested.geom; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.place_polygon_nested.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: road_major; Type: TABLE; Schema: osm_wa; Owner: -
--

CREATE TABLE osm_wa.road_major (
    osm_id bigint NOT NULL,
    osm_type text NOT NULL,
    name text,
    ref text,
    maxspeed integer,
    layer integer NOT NULL,
    tunnel text,
    bridge text,
    major boolean NOT NULL,
    member_ids jsonb,
    geom public.geometry(MultiLineString,3857) NOT NULL
);


--
-- Name: TABLE road_major; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON TABLE osm_wa.road_major IS 'OpenStreetMap roads - Major only. Classification handled by helpers.major_road(). Generated by osm2pgsql Flex output using pgosm-flex/flex-config/road_major.lua';


--
-- Name: COLUMN road_major.osm_id; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.road_major.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.';


--
-- Name: COLUMN road_major.osm_type; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.road_major.osm_type IS 'Value from "highway" key from OpenStreetMap data.  e.g. motorway, residential, etc.';


--
-- Name: COLUMN road_major.name; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.road_major.name IS 'Best name option determined by helpers.get_name(). Keys with priority are: name, short_name, alt_name and loc_name.  See pgosm-flex/flex-config/helpers.lua for full logic of selection.';


--
-- Name: COLUMN road_major.ref; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.road_major.ref IS 'Reference number or code. Best ref option determined by helpers.get_ref(). https://wiki.openstreetmap.org/wiki/Key:ref';


--
-- Name: COLUMN road_major.maxspeed; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.road_major.maxspeed IS 'Maximum posted speed limit in kilometers per hour (km/hr).  Units not enforced by OpenStreetMap.  Please fix values in MPH in OpenStreetMap.org to either the value in km/hr OR with the suffix "mph" so it can be properly converted.  See https://wiki.openstreetmap.org/wiki/Key:maxspeed';


--
-- Name: COLUMN road_major.layer; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.road_major.layer IS 'Vertical ordering layer (Z) to handle crossing/overlapping features. "All ways without an explicit value are assumed to have layer 0." - per Wiki - https://wiki.openstreetmap.org/wiki/Key:layer';


--
-- Name: COLUMN road_major.tunnel; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.road_major.tunnel IS 'If empty, assume not a tunnel.  If not empty, check value for details.';


--
-- Name: COLUMN road_major.bridge; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.road_major.bridge IS 'If empty, assume not a bridge.  If not empty, check value for details.';


--
-- Name: COLUMN road_major.geom; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.road_major.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: vplace_polygon_subdivide; Type: MATERIALIZED VIEW; Schema: osm_wa; Owner: -
--

CREATE MATERIALIZED VIEW osm_wa.vplace_polygon_subdivide AS
 SELECT osm_id,
    public.st_subdivide(geom) AS geom
   FROM osm_wa.place_polygon
  WITH NO DATA;


--
-- Name: MATERIALIZED VIEW vplace_polygon_subdivide; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON MATERIALIZED VIEW osm_wa.vplace_polygon_subdivide IS 'Subdivided geometry from osm_wa.vplace_polygon.  Multiple rows per osm_id, one for each subdivided geometry.';


--
-- Name: COLUMN vplace_polygon_subdivide.osm_id; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.vplace_polygon_subdivide.osm_id IS 'OpenStreetMap ID. Unique along with geometry type.  Duplicated in this view!';


--
-- Name: COLUMN vplace_polygon_subdivide.geom; Type: COMMENT; Schema: osm_wa; Owner: -
--

COMMENT ON COLUMN osm_wa.vplace_polygon_subdivide.geom IS 'Geometry loaded by osm2pgsql.';


--
-- Name: road; Type: TABLE; Schema: pgosm; Owner: -
--

CREATE TABLE pgosm.road (
    id bigint NOT NULL,
    region text DEFAULT 'United States'::text NOT NULL,
    osm_type text NOT NULL,
    route_motor boolean DEFAULT true,
    route_foot boolean DEFAULT true,
    route_cycle boolean DEFAULT true,
    maxspeed numeric(6,2) NOT NULL,
    maxspeed_mph numeric(6,2) GENERATED ALWAYS AS ((maxspeed / 1.609344)) STORED NOT NULL
);


--
-- Name: TABLE road; Type: COMMENT; Schema: pgosm; Owner: -
--

COMMENT ON TABLE pgosm.road IS 'Provides lookup information for road layers, generally related to routing use cases.';


--
-- Name: COLUMN road.region; Type: COMMENT; Schema: pgosm; Owner: -
--

COMMENT ON COLUMN pgosm.road.region IS 'Allows defining different definitions based on region.  Can be custom defined.';


--
-- Name: COLUMN road.osm_type; Type: COMMENT; Schema: pgosm; Owner: -
--

COMMENT ON COLUMN pgosm.road.osm_type IS 'Value from highway tags.';


--
-- Name: COLUMN road.route_motor; Type: COMMENT; Schema: pgosm; Owner: -
--

COMMENT ON COLUMN pgosm.road.route_motor IS 'Used to filter for classifications that typically allow motorized traffic.';


--
-- Name: COLUMN road.route_foot; Type: COMMENT; Schema: pgosm; Owner: -
--

COMMENT ON COLUMN pgosm.road.route_foot IS 'Used to filter for classifications that typically allow foot traffic.';


--
-- Name: COLUMN road.route_cycle; Type: COMMENT; Schema: pgosm; Owner: -
--

COMMENT ON COLUMN pgosm.road.route_cycle IS 'Used to filter for classifications that typically allow bicycle traffic.';


--
-- Name: COLUMN road.maxspeed; Type: COMMENT; Schema: pgosm; Owner: -
--

COMMENT ON COLUMN pgosm.road.maxspeed IS 'Maxspeed in km/hr';


--
-- Name: COLUMN road.maxspeed_mph; Type: COMMENT; Schema: pgosm; Owner: -
--

COMMENT ON COLUMN pgosm.road.maxspeed_mph IS 'Maxspeed in mph';


--
-- Name: road_id_seq; Type: SEQUENCE; Schema: pgosm; Owner: -
--

ALTER TABLE pgosm.road ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME pgosm.road_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: layer_styles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.layer_styles (
    id integer NOT NULL,
    f_table_catalog character varying(256),
    f_table_schema character varying(256),
    f_table_name character varying(256),
    f_geometry_column character varying(256),
    stylename character varying(30),
    styleqml xml,
    stylesld xml,
    useasdefault boolean,
    description text,
    owner character varying(30),
    ui xml,
    update_time timestamp without time zone DEFAULT now(),
    type character varying
);


--
-- Name: layer_styles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.layer_styles_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: layer_styles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.layer_styles_id_seq OWNED BY public.layer_styles.id;


--
-- Name: layer_styles_staging; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.layer_styles_staging (
    id integer NOT NULL,
    f_table_catalog character varying(256),
    f_table_schema character varying(256),
    f_table_name character varying(256),
    f_geometry_column character varying(256),
    stylename character varying(30),
    styleqml xml,
    stylesld xml,
    useasdefault boolean,
    description text,
    owner character varying(30),
    ui xml,
    update_time timestamp without time zone DEFAULT now(),
    type character varying
);


--
-- Name: TABLE layer_styles_staging; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.layer_styles_staging IS 'Staging table to load QGIS Layer Styles.  Similar to QGIS-created table, no primary key.';


--
-- Name: osm2pgsql_properties; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.osm2pgsql_properties (
    property text NOT NULL,
    value text NOT NULL
);


--
-- Name: srid_bbox; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.srid_bbox (
    srid bigint NOT NULL,
    geom public.geometry(Polygon,3857)
);


--
-- Name: TABLE srid_bbox; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.srid_bbox IS 'Bounding boxes for SRIDs sourced from https://spatialreference.org';


--
-- Name: COLUMN srid_bbox.srid; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.srid_bbox.srid IS 'Spatial Reference identifier, matches values in public.spatial_ref_sys and used to look up bbox from source.';


--
-- Name: COLUMN srid_bbox.geom; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.srid_bbox.geom IS 'Bounding box for the SRID from WGS84 Bounds defined at https://spatialreference.org/ref/epsg/{srid}/';


--
-- Name: srid_units; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.srid_units AS
 SELECT srs.srid,
        CASE
            WHEN ((srs.proj4text)::text ~~ '%+units=%'::text) THEN true
            ELSE false
        END AS units_set,
        CASE
            WHEN ((srs.proj4text)::text ~~ '%+units=m%'::text) THEN 'Meters'::text
            WHEN ((srs.proj4text)::text ~~ '%+units=ft%'::text) THEN 'Feet'::text
            WHEN ((srs.proj4text)::text ~~ '%+units=us-ft%'::text) THEN 'Feet'::text
            WHEN (((srs.proj4text)::text ~~ '%+units=link%'::text) OR ((srs.proj4text)::text ~~ '%+units=%'::text)) THEN 'Set, not caught properly'::text
            ELSE 'Decimal Degrees'::text
        END AS units,
    srs.proj4text,
    srs.srtext,
    public.st_area((public.st_transform(bbox.geom, 4326))::public.geography) AS geom_area,
    bbox.geom
   FROM (public.spatial_ref_sys srs
     LEFT JOIN public.srid_bbox bbox ON ((srs.srid = bbox.srid)));


--
-- Name: VIEW srid_units; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.srid_units IS 'PostGIS specific view to make it easier to find what units each SRID is in and the bounding box indicating where the SRID is best suited for.';


--
-- Name: road_line; Type: TABLE; Schema: routing; Owner: -
--

CREATE TABLE routing.road_line (
    id bigint NOT NULL,
    osm_id bigint,
    osm_type text,
    maxspeed integer,
    oneway smallint,
    layer integer,
    route_foot boolean,
    route_cycle boolean,
    route_motor boolean,
    access text,
    geom public.geometry
);


--
-- Name: COLUMN road_line.id; Type: COMMENT; Schema: routing; Owner: -
--

COMMENT ON COLUMN routing.road_line.id IS 'Surrogate ID, because we cannot rely on osm_id being unique after converting multi-linestrings to linestrings.';


--
-- Name: road_line_noded; Type: TABLE; Schema: routing; Owner: -
--

CREATE TABLE routing.road_line_noded (
    id bigint NOT NULL,
    old_id integer,
    sub_id integer,
    source bigint,
    target bigint,
    geom public.geometry(LineString,3857),
    oneway smallint NOT NULL,
    cost_length numeric GENERATED ALWAYS AS (
CASE
    WHEN (oneway = ANY (ARRAY[0, 1])) THEN public.st_length(geom)
    WHEN (oneway = '-1'::integer) THEN (('-1'::integer)::double precision * public.st_length(geom))
    ELSE NULL::double precision
END) STORED,
    cost_length_reverse numeric GENERATED ALWAYS AS (
CASE
    WHEN (oneway = ANY (ARRAY[0, '-1'::integer])) THEN public.st_length(geom)
    WHEN (oneway = 1) THEN (('-1'::integer)::double precision * public.st_length(geom))
    ELSE NULL::double precision
END) STORED
);


--
-- Name: road_line_noded_id_seq; Type: SEQUENCE; Schema: routing; Owner: -
--

CREATE SEQUENCE routing.road_line_noded_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: road_line_noded_id_seq; Type: SEQUENCE OWNED BY; Schema: routing; Owner: -
--

ALTER SEQUENCE routing.road_line_noded_id_seq OWNED BY routing.road_line_noded.id;


--
-- Name: road_line_noded_vertices_pgr; Type: TABLE; Schema: routing; Owner: -
--

CREATE TABLE routing.road_line_noded_vertices_pgr (
    id bigint NOT NULL,
    cnt integer,
    chk integer,
    ein integer,
    eout integer,
    the_geom public.geometry(Point,3857)
);


--
-- Name: road_line_noded_vertices_pgr_id_seq; Type: SEQUENCE; Schema: routing; Owner: -
--

CREATE SEQUENCE routing.road_line_noded_vertices_pgr_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: road_line_noded_vertices_pgr_id_seq; Type: SEQUENCE OWNED BY; Schema: routing; Owner: -
--

ALTER SEQUENCE routing.road_line_noded_vertices_pgr_id_seq OWNED BY routing.road_line_noded_vertices_pgr.id;


--
-- Name: layer_styles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.layer_styles ALTER COLUMN id SET DEFAULT nextval('public.layer_styles_id_seq'::regclass);


--
-- Name: road_line_noded id; Type: DEFAULT; Schema: routing; Owner: -
--

ALTER TABLE ONLY routing.road_line_noded ALTER COLUMN id SET DEFAULT nextval('routing.road_line_noded_id_seq'::regclass);


--
-- Name: road_line_noded_vertices_pgr id; Type: DEFAULT; Schema: routing; Owner: -
--

ALTER TABLE ONLY routing.road_line_noded_vertices_pgr ALTER COLUMN id SET DEFAULT nextval('routing.road_line_noded_vertices_pgr_id_seq'::regclass);


--
-- PostgreSQL database dump complete
--

