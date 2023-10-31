# Bluebox

The Bluebox sample database is an updated sample database for PostgreSQL, building off of the [Pagila database](https://github.com/devrimgunduz/pagila/tree/master).

Although this database is far from complete, I had a few goals when modifying Pagila to create a more full-featured database that could be used for demonstrations and training.

The name **Bluebox** is a play on the US DVD vending machine company called Redbox<sup>TM</sup>, but blue for our favorite PostgreSQL elephant, Sloink.

## Download
The initial database has nearly two years of rental and payment data. This makes the backup just over 100MB and larger than I can upload to Github. Therefore, I am currently hosting the dump file in OneDrive and sharing it publicaly.

A future version of the database backup will be smaller once I have decent instructions for creating more data using the included functions.

https://bit.ly/bluebox_v0-1

### Goal 1: Utilize real movie data
I appreciate the fun nature of the fake movie titles, but it makes it more difficult to demonstrate information about common, often popular, movies. To this end, I settled on using [The Movie Database (TMDB)](https://www.themoviedb.org/), an open-source, community contributed database of movie and TV show information.

Using the [TMDB API](https://developer.themoviedb.org/docs), I could search for and import movie titles across multiple decades, including production companies, cast and crew, revenue and rating data, and more. There is certainly more work to do, but this is a starting place.

### Goal 2: Create fake but realistic geographical locations for stores and customers
I wanted to be able to use the store and customer data to create interesting queries, including ways of demonstrating basic PostGIS functionality. There is no way I could have done this on my own, and so I proposed the idea to Ryan Lambert ([Rustproof Labs](https://blog.rustprooflabs.com/)) who took the idea and ran with it. He's awesome like that! 

The result was the creation of [Geofaker](https://geofaker.com/geo-faker.html), a Docker image that can create commercial and residential points, along with fake names, phone numbers, and more. The process was straightforward thanks to Ryan's excellent documentation and provided Docker image.

For this initial sample database, I chose to use New York state as the boundary for creating locations.

### Goal 3: Historical and ongoing data generation
This is a sample database. I could spend months trying to create sophisticated functions to create hyper-realistic rental patterns across each store location, based on the number of nearby customers. 

I didn't do that. At least not now. 🙂

What I did create were some simple functions and stored procedures to:
 - create historical rentals where DVDs couldn't be checked out multiple times for the same period
 - create ongoing DVD rentals using a tool like pg_cron to invoke rental and payment functions
 - incorporate a simple US holiday calendar for major government holidays, to increase rental activity during holidays

 Again, these aren't the most sophisticated functions and stored procedures, but they are a starting point and provides users with the opportunity to create more data as time moves forward.

## External data sources
As mentioned above, the initial data came from a number of sources. To the best of my knowledge and investigation, all of this data is open-source or has a license that allows redistribution.

- [Geofaker]() by Ryan Lambert
- The [TMDB API]()
  - Utilizing the [tmdbv3api](https://github.com/AnthonyBloomer/tmdbv3api) Python package
- [US Public Holidays](https://learn.microsoft.com/en-us/azure/open-datasets/dataset-public-holidays?tabs=azureml-opendatasets) from the Azure Open Datasets packages
- The **Basic** dataset from [simplemaps](https://simplemaps.com/data/us-zips)

## Todo
There is a lot to do for this database to become more feature complete. I consider this a v0.1 currently. However, I have enough data and features to utilize this for upcoming training and presentations.

- Review and create proper indexing
  - For training, it's actually helpful to have missing indexes, but any full backup I provide should have reasonable indexing for other uses.
- recreate some of the VIEWS that existed in Pagila using the updated schema
- move application tables into a new, non-`public` schema
- remove the `staff` requirement
- possibly rename some tables
  - `person` (this is what TMDB calls actors/crew)
- add partitioning back to the `payment` table and possibly `rentals` as well
