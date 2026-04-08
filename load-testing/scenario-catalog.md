# Load Testing Scenario Catalog

## Scheduling Modes

Scenarios use one of two scheduling modes:

- **Weighted:** Selected proportionally from the RPM-driven pool. Frequency scales with `BASE_RPM` and time-of-day multipliers. Used for realistic app traffic.
- **Interval:** Fires on a fixed cadence (e.g., every 4-8 hours), independent of RPM. Used for infrequent analytics, demos, and maintenance operations.

## Weighted Scenarios

Baseline: `BASE_RPM=60`, time-of-day multipliers from `scheduler.py`, weekend 1.4x.
Total weight = 368.

- **Weekday total:** ~83,000 weighted requests/day
- **Weekend total:** ~116,200 weighted requests/day

### Realistic App Traffic

| Scenario | Wt | % | Weekday/day | Weekend/day | Cat | Main Tables / Views | What It Does |
|---|---|---|---|---|---|---|---|
| `browse_films` | 50 | 13.6% | ~11,300 | ~15,800 | read | film, film_genre, zip_code_info | 4 random search strategies (genre, rating, popularity, fulltext) |
| `film_detail` | 40 | 10.9% | ~9,000 | ~12,600 | read | film, film_cast, film_crew, person | Film detail page (3 queries) |
| `customer_rentals` | 30 | 8.2% | ~6,800 | ~9,500 | read | rental, inventory, film, payment | Customer rental history |
| `store_inventory` | 25 | 6.8% | ~5,600 | ~7,900 | read | inventory, film, rental | Store inventory + availability |
| `film_availability` | 20 | 5.4% | ~4,500 | ~6,300 | read | store, inventory, film, zip_code_info | Check film availability at nearby stores (PostGIS) |
| `film_cast` | 20 | 5.4% | ~4,500 | ~6,300 | read | film_cast, person | Cast list for a film |
| `create_rental` | 15 | 4.1% | ~3,400 | ~4,700 | write | customer, store, inventory, rental | Create open rental |
| `new_at_store` | 15 | 4.1% | ~3,400 | ~4,700 | read | inventory, film | New releases in stock at a store |
| `stores_nearby` | 15 | 4.1% | ~3,400 | ~4,700 | read | store, zip_code_info | PostGIS proximity search |
| `genre_popularity` | 15 | 4.1% | ~3,400 | ~4,700 | read | rental, inventory, film, film_genre | Genre rental counts (30-90 day window) |
| `return_rental` | 12 | 3.3% | ~2,700 | ~3,800 | write | rental, payment, inventory, store | Close rental + payment + inventory move |
| `browse_catalog` | 10 | 2.7% | ~2,300 | ~3,200 | read | **v_film_catalog** | Filter catalog by release date, rating, or budget |
| `overdue_rentals` | 10 | 2.7% | ~2,300 | ~3,200 | read | rental, customer, inventory, film | Open rentals past 5-day threshold |
| `customer_account` | 8 | 2.2% | ~1,800 | ~2,500 | read | **v_customer_rentals** | Rental history, spending summary, store-filtered history |
| `store_dashboard` | 8 | 2.2% | ~1,800 | ~2,500 | read | **v_store_inventory_summary** | Inventory status breakdown, cross-store comparison |
| `overdue_check` | 5 | 1.4% | ~1,100 | ~1,600 | read | **v_overdue_rentals** | Overdue rental lookup for ops (all or by store) |
| `revenue_dashboard` | 5 | 1.4% | ~1,100 | ~1,600 | read | **v_revenue_summary** | Monthly revenue trends, store rankings |

### Anti-Pattern Demos (Weighted)

These run frequently as part of normal traffic to populate pg_stat_statements with recognizable patterns.

