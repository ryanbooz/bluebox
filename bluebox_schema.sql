--
-- PostgreSQL database dump
--

-- Dumped from database version 18.1 (Debian 18.1-1.pgdg12+2)
-- Dumped by pg_dump version 18.1

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
-- transaction_timeout is a PG 17+ parameter and not necessary for init scripts
-- SET transaction_timeout = 0;
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
-- Name: complete_rentals(interval, numeric, numeric, integer, interval, interval, boolean); Type: PROCEDURE; Schema: bluebox; Owner: -
--

CREATE PROCEDURE bluebox.complete_rentals(IN p_min_rental_age interval DEFAULT '16:00:00'::interval, IN p_completion_pct numeric DEFAULT 15.0, IN p_skip_pct numeric DEFAULT 0.1, IN p_store_distance integer DEFAULT 25000, IN p_min_duration interval DEFAULT '16:00:00'::interval, IN p_max_duration interval DEFAULT '96:00:00'::interval, IN p_print_debug boolean DEFAULT false)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_eligible_count int;
    v_skip_count int;
    v_target_count int;
    v_completed_count int;
    v_payments_created int;
BEGIN
    -- Count eligible rentals (open and old enough)
    SELECT count(*) INTO v_eligible_count
    FROM bluebox.rental
    WHERE upper(rental_period) IS NULL
      AND lower(rental_period) < now() - p_min_rental_age;
    
    IF v_eligible_count = 0 THEN
        IF p_print_debug THEN
            RAISE NOTICE 'No eligible rentals to complete';
        END IF;
        RETURN;
    END IF;
    
    -- Calculate how many to skip (future lost items) and how many to complete
    v_skip_count := GREATEST(0, (v_eligible_count * p_skip_pct / 100)::int);
    v_target_count := GREATEST(1, (v_eligible_count * p_completion_pct / 100)::int);
    
    IF p_print_debug THEN
        RAISE NOTICE 'Eligible rentals: %, Skipping: % (%.2f%%), Target to complete: % (%.1f%%)', 
            v_eligible_count, v_skip_count, p_skip_pct, v_target_count, p_completion_pct;
    END IF;

    -- Complete rentals and move inventory in a single CTE chain
    WITH eligible_rentals AS MATERIALIZED (
        SELECT 
            r.rental_id,
            r.customer_id,
            r.inventory_id,
            r.store_id as rental_store_id,
            r.rental_period,
            lower(r.rental_period) as rental_start,
            row_number() OVER (ORDER BY random()) as rn
        FROM bluebox.rental r
        WHERE upper(r.rental_period) IS NULL
          AND lower(r.rental_period) < now() - p_min_rental_age
    ),
    
    sampled_rentals AS MATERIALIZED (
        SELECT rental_id, customer_id, inventory_id, rental_store_id, rental_period, rental_start
        FROM eligible_rentals
        WHERE rn > v_skip_count
          AND rn <= v_skip_count + v_target_count
    ),
    
    rentals_with_return_store AS MATERIALIZED (
        SELECT 
            sr.*,
            COALESCE(return_store.store_id, sr.rental_store_id) as return_store_id,
            GREATEST(
                now(),
                sr.rental_start + p_min_duration + 
                    (random() * EXTRACT(EPOCH FROM (p_max_duration - p_min_duration))) * interval '1 second'
            ) as return_time
        FROM sampled_rentals sr
        LEFT JOIN LATERAL (
            SELECT s.store_id
            FROM bluebox.store s
            JOIN bluebox.customer c ON c.customer_id = sr.customer_id
            WHERE ST_DWithin(s.geog, c.geog, p_store_distance)
            ORDER BY random()
            LIMIT 1
        ) return_store ON true
    ),
    
    completed_rentals AS (
        UPDATE bluebox.rental r
        SET rental_period = tstzrange(lower(r.rental_period), rwr.return_time)
        FROM rentals_with_return_store rwr
        WHERE r.rental_id = rwr.rental_id
        RETURNING r.rental_id, r.customer_id, r.inventory_id, 
                  rwr.return_store_id, rwr.return_time
    ),
    
    inventory_moves AS (
        UPDATE bluebox.inventory i
        SET store_id = cr.return_store_id,
            last_update = now()
        FROM completed_rentals cr
        WHERE i.inventory_id = cr.inventory_id
          AND i.store_id != cr.return_store_id
        RETURNING i.inventory_id
    ),
    
    payment_info AS (
        SELECT 
            cr.rental_id,
            cr.customer_id,
            cr.return_time as payment_date,
            GREATEST(1, 
                CEILING(EXTRACT(EPOCH FROM (cr.return_time - lower(r.rental_period))) / 86400)
            ) as rental_days,
            i.film_id
        FROM completed_rentals cr
        JOIN bluebox.rental r ON r.rental_id = cr.rental_id
        JOIN bluebox.inventory i ON i.inventory_id = cr.inventory_id
    ),
    
    created_payments AS (
        INSERT INTO bluebox.payment (customer_id, rental_id, amount, payment_date)
        SELECT 
            customer_id,
            rental_id,
            rental_days * bluebox.get_daily_rental_rate(film_id) AS amount,
            payment_date
        FROM payment_info
        RETURNING payment_id
    )
    
    SELECT 
        (SELECT count(*) FROM completed_rentals),
        (SELECT count(*) FROM created_payments)
    INTO v_completed_count, v_payments_created;
    
    IF p_print_debug THEN
        RAISE NOTICE 'Completed % rentals, created % payments', v_completed_count, v_payments_created;
    END IF;
    
    COMMIT;
END;
$$;


--
-- Name: PROCEDURE complete_rentals(IN p_min_rental_age interval, IN p_completion_pct numeric, IN p_skip_pct numeric, IN p_store_distance integer, IN p_min_duration interval, IN p_max_duration interval, IN p_print_debug boolean); Type: COMMENT; Schema: bluebox; Owner: -
--

COMMENT ON PROCEDURE bluebox.complete_rentals(IN p_min_rental_age interval, IN p_completion_pct numeric, IN p_skip_pct numeric, IN p_store_distance integer, IN p_min_duration interval, IN p_max_duration interval, IN p_print_debug boolean) IS 'Complete (close out) open rentals, simulating customer returns.

This procedure:
1. Finds open rentals older than p_min_rental_age
2. Skips p_skip_pct of them (these will eventually become "lost")
3. Completes p_completion_pct of them
4. Sets the rental end time (between p_min_duration and p_max_duration from start)
5. Moves inventory to a random nearby store (simulating return location)
6. Creates payment records

Parameters:
  p_min_rental_age  - Minimum time since rental start before eligible (default: 16 hours)
  p_completion_pct  - Percentage of eligible rentals to complete (default: 15%)
  p_skip_pct        - Percentage of eligible rentals to skip/ignore (default: 0.1%)
                      These accumulate and are eventually marked lost by process_lost_rentals()
  p_store_distance  - Max distance (meters) for return store (default: 25000)
  p_min_duration    - Minimum rental duration (default: 16 hours)
  p_max_duration    - Maximum rental duration (default: 96 hours)
  p_print_debug     - Print debug messages (default: false)

Typical usage with pg_cron:
  -- Complete ~15% of eligible rentals every 15 minutes
  SELECT cron.schedule(''complete-rentals'', ''*/15 * * * *'', 
      $CALL bluebox.complete_rentals()$);

Examples:
  -- Default: complete 15% of rentals older than 16 hours, skip 0.1%
  CALL bluebox.complete_rentals();
  
  -- More aggressive: complete 25% of rentals older than 12 hours
  CALL bluebox.complete_rentals(
      p_min_rental_age := interval ''12 hours'',
      p_completion_pct := 25.0,
      p_print_debug := true
  );
  
  -- Clear backlog: complete all eligible rentals (skip none)
  CALL bluebox.complete_rentals(p_completion_pct := 100.0, p_skip_pct := 0);
';


--
-- Name: generate_rental_history(date, date, numeric, numeric, numeric, integer, boolean); Type: PROCEDURE; Schema: bluebox; Owner: -
--

