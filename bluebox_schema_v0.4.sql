--
-- PostgreSQL database dump
--

-- Dumped from database version 17.6 (Debian 17.6-1.pgdg12+1)
-- Dumped by pg_dump version 17.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: bluebox; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA bluebox;


--
-- Name: staging; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA staging;


--
-- Name: topology; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA topology;


--
-- Name: SCHEMA topology; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA topology IS 'PostGIS Topology schema';


--
-- Name: pg_stat_statements; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA public;


--
-- Name: EXTENSION pg_stat_statements; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_stat_statements IS 'track planning and execution statistics of all SQL statements executed';


--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry and geography spatial types and functions';


--
-- Name: mpaa_rating; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.mpaa_rating AS ENUM (
    'G',
    'PG',
    'PG-13',
    'R',
    'NC-17',
    'NR'
);


--
-- Name: year; Type: DOMAIN; Schema: public; Owner: -
--

CREATE DOMAIN public.year AS integer
	CONSTRAINT year_check CHECK (((VALUE >= 1901) AND (VALUE <= 2155)));


--
-- Name: add_new_inventory(); Type: PROCEDURE; Schema: bluebox; Owner: -
--

CREATE PROCEDURE bluebox.add_new_inventory()
    LANGUAGE plpgsql
    AS $$
DECLARE
	storeid int;
	maxrd date;
BEGIN 
	/*
 * This query was a first attempt to fill the inventory
 * table with some kind relevance - ie. newer, popular movies
 * get more copies than older or less popular movies.
 */
	FOR storeid IN SELECT store_id FROM bluebox.store
	LOOP
		SELECT max(release_date) INTO maxrd FROM bluebox.inventory i
			JOIN bluebox.film f USING(film_id)
		WHERE store_id=storeid;
		
		WITH inventory_tmp (film_id, popularity, total_i, release_date) AS (
			SELECT f.film_id, f.popularity, CASE
				WHEN f.popularity <= 20 THEN ARRAY[0,3]
				WHEN f.popularity BETWEEN 20 AND 35 THEN ARRAY[0,5]
				WHEN f.popularity BETWEEN 35 AND 75 THEN ARRAY[2,6]
				WHEN f.popularity BETWEEN 75 AND 100 THEN ARRAY[5,8]
				WHEN f.popularity BETWEEN 100 AND 500 THEN ARRAY[8,12]
				WHEN f.popularity >500 THEN ARRAY[12,20]
				END,
				release_date
			FROM bluebox.film f
				WHERE film_id NOT IN (SELECT count(DISTINCT film_id) FROM bluebox.inventory WHERE store_id=storeid)
					AND release_date > maxrd
		),
		adjusted_inventory AS (
			SELECT it.film_id, it.popularity, 
			CASE 
				WHEN release_date > now()-'1 year'::INTERVAL THEN it.total_i
				WHEN release_date BETWEEN now()-'3 years'::INTERVAL AND now()-'1 year'::INTERVAL THEN
					array_agg(greatest(val-1,0))
				WHEN release_date BETWEEN now()-'4 years'::INTERVAL AND now()-'3 year'::INTERVAL THEN
					array_agg(greatest(val-2,0))
				WHEN release_date < now()-'4 years'::INTERVAL THEN
					array_agg(greatest(val-3,0))
			END AS total_i
			FROM inventory_tmp it, unnest(it.total_i) AS val
			GROUP BY it.film_id, it.popularity, it.release_date, it.total_i
		)
--		SELECT * FROM adjusted_inventory;
		INSERT INTO bluebox.inventory (film_id, store_id)
		SELECT film_id, storeid
		FROM adjusted_inventory ai, random_between(ai.total_i[1],ai.total_i[2]) x(i), generate_series(1,x.i)
		WHERE x.i>0;

	COMMIT;
	END LOOP;
END;
$$;


--
-- Name: complete_recent_rentals(interval, integer); Type: PROCEDURE; Schema: bluebox; Owner: -
--

CREATE PROCEDURE bluebox.complete_recent_rentals(IN min_rental_interval interval DEFAULT '24:00:00'::interval, IN max_store_dist integer DEFAULT 25000)
    LANGUAGE plpgsql
    AS $_$
 DECLARE 
	pid int;
 	rid int;
	cus_id int;
	inv_id int;
	sid int;
	r_sid int;
	tmp_rental_tablename TEXT;
	sqlstr TEXT;
 BEGIN
	 
	SELECT pg_backend_pid() INTO pid; 
	
	tmp_rental_tablename = 'tmp_open_rentals_' || pid::TEXT;
 
	RAISE NOTICE '%',tmp_rental_tablename;

	EXECUTE FORMAT($$CREATE TEMPORARY TABLE %1$I (
		rental_id int,
		customer_id int,
		inventory_id int,
		store_id int
	);$$,tmp_rental_tablename);


	EXECUTE FORMAT($$INSERT INTO %1$I 
	SELECT rental_id, customer_id, inventory_id, store_id FROM bluebox.rental WHERE upper(rental_period) IS NULL 
		AND lower(rental_period) < now()-%2$L::INTERVAL;$$,tmp_rental_tablename,min_rental_interval);


	EXECUTE 'ANALYZE ' || tmp_rental_tablename;
	-- sample 0.01% of the rows from available customers for the given day 
	-- loop over them and

	FOR rid,cus_id,inv_id,r_sid IN EXECUTE FORMAT('SELECT rental_id, customer_id, inventory_id,store_id FROM %1$I TABLESAMPLE bernoulli(random_between(10,20,1))',tmp_rental_tablename)
 	LOOP
	 	-- update the rental end period to be between 16 hours and 4 days from initial rental.
	 	-- end the rental between 16 hours and 96 hours after start
	 	UPDATE bluebox.rental SET rental_period = tstzrange(lower(rental_period), (lower(rental_period) + (random_between(57600,345600)::TEXT || ' seconds')::INTERVAL))
	 	WHERE rental_id = rid;
	 
	 	-- Find a store that's within the specified distance. This will give some randomness
	 	-- to the rental locations for each customer
	 	WITH store_inv AS (
			SELECT s.store_id, ST_Distance(s.geog,cus.geog) dist FROM bluebox.store s,
				bluebox.customer cus
			WHERE ST_DWithin(s.geog,cus.geog,max_store_dist)
				AND cus.customer_id = cus_id
			ORDER BY random()
			LIMIT 1
		)
		SELECT store_id INTO sid FROM store_inv;
	
		IF sid IS NULL THEN
			sid := r_sid;
		END IF;
	
        UPDATE bluebox.inventory SET store_id = sid
		WHERE inventory_id = inv_id; 
		
		COMMIT;
		
		sid:=NULL;
	
		CALL bluebox.insert_single_payment(rid);
		
 	end LOOP;	 
	 
 	EXECUTE 'DROP TABLE ' || tmp_rental_tablename;


 END;
