# Changelog

All notable changes to the Bluebox project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.7.0] - 2026-04-08

### Added
- **Database views** for common app and analytics access patterns:
  - `v_film_catalog` — film browse page with genre names, cast/crew counts
  - `v_store_inventory_summary` — per-store inventory breakdown by status
  - `v_customer_rentals` — customer rental history with payment and film details
  - `v_overdue_rentals` — open rentals past 5-day threshold with customer/store context
  - `v_revenue_summary` — monthly revenue rollup by store
- **New load test scenarios** querying the views:
  - `browse_catalog` (weight=10) — filter film catalog by release date, rating, budget
  - `customer_account` (weight=8) — customer rental history and spending summaries
  - `store_dashboard` (weight=8) — store inventory status and cross-store comparison
  - `overdue_check` (weight=5) — overdue rental lookup for operations
  - `revenue_dashboard` (weight=5) — monthly revenue trends and store rankings

### To Do
- Clean regeneration of rental/payment data with the updated procedure
- Fix `generate_rentals` to exclude inventory with near-future historical rentals

## [0.6.0] - 2026-04-07

### Added
- **Load testing framework** (`load-testing/`): multi-threaded query load generator with psycopg3 connection pool
  - 28 scenarios covering reads, writes, and analytics
  - Weight-based scheduling for realistic app traffic (17 scenarios)
  - Interval-based scheduling for infrequent analytics and anti-pattern demos (10 scenarios)
  - Time-of-day RPM multipliers (night/morning/evening/weekend/holiday)
  - In-memory entity pools with periodic refresh, replacing `ORDER BY random()` table scans
  - Title fragment search for realistic film lookups
  - Optional OpenTelemetry tracing with span attributes
  - Scenario catalog documentation (`scenario-catalog.md`)
- **New load test scenarios:**
  - `film_availability` — check film stock at nearby stores (PostGIS)
  - `new_at_store` — recent releases in stock at a store
  - `overdue_rentals` — open rentals past 5-day threshold
  - `track_disc` — full rental journey of a single inventory item with geography
  - `store_performance` — revenue and utilization comparison across stores
  - `inventory_utilization` — rental count vs copy count per film at a store
  - `stale_inventory` — discs not rented in 90+ days
  - `disc_recycling` — retire heavily-rented discs (mutates data)
- **Anti-pattern demo scenarios** for training and product demos:
  - Variable IN-list queryid pollution (PG<=17 vs PG18 comparison)
  - Wrong index choice (backward PK/btree scan)
  - Correlated subquery in HAVING clause
  - Inventory fan-out (millions of intermediate rows)
  - Wide-row external disk sort (work_mem spill)
- **TMDB data loader** (`tmdb-dataload/`): restructured as a proper Python project with `uv` + `pyproject.toml`, CLI entry point `bluebox-tmdb`

### Changed
- `generate_rental_history` rewritten for ~10x performance improvement (3-4 sec/day vs 30-45 sec/day)
  - Store-centric loop design instead of global customer selection
  - Pre-computed store-customer proximity pool (ST_DWithin geo-join runs once per call)
  - Proportional per-store targeting to prevent over-counting from overlapping catchment areas
  - `t_day_outstanding` temp table for cross-store exclusion within a day
  - Corrected `&&` (overlaps) operator for rental period checks (was `@>` / contains)
  - Inventory movement restored: each rental relocates the disc to a random nearby store, P(same store) = 1/N
- `return_rental` load test scenario now relocates inventory to a random nearby store on return, matching `complete_rentals` behavior
- Migrated sequences to identity columns in remaining tables
- Critical fix for load testing: `autocommit=True` + `prepare_threshold=None` on ConnectionPool to prevent pg_stat_statements queryid pollution from prepared statements

## [0.5.0] - 2026-02-12

### Added
- Flyway Enterprise project for schema migrations (`bluebox_schema/`)
  - Baseline migration from v0.4
  - Migrations V002-V009 for v0.5 changes
  - Redgate schema model (`.rgm` files) for all database objects
- `complete_rentals` procedure — batch-closes open rentals with inventory relocation
- `process_lost_rentals` / `process_lost_inventory` procedures
- `update_customer_activity` procedure — deactivates dormant customers
- `nightly_maintenance` procedure — orchestrates lost inventory, customer activity, and ANALYZE
- `rebalance_inventory` procedure — redistributes inventory based on nearby customer density
- `populate_inventory` procedure — tiered inventory distribution (A/B/C/D tiers by film popularity)
- `get_daily_rental_rate` function — calculates rental pricing
- `insert_payments` procedure — generates payment records for completed rentals
- Schema and data dump files for Docker project compatibility

### Changed
- Rental tracking switched from separate `rental_date`/`return_date` columns to `tstzrange` column (`rental_period`) with GiST index
- Added `inventory_status` table with status tracking (in_circulation, lost, damaged, retired)
- Added `circulation_start` to inventory table
- Updated `generate_rental_history` and `generate_rentals` for new rental_period column
- Customer table: added `full_name` generated column, `geog` geography column
- Store table: added geography column for PostGIS spatial queries
- Holiday table for rental volume adjustments

## [0.4.0] - 2025-11-02

### Added
- PostGIS geography columns for stores and customers
- `generate_rental_history` procedure — bulk-generates historical rental data
- `generate_rentals` procedure — creates new rentals for a time window
- TMDB API integration for real movie data (films, cast, crew, production companies)
- Staging schema with `film_credits`, `film_detail` tables and transform functions
- `zip_code_info` table with geographic data for location-based queries
- Schema-only and data-only dump files for flexible restoration
- Installation documentation

### Changed
- Film data sourced from TMDB API instead of fake Pagila titles
- Database requires PostGIS extension
- Schema restructured into `bluebox` (main), `staging` (ETL), `public` schemas

## [0.1.0] - 2023-10-31

### Added
- Initial Bluebox schema based on Pagila database
- Database dump for PostgreSQL
- Basic README and installation instructions

[Unreleased]: https://github.com/ryanbooz/bluebox/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/ryanbooz/bluebox/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/ryanbooz/bluebox/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/ryanbooz/bluebox/compare/v0.1.0...v0.4.0
[0.1.0]: https://github.com/ryanbooz/bluebox/releases/tag/v0.1.0