CREATE PROCEDURE bluebox.generate_rental_history(IN p_start_date date, IN p_end_date date DEFAULT (CURRENT_DATE - 1), IN p_min_cust_pct numeric DEFAULT 0.8, IN p_max_cust_pct numeric DEFAULT 2.5, IN p_holiday_multiplier numeric DEFAULT 2.5, IN p_store_distance integer DEFAULT 25000, IN p_print_debug boolean DEFAULT false)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_current_date date;
    v_day_start timestamptz;
    v_day_end timestamptz;
    v_cust_percent numeric;
    v_is_holiday boolean;
    v_target_rentals int;
    v_active_customer_count int;
    v_sample_pct numeric;
    v_rentals_created int;
    v_total_rentals int := 0;
    v_days_processed int := 0;
    v_start_time timestamptz;
BEGIN
    -- Validate inputs
    IF p_start_date > p_end_date THEN
        RAISE EXCEPTION 'p_end_date must be on or after p_start_date';
    END IF;
    
    IF p_end_date - p_start_date > 366 THEN
        RAISE EXCEPTION 'Maximum range is 366 days. Requested: % days', p_end_date - p_start_date;
    END IF;
    
    v_start_time := clock_timestamp();
    
    IF p_print_debug THEN
        RAISE NOTICE '=== Starting rental history generation ===';
        RAISE NOTICE 'Date range: % to % (% days)', p_start_date, p_end_date, p_end_date - p_start_date + 1;
    END IF;
    
    -- Get active customer count (constant for the run)
    SELECT count(*) INTO v_active_customer_count 
    FROM bluebox.customer WHERE activebool = TRUE;
    
    -- Loop through each day
    v_current_date := p_start_date;
    
    WHILE v_current_date <= p_end_date LOOP
        v_day_start := v_current_date::timestamptz;
        v_day_end := (v_current_date + 1)::timestamptz;
        
        -- Check if this day is a holiday
        v_is_holiday := EXISTS (
            SELECT 1 FROM bluebox.holiday 
            WHERE holiday_date = v_current_date
        );
        
        -- Calculate customer percentage for this day
        IF v_is_holiday THEN
            v_cust_percent := bluebox.random_between(
                p_min_cust_pct * p_holiday_multiplier, 
                p_max_cust_pct * p_holiday_multiplier, 
                3
            );
        ELSE
            v_cust_percent := bluebox.random_between(p_min_cust_pct, p_max_cust_pct, 3);
        END IF;
        
        -- Calculate target rentals for this day
        v_target_rentals := GREATEST(1, (v_active_customer_count * v_cust_percent / 100)::int);
        
        -- Calculate TABLESAMPLE percentage
        v_sample_pct := GREATEST(0.001, LEAST(100, 
            (v_target_rentals * 1.5 / NULLIF(v_active_customer_count, 0) * 100)::numeric(10,4)
        ));
        
        -- Generate rentals for this day
        WITH outstanding_rentals AS MATERIALIZED (
            -- For historical generation, only exclude inventory currently rented on this day
            -- Customers CAN rent again if their previous rental from an earlier day is returned
            SELECT inventory_id 
            FROM bluebox.rental
            WHERE rental_period && tstzrange(v_day_start, v_day_end)
        ),
        
        -- Get customers who don't have an active rental on this specific day
        rental_customers AS MATERIALIZED (
            SELECT c.customer_id, c.geog
            FROM bluebox.customer c TABLESAMPLE BERNOULLI(v_sample_pct)
            WHERE c.activebool = TRUE
              AND NOT EXISTS (
                  SELECT 1 FROM bluebox.rental r
                  WHERE r.customer_id = c.customer_id
                    AND r.rental_period && tstzrange(v_day_start, v_day_end)
              )
            LIMIT v_target_rentals
        ),
        
        customer_stores AS MATERIALIZED (
            SELECT 
                c.customer_id,
                stores.rental_store_id,
                stores.return_store_id,
                row_number() OVER (PARTITION BY stores.rental_store_id ORDER BY random()) as store_rn
            FROM rental_customers c
            CROSS JOIN LATERAL (
                SELECT 
                    store_ids[1] as rental_store_id,
                    COALESCE(store_ids[2], store_ids[1]) as return_store_id
                FROM (
                    SELECT array_agg(s.store_id) as store_ids
                    FROM (
                        SELECT store_id
                        FROM bluebox.store s
                        WHERE ST_DWithin(s.geog, c.geog, p_store_distance)
                        ORDER BY random()
                        LIMIT 2
                    ) s
                ) sub
            ) stores
        ),
        
        matched_rentals AS MATERIALIZED (
            SELECT 
                cs.customer_id,
                cs.rental_store_id,
                cs.return_store_id,
                inv.inventory_id,
                -- Random start time within the day
                v_day_start + (random() * 86400) * interval '1 second' as rental_start_time
            FROM customer_stores cs
            CROSS JOIN LATERAL (
                SELECT i.inventory_id
                FROM bluebox.inventory i
                INNER JOIN bluebox.film f USING(film_id)
                WHERE i.store_id = cs.rental_store_id
                  AND i.status_id = 1
                  AND i.inventory_id NOT IN (SELECT inventory_id FROM outstanding_rentals)
                  AND f.release_date <= v_current_date
                ORDER BY random()
                LIMIT 1
            ) inv
        ),
        
        created_rentals AS (
            INSERT INTO bluebox.rental (rental_period, inventory_id, customer_id, store_id)
            SELECT 
                -- Closed rental: 10-72 hours duration
                tstzrange(
                    rental_start_time,
                    rental_start_time + ((random() * 62 + 10) * interval '1 hour')
                ),
                inventory_id,
                customer_id,
                rental_store_id
            FROM matched_rentals
            RETURNING rental_id, inventory_id
        ),
        
        inventory_updates AS (
            UPDATE bluebox.inventory i
            SET store_id = mr.return_store_id,
                last_update = now()
            FROM matched_rentals mr
            WHERE i.inventory_id = mr.inventory_id
              AND mr.return_store_id IS DISTINCT FROM mr.rental_store_id
            RETURNING i.inventory_id
        )
        
        SELECT count(*) INTO v_rentals_created FROM created_rentals;
        
        -- Generate payments for this day's rentals
        IF v_rentals_created > 0 THEN
            CALL bluebox.insert_payments(v_current_date);
        END IF;
        
        v_total_rentals := v_total_rentals + v_rentals_created;
        v_days_processed := v_days_processed + 1;
        
        IF p_print_debug THEN
            RAISE NOTICE '% | % rentals | cust%%: % | holiday: %', 
                v_current_date, 
                v_rentals_created,
                round(v_cust_percent, 2),
                v_is_holiday;
        END IF;
        
        COMMIT;
        
        v_current_date := v_current_date + 1;
    END LOOP;
    
    IF p_print_debug THEN
        RAISE NOTICE '=== Rental history generation complete ===';
        RAISE NOTICE 'Days processed: %, Total rentals: %, Time: % seconds', 
            v_days_processed,
            v_total_rentals,
            round(EXTRACT(EPOCH FROM clock_timestamp() - v_start_time)::numeric, 2);
    END IF;
END;
$$;


--
-- Name: generate_rentals(timestamp with time zone, timestamp with time zone, boolean, numeric, numeric, numeric, integer, boolean); Type: PROCEDURE; Schema: bluebox; Owner: -
--

CREATE PROCEDURE bluebox.generate_rentals(IN p_start_time timestamp with time zone DEFAULT now(), IN p_end_time timestamp with time zone DEFAULT (now() + '00:05:00'::interval), IN p_close_rentals boolean DEFAULT false, IN p_min_cust_pct numeric DEFAULT 0.8, IN p_max_cust_pct numeric DEFAULT 2.5, IN p_holiday_multiplier numeric DEFAULT 2.5, IN p_store_distance integer DEFAULT 25000, IN p_print_debug boolean DEFAULT false)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_cust_percent float;
    v_target_rentals int;
    v_active_customer_count int;
    v_interval_hours numeric;
    v_sample_pct numeric;
    v_rentals_created int;
