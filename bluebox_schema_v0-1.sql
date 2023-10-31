--
-- PostgreSQL database dump
--

-- Dumped from database version 16.0 (Debian 16.0-1.pgdg110+1)
-- Dumped by pg_dump version 16.0 (Ubuntu 16.0-1.pgdg20.04+1)

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
-- Name: geofaker; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA geofaker;


ALTER SCHEMA geofaker OWNER TO postgres;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: postgres
--

-- *not* creating schema, since initdb creates it


ALTER SCHEMA public OWNER TO postgres;

--
-- Name: staging; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA staging;


ALTER SCHEMA staging OWNER TO postgres;

--
-- Name: pg_stat_statements; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA public;


--
-- Name: EXTENSION pg_stat_statements; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_stat_statements IS 'track planning and execution statistics of all SQL statements executed';


--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry and geography spatial types and functions';


--
-- Name: bıgınt; Type: DOMAIN; Schema: public; Owner: postgres
--

CREATE DOMAIN public."bıgınt" AS bigint;


ALTER DOMAIN public."bıgınt" OWNER TO postgres;

--
-- Name: mpaa_rating; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.mpaa_rating AS ENUM (
    'G',
    'PG',
    'PG-13',
    'R',
    'NC-17',
    'NR'
);


ALTER TYPE public.mpaa_rating OWNER TO postgres;

--
-- Name: year; Type: DOMAIN; Schema: public; Owner: postgres
--

CREATE DOMAIN public.year AS integer
	CONSTRAINT year_check CHECK (((VALUE >= 1901) AND (VALUE <= 2155)));


ALTER DOMAIN public.year OWNER TO postgres;

--
-- Name: n_points_in_polygon(public.geometry, integer); Type: FUNCTION; Schema: geofaker; Owner: postgres
--

CREATE FUNCTION geofaker.n_points_in_polygon(geom public.geometry, num_points integer) RETURNS SETOF public.geometry
    LANGUAGE plpgsql
    AS $$
DECLARE
	target_proportion numeric;
	n_ret integer := 0;
	loops integer := 0;
	x_min float8;
	y_min float8;
	x_max float8;
	y_max float8;
	srid integer;
	rpoint geometry;
BEGIN
	-- Get envelope and SRID of source polygon
	SELECT ST_XMin(geom), ST_YMin(geom), ST_XMax(geom), ST_YMax(geom), ST_SRID(geom)
		INTO x_min, y_min, x_max, y_max, srid;
	-- Get the area proportion of envelope size to determine if a
	-- result can be returned in a reasonable amount of time
	SELECT ST_Area(geom)/ST_Area(ST_Envelope(geom)) INTO target_proportion;
	RAISE DEBUG 'geom: SRID %, NumGeometries %, NPoints %, area proportion within envelope %',
					srid, ST_NumGeometries(geom), ST_NPoints(geom),
					round(100.0*target_proportion, 2) || '%';
	IF target_proportion < 0.0001 THEN
		RAISE EXCEPTION 'Target area proportion of geometry is too low (%)', 
						100.0*target_proportion || '%';
	END IF;
	RAISE DEBUG 'bounds: % % % %', x_min, y_min, x_max, y_max;
	
	WHILE n_ret < num_points LOOP
		loops := loops + 1;
		SELECT ST_SetSRID(ST_MakePoint(random()*(x_max - x_min) + x_min,
									random()*(y_max - y_min) + y_min),
						srid) INTO rpoint;
		IF ST_Contains(geom, rpoint) THEN
		n_ret := n_ret + 1;
		RETURN NEXT rpoint;
		END IF;
	END LOOP;
	RAISE DEBUG 'determined in % loops (% efficiency)', loops, round(100.0*num_points/loops, 2) || '%';
END
$$;


ALTER FUNCTION geofaker.n_points_in_polygon(geom public.geometry, num_points integer) OWNER TO postgres;

--
-- Name: FUNCTION n_points_in_polygon(geom public.geometry, num_points integer); Type: COMMENT; Schema: geofaker; Owner: postgres
--

COMMENT ON FUNCTION geofaker.n_points_in_polygon(geom public.geometry, num_points integer) IS 'Creates N points randomly within the given polygon.  From: https://trac.osgeo.org/postgis/wiki/UserWikiRandomPoint';


--
-- Name: point_in_place_landuse(); Type: PROCEDURE; Schema: geofaker; Owner: postgres
--

CREATE PROCEDURE geofaker.point_in_place_landuse()
    LANGUAGE plpgsql
    AS $$
