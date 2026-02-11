-- ============================================================
-- BLUEBOX SHOWCASE QUERIES
-- Fun, informative queries demonstrating the richness of the data
-- ============================================================

-- ============================================================
-- GEOGRAPHIC ANALYSIS
-- ============================================================

-- Rental hotspots: which cities rent the most?
SELECT 
    z.city,
    z.state_id,
    count(r.rental_id) as total_rentals,
    count(DISTINCT c.customer_id) as customers,
    round(count(r.rental_id)::numeric / count(DISTINCT c.customer_id), 1) as rentals_per_customer
FROM bluebox.customer c
JOIN bluebox.zip_code_info z ON c.zip_code = z.zip_code
JOIN bluebox.rental r ON c.customer_id = r.customer_id
GROUP BY z.city, z.state_id
ORDER BY total_rentals DESC
LIMIT 10;

-- How far do customers travel to rent?
SELECT 
    CASE 
        WHEN dist_km < 5 THEN '< 5 km'
        WHEN dist_km < 10 THEN '5-10 km'
        WHEN dist_km < 15 THEN '10-15 km'
        WHEN dist_km < 20 THEN '15-20 km'
        ELSE '20+ km'
    END as distance_bucket,
    count(*) as rentals,
    round(100.0 * count(*) / sum(count(*)) OVER (), 1) as pct
FROM (
    SELECT 
        r.rental_id,
        ST_Distance(c.geog, s.geog) / 1000 as dist_km
    FROM bluebox.rental r
    JOIN bluebox.customer c ON r.customer_id = c.customer_id
    JOIN bluebox.store s ON r.store_id = s.store_id
) x
GROUP BY 1
ORDER BY min(dist_km);


-- ============================================================
-- SEASONAL TRENDS
-- ============================================================

-- Rentals by day of week
SELECT 
    to_char(lower(rental_period), 'Day') as day_of_week,
    extract(dow FROM lower(rental_period))::int as dow_num,
    count(*) as rentals,
    round(100.0 * count(*) / sum(count(*)) OVER (), 1) as pct
FROM bluebox.rental
GROUP BY 1, 2
ORDER BY dow_num;

-- Monthly trends with month-over-month change
SELECT 
    to_char(lower(rental_period), 'YYYY-MM') as month,
    count(*) as rentals,
    round(sum(p.amount)::numeric, 2) as revenue,
    round(100.0 * (count(*) - lag(count(*)) OVER (ORDER BY to_char(lower(rental_period), 'YYYY-MM'))) 
        / nullif(lag(count(*)) OVER (ORDER BY to_char(lower(rental_period), 'YYYY-MM')), 0), 1) as mom_change_pct
FROM bluebox.rental r
LEFT JOIN bluebox.payment p ON r.rental_id = p.rental_id
GROUP BY 1
ORDER BY 1 DESC
LIMIT 12;

-- Busiest holidays
SELECT 
    h.holiday_name,
    h.holiday_date,
    count(r.rental_id) as rentals_on_holiday
FROM bluebox.holiday h
LEFT JOIN bluebox.rental r ON lower(r.rental_period)::date = h.holiday_date
WHERE h.holiday_date BETWEEN '2024-01-01' AND '2025-12-31'
GROUP BY h.holiday_name, h.holiday_date
ORDER BY rentals_on_holiday DESC
LIMIT 10;


-- ============================================================
-- GENRE & ACTOR INSIGHTS
-- ============================================================

-- Most popular genres by rentals
SELECT 
    fg.name as genre,
    count(r.rental_id) as total_rentals,
    count(DISTINCT f.film_id) as films_in_genre,
    round(count(r.rental_id)::numeric / count(DISTINCT f.film_id), 0) as rentals_per_film
FROM bluebox.rental r
JOIN bluebox.inventory i ON r.inventory_id = i.inventory_id
JOIN bluebox.film f ON i.film_id = f.film_id
JOIN bluebox.film_genre fg ON fg.genre_id = ANY(f.genre_ids)
GROUP BY fg.name
ORDER BY total_rentals DESC
LIMIT 10;

-- Most rented actors
EXPLAIN
SELECT 
    p.name as actor,
    count(DISTINCT fc.film_id) as films,
    count(r.rental_id) as total_rentals,
    round(count(r.rental_id)::numeric / count(DISTINCT fc.film_id), 0) as rentals_per_film
FROM bluebox.person p
JOIN bluebox.film_cast fc ON p.person_id = fc.person_id
JOIN bluebox.inventory i ON fc.film_id = i.film_id
JOIN bluebox.rental r ON i.inventory_id = r.inventory_id
GROUP BY p.person_id, p.name
HAVING count(DISTINCT fc.film_id) >= 3
ORDER BY total_rentals DESC
LIMIT 15;

-- Most successful directors (by revenue)
SELECT 
    p.name as director,
    count(DISTINCT fc.film_id) as films_directed,
    count(r.rental_id) as total_rentals,
    round(sum(pay.amount)::numeric, 2) as total_revenue
FROM bluebox.person p
JOIN bluebox.film_crew fc ON p.person_id = fc.person_id
JOIN bluebox.inventory i ON fc.film_id = i.film_id
JOIN bluebox.rental r ON i.inventory_id = r.inventory_id
LEFT JOIN bluebox.payment pay ON r.rental_id = pay.rental_id
WHERE fc.job = 'Director'
GROUP BY p.person_id, p.name
HAVING count(DISTINCT fc.film_id) >= 2
ORDER BY total_rentals DESC
LIMIT 10;

-- Actor pairs who frequently work together
SELECT 
    p1.name as actor_1,
    p2.name as actor_2,
    count(DISTINCT fc1.film_id) as films_together
FROM bluebox.film_cast fc1
JOIN bluebox.film_cast fc2 ON fc1.film_id = fc2.film_id 
    AND fc1.person_id < fc2.person_id
JOIN bluebox.person p1 ON fc1.person_id = p1.person_id
JOIN bluebox.person p2 ON fc2.person_id = p2.person_id
GROUP BY p1.name, p2.name
HAVING count(DISTINCT fc1.film_id) >= 5
ORDER BY films_together DESC
LIMIT 15;

-- Find all films featuring a specific actor
SELECT 
    f.title,
    f.release_date,
    fc.film_character,
    f.vote_average
FROM bluebox.person p
JOIN bluebox.film_cast fc ON p.person_id = fc.person_id
JOIN bluebox.film f ON fc.film_id = f.film_id
WHERE p.name ILIKE '%Tom Hanks%'
ORDER BY f.release_date DESC;