$_$;


--
-- Name: generate_individual_rental(integer); Type: PROCEDURE; Schema: bluebox; Owner: -
--

CREATE PROCEDURE bluebox.generate_individual_rental(IN max_store_dist integer DEFAULT 25000)
    LANGUAGE plpgsql
    AS $$
 DECLARE cus record;
	c_id int;
	c_sid int;
	inv_id int;
	rental_start timestamptz;
    rental_nextday timestamptz;
    rental_range tstzrange;
	sqlstr TEXT;
	pid int;
	tmp_cust_tablename TEXT;
	tmp_inv_tablename TEXT;
 BEGIN

	rental_start = now();
	
	-- Get a random customer to rent a movie for
	SELECT customer_id INTO c_id FROM customer 
		WHERE customer_id NOT IN (SELECT customer_id from rental WHERE rental_period @> rental_start)
		ORDER BY random()
		LIMIT 1;
	
	
	WITH rental_store AS (
		SELECT s.store_id, ST_Distance(s.geog,c.geog) dist FROM bluebox.store s,
			bluebox.customer c
		WHERE ST_DWithin(s.geog,c.geog,max_store_dist)
			AND c.customer_id = c_id
		ORDER BY random()
		LIMIT 1
	)
	SELECT store_id INTO c_sid FROM rental_store;
	 	
 	SELECT inventory_id INTO inv_id FROM inventory
 		WHERE inventory_id NOT IN (SELECT inventory_id FROM rental WHERE rental_period @> rental_start)
 			AND store_id = c_sid
 		ORDER BY random()
 		LIMIT 1;
	 	
	IF (inv_id IS NOT NULL) THEN  	
		INSERT INTO bluebox.rental (rental_period, inventory_id, customer_id, store_id)
			 	VALUES (tstzrange(rental_start,NULL),
					inv_id,
					c_id,
					c_sid); 
	END IF;

	COMMIT;	
 END;
$$;


--
-- Name: generate_new_rentals(interval, real, real, integer); Type: PROCEDURE; Schema: bluebox; Owner: -
--