BEGIN

	-- Define a custom `landuse_osm_types` table before executing to customize areas
	CREATE TEMP TABLE IF NOT EXISTS landuse_osm_types AS
	SELECT 'retail' AS osm_type
	UNION
	SELECT 'commercial' AS osm_type
	;


	-- Basic selection, provide attributes used to rank locations
	DROP TABLE IF EXISTS places_for_shops_1;
	CREATE TEMP TABLE places_for_shops_1 AS
	WITH base AS (
	SELECT osm_id, name, osm_type, admin_level, nest_level,
			-- Rounding is assuming SRID 3857, or another unit in Meters or Feet.
			ROUND(public.ST_Area(geom)::NUMERIC, 0) AS geom_area,
			geom
		FROM osm.place_polygon_nested
		-- Using innermost places to reduce likelihood over overlap
		WHERE innermost
			-- originally had following more strict checks, considering leaving
			-- them off to make more flexible
			/*AND name <> ''
			AND admin_level < 99*/
	), with_space AS (
	-- Within each Place, find how many places are "near" (intersects)
	-- or contain the types of places (commercial, retail, residential, etc)
	-- defined in landuse_osm_types  
	SELECT b.osm_id,
			COUNT(lp.osm_id) AS near_areas,
			COALESCE(SUM(public.ST_Area(lp.geom)), 0) AS near_space,
			COUNT(c.osm_id) AS contained_areas,
			COALESCE(SUM(public.ST_Area(c.geom)), 0) AS contained_space
		FROM base b
		LEFT JOIN osm.landuse_polygon lp
			ON public.ST_Intersects(b.geom, lp.geom)
				AND lp.osm_type IN (SELECT osm_type FROM landuse_osm_types)
		LEFT JOIN osm.landuse_polygon c
			ON public.ST_Contains(b.geom, c.geom)
				AND c.osm_type IN (SELECT osm_type FROM landuse_osm_types)
		GROUP BY b.osm_id
	)
	SELECT b.*, ws.contained_areas, ws.contained_space,
			ws.near_areas, ws.near_space
		FROM base b
		INNER JOIN with_space ws ON b.osm_id = ws.osm_id
	;


	DROP TABLE IF EXISTS places_for_shops;
	CREATE TEMP TABLE places_for_shops AS
	SELECT osm_id, name, osm_type, admin_level, contained_areas, contained_space,
			near_areas, near_space, geom_area,
			contained_space / geom_area AS space_contained_ratio_higher_is_better,
			near_space / geom_area AS space_near_ratio_higher_is_better,
			geom
		FROM places_for_shops_1
		ORDER BY space_contained_ratio_higher_is_better DESC,
				space_near_ratio_higher_is_better DESC
	;


	/*
	* The following scoring logic creates scores for each place depending
	* on how it's contained and nearby landuse data compare to the area's
	* percentile values.
	*/
	DROP TABLE IF EXISTS place_scores;
	CREATE TEMP TABLE place_scores AS
	WITH breakpoints AS (
	-- Calculate percentiles of space available across all available place inputs
	-- This should let each region adjust for the input data
	SELECT percentile_cont(0.25)
				within group (order by contained_space asc)
				as contained_space_25_perc,
			percentile_cont(0.50)
				within group (order by contained_space asc)
				as contained_space_50_perc,
			percentile_cont(0.90)
				within group (order by near_space asc)
				as near_space_90_perc
		FROM places_for_shops
		WHERE near_areas > 0
	)
	SELECT p.osm_id,
			-- Actual ranking is arbitrary, they key is understanding that scores
			-- under a random value in the next step (where random between 0.0 and 1.0)
			-- so increasing the max score here results in some areas almost always
			-- being picked
			CASE WHEN b.contained_space_50_perc < p.contained_space
					THEN .55
				WHEN b.contained_space_25_perc < p.contained_space
					THEN .35
				ELSE .01
			END AS contained_space_score,
			CASE WHEN b.near_space_90_perc < p.near_space
					THEN .1
				ELSE .01
			END AS near_space_score
		FROM places_for_shops p
		INNER JOIN breakpoints b ON True
		-- Excludes places that aren't even nearby (intersects) an appropriate
		-- place type
		WHERE p.near_areas > 0
	;

	DROP TABLE IF EXISTS selected;
	CREATE TEMP TABLE selected AS
	WITH a AS (
	SELECT p.osm_id,
			-- Range of total_score:  .02 - .65
			s.contained_space_score + s.near_space_score
				AS total_score,
			random() as rnd
		FROM places_for_shops p
		INNER JOIN place_scores s
			ON p.osm_id = s.osm_id
	)
	SELECT a.osm_id
		FROM a  
		WHERE a.total_score > a.rnd
	;

	-- Selected areas to put points into.
	DROP TABLE IF EXISTS faker_place_polygon; 
	CREATE TEMP TABLE faker_place_polygon AS
	SELECT p.*
		FROM selected s
		INNER JOIN places_for_shops p ON s.osm_id = p.osm_id
		ORDER BY p.name
	;

	CREATE INDEX gix_faker_place_polygon
		ON faker_place_polygon USING GIST (geom)
	;

	/*
		Ranking roads by osm_type with goal of scoring roads with lower speed
		limits higher.  Uses helper table loaded by PgOSM Flex.

		Uses window function for rank steps, then normalize to 0-1 range.
		Finally, squishes range into 0.05 - 0.90 to prevent guarantees of
		never or always included.
	*/ 
	DROP TABLE IF EXISTS road_osm_type_rank;
	CREATE TEMP TABLE road_osm_type_rank AS
	WITH rank_lower_speed_better AS (
	SELECT osm_type, maxspeed_mph,
			RANK() OVER  (ORDER BY maxspeed_mph desc) AS rnk_raw
		FROM pgosm.road
		WHERE route_motor
			AND osm_type NOT LIKE '%link'
	), aggs_for_normalization AS (
	SELECT MIN(rnk_raw) AS min_rnk, MAX(rnk_raw) AS max_rnk
		FROM rank_lower_speed_better
	), normal_rnk AS (
	SELECT r.osm_type, r.maxspeed_mph,
			(rnk_raw * 1.0 - min_rnk) / (max_rnk - min_rnk)
				AS normalized_rnk
		FROM rank_lower_speed_better r
		JOIN aggs_for_normalization ON True
	)
	SELECT osm_type, maxspeed_mph,
			CASE WHEN normalized_rnk < 0.05 THEN 0.05
				WHEN normalized_rnk > 0.9 THEN .9
				ELSE normalized_rnk
				END AS normalized_rnk
		FROM normal_rnk
	;

	/*
	Identify roads where a building could be
	Not using actual buildings / addresses because:
	    a) privacy
	    b) coverage

	Main limitation of this is the point chosen on the road could extend far
	outside of the landuse.
	As I'm writing these initial versions I don't care, consider splitting road
	lines on the place boundaries to limit in the future if desired.
	*/
	DROP TABLE IF EXISTS selected_roads ;
	CREATE TEMP TABLE selected_roads AS
	WITH road_ranks AS (
	SELECT p.osm_id AS place_osm_id, p.osm_type AS place_osm_type,
			p.name AS place_name,
			rr.normalized_rnk AS road_type_score,
			r.osm_id AS road_osm_id
		FROM faker_place_polygon p
		INNER JOIN osm.landuse_polygon c
			ON public.ST_Contains(p.geom, c.geom)
				AND c.osm_type IN (SELECT osm_type FROM landuse_osm_types)
		INNER JOIN osm.road_line r
			ON c.geom && r.geom
				AND r.route_motor
				AND r.osm_type NOT IN ('service')
				AND r.osm_type NOT LIKE '%link'
		INNER JOIN road_osm_type_rank rr
			ON r.osm_type = rr.osm_type
	), ranked AS (
	SELECT *,
			ROW_NUMBER() OVER (
				PARTITION BY place_osm_id
				ORDER BY road_type_score DESC, random()) AS rnk
		FROM road_ranks
	)
	SELECT *
		FROM ranked
		WHERE rnk = 1
		;


	DROP TABLE IF EXISTS faker_store_location;
	CREATE TEMP TABLE faker_store_location AS
	SELECT ROW_NUMBER() OVER () AS store_id, a.place_name AS city,
			r.name AS street_name, r.ref AS road_ref,
            pgfaker.company(), pgfaker.slogan(), pgfaker.phone(),
			public.ST_LineInterpolatePoint(public.ST_LineMerge(r.geom), random()) AS geom
		FROM selected_roads a
		INNER JOIN osm.road_line r ON a.road_osm_id = r.osm_id
	;


END
$$;


ALTER PROCEDURE geofaker.point_in_place_landuse() OWNER TO postgres;

--
-- Name: PROCEDURE point_in_place_landuse(); Type: COMMENT; Schema: geofaker; Owner: postgres
--

COMMENT ON PROCEDURE geofaker.point_in_place_landuse() IS 'Uses osm.landuse_polygon and osm.road_line to simulate probable locations for commercial store locations.  Can be customized for custom landuse types by manually defining landuse_osm_types temp table.';


