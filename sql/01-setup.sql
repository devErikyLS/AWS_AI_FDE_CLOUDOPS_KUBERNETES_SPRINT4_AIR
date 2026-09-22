CREATE TABLE IF NOT EXISTS items (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL
);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT FROM pg_roles WHERE rolname = 'anon'
    ) THEN
        CREATE ROLE anon NOLOGIN;
    END IF;
END
$$;

GRANT USAGE ON SCHEMA public TO anon;

GRANT SELECT, INSERT ON TABLE items TO anon;

GRANT USAGE, SELECT ON SEQUENCE items_id_seq TO anon;