CREATE PROCEDURE bluebox.generate_new_rentals(IN rental_interval interval DEFAULT '00:05:00'::interval, IN cust_percent real DEFAULT 0.025, IN holiday_multiplier real DEFAULT 2.5, IN max_store_dist integer DEFAULT 25000)
    LANGUAGE plpgsql
    AS $_$
 DECLARE cus record;
	c_inv int;
	a_inv int[];
	rental_start timestamptz;
    rental_nextday timestamptz;
    rental_range tstzrange;
	sqlstr TEXT;
	pid int;
	tmp_cust_tablename TEXT;
	tmp_inv_tablename TEXT;
 BEGIN

	SELECT pg_backend_pid() INTO pid; 
	
	tmp_cust_tablename = 'tmp_av_customer_' || pid::TEXT;
	tmp_inv_tablename = 'tmp_av_inventory_' || pid::TEXT;
	 
	EXECUTE 'CREATE TEMPORARY TABLE ' || tmp_cust_tablename || ' (LIKE bluebox.customer INCLUDING ALL)';
	EXECUTE 'CREATE TEMPORARY TABLE ' || tmp_inv_tablename || ' (LIKE bluebox.inventory INCLUDING ALL)';
	EXECUTE 'CREATE INDEX tmp_av_inventory_id_' || pid::TEXT || ' ON ' || tmp_inv_tablename || '(inventory_id)';
	EXECUTE 'CREATE INDEX tmp_av_inventory_storeid_' || pid::TEXT || ' ON ' || tmp_inv_tablename || '(store_id)';

	rental_start = now();
	rental_range = tstzrange(now(),now()+rental_interval);

	IF EXISTS (SELECT 1 FROM bluebox.holiday WHERE holiday_date::timestamptz <@ rental_range) THEN 
		SELECT pct INTO cust_percent FROM random_between(cust_percent,cust_percent*holiday_multiplier,3) x(pct);
	END IF;
	
		-- Get a list of inventory that is currently on loan as of the rental_start day
		-- For new rentals this is a bit faulty as the "rental_start" is a single timestamp
		-- but the start time 
		sqlstr := FORMAT($$WITH outstanding_rentals AS (
			SELECT * FROM bluebox.rental
			WHERE rental_period @> %3$L
		),
		-- get a list of inventory that is available
		available_inventory AS (
			INSERT INTO  %1$I --tmp_av_inventory
			SELECT i.* FROM bluebox.inventory i
				LEFT JOIN outstanding_rentals o using(inventory_id)
			WHERE o.inventory_id IS NULL
		)
		-- get a list of customers that do not currently have a video on loan
		-- as of this time
		INSERT INTO %2$I --tmp_av_customer
		SELECT c.* FROM bluebox.customer c
		 	LEFT JOIN outstanding_rentals o using(customer_id)
		WHERE o.customer_id IS NULL
			AND c.activebool IS TRUE;
		$$,tmp_inv_tablename, tmp_cust_tablename, rental_range);
		
		--RAISE NOTICE '%',sqlstr;
	
		EXECUTE sqlstr;
	
		-- sample 0.01% of the rows from available customers for the given day 
		-- loop over them and
	 	FOR cus IN EXECUTE FORMAT('SELECT customer_id, store_id FROM %1$I TABLESAMPLE bernoulli(%2$L)',tmp_cust_tablename,cust_percent)
	 	LOOP
		 	-- This is not efficient on larger tables. For a small table like this
		 	-- using 'random()' to order is faster and easier than a multi-step search
		 	WITH store_inv AS (
				SELECT s.store_id, ST_Distance(s.geog,c.geog) dist FROM bluebox.store s,
					bluebox.customer c
				WHERE ST_DWithin(s.geog,c.geog,max_store_dist)
					AND c.customer_id = cus.customer_id
				ORDER BY random()
				LIMIT 1
			)
			SELECT store_id INTO cus.store_id FROM store_inv;
		 	
		 	EXECUTE FORMAT($$SELECT inventory_id FROM %1$I 
		 		WHERE inventory_id NOT IN (SELECT UNNEST(%2$L::int[]))
		 			AND store_id = %3$s
		 		ORDER BY random()
		 		LIMIT 1$$,tmp_inv_tablename,a_inv,cus.store_id) INTO c_inv;
		 	
		 	--RAISE NOTICE 'customer_id: %, inventory_id: %, a_inv: %',cus.customer_id, c_inv, a_inv;
		 	
		 	sqlstr := FORMAT($$INSERT INTO bluebox.rental (rental_period, inventory_id, customer_id, store_id)
			 	VALUES (tstzrange((%1$L::timestamptz + trunc(random() * 300) * '1 second'::INTERVAL),NULL),
					%2$s,
					%3$s,
					%4$s) 
					$$,rental_start,c_inv,cus.customer_id,cus.store_id); 
					
 			RAISE NOTICE '%',sqlstr;				
			EXECUTE sqlstr;
 			COMMIT;
		
			a_inv := array_append(a_inv, c_inv);
			
	 	end LOOP;
	 	--RAISE NOTICE '%',sqlstr;
	 	--EXECUTE sqlstr;
	 
		EXECUTE 'DROP TABLE ' || tmp_cust_tablename;
		EXECUTE 'DROP TABLE ' || tmp_inv_tablename; 

 END;
$_$;


--
-- Name: generate_rental_history(timestamp with time zone, timestamp with time zone, numeric, numeric, double precision, integer, boolean); Type: PROCEDURE; Schema: bluebox; Owner: -
--