--
-- Name: points_around_point(numeric, numeric); Type: PROCEDURE; Schema: geofaker; Owner: postgres
--

CREATE PROCEDURE geofaker.points_around_point(IN _distance_scale numeric DEFAULT 1.0, IN _density_scale numeric DEFAULT 1.0)
    LANGUAGE plpgsql
    AS $$
DECLARE
	stores_to_process BIGINT;
	t_row faker_store_location%rowtype;
BEGIN

	SELECT  COUNT(*) INTO stores_to_process
		FROM faker_store_location
	;
	RAISE NOTICE 'Generating customers for % stores...', stores_to_process;

	DROP TABLE IF EXISTS faker_customer_location;
	CREATE TEMP TABLE faker_customer_location
	(
		id BIGINT NOT NULL GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
		store_id BIGINT NOT NULL,
		customer_id BIGINT NOT NULL,
		full_name TEXT NOT NULL,
		email TEXT NOT NULL,
		phone TEXT NULL,
		geom GEOMETRY(POINT, 3857) NOT NULL
	);


	FOR t_row IN SELECT * FROM faker_store_location LOOP
		IF t_row.store_id % 10 = 0 THEN
			RAISE NOTICE 'Store ID: %', t_row.store_id;
		END IF;

		DROP TABLE IF EXISTS place_buffer;
		CREATE TEMP TABLE place_buffer AS
		WITH buffers AS (
		SELECT store_id, geom,
                ST_Buffer(geom, 5000 * _distance_scale) AS geom_buffer_inner,
                ST_Buffer(geom, 15000 * _distance_scale) AS geom_buffer_middle_tmp,
                ST_Buffer(geom, 30000 * _distance_scale) AS geom_buffer_outer_tmp
			FROM faker_store_location
			WHERE store_id = t_row.store_id
		)
		SELECT store_id, geom, geom_buffer_inner,
		      ST_Difference(geom_buffer_middle_tmp, geom_buffer_inner)
		          AS geom_buffer_middle,
		      ST_Difference(geom_buffer_outer_tmp, geom_buffer_middle_tmp)
                  AS geom_buffer_outer
		  FROM buffers
		;

		DROP TABLE IF EXISTS store_potential_customers;
		CREATE TEMP TABLE store_potential_customers AS
		SELECT store_id,
				geofaker.n_points_in_polygon(geom_buffer_inner, (1000 * _density_scale)::INT )
					AS geom
			FROM place_buffer
		UNION
		SELECT store_id,
				geofaker.n_points_in_polygon(geom_buffer_middle, (300 * _density_scale)::INT )
                    AS geom
            FROM place_buffer
        UNION
        SELECT store_id,
                geofaker.n_points_in_polygon(geom_buffer_outer, (75 * _density_scale)::INT )
                    AS geom
			FROM place_buffer
		;
		ALTER TABLE store_potential_customers
			ADD customer_id BIGINT NOT NULL GENERATED BY DEFAULT AS IDENTITY;


		--EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
		WITH possible_roads AS (
		SELECT p.store_id, p.customer_id, p.geom AS geom_customer,
				r.geom AS geom_road,
				ST_Distance(p.geom, r.geom) AS distance
			FROM osm.road_line r
			INNER JOIN store_potential_customers p
				ON ST_DWithin(r.geom, p.geom, 300)
			WHERE r.route_motor
		), ranked AS (
		SELECT *, ROW_NUMBER() OVER (
					PARTITION BY store_id, customer_id ORDER BY distance
					) AS rnk
			FROM possible_roads
		)
		INSERT INTO faker_customer_location (store_id, customer_id,
				full_name, email, phone, geom)
		SELECT store_id, customer_id,
				pgfaker.person_full_name(), pgfaker.email(),
        		pgfaker.phone(),
				ST_Snap(geom_customer, geom_road, 300) AS geom_snapped
			FROM ranked
			WHERE rnk = 1
		;
		COMMIT;

	END LOOP;

    RAISE NOTICE 'Completed';

END;
$$;


ALTER PROCEDURE geofaker.points_around_point(IN _distance_scale numeric, IN _density_scale numeric) OWNER TO postgres;