| Scenario | Wt | % | Weekday/day | Weekend/day | Cat | Anti-Pattern | Impact |
|---|---|---|---|---|---|---|---|
| `batch_customer_rentals` | 15 | 4.1% | ~3,400 | ~4,700 | read | Variable IN-list | queryid pollution (PG<=17) |
| `batch_film_lookup` | 15 | 4.1% | ~3,400 | ~4,700 | read | Variable IN-list (title fragment search) | queryid pollution (PG<=17) |
| `multi_store_inventory` | 15 | 4.1% | ~3,400 | ~4,700 | read | Variable IN-list + NOT EXISTS | queryid pollution + correlated subquery |
| `recent_store_rentals` | 10 | 2.7% | ~2,300 | ~3,200 | read | Wrong index (ORDER BY rental_id DESC) | Backward PK scan |
| `recent_store_activity` | 10 | 2.7% | ~2,300 | ~3,200 | read | Wrong index (ORDER BY last_update DESC) | Backward btree scan |

## Interval Scenarios

These fire on a fixed cadence regardless of `BASE_RPM`. They do not respect time-of-day multipliers.

### Tier 2: Periodic Analytics & Operations (every 10-60 minutes)

| Scenario | Schedule | ~Calls/day | Cat | Main Tables | What It Does |
|---|---|---|---|---|---|
| `payment_detail_report` | 10-30m | 48-144 | analytics | rental, payment, customer, inventory, film | Wide 5-table join, external disk sort with default work_mem |
| `track_disc` | 15-30m | 48-96 | read | rental, store, customer, inventory, payment | Full journey of a disc through the system with geography |
| `store_performance` | 15-30m | 48-96 | analytics | store, rental, payment, inventory | Revenue, rental count, avg duration per store |
| `inventory_utilization` | 15-30m | 48-96 | analytics | inventory, film, rental | Rental count vs copy count per film at a store |
| `revenue_report` | 15-30m | 48-96 | analytics | rental, payment | Monthly revenue with LAG() window function |
| `rental_trends_report` | 15-30m | 48-96 | analytics | rental | Rentals by day-of-week, GiST range overlap |
| `stale_inventory` | 30-60m | 24-48 | analytics | inventory, film, rental | Discs not rented in 90+ days |

### Tier 2/3: Maintenance & Heavy Demos (every 2-8 hours)

| Scenario | Schedule | ~Calls/day | Cat | What It Does | Impact |
|---|---|---|---|---|---|
| `disc_recycling` | 2-4h | 6-12 | write | (currently disabled) Retires heavily-rented discs (status_id=4). Mutates data. | Gradually shrinks inventory at high-traffic stores |
| `above_avg_renters` | 4-8h | 3-6 | analytics | Correlated subquery anti-pattern | Re-executes constant subquery per row |
| `top_actors_naive` | 4-8h | 3-6 | analytics | Inventory fan-out anti-pattern | ~2.3M intermediate rows, 115MB spill per call |

## Disabled Scenarios

| Scenario | Cat | Purpose |
|---|---|---|
| `top_actors_report` (weight=0) | analytics | Fixed version of `top_actors_naive` with CTE pre-aggregation. Kept as a reference for demos, not executed during load testing. |

## Notes

- All entity selection (stores, customers, films, etc.) uses in-memory pools loaded at startup and refreshed hourly, eliminating `ORDER BY random()` table scans
- `batch_film_lookup` now searches by title fragment via ILIKE, producing naturally variable result counts
- The three IN-list scenarios combined are ~12.3% of weighted traffic -- significant queryid pollution, useful for PG<=17 vs PG18 comparison demos
- Write scenarios (`create_rental`, `return_rental`) use raw SQL, not the database procedures (`generate_rentals`, `complete_rentals`)
- `return_rental` relocates inventory to a random nearby store on return
- `disc_recycling` is the only interval scenario that mutates data -- it gradually retires worn-out discs
- Five view-based scenarios (`browse_catalog`, `customer_account`, `store_dashboard`, `overdue_check`, `revenue_dashboard`) query database views that exercise unindexed columns (film.release_date, film.vote_average, film.budget, inventory.status_id, payment.customer_id) — useful for missing-index analysis
- No periodic batch operations are simulated yet (nightly_maintenance, rebalance_inventory, complete_rentals)