BEGIN
    -- Validate inputs
    IF p_start_time >= p_end_time THEN
        RAISE EXCEPTION 'p_end_time must be after p_start_time';
    END IF;
    
    -- Calculate interval in hours
    v_interval_hours := EXTRACT(EPOCH FROM (p_end_time - p_start_time)) / 3600.0;
    
    IF v_interval_hours > 24 THEN
        RAISE EXCEPTION 'Maximum interval is 24 hours. For multi-day generation, use generate_rental_history() instead. Requested: % hours', v_interval_hours;
    END IF;
    
    -- Get active customer count
    SELECT count(*) INTO v_active_customer_count 
    FROM bluebox.customer WHERE activebool = TRUE;
    
    -- Calculate customer percentage (QUALIFIED)
    SELECT bluebox.random_between(p_min_cust_pct, p_max_cust_pct, 3) INTO v_cust_percent;
    
    -- Check for holidays - increase volume
    IF EXISTS (
        SELECT 1 FROM bluebox.holiday 
        WHERE holiday_date::timestamptz <@ tstzrange(p_start_time, p_end_time)
    ) THEN
        IF p_print_debug THEN
            RAISE NOTICE 'Holiday detected in range';
        END IF;
        SELECT bluebox.random_between(
            p_min_cust_pct * p_holiday_multiplier, 
            p_max_cust_pct * p_holiday_multiplier, 
            3
        ) INTO v_cust_percent;
    END IF;
    
    -- Calculate target rentals, scaled by interval
    v_target_rentals := GREATEST(1,
        (v_active_customer_count * v_cust_percent / 100 * v_interval_hours / 24)::int
    );
    
    -- Calculate TABLESAMPLE percentage (with buffer for filtering)
    v_sample_pct := GREATEST(0.001, LEAST(100, 
        (v_target_rentals * 1.5 / NULLIF(v_active_customer_count, 0) * 100)::numeric(10,4)
    ));
    
    IF p_print_debug THEN
        RAISE NOTICE 'Time range: % to % (% hours)', p_start_time, p_end_time, round(v_interval_hours::numeric, 2);
        RAISE NOTICE 'Active customers: %, Cust%%: %, Target rentals: %', 
            v_active_customer_count, round(v_cust_percent::numeric, 3), v_target_rentals;
        RAISE NOTICE 'Close rentals: %, Sample%%: %', p_close_rentals, v_sample_pct;
    END IF;

    -- Single unified CTE chain - behavior controlled by p_close_rentals
    WITH outstanding_rentals AS MATERIALIZED (
        SELECT customer_id, inventory_id 
        FROM bluebox.rental
        WHERE rental_period && tstzrange(p_start_time, p_end_time)
           -- For open rentals mode, also exclude customers with any open rental
           OR (NOT p_close_rentals AND upper(rental_period) IS NULL)
    ),
    
    rental_customers AS MATERIALIZED (
        SELECT c.customer_id, c.geog
        FROM bluebox.customer c TABLESAMPLE BERNOULLI(v_sample_pct)
        WHERE c.activebool = TRUE
          AND c.customer_id NOT IN (SELECT customer_id FROM outstanding_rentals)
        LIMIT v_target_rentals
    ),
    
    customer_stores AS MATERIALIZED (
        SELECT 
            c.customer_id,
            stores.rental_store_id,
            stores.return_store_id,
            row_number() OVER (PARTITION BY stores.rental_store_id ORDER BY random()) as store_rn
        FROM rental_customers c
        CROSS JOIN LATERAL (
            SELECT 
                store_ids[1] as rental_store_id,
                CASE 
                    WHEN p_close_rentals THEN COALESCE(store_ids[2], store_ids[1])
                    ELSE store_ids[1]
                END as return_store_id
            FROM (
                SELECT array_agg(s.store_id) as store_ids
                FROM (
                    SELECT store_id
                    FROM bluebox.store s
                    WHERE ST_DWithin(s.geog, c.geog, p_store_distance)
                    ORDER BY random()
                    LIMIT CASE WHEN p_close_rentals THEN 2 ELSE 1 END
                ) s
            ) sub
        ) stores
    ),
    
    matched_rentals AS MATERIALIZED (
        SELECT 
            cs.customer_id,
            cs.rental_store_id,
            cs.return_store_id,
            inv.inventory_id,
            p_start_time + (random() * v_interval_hours * 3600) * interval '1 second' as rental_start_time
        FROM customer_stores cs
        CROSS JOIN LATERAL (
            SELECT i.inventory_id
            FROM bluebox.inventory i
            INNER JOIN bluebox.film f USING(film_id)
            WHERE i.store_id = cs.rental_store_id
              AND i.status_id = 1
              AND i.inventory_id NOT IN (SELECT inventory_id FROM outstanding_rentals)
              AND f.release_date <= p_start_time::date
            ORDER BY random()
            LIMIT 1
        ) inv
    ),
    
    created_rentals AS (
        INSERT INTO bluebox.rental (rental_period, inventory_id, customer_id, store_id)
        SELECT 
            CASE 
                WHEN p_close_rentals THEN
                    tstzrange(
                        rental_start_time,
                        rental_start_time + ((random() * 62 + 10) * interval '1 hour')
                    )
                ELSE
                    tstzrange(rental_start_time, NULL)
            END,
            inventory_id,
            customer_id,
            rental_store_id
        FROM matched_rentals
        RETURNING rental_id, inventory_id
    ),
    
    inventory_updates AS (
        UPDATE bluebox.inventory i
        SET store_id = mr.return_store_id,
            last_update = now()
        FROM matched_rentals mr
        WHERE i.inventory_id = mr.inventory_id
          AND p_close_rentals
          AND mr.return_store_id IS DISTINCT FROM mr.rental_store_id
        RETURNING i.inventory_id
    )
    
    SELECT count(*) INTO v_rentals_created FROM created_rentals;
    
    IF p_print_debug THEN
        RAISE NOTICE 'Created % rentals (closed: %)', v_rentals_created, p_close_rentals;
    END IF;
    
    COMMIT;
    
    -- Generate payments for closed rentals
    IF p_close_rentals AND v_rentals_created > 0 THEN
        CALL bluebox.insert_payments(p_start_time::date);
        IF p_print_debug THEN
            RAISE NOTICE 'Payments generated for %', p_start_time::date;
        END IF;
    END IF;
END;
$$;


--
-- Name: get_customer_balance(integer, timestamp with time zone); Type: FUNCTION; Schema: bluebox; Owner: -
--

CREATE FUNCTION bluebox.get_customer_balance(p_customer_id integer, p_effective_date timestamp with time zone) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_rental_fees NUMERIC(10,2);  -- total amount owed from rentals
    v_payments NUMERIC(10,2);     -- total payments made
BEGIN
    -- Sum of rental fees (from payment records for rentals starting before effective date)
    SELECT COALESCE(SUM(p.amount), 0) INTO v_rental_fees
    FROM bluebox.rental r
    JOIN bluebox.payment p ON r.rental_id = p.rental_id
    WHERE r.customer_id = p_customer_id
      AND lower(r.rental_period) <= p_effective_date;

    -- Sum of payments made before effective date
    SELECT COALESCE(SUM(amount), 0) INTO v_payments
    FROM bluebox.payment
    WHERE customer_id = p_customer_id
      AND payment_date <= p_effective_date;

    -- In your current model, payment is created when rental ends,
    -- so balance should typically be 0. But this preserves the 
    -- "what did they owe as of date X" logic.
    RETURN v_rental_fees - v_payments;
END $$;


--
-- Name: get_customer_status_summary(); Type: FUNCTION; Schema: bluebox; Owner: -
--

CREATE FUNCTION bluebox.get_customer_status_summary() RETURNS TABLE(status text, customer_count bigint, pct_of_total numeric, avg_lifetime_rentals numeric, avg_lifetime_value numeric)
    LANGUAGE sql
    AS $$
    WITH customer_stats AS (
        SELECT 
            c.customer_id,
            c.activebool,
            COUNT(r.rental_id) as rental_count,
            COALESCE(SUM(p.amount), 0) as total_spent,
            MAX(lower(r.rental_period)) as last_rental
        FROM bluebox.customer c
        LEFT JOIN bluebox.rental r ON c.customer_id = r.customer_id
        LEFT JOIN bluebox.payment p ON r.rental_id = p.rental_id
        GROUP BY c.customer_id, c.activebool
    )
    SELECT 
        CASE 
            WHEN NOT activebool THEN 'Inactive'
            WHEN last_rental > now() - interval '30 days' THEN 'Active (30d)'
            WHEN last_rental > now() - interval '90 days' THEN 'Recent (30-90d)'
            WHEN last_rental > now() - interval '180 days' THEN 'Dormant (90-180d)'
            ELSE 'At Risk (>180d)'
        END as status,
        COUNT(*),
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2),
        ROUND(AVG(rental_count), 1),
        ROUND(AVG(total_spent), 2)
    FROM customer_stats
    GROUP BY 1
    ORDER BY 2 DESC;