CREATE PROCEDURE bluebox.generate_rental_history(IN data_start timestamp with time zone, IN data_end timestamp with time zone, IN min_cust_pct numeric DEFAULT 0.8, IN max_cust_pct numeric DEFAULT 2.5, IN holiday_multiplier double precision DEFAULT 2.5, IN store_distance integer DEFAULT 25000, IN print_debug boolean DEFAULT false)
    LANGUAGE plpgsql
    AS $$
 DECLARE cus record;
	rental_start timestamptz;
    rental_nextday timestamptz;
	cust_percent float4;
	total_cus bigint;
 BEGIN
	 
	IF data_start > data_end THEN
		RAISE EXCEPTION 'End date must be after start date!';
	END IF;
	
	IF (data_end-data_start) > '366 days'::INTERVAL THEN
		RAISE EXCEPTION 'You can only do one year at time! %', (data_end-data_start);
	END IF;

	rental_start = data_start;

	WHILE rental_start <= data_end THEN
	LOOP -- daily LOOP FOR rentals
	
		-- this is used during the INSERT and pulled out here for visibility
		rental_nextday = rental_start + '1 day'::INTERVAL;
		SELECT pct INTO cust_percent FROM random_between(min_cust_pct,max_cust_pct,3) x(pct);
		
		IF EXISTS (SELECT 1 FROM bluebox.holiday WHERE holiday_date::timestamptz <@ tstzrange(rental_start,rental_nextday)) THEN 
			IF print_debug THEN
				RAISE NOTICE 'It is a holiday!';
			END IF;
			SELECT pct INTO cust_percent FROM random_between((min_cust_pct*holiday_multiplier)::numeric,(max_cust_pct*holiday_multiplier)::numeric,3) x(pct);
		END IF;
	
		IF print_debug THEN
			RAISE NOTICE 'customer pct: %', cust_percent;
			RAISE NOTICE 'begin: find customers and inventory: %', clock_timestamp();		
		END IF;
	
		-- 
	    SELECT (reltuples::bigint*(cust_percent/100))::int into total_cus FROM pg_class WHERE oid = 'bluebox.customer'::regclass;

		IF print_debug THEN				
			RAISE NOTICE 'total customers to rent for today: %', total_cus;		
		END IF;

		WITH outstanding_rentals AS MATERIALIZED (
			SELECT * FROM bluebox.rental
			WHERE rental_period @> tstzrange(rental_start, rental_nextday)
		),
		rental_customers AS MATERIALIZED (
			SELECT c.* FROM bluebox.customer c
				WHERE customer_id not in (select customer_id from outstanding_rentals)
			ORDER BY random()
			LIMIT total_cus
		),
		available_inventory AS ( 
			SELECT i.* FROM bluebox.inventory i
				INNER JOIN bluebox.film f USING(film_id)
			WHERE inventory_id not in (select inventory_id from outstanding_rentals) 
				AND release_date <= rental_start
		),
		customer_stores as (
			SELECT c.customer_id, c.store_id home_store_id, store_ids,
				row_number() OVER (PARTITION BY store_ids[1] ORDER BY random()) AS rn
			FROM rental_customers c
			inner join lateral (
				select customer_id, array_agg(s.store_id) store_ids FROM
				( 
					SELECT store_id
					from bluebox.store s
					WHERE ST_DWithin(s.geog,c.geog,store_distance)
					ORDER BY random()
					LIMIT 2 
				) s
			) t on true
		),
		random_inv AS (
			SELECT *, row_number() OVER (PARTITION BY store_id ORDER BY random()) AS rn
			FROM available_inventory
		),
		random_rental AS (
			SELECT *, (rental_start + trunc(random() * 1439) * '1 minute'::INTERVAL) as rental_start2 FROM customer_stores cs
			JOIN random_inv ri ON ri.store_id = cs.store_ids[1]
			AND ri.rn = cs.rn
		),
		create_rentals as (
			INSERT INTO bluebox.rental (rental_period, inventory_id, customer_id, store_id)
				-- Rentals are at least 10 hours in length and up to ~3.5 days (3 days + 10 hours) for historical data
				SELECT tstzrange(rental_start2,(rental_start2 + (trunc(random() * 4320) + 600) * '1 minute'::INTERVAL)) AS rental_period,
					inventory_id,
					customer_id,
					store_ids[1]
				FROM random_rental
		)
		update bluebox.inventory i set store_id = coalesce(rr.store_ids[2], rr.store_ids[1])
		 from random_rental rr where rr.inventory_id = i.inventory_id;
		
		-- commit current day of rentals
	    COMMIT;
		
		-- Create the payments for any rentals that started on this date
		CALL bluebox.insert_payments(rental_start::date);
	
		-- Move to the next day in the cycle
		rental_start = rental_nextday;
		
		IF print_debug THEN
			RAISE NOTICE 'Next day: %', rental_start;
		END IF;

	end LOOP; -- WHILE LOOP

 END;
$$;


--
-- Name: insert_payments(date); Type: PROCEDURE; Schema: bluebox; Owner: -
--

CREATE PROCEDURE bluebox.insert_payments(IN rd date)
    LANGUAGE plpgsql
    AS $$	
 DECLARE
 	rental_rate float4 = 1.99;
 BEGIN 
	WITH payment_info AS (
		SELECT r.rental_id, rental_period, GREATEST(CEILING(EXTRACT(epoch from (upper(rental_period)-lower(rental_period)))/3600/24),1) rental_days,
			inventory_id, r.customer_id, upper(rental_period) AS payment_date
		FROM bluebox.rental r
			INNER JOIN bluebox.inventory i USING(inventory_id)
			INNER JOIN bluebox.film f USING(film_id)
			LEFT JOIN bluebox.payment p ON r.rental_id = p.rental_id
		WHERE lower(rental_period) >= rd AND lower(rental_period) <= rd+'5 days'::INTERVAL
		AND p.rental_id IS NULL 
	)
	INSERT INTO bluebox.payment (customer_id, rental_id, amount, payment_date)
	SELECT customer_id, rental_id, rental_days*rental_rate AS amount, payment_date
		FROM payment_info;
	
	END;
$$;


--
-- Name: insert_single_payment(integer); Type: PROCEDURE; Schema: bluebox; Owner: -
--

CREATE PROCEDURE bluebox.insert_single_payment(IN rid integer)
    LANGUAGE plpgsql
    AS $$	
 DECLARE
 	rental_rate float4 = 1.99;
 BEGIN 
	WITH payment_info AS (
		SELECT rental_id, rental_period, GREATEST(CEILING(EXTRACT(epoch from (upper(rental_period)-lower(rental_period)))/3600/24),1) rental_days,
			inventory_id, customer_id, upper(rental_period) AS payment_date
		FROM bluebox.rental r
			INNER JOIN bluebox.inventory i USING(inventory_id)
			INNER JOIN bluebox.film f USING(film_id)
		WHERE r.rental_id = rid
	)
	INSERT INTO bluebox.payment (customer_id, rental_id, amount, payment_date)
	SELECT customer_id, rental_id, rental_days*rental_rate AS amount, payment_date
		FROM payment_info;
	
	END;
$$;


--
-- Name: move_cast_and_crew(); Type: PROCEDURE; Schema: bluebox; Owner: -
--

CREATE PROCEDURE bluebox.move_cast_and_crew()
    LANGUAGE plpgsql
    AS $$