--
-- Name: _group_concat(text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public._group_concat(text, text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$
SELECT CASE
  WHEN $2 IS NULL THEN $1
  WHEN $1 IS NULL THEN $2
  ELSE $1 || ', ' || $2
END
$_$;


ALTER FUNCTION public._group_concat(text, text) OWNER TO postgres;

--
-- Name: complete_recent_rentals(); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.complete_recent_rentals()
    LANGUAGE plpgsql
    AS $$
 DECLARE 
	rid int;
	min_interval INTERVAL = '96 hours'::INTERVAL;
 BEGIN

	CREATE TEMPORARY TABLE IF NOT exists tmp_open_rentals (
		rental_id int
	);

	TRUNCATE tmp_open_rentals;

	INSERT INTO tmp_open_rentals 
	SELECT rental_id FROM rental WHERE upper(rental_period) IS NULL 
		AND lower(rental_period) > now()-min_interval;


	ANALYZE tmp_open_rentals;
	-- sample 0.01% of the rows from available customers for the given day 
	-- loop over them and
 	IF EXISTS (SELECT 1 FROM tmp_open_rentals) THEN 
		FOR rid IN (SELECT rental_id FROM tmp_open_rentals TABLESAMPLE bernoulli(random_between(10,20,1)))
	 	LOOP
		 	-- update the rental end period to be between 16 hours and 4 days from initial rental.
		 	UPDATE rental SET rental_period = tstzrange(lower(rental_period), (lower(rental_period) + (random_between(57600,345600)::TEXT || ' seconds')::INTERVAL))
		 	WHERE rental_id = rid;
			 
			COMMIT;
		
			CALL insert_single_payment(rid);
			
	 	end LOOP;
	END IF;
 END;
$$;


ALTER PROCEDURE public.complete_recent_rentals() OWNER TO postgres;

--
-- Name: film_in_stock(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.film_in_stock(p_film_id integer, p_store_id integer, OUT p_film_count integer) RETURNS SETOF integer
    LANGUAGE sql
    AS $_$
     SELECT inventory_id
     FROM inventory
     WHERE film_id = $1
     AND store_id = $2
     AND inventory_in_stock(inventory_id);
$_$;


ALTER FUNCTION public.film_in_stock(p_film_id integer, p_store_id integer, OUT p_film_count integer) OWNER TO postgres;

--
-- Name: film_not_in_stock(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.film_not_in_stock(p_film_id integer, p_store_id integer, OUT p_film_count integer) RETURNS SETOF integer
    LANGUAGE sql
    AS $_$
    SELECT inventory_id
    FROM inventory
    WHERE film_id = $1
    AND store_id = $2
    AND NOT inventory_in_stock(inventory_id);
$_$;


ALTER FUNCTION public.film_not_in_stock(p_film_id integer, p_store_id integer, OUT p_film_count integer) OWNER TO postgres;

--
-- Name: generate_new_rental(); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.generate_new_rental()
    LANGUAGE plpgsql
    AS $$
 DECLARE cus record;
	c_inv int;
	a_inv int[];
	rental_start timestamptz;
    rental_nextday timestamptz;
    rental_range tstzrange;
	sqlstr TEXT;
	cust_percent float4 = .01;
 BEGIN

	CREATE TEMPORARY TABLE tmp_av_customer(LIKE customer INCLUDING ALL);
	CREATE TEMPORARY TABLE tmp_av_inventory (LIKE inventory INCLUDING ALL);

	CREATE INDEX tmp_av_inventory_id ON tmp_av_inventory (inventory_id);

	rental_start = now();
	rental_range = tstzrange(now(),now()+'5 minutes'::INTERVAL);

	-- precautionary
	TRUNCATE tmp_av_customer;
	TRUNCATE tmp_av_inventory; 
	
	IF EXISTS (SELECT 1 FROM public.holiday WHERE holiday_date::timestamptz <@ rental_range) THEN 
		SELECT pct INTO cust_percent FROM random_between(.015,.025,3) x(pct);
	END IF;
	
		-- Get a list of inventory that is currently on loan as of the rental_start day
		-- For new rentals this is a bit faulty as the "rental_start" is a single timestamp
		-- but the start time 
		WITH outstanding_rentals AS (
			SELECT * FROM rental
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
		
			a_inv := array_append(a_inv, c_inv);
			
	 	end LOOP;
	 
	    TRUNCATE tmp_av_customer;
		TRUNCATE tmp_av_inventory; 

		--CALL insert_payments(rental_start::date);
	
		rental_start = rental_nextday;
		
	
		RAISE NOTICE 'Next day: %', rental_start;

 END;
$$;


ALTER PROCEDURE public.generate_new_rental() OWNER TO postgres;

--
-- Name: generate_new_rentals(timestamp with time zone, timestamp with time zone); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.generate_new_rentals(IN data_start timestamp with time zone, IN data_end timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
 DECLARE cus record;
	c_inv int;
	a_inv int[];
	rental_start timestamptz;
    rental_nextday timestamptz;
	sqlstr TEXT;
	cust_percent int = 4;
 BEGIN
	 
	IF data_start > data_end THEN
		RAISE EXCEPTION 'End date must be after start date!';
	END IF;
	
	IF (data_end-data_start) > '365 days'::INTERVAL THEN
		RAISE EXCEPTION 'You can only do one year at time! %', (data_end-data_start);
	END IF;

	rental_start = data_start;

	-- precautionary
	TRUNCATE tmp_av_customer;
	TRUNCATE tmp_av_inventory; 

	WHILE rental_start <= data_end THEN
	LOOP -- daily LOOP FOR rentals
		-- this is used during the INSERT and pulled out here for visibility
		rental_nextday = rental_start + '1 day'::INTERVAL;
		
		RAISE NOTICE 'rental_start: %', rental_start;
		RAISE NOTICE 'data_end: %', data_end;	
	
		IF EXISTS (SELECT 1 FROM public.holiday WHERE holiday_date::timestamptz <@ tstzrange(rental_start,rental_nextday)) THEN 
			SELECT pct INTO cust_percent FROM random_between(4,8);
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
		-- sample 30% of the rows from available customers for the given day 
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
	 
	    TRUNCATE tmp_av_customer;
		TRUNCATE tmp_av_inventory; 

		--CALL insert_payments(rental_start::date);
	
		rental_start = rental_nextday;
		
	
		RAISE NOTICE 'Next day: %', rental_start;
	
	end LOOP; -- WHILE LOOP

 END;
$$;


ALTER PROCEDURE public.generate_new_rentals(IN data_start timestamp with time zone, IN data_end timestamp with time zone) OWNER TO postgres;

--
-- Name: generate_rental_history(timestamp with time zone, timestamp with time zone); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.generate_rental_history(IN data_start timestamp with time zone, IN data_end timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
 DECLARE cus record;
	rental_start timestamptz;
    rental_nextday timestamptz;
	cust_percent float4 = 1.2;
	cid bigint;
 BEGIN
	 
	IF data_start > data_end THEN
		RAISE EXCEPTION 'End date must be after start date!';
	END IF;
	
	IF (data_end-data_start) > '365 days'::INTERVAL THEN
		RAISE EXCEPTION 'You can only do one year at time! %', (data_end-data_start);
	END IF;

	rental_start = data_start;

	CREATE TEMPORARY TABLE IF NOT EXISTS tmp_av_customer(LIKE customer INCLUDING ALL);
	CREATE TEMPORARY TABLE IF NOT EXISTS tmp_av_inventory (LIKE inventory INCLUDING ALL);
	CREATE TEMPORARY TABLE IF NOT EXISTS tmp_rental (LIKE rental INCLUDING ALL);
--
--	CREATE INDEX tmp_av_inventory_id ON tmp_av_inventory (inventory_id);

	-- precautionary
	TRUNCATE tmp_av_customer;
	TRUNCATE tmp_av_inventory; 
	TRUNCATE tmp_rental;

	WHILE rental_start <= data_end THEN
	LOOP -- daily LOOP FOR rentals
		-- this is used during the INSERT and pulled out here for visibility
		rental_nextday = rental_start + '1 day'::INTERVAL;
		SELECT pct INTO cust_percent FROM random_between(0.8,1.9,3) x(pct);
		
		RAISE NOTICE 'rental_start: %', rental_start;
		RAISE NOTICE 'rental_nextday: %', rental_nextday;
	--	RAISE NOTICE 'data_end: %', data_end;	

		IF EXISTS (SELECT 1 FROM public.holiday WHERE holiday_date::timestamptz <@ tstzrange(rental_start,rental_nextday)) THEN 
			SELECT pct INTO cust_percent FROM random_between(2.6,3.6,3) x(pct);
		END IF;
	
		RAISE NOTICE 'customer pct: %', cust_percent;		
	
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
		--SELECT * FROM available_inventory;
		-- get a list of customers that do not currently have a video on loan
		-- as of today
		INSERT INTO tmp_av_customer
		SELECT c.* FROM customer c
		 	LEFT JOIN outstanding_rentals o using(customer_id)
		WHERE o.customer_id IS NULL;
		 
		ANALYZE tmp_av_inventory;
		ANALYZE tmp_av_customer;
		-- sample 3% of the rows from available customers for the given day 
		-- loop over them and
	 	
		WITH t_customer AS (
			SELECT customer_id, store_id FROM tmp_av_customer TABLESAMPLE bernoulli(cust_percent)
		),
		t_inv AS (
		 	-- This is not efficient on larger tables. For a small table like this
		 	-- using 'random()' to order is faster and easier than a multi-step search
		 	SELECT inventory_id, store_id FROM tmp_av_inventory
		 	ORDER BY random()
		)
		INSERT INTO tmp_rental (rental_period, inventory_id, customer_id, staff_id)
		SELECT tstzrange((rental_start + trunc(random() * 1439) * '1 minute'::INTERVAL),(rental_nextday + trunc(random() * 4320) * '1 minute'::INTERVAL)) rental_period,
					t_inv.inventory_id,
					tc.customer_id,
		--				timestamptz(rental_nextday + trunc(random() * 4320) * '1 minute'::INTERVAL) return_date,
					1 staff_id
		FROM t_customer tc
		inner join t_inv USING (store_id);	

		FOR cid IN (SELECT DISTINCT(customer_id) FROM tmp_rental)
	 	LOOP	
	 		INSERT INTO rental (rental_period, inventory_id, customer_id, staff_id)
	 		SELECT rental_period, inventory_id, customer_id, staff_id
	 		FROM tmp_rental
	 		WHERE customer_id = cid
	 		LIMIT 1;
	 	END LOOP;
		

	
	    COMMIT;
	    TRUNCATE tmp_av_customer;
		TRUNCATE tmp_av_inventory;
		TRUNCATE tmp_rental;
		
		CALL insert_payments(rental_start::date);
	
		rental_start = rental_nextday;
		
	
		RAISE NOTICE 'Next day: %', rental_start;
	
	end LOOP; -- WHILE LOOP

 END;
$$;


ALTER PROCEDURE public.generate_rental_history(IN data_start timestamp with time zone, IN data_end timestamp with time zone) OWNER TO postgres;

--
-- Name: get_customer_balance(integer, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_customer_balance(p_customer_id integer, p_effective_date timestamp with time zone) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
       --#OK, WE NEED TO CALCULATE THE CURRENT BALANCE GIVEN A CUSTOMER_ID AND A DATE
       --#THAT WE WANT THE BALANCE TO BE EFFECTIVE FOR. THE BALANCE IS:
       --#   1) RENTAL FEES FOR ALL PREVIOUS RENTALS
       --#   2) ONE DOLLAR FOR EVERY DAY THE PREVIOUS RENTALS ARE OVERDUE
       --#   3) IF A FILM IS MORE THAN RENTAL_DURATION * 2 OVERDUE, CHARGE THE REPLACEMENT_COST
       --#   4) SUBTRACT ALL PAYMENTS MADE BEFORE THE DATE SPECIFIED
DECLARE
    v_rentfees DECIMAL(5,2); --#FEES PAID TO RENT THE VIDEOS INITIALLY
    v_overfees INTEGER;      --#LATE FEES FOR PRIOR RENTALS
    v_payments DECIMAL(5,2); --#SUM OF PAYMENTS MADE PREVIOUSLY
BEGIN
    SELECT COALESCE(SUM(film.rental_rate),0) INTO v_rentfees
    FROM film, inventory, rental
    WHERE film.film_id = inventory.film_id
      AND inventory.inventory_id = rental.inventory_id
      AND rental.rental_date <= p_effective_date
      AND rental.customer_id = p_customer_id;

    SELECT COALESCE(SUM(IF((rental.return_date - rental.rental_date) > (film.rental_duration * '1 day'::interval),
        ((rental.return_date - rental.rental_date) - (film.rental_duration * '1 day'::interval)),0)),0) INTO v_overfees
    FROM rental, inventory, film
    WHERE film.film_id = inventory.film_id
      AND inventory.inventory_id = rental.inventory_id
      AND rental.rental_date <= p_effective_date
      AND rental.customer_id = p_customer_id;

    SELECT COALESCE(SUM(payment.amount),0) INTO v_payments
    FROM payment
    WHERE payment.payment_date <= p_effective_date
    AND payment.customer_id = p_customer_id;

    RETURN v_rentfees + v_overfees - v_payments;
END
$$;


ALTER FUNCTION public.get_customer_balance(p_customer_id integer, p_effective_date timestamp with time zone) OWNER TO postgres;

--
-- Name: get_inventory(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_inventory() RETURNS TABLE(film_id bigint, popularity real, total_i integer[], x numeric)
    LANGUAGE plpgsql
    AS $$
BEGIN
	RETURN query 
	WITH inventory_tmp (film_id, popularity, total_i, release_date) AS (
	SELECT f.film_id, f.popularity, CASE
		WHEN f.popularity <= 20 THEN ARRAY[0,2]
		WHEN f.popularity BETWEEN 20 AND 35 THEN ARRAY[0,2]
		WHEN f.popularity BETWEEN 35 AND 75 THEN ARRAY[1,3]
		WHEN f.popularity BETWEEN 75 AND 100 THEN ARRAY[2,6]
		WHEN f.popularity BETWEEN 100 AND 500 THEN ARRAY[3,6]
		WHEN f.popularity >500 THEN ARRAY[6,10]
		END,
		release_date
	FROM film f
),
adjusted_inventory AS (
	SELECT it.film_id, it.popularity, 
	CASE 
		WHEN release_date > now()-'1 year'::INTERVAL THEN it.total_i
		WHEN release_date BETWEEN now()-'3 years'::INTERVAL AND now()-'1 year'::INTERVAL THEN
			array_agg(greatest(val-1,0))
		WHEN release_date BETWEEN now()-'4 years'::INTERVAL AND now()-'3 year'::INTERVAL THEN
			array_agg(greatest(val-2,0))
		WHEN release_date < now()-'3 years'::INTERVAL THEN
			array_agg(greatest(val-3,0))
	END AS total_i
	FROM inventory_tmp it, unnest(it.total_i) AS val
	GROUP BY it.film_id, it.popularity, it.release_date, it.total_i
)
SELECT ai.film_id, ai.popularity, ai.total_i, x.i FROM adjusted_inventory ai, random_between(ai.total_i[1],ai.total_i[2]) x(i);

END; $$;


ALTER FUNCTION public.get_inventory() OWNER TO postgres;

--
-- Name: insert_payments(date); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.insert_payments(IN rd date)
    LANGUAGE plpgsql
    AS $$	
 DECLARE
 	rental_rate float4 = 1.99;
 BEGIN 
	WITH payment_info AS (
		SELECT r.rental_id, rental_period, GREATEST(CEILING(EXTRACT(epoch from (upper(rental_period)-lower(rental_period)))/3600/24),1) rental_days,
			inventory_id, r.customer_id, r.staff_id, upper(rental_period) AS payment_date
		FROM rental r
			INNER JOIN inventory i USING(inventory_id)
			INNER JOIN film f USING(film_id)
			LEFT JOIN payment p ON r.rental_id = p.rental_id
		WHERE lower(rental_period) >= rd AND lower(rental_period) <= rd+'5 days'::INTERVAL
		AND p.rental_id IS NULL 
	)
	INSERT INTO payment (customer_id, staff_id, rental_id, amount, payment_date)
	SELECT customer_id, staff_id, rental_id, rental_days*rental_rate AS amount, payment_date
		FROM payment_info;
	
	END;
$$;


ALTER PROCEDURE public.insert_payments(IN rd date) OWNER TO postgres;

--
-- Name: insert_single_payment(integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.insert_single_payment(IN rid integer)
    LANGUAGE plpgsql
    AS $$	
 DECLARE
 	rental_rate float4 = 1.99;
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
	SELECT customer_id, staff_id, rental_id, rental_days*rental_rate AS amount, payment_date
		FROM payment_info;
	
	END;
$$;


ALTER PROCEDURE public.insert_single_payment(IN rid integer) OWNER TO postgres;

--
-- Name: inventory_held_by_customer(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.inventory_held_by_customer(p_inventory_id integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_customer_id INTEGER;
BEGIN

  SELECT customer_id INTO v_customer_id
  FROM rental
  WHERE return_date IS NULL
  AND inventory_id = p_inventory_id;

  RETURN v_customer_id;
END $$;


ALTER FUNCTION public.inventory_held_by_customer(p_inventory_id integer) OWNER TO postgres;

--
-- Name: inventory_in_stock(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.inventory_in_stock(p_inventory_id integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_rentals INTEGER;
    v_out     INTEGER;
BEGIN
    -- AN ITEM IS IN-STOCK IF THERE ARE EITHER NO ROWS IN THE rental TABLE
    -- FOR THE ITEM OR ALL ROWS HAVE return_date POPULATED

    SELECT count(*) INTO v_rentals
    FROM rental
    WHERE inventory_id = p_inventory_id;

    IF v_rentals = 0 THEN
      RETURN TRUE;
    END IF;

    SELECT COUNT(rental_id) INTO v_out
    FROM inventory LEFT JOIN rental USING(inventory_id)
    WHERE inventory.inventory_id = p_inventory_id
    AND rental.return_date IS NULL;

    IF v_out > 0 THEN
      RETURN FALSE;
    ELSE
      RETURN TRUE;
    END IF;
END $$;


ALTER FUNCTION public.inventory_in_stock(p_inventory_id integer) OWNER TO postgres;

--
-- Name: last_day(timestamp with time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.last_day(timestamp with time zone) RETURNS date
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
  SELECT CASE
    WHEN EXTRACT(MONTH FROM $1) = 12 THEN
      (((EXTRACT(YEAR FROM $1) + 1) operator(pg_catalog.||) '-01-01')::date - INTERVAL '1 day')::date
    ELSE
      ((EXTRACT(YEAR FROM $1) operator(pg_catalog.||) '-' operator(pg_catalog.||) (EXTRACT(MONTH FROM $1) + 1) operator(pg_catalog.||) '-01')::date - INTERVAL '1 day')::date
    END
$_$;


ALTER FUNCTION public.last_day(timestamp with time zone) OWNER TO postgres;

--
-- Name: last_updated(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.last_updated() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.last_update = CURRENT_TIMESTAMP;
    RETURN NEW;
END $$;


ALTER FUNCTION public.last_updated() OWNER TO postgres;

--
-- Name: random_between(numeric, numeric, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.random_between(min_val numeric, max_val numeric, round_to integer DEFAULT 0) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
 DECLARE
 	value NUMERIC = random()* (min_val - max_val) + max_val;
BEGIN
   IF round_to = 0 THEN 
	 RETURN floor(value);
   ELSE 
   	 RETURN round(value,round_to);
   END IF;
END
$$;


ALTER FUNCTION public.random_between(min_val numeric, max_val numeric, round_to integer) OWNER TO postgres;

--
-- Name: transform_credits(); Type: PROCEDURE; Schema: staging; Owner: postgres
--

CREATE PROCEDURE staging.transform_credits()
    LANGUAGE plpgsql
    AS $$	
 BEGIN 
	WITH cast_temp AS (
		SELECT film_id, (x->>'id')::bigint id, 1 credit_type, (x->>'gender')::int gender, x->>'character' "character", NULL department, NULL job FROM staging.film_credits, jsonb_array_elements("cast") x
	)
	INSERT INTO staging.film_cast
	SELECT film_id, id, "character" FROM cast_temp
	ON CONFLICT ON CONSTRAINT film_cast_pk DO NOTHING;
	
	WITH crew_temp AS ( 
		SELECT film_id, (x->>'id')::bigint id, 2 credit_type, (x->>'gender')::int gender,  NULL "character", x->>'department' department, x->>'job' job FROM staging.film_credits, jsonb_array_elements("crew") x
	)
	INSERT INTO staging.film_crew
	SELECT film_id, id, department, job FROM crew_temp
	ON CONFLICT ON CONSTRAINT film_crew_pk DO NOTHING; 
	
	END;
$$;


ALTER PROCEDURE staging.transform_credits() OWNER TO postgres;

--
-- Name: transform_film_details(); Type: PROCEDURE; Schema: staging; Owner: postgres
--

CREATE PROCEDURE staging.transform_film_details()
    LANGUAGE plpgsql
    AS $$	
 BEGIN 
	WITH production_companies AS (
		SELECT film_id, (x->>'id')::int id, x->>'name' "name" FROM staging.film_detail, jsonb_array_elements(production_companies) x
		WHERE processed IS FALSE 
	),
	save_production_company AS (
		INSERT INTO public.production_company
		SELECT id, "name" FROM production_companies
		ON CONFLICT (production_company_id) DO NOTHING
	)
	INSERT INTO public.film_production_company
	SELECT film_id, id FROM production_companies
	ON CONFLICT ON CONSTRAINT film_production_company_pk DO NOTHING;
	
	END;
$$;


ALTER PROCEDURE staging.transform_film_details() OWNER TO postgres;

--
-- Name: group_concat(text); Type: AGGREGATE; Schema: public; Owner: postgres
--

CREATE AGGREGATE public.group_concat(text) (
    SFUNC = public._group_concat,
    STYPE = text
);


ALTER AGGREGATE public.group_concat(text) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: customer; Type: TABLE; Schema: geofaker; Owner: postgres
--

CREATE TABLE geofaker.customer (
    id bigint,
    store_id bigint,
    customer_id bigint,
    full_name text,
    email text,
    phone text,
    geom public.geometry(Point,3857),
    geog public.geography(Point,4326),
    zip_code integer
);


ALTER TABLE geofaker.customer OWNER TO postgres;

--
-- Name: TABLE customer; Type: COMMENT; Schema: geofaker; Owner: postgres
--

COMMENT ON TABLE geofaker.customer IS 'Created by Geo Faker, a PgOSM Flex based project.';


--
-- Name: store; Type: TABLE; Schema: geofaker; Owner: postgres
--

CREATE TABLE geofaker.store (
    store_id bigint,
    city text,
    street_name text,
    road_ref text,
    company text,
    slogan text,
    phone text,
    geom public.geometry,
    geog public.geography(Point,4326),
    zip_code integer
);


ALTER TABLE geofaker.store OWNER TO postgres;

--
-- Name: TABLE store; Type: COMMENT; Schema: geofaker; Owner: postgres
--

COMMENT ON TABLE geofaker.store IS 'Created by Geo Faker, a PgOSM Flex based project.';


--
-- Name: actor_actor_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.actor_actor_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.actor_actor_id_seq OWNER TO postgres;

--
-- Name: address_address_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.address_address_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.address_address_id_seq OWNER TO postgres;

--
-- Name: category_category_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.category_category_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.category_category_id_seq OWNER TO postgres;

--
-- Name: city_city_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.city_city_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.city_city_id_seq OWNER TO postgres;

--
-- Name: country_country_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.country_country_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.country_country_id_seq OWNER TO postgres;

--
-- Name: customer; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.customer (
    customer_id bigint NOT NULL,
    store_id integer NOT NULL,
    full_name text NOT NULL,
    email text,
    phone text,
    zip_code integer,
    activebool boolean DEFAULT true NOT NULL,
    create_date date DEFAULT CURRENT_DATE NOT NULL,
    geog public.geography(Point,4326),
    last_update timestamp with time zone DEFAULT now()
);


ALTER TABLE public.customer OWNER TO postgres;

--
-- Name: customer_customer_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.customer_customer_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.customer_customer_id_seq OWNER TO postgres;

--
-- Name: film; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.film (
    film_id bigint NOT NULL,
    title text NOT NULL,
    overview text NOT NULL,
    release_date date,
    genre_ids integer[],
    original_language text,
    rating public.mpaa_rating,
    popularity real,
    vote_count integer,
    vote_average real,
    budget bigint,
    revenue bigint,
    runtime integer,
    fulltext tsvector GENERATED ALWAYS AS (to_tsvector('english'::regconfig, ((COALESCE(title, ''::text) || ' '::text) || COALESCE(overview, ''::text)))) STORED
);


ALTER TABLE public.film OWNER TO postgres;

--
-- Name: film_cast; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.film_cast (
    film_id bigint NOT NULL,
    person_id bigint NOT NULL,
    film_character text NOT NULL
);


ALTER TABLE public.film_cast OWNER TO postgres;

--
-- Name: film_crew; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.film_crew (
    film_id bigint NOT NULL,
    person_id bigint NOT NULL,
    department text,
    job text
);


ALTER TABLE public.film_crew OWNER TO postgres;

--
-- Name: film_film_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.film_film_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.film_film_id_seq OWNER TO postgres;

--
-- Name: film_production_company; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.film_production_company (
    film_id bigint NOT NULL,
    production_company_id bigint NOT NULL
);


ALTER TABLE public.film_production_company OWNER TO postgres;

--
-- Name: genre; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.genre (
    genre_id integer NOT NULL,
    name text
);


ALTER TABLE public.genre OWNER TO postgres;

--
-- Name: genre_genre_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.genre ALTER COLUMN genre_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.genre_genre_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: holiday; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.holiday (
    id bigint NOT NULL,
    holiday_name text,
    is_paid_time_off boolean,
    holiday_date date
);


ALTER TABLE public.holiday OWNER TO postgres;

--
-- Name: inventory_inventory_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.inventory_inventory_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.inventory_inventory_id_seq OWNER TO postgres;

--
-- Name: inventory; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.inventory (
    inventory_id integer DEFAULT nextval('public.inventory_inventory_id_seq'::regclass) NOT NULL,
    film_id integer NOT NULL,
    store_id integer NOT NULL,
    last_update timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.inventory OWNER TO postgres;

--
-- Name: language_language_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.language_language_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.language_language_id_seq OWNER TO postgres;

--
-- Name: language; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.language (
    language_id integer DEFAULT nextval('public.language_language_id_seq'::regclass) NOT NULL,
    name character(20) NOT NULL,
    last_update timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.language OWNER TO postgres;

--
-- Name: payment_payment_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.payment_payment_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.payment_payment_id_seq OWNER TO postgres;

--
-- Name: payment; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.payment (
    payment_id integer DEFAULT nextval('public.payment_payment_id_seq'::regclass) NOT NULL,
    customer_id integer NOT NULL,
    staff_id integer NOT NULL,
    rental_id integer NOT NULL,
    amount numeric(5,2) NOT NULL,
    payment_date timestamp with time zone NOT NULL
);


ALTER TABLE public.payment OWNER TO postgres;

--
-- Name: person; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.person (
    person_id bigint NOT NULL,
    name text NOT NULL,
    also_known_as text[],
    birth_date date,
    death_date date,
    gender integer,
    popularity real,
    imdb_id text,
    biography text
);


ALTER TABLE public.person OWNER TO postgres;

--
-- Name: person_person_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.person ALTER COLUMN person_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.person_person_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: production_company; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.production_company (
    production_company_id bigint NOT NULL,
    production_company_name text NOT NULL
);


ALTER TABLE public.production_company OWNER TO postgres;

--
-- Name: release_type; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.release_type (
    release_type_id integer NOT NULL,
    release_type text NOT NULL
);


ALTER TABLE public.release_type OWNER TO postgres;

--
-- Name: rental; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.rental (
    rental_id bigint NOT NULL,
    rental_period tstzrange,
    inventory_id integer NOT NULL,
    customer_id integer NOT NULL,
    staff_id integer NOT NULL,
    last_update timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.rental OWNER TO postgres;

--
-- Name: rental_rental_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.rental_rental_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.rental_rental_id_seq OWNER TO postgres;

--
-- Name: rental_rental_id_seq1; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.rental ALTER COLUMN rental_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.rental_rental_id_seq1
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: staff_staff_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.staff_staff_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.staff_staff_id_seq OWNER TO postgres;

--
-- Name: staff; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.staff (
    staff_id integer DEFAULT nextval('public.staff_staff_id_seq'::regclass) NOT NULL,
    first_name text NOT NULL,
    last_name text NOT NULL,
    address_id integer NOT NULL,
    email text,
    store_id integer NOT NULL,
    active boolean DEFAULT true NOT NULL,
    username text NOT NULL,
    password text,
    last_update timestamp with time zone DEFAULT now() NOT NULL,
    picture bytea
);


ALTER TABLE public.staff OWNER TO postgres;

--
-- Name: store; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.store (
    store_id bigint NOT NULL,
    street_name text,
    road_ref text,
    phone text,
    zip_code integer,
    geog public.geography(Point,4326)
);


ALTER TABLE public.store OWNER TO postgres;

--
-- Name: store_store_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.store_store_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.store_store_id_seq OWNER TO postgres;

--
-- Name: us_postal_code; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.us_postal_code (
    zip integer,
    lat real,
    lng real,
    city character varying(50),
    state_id character varying(50),
    state_name character varying(50),
    zcta boolean,
    parent_zcta character varying(50),
    population integer,
    density real,
    county_fips integer,
    county_name character varying(50),
    county_weights character varying(128),
    county_names_all character varying(64),
    county_fips_all character varying(50),
    imprecise boolean,
    military boolean,
    timezone character varying(50),
    geog public.geography(Point,4326)
);


ALTER TABLE public.us_postal_code OWNER TO postgres;

--
-- Name: film_cast; Type: TABLE; Schema: staging; Owner: postgres
--

CREATE TABLE staging.film_cast (
    film_id bigint NOT NULL,
    person_id bigint NOT NULL,
    film_character text NOT NULL
);


ALTER TABLE staging.film_cast OWNER TO postgres;

--
-- Name: film_credits; Type: TABLE; Schema: staging; Owner: postgres
--

CREATE TABLE staging.film_credits (
    film_id bigint NOT NULL,
    "cast" jsonb,
    crew jsonb
);


ALTER TABLE staging.film_credits OWNER TO postgres;

--
-- Name: film_crew; Type: TABLE; Schema: staging; Owner: postgres
--

CREATE TABLE staging.film_crew (
    film_id bigint NOT NULL,
    person_id bigint NOT NULL,
    department text,
    job text
);


ALTER TABLE staging.film_crew OWNER TO postgres;

--
-- Name: film_detail; Type: TABLE; Schema: staging; Owner: postgres
--

CREATE TABLE staging.film_detail (
    film_id bigint,
    budget bigint,
    revenue bigint,
    runtime integer,
    production_companies jsonb,
    processed boolean DEFAULT false
);


ALTER TABLE staging.film_detail OWNER TO postgres;

--
-- Name: holiday; Type: TABLE; Schema: staging; Owner: postgres
--

CREATE TABLE staging.holiday (
    id bigint NOT NULL,
    region text,
    holiday_name text,
    normalized_name text,
    is_paid_time_off boolean,
    country_region_code text,
    holiday_date date
);


ALTER TABLE staging.holiday OWNER TO postgres;

--
-- Name: release_date; Type: TABLE; Schema: staging; Owner: postgres
--

CREATE TABLE staging.release_date (
    film_id bigint,
    releases jsonb
);


ALTER TABLE staging.release_date OWNER TO postgres;

--
-- Name: customer customer_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customer
    ADD CONSTRAINT customer_pkey PRIMARY KEY (customer_id);


--
-- Name: film_cast film_cast_pk; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.film_cast
    ADD CONSTRAINT film_cast_pk PRIMARY KEY (film_id, person_id);


--
-- Name: film_crew film_crew_pk; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.film_crew
    ADD CONSTRAINT film_crew_pk PRIMARY KEY (film_id, person_id);


--
-- Name: film film_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.film
    ADD CONSTRAINT film_pkey PRIMARY KEY (film_id);


--
-- Name: film_production_company film_production_company_pk; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.film_production_company
    ADD CONSTRAINT film_production_company_pk PRIMARY KEY (film_id, production_company_id);


--
-- Name: genre genre_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.genre
    ADD CONSTRAINT genre_pkey PRIMARY KEY (genre_id);


--
-- Name: payment payment_bak_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payment
    ADD CONSTRAINT payment_bak_pkey PRIMARY KEY (payment_date, payment_id);


--
-- Name: person person_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.person
    ADD CONSTRAINT person_pkey PRIMARY KEY (person_id);


--
-- Name: production_company production_company_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.production_company
    ADD CONSTRAINT production_company_pkey PRIMARY KEY (production_company_id);


--
-- Name: release_type release_type_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.release_type
    ADD CONSTRAINT release_type_pkey PRIMARY KEY (release_type_id);


--
-- Name: rental rental_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rental
    ADD CONSTRAINT rental_pkey PRIMARY KEY (rental_id);


--
-- Name: store store_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.store
    ADD CONSTRAINT store_pkey PRIMARY KEY (store_id);


--
-- Name: film_cast film_cast_pk; Type: CONSTRAINT; Schema: staging; Owner: postgres
--

ALTER TABLE ONLY staging.film_cast
    ADD CONSTRAINT film_cast_pk PRIMARY KEY (film_id, person_id);


--
-- Name: film_credits film_credits_pkey; Type: CONSTRAINT; Schema: staging; Owner: postgres
--

ALTER TABLE ONLY staging.film_credits
    ADD CONSTRAINT film_credits_pkey PRIMARY KEY (film_id);


--
-- Name: film_crew film_crew_pk; Type: CONSTRAINT; Schema: staging; Owner: postgres
--

ALTER TABLE ONLY staging.film_crew
    ADD CONSTRAINT film_crew_pk PRIMARY KEY (film_id, person_id);


--
-- Name: geofaker_customer_geog_gix; Type: INDEX; Schema: geofaker; Owner: postgres
--

CREATE INDEX geofaker_customer_geog_gix ON geofaker.customer USING gist (geog);


--
-- Name: geofaker_store_geog_gix; Type: INDEX; Schema: geofaker; Owner: postgres
--

CREATE INDEX geofaker_store_geog_gix ON geofaker.store USING gist (geog);


--
-- Name: film_fulltext_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX film_fulltext_idx ON public.film USING gin (fulltext);


--
-- Name: us_postal_code_geog_gix; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX us_postal_code_geog_gix ON public.us_postal_code USING gist (geog);


--
-- Name: stg_cast_idx_person_id; Type: INDEX; Schema: staging; Owner: postgres
--

CREATE INDEX stg_cast_idx_person_id ON staging.film_cast USING btree (person_id);


--
-- Name: stg_crew_idx_person_id; Type: INDEX; Schema: staging; Owner: postgres
--

CREATE INDEX stg_crew_idx_person_id ON staging.film_crew USING btree (person_id);


--
-- Name: film_cast film_cast_film_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.film_cast
    ADD CONSTRAINT film_cast_film_id_fkey FOREIGN KEY (film_id) REFERENCES public.film(film_id) ON DELETE CASCADE;


--
-- Name: film_cast film_cast_person_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.film_cast
    ADD CONSTRAINT film_cast_person_id_fkey FOREIGN KEY (person_id) REFERENCES public.person(person_id) ON DELETE CASCADE;


--
-- Name: film_crew film_crew_film_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.film_crew
    ADD CONSTRAINT film_crew_film_id_fkey FOREIGN KEY (film_id) REFERENCES public.film(film_id) ON DELETE CASCADE;


--
-- Name: film_crew film_crew_person_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.film_crew
    ADD CONSTRAINT film_crew_person_id_fkey FOREIGN KEY (person_id) REFERENCES public.person(person_id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