$$;


--
-- Name: get_daily_rental_rate(bigint); Type: FUNCTION; Schema: bluebox; Owner: -
--

CREATE FUNCTION bluebox.get_daily_rental_rate(p_film_id bigint DEFAULT NULL::bigint) RETURNS numeric
    LANGUAGE sql STABLE
    AS $$
    SELECT bluebox.get_pricing('daily_rental_rate');
$$;


--
-- Name: get_film_availability(integer); Type: FUNCTION; Schema: bluebox; Owner: -
--

CREATE FUNCTION bluebox.get_film_availability(min_stores integer DEFAULT 0) RETURNS TABLE(film_id bigint, title text, release_date date, popularity real, stores_with_film bigint, total_copies bigint, copies_available bigint)
    LANGUAGE sql
    AS $$
    WITH inventory_stats AS (
        SELECT 
            i.film_id,
            count(DISTINCT i.store_id) as stores_with_film,
            count(*) as total_copies,
            count(*) FILTER (WHERE i.status_id = 1 
                AND NOT EXISTS (
                    SELECT 1 FROM bluebox.rental r 
                    WHERE r.inventory_id = i.inventory_id 
                    AND upper(r.rental_period) IS NULL
                )
            ) as copies_available
        FROM bluebox.inventory i
        GROUP BY i.film_id
    )
    SELECT 
        f.film_id,
        f.title,
        f.release_date,
        f.popularity,
        COALESCE(inv.stores_with_film, 0),
        COALESCE(inv.total_copies, 0),
        COALESCE(inv.copies_available, 0)
    FROM bluebox.film f
    LEFT JOIN inventory_stats inv ON f.film_id = inv.film_id
    WHERE COALESCE(inv.stores_with_film, 0) >= min_stores
    ORDER BY f.popularity DESC;
$$;


--
-- Name: get_inventory_balance_report(); Type: FUNCTION; Schema: bluebox; Owner: -
--

CREATE FUNCTION bluebox.get_inventory_balance_report() RETURNS TABLE(store_id bigint, nearby_customers bigint, current_inventory bigint, target_inventory integer, variance integer, variance_pct numeric)
    LANGUAGE sql
    AS $$
    WITH store_metrics AS (
        SELECT 
            s.store_id,
            count(DISTINCT c.customer_id) as nearby_customers
        FROM bluebox.store s
        LEFT JOIN bluebox.customer c ON ST_DWithin(s.geog, c.geog, 25000)
        GROUP BY s.store_id
    ),
    totals AS (
        SELECT 
            (SELECT count(*) FROM bluebox.inventory WHERE status_id = 1) as total_inventory,
            (SELECT count(*) FROM bluebox.store) as store_count,
            sum(nearby_customers) as total_customers
        FROM store_metrics
    ),
    dynamic_params AS (
        SELECT 
            (total_inventory / store_count * 0.4)::int as floor_inventory,
            total_inventory - (total_inventory / store_count * 0.4)::int * store_count as remainder,
            total_customers
        FROM totals
    ),
    store_inventory AS (
        SELECT store_id, count(*) as inv_count
        FROM bluebox.inventory
        WHERE status_id = 1
        GROUP BY store_id
    )
    SELECT 
        sm.store_id,
        sm.nearby_customers,
        COALESCE(si.inv_count, 0) as current_inventory,
        dp.floor_inventory + (sm.nearby_customers::float / dp.total_customers * dp.remainder)::int as target_inventory,
        COALESCE(si.inv_count, 0) - (dp.floor_inventory + (sm.nearby_customers::float / dp.total_customers * dp.remainder)::int) as variance,
        ROUND(100.0 * (COALESCE(si.inv_count, 0) - (dp.floor_inventory + (sm.nearby_customers::float / dp.total_customers * dp.remainder)::int)) 
            / (dp.floor_inventory + (sm.nearby_customers::float / dp.total_customers * dp.remainder)::int), 1) as variance_pct
    FROM store_metrics sm
    CROSS JOIN dynamic_params dp
    LEFT JOIN store_inventory si ON sm.store_id = si.store_id
    ORDER BY variance DESC;
$$;


--
-- Name: get_inventory_status_summary(); Type: FUNCTION; Schema: bluebox; Owner: -
--

CREATE FUNCTION bluebox.get_inventory_status_summary() RETURNS TABLE(status_code text, description text, inventory_count bigint, pct_of_total numeric)
    LANGUAGE sql
    AS $$
    SELECT 
        s.status_code,
        s.description,
        COUNT(i.inventory_id),
        ROUND(100.0 * COUNT(i.inventory_id) / SUM(COUNT(i.inventory_id)) OVER (), 2)
    FROM bluebox.inventory_status s
    LEFT JOIN bluebox.inventory i ON s.status_id = i.status_id
    GROUP BY s.status_id, s.status_code, s.description, s.display_order
    ORDER BY s.display_order;
$$;


--
-- Name: get_overdue_rentals(integer); Type: FUNCTION; Schema: bluebox; Owner: -
--

CREATE FUNCTION bluebox.get_overdue_rentals(overdue_days integer DEFAULT 7) RETURNS TABLE(rental_id bigint, customer_id bigint, customer_name text, film_title text, rental_start timestamp with time zone, days_overdue integer, replacement_cost numeric)
    LANGUAGE sql
    AS $$
    SELECT 
        r.rental_id,
        c.customer_id,
        c.full_name,
        f.title,
        lower(r.rental_period),
        EXTRACT(day FROM now() - lower(r.rental_period))::INTEGER,
        f.replacement_cost
    FROM bluebox.rental r
    JOIN bluebox.customer c ON r.customer_id = c.customer_id
    JOIN bluebox.inventory i ON r.inventory_id = i.inventory_id
    JOIN bluebox.film f ON i.film_id = f.film_id
    WHERE upper(r.rental_period) IS NULL
      AND lower(r.rental_period) < now() - (overdue_days || ' days')::INTERVAL
      AND i.status_id = 1  -- only in_circulation items
    ORDER BY lower(r.rental_period);
$$;


--
-- Name: get_pricing(text); Type: FUNCTION; Schema: bluebox; Owner: -
--

CREATE FUNCTION bluebox.get_pricing(p_key text) RETURNS numeric
    LANGUAGE sql STABLE
    AS $$
    SELECT pricing_value 
    FROM bluebox.pricing 
    WHERE pricing_key = p_key;
$$;


--
-- Name: get_replacement_cost(integer); Type: FUNCTION; Schema: bluebox; Owner: -
--

CREATE FUNCTION bluebox.get_replacement_cost(p_inventory_id integer) RETURNS numeric
    LANGUAGE sql STABLE
    AS $$
    SELECT bluebox.get_replacement_cost(i.film_id)
    FROM bluebox.inventory i
    WHERE i.inventory_id = p_inventory_id;
$$;


--
-- Name: get_replacement_cost(bigint); Type: FUNCTION; Schema: bluebox; Owner: -
--

CREATE FUNCTION bluebox.get_replacement_cost(p_film_id bigint) RETURNS numeric
    LANGUAGE sql STABLE
    AS $$
    SELECT CASE
        WHEN f.release_date > CURRENT_DATE - INTERVAL '1 year' 
            THEN bluebox.get_pricing('replacement_cost_new')
        WHEN f.release_date > CURRENT_DATE - INTERVAL '3 years' 
            THEN bluebox.get_pricing('replacement_cost_recent')
        WHEN f.release_date > CURRENT_DATE - INTERVAL '10 years' 
            THEN bluebox.get_pricing('replacement_cost_catalog')
        ELSE 
            bluebox.get_pricing('replacement_cost_classic')
    END
    FROM bluebox.film f
    WHERE f.film_id = p_film_id;