BEGIN
	/*
	 * Hopefully not needed anymore, but keeping for safety. At some
	 * points during development films would exist in the staging tables
	 * but not in the main table, which should happen. In most cases I checked
	 * the films weren't of value anyway, and I suspected that IDs changed between
	 * API runs over a few months of development (and not cleaning old record
	 * up along the way)
	 */
	DELETE FROM staging.film_crew WHERE film_id IN (
	SELECT DISTINCT(fc.film_id) FROM
		staging.film_crew fc
		LEFT JOIN bluebox.film f USING (film_id)
		WHERE f.film_id IS NULL 
	);
	
	DELETE FROM staging.film_cast WHERE film_id IN (
	SELECT DISTINCT(fc.film_id) FROM
		staging.film_cast fc
		LEFT JOIN bluebox.film f USING (film_id)
		WHERE f.film_id IS NULL 
	);
	
	/*
	 * Now insert any crew records that don't exist in the main 
	 * film_crew table or film_cast table
	 */
	INSERT INTO bluebox.film_crew (film_id, person_id, department, job)
	SELECT film_id, person_id, fc.department, fc.job FROM staging.film_crew fc
		LEFT JOIN bluebox.film_crew fc1 using(film_id, person_id)
	WHERE fc1.person_id IS NULL AND fc1.film_id IS NULL;
	
	
	INSERT INTO bluebox.film_cast (film_id, person_id, film_character)
	SELECT film_id, person_id, fc.film_character FROM staging.film_cast fc
		LEFT JOIN bluebox.film_cast fc1 using(film_id,person_id)
	WHERE fc1.person_id IS NULL AND fc1.film_id IS NULL;
END;
$$;


--
-- Name: update_movie_rating(); Type: PROCEDURE; Schema: bluebox; Owner: -
--

CREATE PROCEDURE bluebox.update_movie_rating()
    LANGUAGE plpgsql
    AS $$
BEGIN 
	UPDATE bluebox.film SET rating = y.mpaa::mpaa_rating
	FROM (
		SELECT film_id, trim(x->>'certification') mpaa, x->>'type' type FROM staging.release_date rd, jsonb_array_elements(releases) x
		WHERE x->>'iso_3166_1' = 'US'
		--AND (x->>'type')::int = 3
		AND (x->>'certification') != ''
		AND film_id IN (SELECT film_id FROM film WHERE rating IS NULL)	
		) y 
	WHERE film.film_id = y.film_id;
END;
$$;


