SET check_function_bodies = false;

DO LANGUAGE plpgsql $$BEGIN RAISE NOTICE 'Creating bluebox.person.fulltext...';END$$;
ALTER TABLE bluebox.person ADD COLUMN fulltext tsvector GENERATED ALWAYS AS (to_tsvector('english'::regconfig, ((COALESCE(name, ''::text) || ' '::text) || COALESCE(biography, ''::text)))) STORED;