$$;


--
-- Name: insert_payments(date); Type: PROCEDURE; Schema: bluebox; Owner: -
--

CREATE PROCEDURE bluebox.insert_payments(IN rd date)
    LANGUAGE plpgsql
    AS $$
BEGIN 
    WITH payment_info AS (
        SELECT 
            r.rental_id, 
            rental_period, 
            GREATEST(CEILING(EXTRACT(epoch FROM (upper(rental_period)-lower(rental_period)))/3600/24), 1) AS rental_days,
            inventory_id, 
            r.customer_id, 
            upper(rental_period) AS payment_date,
            i.film_id
        FROM bluebox.rental r
        INNER JOIN bluebox.inventory i USING(inventory_id)
        LEFT JOIN bluebox.payment p ON r.rental_id = p.rental_id
        WHERE upper(rental_period) IS NOT NULL
          AND lower(rental_period) >= rd - '1 days'::INTERVAL
          AND lower(rental_period) <= rd + '1 days'::INTERVAL
          AND p.rental_id IS NULL 
    )
    INSERT INTO bluebox.payment (customer_id, rental_id, amount, payment_date)
    SELECT 
        customer_id, 
        rental_id, 
        rental_days * bluebox.get_daily_rental_rate(film_id) AS amount, 
        payment_date
    FROM payment_info;
END;
$$;


--
-- Name: last_day(timestamp with time zone); Type: FUNCTION; Schema: bluebox; Owner: -
--

CREATE FUNCTION bluebox.last_day(timestamp with time zone) RETURNS date
    LANGUAGE sql IMMUTABLE
    AS $_$
  SELECT CASE
    WHEN EXTRACT(MONTH FROM $1) = 12 THEN
      (((EXTRACT(YEAR FROM $1) + 1) operator(pg_catalog.||) '-01-01')::date - INTERVAL '1 day')::date
    ELSE
      ((EXTRACT(YEAR FROM $1) operator(pg_catalog.||) '-' operator(pg_catalog.||) (EXTRACT(MONTH FROM $1) + 1) operator(pg_catalog.||) '-01')::date - INTERVAL '1 day')::date
    END
$_$;


--
-- Name: last_updated(); Type: FUNCTION; Schema: bluebox; Owner: -
--

CREATE FUNCTION bluebox.last_updated() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.last_update = CURRENT_TIMESTAMP;
    RETURN NEW;
END $$;


--
-- Name: log_customer_status(integer, text, text, text, bigint, timestamp with time zone); Type: FUNCTION; Schema: bluebox; Owner: -
--

CREATE FUNCTION bluebox.log_customer_status(p_customer_id integer, p_status text, p_reason_code text, p_notes text DEFAULT NULL::text, p_rental_id bigint DEFAULT NULL::bigint, p_status_date timestamp with time zone DEFAULT now()) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_log_id bigint;
BEGIN
    INSERT INTO bluebox.customer_status_log 
        (customer_id, status_date, status, reason_code, notes, rental_id)
    VALUES 
        (p_customer_id, p_status_date, p_status, p_reason_code, p_notes, p_rental_id)
    RETURNING log_id INTO v_log_id;
    
    RETURN v_log_id;
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
-- Name: nightly_maintenance(integer, boolean, integer, numeric, boolean); Type: PROCEDURE; Schema: bluebox; Owner: -
--

CREATE PROCEDURE bluebox.nightly_maintenance(IN lost_threshold_days integer DEFAULT 30, IN deactivate_lost_customers boolean DEFAULT true, IN dormant_days integer DEFAULT 180, IN reactivate_pct numeric DEFAULT 0.5, IN print_debug boolean DEFAULT false)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_start_time TIMESTAMPTZ;
    v_step_time TIMESTAMPTZ;
BEGIN
    v_start_time := clock_timestamp();
    
    IF print_debug THEN
        RAISE NOTICE '=== Starting nightly maintenance at % ===', v_start_time;
    END IF;

    -- Step 1: Process lost inventory
    v_step_time := clock_timestamp();
    IF print_debug THEN
        RAISE NOTICE 'Step 1: Processing lost inventory...';
    END IF;
    
    CALL bluebox.process_lost_inventory(
        lost_threshold_days := lost_threshold_days,
        deactivate_customer := deactivate_lost_customers,
        print_debug := print_debug
    );
    
    IF print_debug THEN
        RAISE NOTICE 'Step 1 completed in % ms', EXTRACT(MILLISECOND FROM clock_timestamp() - v_step_time);
    END IF;

    -- Step 2: Update customer activity status
    v_step_time := clock_timestamp();
    IF print_debug THEN
        RAISE NOTICE 'Step 2: Updating customer activity...';
    END IF;
    
    CALL bluebox.update_customer_activity(
        dormant_days := dormant_days,
        reactivate_pct := reactivate_pct,
        print_debug := print_debug
    );
    
    IF print_debug THEN
        RAISE NOTICE 'Step 2 completed in % ms', EXTRACT(MILLISECOND FROM clock_timestamp() - v_step_time);
    END IF;

    -- Step 3: Analyze tables that were modified
    v_step_time := clock_timestamp();
    IF print_debug THEN
        RAISE NOTICE 'Step 3: Analyzing modified tables...';
    END IF;
    
    ANALYZE bluebox.inventory;
    ANALYZE bluebox.customer;
    ANALYZE bluebox.rental;
    ANALYZE bluebox.payment;
    
    IF print_debug THEN
        RAISE NOTICE 'Step 3 completed in % ms', EXTRACT(MILLISECOND FROM clock_timestamp() - v_step_time);
        RAISE NOTICE '=== Nightly maintenance completed in % ms ===', 
            EXTRACT(MILLISECOND FROM clock_timestamp() - v_start_time);
    END IF;

    COMMIT;
END;
$$;


--
-- Name: populate_inventory(boolean, boolean); Type: PROCEDURE; Schema: bluebox; Owner: -
--

CREATE PROCEDURE bluebox.populate_inventory(IN clear_existing boolean DEFAULT false, IN print_debug boolean DEFAULT false)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_start_time TIMESTAMPTZ;
    v_tier_a INT := 0;
    v_tier_b INT := 0;
    v_tier_c INT := 0;
    v_tier_d INT := 0;
    v_total INT := 0;
BEGIN
    v_start_time := clock_timestamp();
    
    IF print_debug THEN
        RAISE NOTICE 'Starting inventory population at %', v_start_time;
    END IF;

    -- Optionally clear existing inventory
    IF clear_existing THEN
        IF print_debug THEN
            RAISE NOTICE 'Truncating inventory, rental, and payment tables...';
        END IF;
        -- TRUNCATE is faster and avoids MVCC bloat
        -- CASCADE handles FK dependencies automatically
        TRUNCATE bluebox.inventory RESTART IDENTITY CASCADE;
        COMMIT;
    END IF;

    -- Create tiered inventory
    WITH film_tiers AS (
        SELECT 
            film_id,
            popularity,
            release_date,
            vote_average,
            CASE 
                WHEN popularity >= 100 OR release_date > now() - interval '1 year' THEN 'A'
                WHEN popularity >= 30 OR release_date > now() - interval '3 years' THEN 'B'
                WHEN popularity >= 10 OR vote_average >= 7.0 THEN 'C'
                ELSE 'D'
            END as tier
        FROM bluebox.film
        WHERE film_id NOT IN (SELECT DISTINCT film_id FROM bluebox.inventory)
    ),
    stores_randomized AS (
        SELECT store_id, random() as rnd
        FROM bluebox.store
    ),
    -- Tier A: All stores, 10-14 copies (new/popular)
    tier_a_inventory AS (
        SELECT f.film_id, s.store_id, floor(random() * 5 + 10)::int as copies
        FROM film_tiers f
        CROSS JOIN bluebox.store s
        WHERE f.tier = 'A'
    ),
    -- Tier B: ~60% of stores, 5-7 copies (medium popularity)
    tier_b_inventory AS (
        SELECT f.film_id, s.store_id, floor(random() * 3 + 5)::int as copies
        FROM film_tiers f
        CROSS JOIN stores_randomized s
        WHERE f.tier = 'B' AND s.rnd < 0.6
    ),
    -- Tier C: ~30% of stores, 2-4 copies (decent)
    tier_c_inventory AS (
        SELECT f.film_id, s.store_id, floor(random() * 3 + 2)::int as copies
        FROM film_tiers f
        CROSS JOIN stores_randomized s
        WHERE f.tier = 'C' AND s.rnd < 0.3
    ),
    -- Tier D: ~10% of stores, 1-2 copies (long tail)
    tier_d_inventory AS (
        SELECT f.film_id, s.store_id, floor(random() * 2 + 1)::int as copies
        FROM film_tiers f
        CROSS JOIN stores_randomized s
        WHERE f.tier = 'D' AND s.rnd < 0.1
    ),
    all_inventory AS (
        SELECT * FROM tier_a_inventory UNION ALL
        SELECT * FROM tier_b_inventory UNION ALL
        SELECT * FROM tier_c_inventory UNION ALL
        SELECT * FROM tier_d_inventory
    )
    INSERT INTO bluebox.inventory (film_id, store_id, status_id)
    SELECT film_id, store_id, 1
    FROM all_inventory, generate_series(1, copies);

    COMMIT;

    -- Get counts for reporting
    SELECT count(*) INTO v_total FROM bluebox.inventory;
    
    IF print_debug THEN
        RAISE NOTICE 'Inventory population complete in % seconds', 
            EXTRACT(EPOCH FROM clock_timestamp() - v_start_time)::numeric(10,2);
        RAISE NOTICE 'Total inventory items: %', v_total;
    END IF;