--
-- Name: _group_concat(text, text); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: film_in_stock(integer, integer); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: film_not_in_stock(integer, integer); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: get_customer_balance(integer, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: get_inventory(); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: inventory_held_by_customer(integer); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: inventory_in_stock(integer); Type: FUNCTION; Schema: public; Owner: -
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
    AND upper(rental.rental_period) IS NULL;

    IF v_out > 0 THEN
      RETURN FALSE;
    ELSE
      RETURN TRUE;
    END IF;
END $$;


--
-- Name: last_day(timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: last_updated(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.last_updated() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.last_update = CURRENT_TIMESTAMP;
    RETURN NEW;
END $$;


--
-- Name: random_between(numeric, numeric, integer); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: transform_credits(); Type: PROCEDURE; Schema: staging; Owner: -
--

CREATE PROCEDURE staging.transform_credits()
    LANGUAGE plpgsql
    AS $$	
 BEGIN 
	WITH cast_temp AS (
		SELECT film_id, (x->>'id')::bigint id, 1 credit_type, (x->>'gender')::int gender, 
			x->>'character' "character", NULL department, NULL job 
		FROM staging.film_credits, jsonb_array_elements("cast") x
	)
	INSERT INTO staging.film_cast
	SELECT film_id, id, "character" FROM cast_temp
	ON CONFLICT ON CONSTRAINT film_cast_pk DO NOTHING;
	
	WITH crew_temp AS ( 
		SELECT film_id, (x->>'id')::bigint id, 2 credit_type, (x->>'gender')::int gender,
			NULL "character", x->>'department' department, x->>'job' job
		FROM staging.film_credits, jsonb_array_elements("crew") x
	)
	INSERT INTO staging.film_crew
	SELECT film_id, id, department, job FROM crew_temp
	ON CONFLICT ON CONSTRAINT film_crew_pk DO NOTHING; 
	
	END;
$$;


--
-- Name: transform_film_details(); Type: PROCEDURE; Schema: staging; Owner: -
--

CREATE PROCEDURE staging.transform_film_details()
    LANGUAGE plpgsql
    AS $$	
 BEGIN 

	-- Every so often, after processing films, it didn't have
	-- all of the info necessary to move forward
	DELETE FROM staging.FILM_DETAIL FD 
	USING staging.film_detail fd2
	LEFT JOIN bluebox.film f USING (film_id)
	WHERE fd.film_id = fd2.film_id AND f.film_id IS NULL;

	WITH production_companies AS (
		SELECT DISTINCT film_id, (x->>'id')::int id, x->>'name' "name" FROM staging.film_detail, jsonb_array_elements(production_companies) x
		WHERE processed IS FALSE 
			--AND film_id NOT IN (SELECT DISTINCT film_id FROM film)
			AND film_id NOT IN (SELECT DISTINCT film_id FROM film_production_company)
	),
	save_production_company AS (
		INSERT INTO bluebox.production_company
		SELECT DISTINCT id, "name" FROM production_companies
		ON CONFLICT (production_company_id) DO NOTHING
	)
	INSERT INTO bluebox.film_production_company
	SELECT DISTINCT film_id, id FROM production_companies
	ON CONFLICT ON CONSTRAINT film_production_company_pk DO NOTHING;
	
	END;
$$;


--
-- Name: group_concat(text); Type: AGGREGATE; Schema: public; Owner: -
--

CREATE AGGREGATE public.group_concat(text) (
    SFUNC = public._group_concat,
    STYPE = text
);


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: customer; Type: TABLE; Schema: bluebox; Owner: -
--

CREATE TABLE bluebox.customer (
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


--
-- Name: film; Type: TABLE; Schema: bluebox; Owner: -
--

CREATE TABLE bluebox.film (
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


--
-- Name: film_cast; Type: TABLE; Schema: bluebox; Owner: -
--

CREATE TABLE bluebox.film_cast (
    film_id bigint NOT NULL,
    person_id bigint NOT NULL,
    film_character text NOT NULL
);


--
-- Name: film_crew; Type: TABLE; Schema: bluebox; Owner: -
--

CREATE TABLE bluebox.film_crew (
    film_id bigint NOT NULL,
    person_id bigint NOT NULL,
    department text,
    job text
);


--
-- Name: film_genre; Type: TABLE; Schema: bluebox; Owner: -
--

CREATE TABLE bluebox.film_genre (
    genre_id integer NOT NULL,
    name text
);


--
-- Name: film_production_company; Type: TABLE; Schema: bluebox; Owner: -
--

CREATE TABLE bluebox.film_production_company (
    film_id bigint NOT NULL,
    production_company_id bigint NOT NULL
);


--
-- Name: genre_genre_id_seq; Type: SEQUENCE; Schema: bluebox; Owner: -
--

ALTER TABLE bluebox.film_genre ALTER COLUMN genre_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME bluebox.genre_genre_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: holiday; Type: TABLE; Schema: bluebox; Owner: -
--

CREATE TABLE bluebox.holiday (
    id bigint NOT NULL,
    holiday_name text,
    is_paid_time_off boolean,
    holiday_date date
);


--
-- Name: inventory_inventory_id_seq; Type: SEQUENCE; Schema: bluebox; Owner: -
--

CREATE SEQUENCE bluebox.inventory_inventory_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: inventory; Type: TABLE; Schema: bluebox; Owner: -
--

CREATE TABLE bluebox.inventory (
    inventory_id integer DEFAULT nextval('bluebox.inventory_inventory_id_seq'::regclass) NOT NULL,
    film_id integer NOT NULL,
    store_id integer NOT NULL,
    last_update timestamp with time zone DEFAULT now() NOT NULL
)
WITH (autovacuum_vacuum_scale_factor='.60', autovacuum_vacuum_threshold='100', autovacuum_analyze_scale_factor='.80');


--
-- Name: language_language_id_seq; Type: SEQUENCE; Schema: bluebox; Owner: -
--

CREATE SEQUENCE bluebox.language_language_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: language; Type: TABLE; Schema: bluebox; Owner: -
--

CREATE TABLE bluebox.language (
    language_id integer DEFAULT nextval('bluebox.language_language_id_seq'::regclass) NOT NULL,
    name character(20) NOT NULL,
    last_update timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: payment_payment_id_seq; Type: SEQUENCE; Schema: bluebox; Owner: -
--

CREATE SEQUENCE bluebox.payment_payment_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: payment; Type: TABLE; Schema: bluebox; Owner: -
--

CREATE TABLE bluebox.payment (
    payment_id integer DEFAULT nextval('bluebox.payment_payment_id_seq'::regclass) NOT NULL,
    customer_id integer NOT NULL,
    rental_id integer NOT NULL,
    amount numeric(5,2) NOT NULL,
    payment_date timestamp with time zone NOT NULL
);


--
-- Name: person; Type: TABLE; Schema: bluebox; Owner: -
--

CREATE TABLE bluebox.person (
    person_id bigint NOT NULL,
    name text NOT NULL,
    also_known_as text[],
    birth_date date,
    death_date date,
    gender integer,
    popularity real,
    imdb_id text,
    biography text,
    place_of_birth text
);


--
-- Name: person_person_id_seq; Type: SEQUENCE; Schema: bluebox; Owner: -
--

ALTER TABLE bluebox.person ALTER COLUMN person_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME bluebox.person_person_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: production_company; Type: TABLE; Schema: bluebox; Owner: -
--

CREATE TABLE bluebox.production_company (
    production_company_id bigint NOT NULL,
    production_company_name text NOT NULL
);


--
-- Name: release_type; Type: TABLE; Schema: bluebox; Owner: -
--

CREATE TABLE bluebox.release_type (
    release_type_id integer NOT NULL,
    release_type text NOT NULL
);


--
-- Name: rental; Type: TABLE; Schema: bluebox; Owner: -
--

CREATE TABLE bluebox.rental (
    rental_id bigint NOT NULL,
    rental_period tstzrange,
    inventory_id integer NOT NULL,
    customer_id integer NOT NULL,
    last_update timestamp with time zone DEFAULT now() NOT NULL,
    store_id integer
)
WITH (autovacuum_vacuum_scale_factor='.60', autovacuum_vacuum_threshold='100', autovacuum_analyze_scale_factor='.80');


--
-- Name: rental_rental_id_seq1; Type: SEQUENCE; Schema: bluebox; Owner: -
--

ALTER TABLE bluebox.rental ALTER COLUMN rental_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME bluebox.rental_rental_id_seq1
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: staff_staff_id_seq; Type: SEQUENCE; Schema: bluebox; Owner: -
--

CREATE SEQUENCE bluebox.staff_staff_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: staff; Type: TABLE; Schema: bluebox; Owner: -
--

CREATE TABLE bluebox.staff (
    staff_id integer DEFAULT nextval('bluebox.staff_staff_id_seq'::regclass) NOT NULL,
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


--
-- Name: store; Type: TABLE; Schema: bluebox; Owner: -
--

CREATE TABLE bluebox.store (
    store_id bigint NOT NULL,
    street_name text,
    road_ref text,
    phone text,
    zip_code integer,
    geog public.geography(Point,4326)
);


--
-- Name: zip_code_info; Type: TABLE; Schema: bluebox; Owner: -
--

CREATE TABLE bluebox.zip_code_info (
    zip_code integer NOT NULL,
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


--
-- Name: film_cast; Type: TABLE; Schema: staging; Owner: -
--

CREATE TABLE staging.film_cast (
    film_id bigint NOT NULL,
    person_id bigint NOT NULL,
    film_character text NOT NULL
);


--
-- Name: film_credits; Type: TABLE; Schema: staging; Owner: -
--

CREATE TABLE staging.film_credits (
    film_id bigint NOT NULL,
    "cast" jsonb,
    crew jsonb,
    id integer NOT NULL
);


--
-- Name: film_credits_id_seq; Type: SEQUENCE; Schema: staging; Owner: -
--

ALTER TABLE staging.film_credits ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME staging.film_credits_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: film_crew; Type: TABLE; Schema: staging; Owner: -
--

CREATE TABLE staging.film_crew (
    film_id bigint NOT NULL,
    person_id bigint NOT NULL,
    department text,
    job text
);


--
-- Name: film_detail; Type: TABLE; Schema: staging; Owner: -
--

CREATE TABLE staging.film_detail (
    film_id bigint,
    budget bigint,
    revenue bigint,
    runtime integer,
    production_companies jsonb,
    processed boolean DEFAULT false
);


--
-- Name: release_date; Type: TABLE; Schema: staging; Owner: -
--

CREATE TABLE staging.release_date (
    film_id bigint,
    releases jsonb
);


--
-- Name: customer customer_pkey; Type: CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.customer
    ADD CONSTRAINT customer_pkey PRIMARY KEY (customer_id);


--
-- Name: film_cast film_cast_pk; Type: CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.film_cast
    ADD CONSTRAINT film_cast_pk PRIMARY KEY (film_id, person_id);


--
-- Name: film_crew film_crew_pk; Type: CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.film_crew
    ADD CONSTRAINT film_crew_pk PRIMARY KEY (film_id, person_id);


--
-- Name: film film_pkey; Type: CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.film
    ADD CONSTRAINT film_pkey PRIMARY KEY (film_id);


--
-- Name: film_production_company film_production_company_pk; Type: CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.film_production_company
    ADD CONSTRAINT film_production_company_pk PRIMARY KEY (film_id, production_company_id);


--
-- Name: film_genre genre_pkey; Type: CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.film_genre
    ADD CONSTRAINT genre_pkey PRIMARY KEY (genre_id);


--
-- Name: inventory inventory_pk; Type: CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.inventory
    ADD CONSTRAINT inventory_pk PRIMARY KEY (inventory_id);


--
-- Name: payment payment_bak_pkey; Type: CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.payment
    ADD CONSTRAINT payment_bak_pkey PRIMARY KEY (payment_date, payment_id);


--
-- Name: person person_pkey; Type: CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.person
    ADD CONSTRAINT person_pkey PRIMARY KEY (person_id);


--
-- Name: production_company production_company_pkey; Type: CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.production_company
    ADD CONSTRAINT production_company_pkey PRIMARY KEY (production_company_id);


--
-- Name: release_type release_type_pkey; Type: CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.release_type
    ADD CONSTRAINT release_type_pkey PRIMARY KEY (release_type_id);


--
-- Name: rental rental_pkey; Type: CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.rental
    ADD CONSTRAINT rental_pkey PRIMARY KEY (rental_id);


--
-- Name: store store_pkey; Type: CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.store
    ADD CONSTRAINT store_pkey PRIMARY KEY (store_id);


--
-- Name: zip_code_info zip_code_info_pk; Type: CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.zip_code_info
    ADD CONSTRAINT zip_code_info_pk PRIMARY KEY (zip_code);


--
-- Name: film_cast film_cast_pk; Type: CONSTRAINT; Schema: staging; Owner: -
--

ALTER TABLE ONLY staging.film_cast
    ADD CONSTRAINT film_cast_pk PRIMARY KEY (film_id, person_id);


--
-- Name: film_credits film_credits_pkey; Type: CONSTRAINT; Schema: staging; Owner: -
--

ALTER TABLE ONLY staging.film_credits
    ADD CONSTRAINT film_credits_pkey PRIMARY KEY (film_id);


--
-- Name: film_crew film_crew_pk; Type: CONSTRAINT; Schema: staging; Owner: -
--

ALTER TABLE ONLY staging.film_crew
    ADD CONSTRAINT film_crew_pk PRIMARY KEY (film_id, person_id);


--
-- Name: film_film_genre_ids_idx; Type: INDEX; Schema: bluebox; Owner: -
--

CREATE INDEX film_film_genre_ids_idx ON bluebox.film USING gin (genre_ids);


--
-- Name: film_fulltext_idx; Type: INDEX; Schema: bluebox; Owner: -
--

CREATE INDEX film_fulltext_idx ON bluebox.film USING gin (fulltext);


--
-- Name: film_person_id_film_id_idx; Type: INDEX; Schema: bluebox; Owner: -
--

CREATE INDEX film_person_id_film_id_idx ON bluebox.film_cast USING btree (person_id, film_id);


--
-- Name: idx_rental_rental_date_brin; Type: INDEX; Schema: bluebox; Owner: -
--

CREATE INDEX idx_rental_rental_date_brin ON bluebox.rental USING brin (lower(rental_period));


--
-- Name: idx_title_trgm; Type: INDEX; Schema: bluebox; Owner: -
--

CREATE INDEX idx_title_trgm ON bluebox.film USING gin (title public.gin_trgm_ops);


--
-- Name: inventory_film_id_idx; Type: INDEX; Schema: bluebox; Owner: -
--

CREATE INDEX inventory_film_id_idx ON bluebox.inventory USING btree (film_id);


--
-- Name: inventory_store_id_idx; Type: INDEX; Schema: bluebox; Owner: -
--

CREATE INDEX inventory_store_id_idx ON bluebox.inventory USING btree (store_id);


--
-- Name: payment_rental_id_amount_idx; Type: INDEX; Schema: bluebox; Owner: -
--

CREATE INDEX payment_rental_id_amount_idx ON bluebox.payment USING btree (rental_id) INCLUDE (amount);


--
-- Name: rental_customer_id_idx; Type: INDEX; Schema: bluebox; Owner: -
--

CREATE INDEX rental_customer_id_idx ON bluebox.rental USING btree (customer_id);


--
-- Name: rental_inventory_id_idx; Type: INDEX; Schema: bluebox; Owner: -
--

CREATE INDEX rental_inventory_id_idx ON bluebox.rental USING btree (inventory_id);


--
-- Name: rental_rental_period_idx; Type: INDEX; Schema: bluebox; Owner: -
--

CREATE INDEX rental_rental_period_idx ON bluebox.rental USING gist (rental_period);


--
-- Name: rental_rental_period_upper_null; Type: INDEX; Schema: bluebox; Owner: -
--

CREATE INDEX rental_rental_period_upper_null ON bluebox.rental USING btree (upper(rental_period)) WHERE (upper(rental_period) IS NULL);


--
-- Name: rental_store_id_idx; Type: INDEX; Schema: bluebox; Owner: -
--

CREATE INDEX rental_store_id_idx ON bluebox.rental USING btree (store_id);


--
-- Name: us_postal_code_geog_gix; Type: INDEX; Schema: bluebox; Owner: -
--

CREATE INDEX us_postal_code_geog_gix ON bluebox.zip_code_info USING gist (geog);


--
-- Name: customer customer_store_id_fkey; Type: FK CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.customer
    ADD CONSTRAINT customer_store_id_fkey FOREIGN KEY (store_id) REFERENCES bluebox.store(store_id) ON DELETE SET NULL;


--
-- Name: customer customer_zip_code_fkey; Type: FK CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.customer
    ADD CONSTRAINT customer_zip_code_fkey FOREIGN KEY (zip_code) REFERENCES bluebox.zip_code_info(zip_code);


--
-- Name: film_cast film_cast_film_id_fkey; Type: FK CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.film_cast
    ADD CONSTRAINT film_cast_film_id_fkey FOREIGN KEY (film_id) REFERENCES bluebox.film(film_id) ON DELETE CASCADE;


--
-- Name: film_cast film_cast_person_id_fkey; Type: FK CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.film_cast
    ADD CONSTRAINT film_cast_person_id_fkey FOREIGN KEY (person_id) REFERENCES bluebox.person(person_id) ON DELETE CASCADE;


--
-- Name: film_crew film_crew_film_id_fkey; Type: FK CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.film_crew
    ADD CONSTRAINT film_crew_film_id_fkey FOREIGN KEY (film_id) REFERENCES bluebox.film(film_id) ON DELETE CASCADE;


--
-- Name: film_crew film_crew_person_id_fkey; Type: FK CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.film_crew
    ADD CONSTRAINT film_crew_person_id_fkey FOREIGN KEY (person_id) REFERENCES bluebox.person(person_id) ON DELETE CASCADE;


--
-- Name: film_production_company film_production_company_film_id_fkey; Type: FK CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.film_production_company
    ADD CONSTRAINT film_production_company_film_id_fkey FOREIGN KEY (film_id) REFERENCES bluebox.film(film_id) ON DELETE CASCADE;


--
-- Name: film_production_company film_production_company_production_company_id_fkey; Type: FK CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.film_production_company
    ADD CONSTRAINT film_production_company_production_company_id_fkey FOREIGN KEY (production_company_id) REFERENCES bluebox.production_company(production_company_id) ON DELETE RESTRICT;


--
-- Name: inventory inventory_film_id_fkey; Type: FK CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.inventory
    ADD CONSTRAINT inventory_film_id_fkey FOREIGN KEY (film_id) REFERENCES bluebox.film(film_id) ON DELETE RESTRICT;


--
-- Name: inventory inventory_store_id_fkkey; Type: FK CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.inventory
    ADD CONSTRAINT inventory_store_id_fkkey FOREIGN KEY (store_id) REFERENCES bluebox.store(store_id) ON DELETE RESTRICT;


--
-- Name: payment payment_customer_id_fkey; Type: FK CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.payment
    ADD CONSTRAINT payment_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES bluebox.customer(customer_id) ON DELETE RESTRICT;


--
-- Name: payment payment_rental_id_fkey; Type: FK CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.payment
    ADD CONSTRAINT payment_rental_id_fkey FOREIGN KEY (rental_id) REFERENCES bluebox.rental(rental_id) ON DELETE CASCADE;


--
-- Name: rental rental_customer_id_fkey; Type: FK CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.rental
    ADD CONSTRAINT rental_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES bluebox.customer(customer_id) ON DELETE RESTRICT;


--
-- Name: rental rental_inventory_id_fkey; Type: FK CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.rental
    ADD CONSTRAINT rental_inventory_id_fkey FOREIGN KEY (inventory_id) REFERENCES bluebox.inventory(inventory_id) ON DELETE RESTRICT;


--
-- Name: store store_zip_code_fkey; Type: FK CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.store
    ADD CONSTRAINT store_zip_code_fkey FOREIGN KEY (zip_code) REFERENCES bluebox.zip_code_info(zip_code);


--
-- PostgreSQL database dump complete
--