END;
$$;


--
-- Name: process_lost_inventory(integer, boolean, boolean); Type: PROCEDURE; Schema: bluebox; Owner: -
--

CREATE PROCEDURE bluebox.process_lost_inventory(IN lost_threshold_days integer DEFAULT 30, IN deactivate_customer boolean DEFAULT true, IN print_debug boolean DEFAULT false)
    LANGUAGE plpgsql
    AS $_$
DECLARE
    v_lost_count INT;
    v_total_charges NUMERIC(10,2);
    v_lost_status_id INT;
BEGIN
    -- Get the status_id for 'lost'
    SELECT status_id INTO v_lost_status_id 
    FROM bluebox.inventory_status 
    WHERE status_code = 'lost';

    -- Find overdue rentals and process them
    WITH overdue_rentals AS (
        SELECT 
            r.rental_id,
            r.customer_id,
            r.inventory_id,
            lower(r.rental_period) as rental_start,
            f.replacement_cost,
            f.title
        FROM bluebox.rental r
        JOIN bluebox.inventory i ON r.inventory_id = i.inventory_id
        JOIN bluebox.film f ON i.film_id = f.film_id
        WHERE upper(r.rental_period) IS NULL
          AND lower(r.rental_period) < now() - (lost_threshold_days || ' days')::INTERVAL
          AND i.status_id = 1  -- only in_circulation items
    ),
    -- Mark inventory as lost
    mark_lost AS (
        UPDATE bluebox.inventory i
        SET status_id = v_lost_status_id, last_update = now()
        FROM overdue_rentals o
        WHERE i.inventory_id = o.inventory_id
        RETURNING i.inventory_id
    ),
    -- Close the rental
    close_rental AS (
        UPDATE bluebox.rental r
        SET rental_period = tstzrange(lower(rental_period), now()),
            last_update = now()
        FROM overdue_rentals o
        WHERE r.rental_id = o.rental_id
        RETURNING r.rental_id, r.customer_id
    ),
    -- Charge replacement cost
    charge_customer AS (
        INSERT INTO bluebox.payment (customer_id, rental_id, amount, payment_date)
        SELECT 
            o.customer_id,
            o.rental_id,
            COALESCE(o.replacement_cost, 19.99),
            now()
        FROM overdue_rentals o
        RETURNING amount
    ),
    -- Optionally deactivate customer
    deactivate AS (
        UPDATE bluebox.customer c
        SET activebool = FALSE, last_update = now()
        FROM overdue_rentals o
        WHERE c.customer_id = o.customer_id
          AND deactivate_customer = TRUE
        RETURNING c.customer_id
    )
    SELECT count(*), COALESCE(sum(amount), 0)
    INTO v_lost_count, v_total_charges
    FROM charge_customer;

    IF print_debug THEN
        RAISE NOTICE 'Lost inventory processing complete:';
        RAISE NOTICE '  Items marked lost: %', v_lost_count;
        RAISE NOTICE '  Total replacement charges: $%', v_total_charges;
    END IF;

    COMMIT;
END;
$_$;


--
-- Name: process_lost_rentals(interval, boolean); Type: PROCEDURE; Schema: bluebox; Owner: -
--

CREATE PROCEDURE bluebox.process_lost_rentals(IN p_lost_after interval DEFAULT '30 days'::interval, IN p_print_debug boolean DEFAULT false)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_lost_count int;
    v_payments_created int;
BEGIN
    WITH lost_rentals AS MATERIALIZED (
        SELECT 
            r.rental_id,
            r.customer_id,
            r.inventory_id,
            r.store_id,
            lower(r.rental_period) as rental_start,
            now() as loss_date
        FROM bluebox.rental r
        WHERE upper(r.rental_period) IS NULL
          AND lower(r.rental_period) < now() - p_lost_after
    ),
    
    closed_rentals AS (
        UPDATE bluebox.rental r
        SET rental_period = tstzrange(lower(r.rental_period), lr.loss_date)
        FROM lost_rentals lr
        WHERE r.rental_id = lr.rental_id
        RETURNING r.rental_id, r.inventory_id, r.customer_id, lr.loss_date
    ),
    
    lost_inventory AS (
        UPDATE bluebox.inventory i
        SET status_id = 2,  -- 'lost'
            last_update = now()
        FROM closed_rentals cr
        WHERE i.inventory_id = cr.inventory_id
        RETURNING i.inventory_id, i.film_id
    ),
    
    payment_info AS (
        SELECT 
            cr.rental_id,
            cr.customer_id,
            cr.loss_date as payment_date,
            bluebox.get_replacement_cost(li.film_id) as amount
        FROM closed_rentals cr
        JOIN lost_inventory li ON li.inventory_id = cr.inventory_id
    ),
    
    created_payments AS (
        INSERT INTO bluebox.payment (customer_id, rental_id, amount, payment_date)
        SELECT customer_id, rental_id, amount, payment_date
        FROM payment_info
        RETURNING payment_id
    )
    
    SELECT 
        (SELECT count(*) FROM closed_rentals),
        (SELECT count(*) FROM created_payments)
    INTO v_lost_count, v_payments_created;
    
    IF p_print_debug THEN
        RAISE NOTICE 'Marked % rentals as lost, created % payments (replacement cost)', 
            v_lost_count, v_payments_created;
    END IF;
    
    COMMIT;
END;
$$;


--
-- Name: PROCEDURE process_lost_rentals(IN p_lost_after interval, IN p_print_debug boolean); Type: COMMENT; Schema: bluebox; Owner: -
--

COMMENT ON PROCEDURE bluebox.process_lost_rentals(IN p_lost_after interval, IN p_print_debug boolean) IS 'Mark very old open rentals as lost and charge replacement cost.

This procedure:
1. Finds open rentals older than p_lost_after
2. Closes the rental (sets end time to now)
3. Marks the inventory as "lost" (status_id = 2)
4. Charges the customer the film replacement cost

Parameters:
  p_lost_after   - How long before an open rental is considered lost (default: 30 days)
  p_print_debug  - Print debug messages (default: false)

Typical usage with pg_cron:
  -- Run daily at 3am to process lost rentals
  SELECT cron.schedule(''process-lost-rentals'', ''0 3 * * *'', 
      $CALL bluebox.process_lost_rentals()$);

Examples:
  -- Default: mark rentals open > 30 days as lost
  CALL bluebox.process_lost_rentals();
  
  -- More aggressive: mark rentals open > 14 days as lost
  CALL bluebox.process_lost_rentals(
      p_lost_after := interval ''14 days'',
      p_print_debug := true
  );
';


--
-- Name: process_lost_rentals(interval, boolean, boolean); Type: PROCEDURE; Schema: bluebox; Owner: -
--

CREATE PROCEDURE bluebox.process_lost_rentals(IN p_lost_after interval DEFAULT '30 days'::interval, IN p_suspend_customer boolean DEFAULT true, IN p_print_debug boolean DEFAULT false)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_lost_count int;
    v_payments_created int;
    v_suspended_count int;
BEGIN
    WITH lost_rentals AS MATERIALIZED (
        SELECT 
            r.rental_id,
            r.customer_id,
            r.inventory_id,
            r.store_id,
            lower(r.rental_period) as rental_start,
            now() as loss_date
        FROM bluebox.rental r
        WHERE upper(r.rental_period) IS NULL
          AND lower(r.rental_period) < now() - p_lost_after
    ),
    
    closed_rentals AS (
        UPDATE bluebox.rental r
        SET rental_period = tstzrange(lower(r.rental_period), lr.loss_date)
        FROM lost_rentals lr
        WHERE r.rental_id = lr.rental_id
        RETURNING r.rental_id, r.inventory_id, r.customer_id, lr.loss_date
    ),
    
    lost_inventory AS (
        UPDATE bluebox.inventory i
        SET status_id = 2,  -- 'lost'
            last_update = now()
        FROM closed_rentals cr
        WHERE i.inventory_id = cr.inventory_id
        RETURNING i.inventory_id, i.film_id
    ),
    
    payment_info AS (
        SELECT 
            cr.rental_id,
            cr.customer_id,
            cr.loss_date as payment_date,
            bluebox.get_replacement_cost(li.film_id) as amount
        FROM closed_rentals cr
        JOIN lost_inventory li ON li.inventory_id = cr.inventory_id
    ),
    
    created_payments AS (
        INSERT INTO bluebox.payment (customer_id, rental_id, amount, payment_date)
        SELECT customer_id, rental_id, amount, payment_date
        FROM payment_info
        RETURNING payment_id, rental_id, customer_id
    ),
    
    -- Suspend customers who lost items
    suspend_customers AS (
        UPDATE bluebox.customer c
        SET activebool = FALSE, last_update = now()
        FROM created_payments cp
        WHERE c.customer_id = cp.customer_id
          AND p_suspend_customer
        RETURNING c.customer_id, cp.rental_id
    ),
    
    -- Log the suspensions
    log_suspensions AS (
        INSERT INTO bluebox.customer_status_log (customer_id, status, reason_code, rental_id, notes)
        SELECT customer_id, 'suspended', 'lost_item', rental_id, 'Item not returned, charged replacement cost'
        FROM suspend_customers
        RETURNING log_id
    )
    
    SELECT 
        (SELECT count(*) FROM closed_rentals),
        (SELECT count(*) FROM created_payments),
        (SELECT count(*) FROM log_suspensions)
    INTO v_lost_count, v_payments_created, v_suspended_count;
    
    IF p_print_debug THEN
        RAISE NOTICE 'Marked % rentals as lost, created % payments, suspended % customers', 
            v_lost_count, v_payments_created, v_suspended_count;
    END IF;
    
    COMMIT;
END;
$$;


--
-- Name: protect_circulation_start(); Type: FUNCTION; Schema: bluebox; Owner: -
--

CREATE FUNCTION bluebox.protect_circulation_start() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF OLD.circulation_start IS DISTINCT FROM NEW.circulation_start THEN
        RAISE WARNING 'circulation_start is immutable and cannot be changed (inventory_id: %). Keeping original value: %', 
            OLD.inventory_id, OLD.circulation_start;
        NEW.circulation_start := OLD.circulation_start;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: random_between(numeric, numeric, integer); Type: FUNCTION; Schema: bluebox; Owner: -
--

CREATE FUNCTION bluebox.random_between(min_val numeric, max_val numeric, round_to integer DEFAULT 0) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
    value NUMERIC = random() * (max_val - min_val) + min_val;
BEGIN
   IF round_to = 0 THEN 
       RETURN floor(value);
   ELSE 
       RETURN round(value, round_to);
   END IF;
END
$$;


--
-- Name: rebalance_inventory(integer, boolean); Type: PROCEDURE; Schema: bluebox; Owner: -
--

CREATE PROCEDURE bluebox.rebalance_inventory(IN max_moves_per_run integer DEFAULT 10000, IN print_debug boolean DEFAULT false)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_start_time TIMESTAMPTZ;
    v_moved INT := 0;
BEGIN
    v_start_time := clock_timestamp();
    
    IF print_debug THEN
        RAISE NOTICE 'Starting inventory rebalance at %', v_start_time;
    END IF;

    -- Calculate store targets dynamically and rebalance
    WITH store_metrics AS (
        SELECT 
            s.store_id,
            count(DISTINCT c.customer_id) as nearby_customers
        FROM bluebox.store s
        LEFT JOIN bluebox.customer c ON ST_DWithin(s.geog, c.geog, 25000)
        GROUP BY s.store_id
    ),
    totals AS (
        SELECT 
            (SELECT count(*) FROM bluebox.inventory WHERE status_id = 1) as total_inventory,
            (SELECT count(*) FROM bluebox.store) as store_count,
            sum(nearby_customers) as total_customers
        FROM store_metrics
    ),
    dynamic_params AS (
        SELECT 
            -- Floor is 40% of average inventory per store
            (total_inventory / store_count * 0.4)::int as floor_inventory,
            -- Remainder to distribute proportionally
            total_inventory - (total_inventory / store_count * 0.4)::int * store_count as remainder,
            total_customers
        FROM totals
    ),
    store_targets AS (
        SELECT 
            sm.store_id,
            sm.nearby_customers,
            -- Dynamic target: floor + proportional share of remainder
            dp.floor_inventory + (sm.nearby_customers::float / dp.total_customers * dp.remainder)::int as target_inventory,
            (SELECT count(*) FROM bluebox.inventory i WHERE i.store_id = sm.store_id AND i.status_id = 1) as current_inventory
        FROM store_metrics sm, dynamic_params dp
    ),
    -- Stores that need inventory (understocked)
    understocked AS (
        SELECT store_id, target_inventory - current_inventory as need
        FROM store_targets
        WHERE current_inventory < target_inventory * 0.9  -- 10% buffer
    ),
    -- Stores with excess inventory (overstocked)  
    overstocked AS (
        SELECT store_id, current_inventory - target_inventory as excess
        FROM store_targets
        WHERE current_inventory > target_inventory * 1.1  -- 10% buffer
    ),
    -- Available inventory to move (in_circulation, not currently rented)
    moveable_inventory AS (
        SELECT i.inventory_id, i.store_id, i.film_id,
            row_number() OVER (PARTITION BY i.store_id ORDER BY random()) as rn,
            o.excess
        FROM bluebox.inventory i
        INNER JOIN overstocked o ON i.store_id = o.store_id
        LEFT JOIN bluebox.rental r ON i.inventory_id = r.inventory_id 
            AND upper(r.rental_period) IS NULL
        WHERE i.status_id = 1
          AND r.rental_id IS NULL  -- not currently rented
    ),
    -- Only take up to 'excess' items from each overstocked store
    limited_moveable AS (
        SELECT inventory_id, store_id, film_id, rn
        FROM moveable_inventory
        WHERE rn <= excess
    ),
    -- Assign each moveable item to an understocked store (round-robin style)
    understocked_numbered AS (
        SELECT store_id, need, 
            row_number() OVER (ORDER BY need DESC) as store_rank,
            count(*) OVER () as total_understocked
        FROM understocked
    ),
    moves AS (
        SELECT 
            lm.inventory_id,
            lm.store_id as from_store,
            un.store_id as to_store
        FROM (SELECT *, row_number() OVER (ORDER BY random()) as global_rn FROM limited_moveable) lm
        JOIN understocked_numbered un 
            ON ((lm.global_rn - 1) % un.total_understocked) + 1 = un.store_rank
        LIMIT max_moves_per_run
    )
    UPDATE bluebox.inventory i
    SET store_id = m.to_store, last_update = now()
    FROM moves m
    WHERE i.inventory_id = m.inventory_id;

    GET DIAGNOSTICS v_moved = ROW_COUNT;

    IF print_debug THEN
        RAISE NOTICE 'Rebalance complete in % seconds', 
            EXTRACT(EPOCH FROM clock_timestamp() - v_start_time)::numeric(10,2);
        RAISE NOTICE 'Inventory items moved: %', v_moved;
    END IF;

    COMMIT;
END;
$$;


--
-- Name: update_customer_activity(integer, numeric, boolean); Type: PROCEDURE; Schema: bluebox; Owner: -
--

CREATE PROCEDURE bluebox.update_customer_activity(IN dormant_days integer DEFAULT 180, IN reactivate_pct numeric DEFAULT 0.5, IN print_debug boolean DEFAULT false)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_deactivated INT;
    v_reactivated INT;
BEGIN
    -- Step 1: Deactivate customers who haven't rented in dormant_days
    -- and don't have any open rentals
    WITH customers_to_deactivate AS (
        SELECT c.customer_id
        FROM bluebox.customer c
        LEFT JOIN bluebox.rental r ON c.customer_id = r.customer_id
        WHERE c.activebool = TRUE
        GROUP BY c.customer_id
        HAVING 
            (MAX(lower(r.rental_period)) IS NULL 
             OR MAX(lower(r.rental_period)) < now() - (dormant_days || ' days')::INTERVAL)
            AND COUNT(*) FILTER (WHERE upper(r.rental_period) IS NULL) = 0
    ),
    do_deactivate AS (
        UPDATE bluebox.customer c
        SET activebool = FALSE, last_update = now()
        FROM customers_to_deactivate ctd
        WHERE c.customer_id = ctd.customer_id
        RETURNING c.customer_id
    ),
    log_deactivations AS (
        INSERT INTO bluebox.customer_status_log (customer_id, status, reason_code, notes)
        SELECT customer_id, 'inactive', 'inactivity', 
               format('No rental in %s days', dormant_days)
        FROM do_deactivate
    )
    SELECT count(*) INTO v_deactivated FROM do_deactivate;

    -- Step 2: Randomly reactivate a small percentage of inactive customers
    -- Simulates win-back marketing campaigns
    WITH random_reactivate AS (
        SELECT customer_id
        FROM bluebox.customer
        WHERE activebool = FALSE
          AND random() < (reactivate_pct / 100.0)
    ),
    do_reactivate AS (
        UPDATE bluebox.customer c
        SET activebool = TRUE, last_update = now()
        FROM random_reactivate rr
        WHERE c.customer_id = rr.customer_id
        RETURNING c.customer_id
    ),
    log_reactivations AS (
        INSERT INTO bluebox.customer_status_log (customer_id, status, reason_code, notes)
        SELECT customer_id, 'active', 'winback', 'Random reactivation (simulated marketing)'
        FROM do_reactivate
    )
    SELECT count(*) INTO v_reactivated FROM do_reactivate;

    IF print_debug THEN
        RAISE NOTICE 'Customer activity update complete:';
        RAISE NOTICE '  Deactivated (inactivity): %', v_deactivated;
        RAISE NOTICE '  Reactivated (win-back): %', v_reactivated;
    END IF;

    COMMIT;
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
-- Name: customer_status_log; Type: TABLE; Schema: bluebox; Owner: -
--

CREATE TABLE bluebox.customer_status_log (
    log_id bigint NOT NULL,
    customer_id integer NOT NULL,
    status_date timestamp with time zone DEFAULT now() NOT NULL,
    status text NOT NULL,
    reason_code text NOT NULL,
    notes text,
    rental_id bigint
);


--
-- Name: customer_status_log_log_id_seq; Type: SEQUENCE; Schema: bluebox; Owner: -
--

ALTER TABLE bluebox.customer_status_log ALTER COLUMN log_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME bluebox.customer_status_log_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
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
    last_update timestamp with time zone DEFAULT now() NOT NULL,
    status_id integer DEFAULT 1 NOT NULL,
    circulation_start timestamp with time zone DEFAULT now() NOT NULL
)
WITH (autovacuum_vacuum_scale_factor='.60', autovacuum_vacuum_threshold='100', autovacuum_analyze_scale_factor='.80');


--
-- Name: inventory_status; Type: TABLE; Schema: bluebox; Owner: -
--

CREATE TABLE bluebox.inventory_status (
    status_id integer NOT NULL,
    status_code text NOT NULL,
    description text,
    display_order integer
);


--
-- Name: inventory_status_status_id_seq; Type: SEQUENCE; Schema: bluebox; Owner: -
--

ALTER TABLE bluebox.inventory_status ALTER COLUMN status_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME bluebox.inventory_status_status_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


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
-- Name: pricing; Type: TABLE; Schema: bluebox; Owner: -
--

CREATE TABLE bluebox.pricing (
    pricing_key text NOT NULL,
    pricing_value numeric(10,2) NOT NULL,
    description text,
    effective_date date DEFAULT CURRENT_DATE NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
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
-- Name: flyway_schema_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.flyway_schema_history (
    installed_rank integer NOT NULL,
    version character varying(50),
    description character varying(200) NOT NULL,
    type character varying(20) NOT NULL,
    script character varying(1000) NOT NULL,
    checksum integer,
    installed_by character varying(100) NOT NULL,
    installed_on timestamp without time zone DEFAULT now() NOT NULL,
    execution_time integer NOT NULL,
    success boolean NOT NULL
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
-- Name: customer_status_log customer_status_log_pkey; Type: CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.customer_status_log
    ADD CONSTRAINT customer_status_log_pkey PRIMARY KEY (log_id);


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
-- Name: inventory_status inventory_status_pkey; Type: CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.inventory_status
    ADD CONSTRAINT inventory_status_pkey PRIMARY KEY (status_id);


--
-- Name: inventory_status inventory_status_status_code_key; Type: CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.inventory_status
    ADD CONSTRAINT inventory_status_status_code_key UNIQUE (status_code);


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
-- Name: pricing pricing_pkey; Type: CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.pricing
    ADD CONSTRAINT pricing_pkey PRIMARY KEY (pricing_key);


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
-- Name: flyway_schema_history flyway_schema_history_pk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flyway_schema_history
    ADD CONSTRAINT flyway_schema_history_pk PRIMARY KEY (installed_rank);


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
-- Name: idx_csl_customer; Type: INDEX; Schema: bluebox; Owner: -
--

CREATE INDEX idx_csl_customer ON bluebox.customer_status_log USING btree (customer_id, status_date DESC);


--
-- Name: idx_csl_date; Type: INDEX; Schema: bluebox; Owner: -
--

CREATE INDEX idx_csl_date ON bluebox.customer_status_log USING btree (status_date);


--
-- Name: idx_csl_status; Type: INDEX; Schema: bluebox; Owner: -
--

CREATE INDEX idx_csl_status ON bluebox.customer_status_log USING btree (status, status_date);


--
-- Name: idx_pricing_key; Type: INDEX; Schema: bluebox; Owner: -
--

CREATE INDEX idx_pricing_key ON bluebox.pricing USING btree (pricing_key);


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
-- Name: rental_store_id_idx; Type: INDEX; Schema: bluebox; Owner: -
--

CREATE INDEX rental_store_id_idx ON bluebox.rental USING btree (store_id);


--
-- Name: us_postal_code_geog_gix; Type: INDEX; Schema: bluebox; Owner: -
--

CREATE INDEX us_postal_code_geog_gix ON bluebox.zip_code_info USING gist (geog);


--
-- Name: flyway_schema_history_s_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flyway_schema_history_s_idx ON public.flyway_schema_history USING btree (success);


--
-- Name: inventory inventory_protect_circulation_start; Type: TRIGGER; Schema: bluebox; Owner: -
--

CREATE TRIGGER inventory_protect_circulation_start BEFORE UPDATE ON bluebox.inventory FOR EACH ROW EXECUTE FUNCTION bluebox.protect_circulation_start();


--
-- Name: customer_status_log customer_status_log_customer_id_fkey; Type: FK CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.customer_status_log
    ADD CONSTRAINT customer_status_log_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES bluebox.customer(customer_id);


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
-- Name: inventory inventory_status_id_fkey; Type: FK CONSTRAINT; Schema: bluebox; Owner: -
--

ALTER TABLE ONLY bluebox.inventory
    ADD CONSTRAINT inventory_status_id_fkey FOREIGN KEY (status_id) REFERENCES bluebox.inventory_status(status_id);


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

