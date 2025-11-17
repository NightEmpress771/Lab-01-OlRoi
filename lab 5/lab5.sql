


-- 1) ІНДЕКСИ
CREATE INDEX IF NOT EXISTS idx_sessions_film_id ON sessions(film_id);
CREATE INDEX IF NOT EXISTS idx_tickets_session_id ON tickets(session_id);
CREATE INDEX IF NOT EXISTS idx_tickets_customer_name ON tickets(customer_name);

-- 2) МАТЕРІАЛІЗОВАНЕ ПРЕДСТАВЛЕННЯ
DROP MATERIALIZED VIEW IF EXISTS film_sales_mat;

CREATE MATERIALIZED VIEW film_sales_mat AS
SELECT f.film_id, f.title, COUNT(t.ticket_id) AS sold, SUM(f.price) AS total_income
FROM films f
LEFT JOIN sessions s ON f.film_id = s.film_id
LEFT JOIN tickets t ON s.session_id = t.session_id
GROUP BY f.film_id, f.title;

CREATE INDEX IF NOT EXISTS idx_film_sales_mat_movie ON film_sales_mat(film_id);

-- 3) ТРИГЕР ОНОВЛЕННЯ MATERIALIZED VIEW
CREATE OR REPLACE FUNCTION refresh_sales_mat()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM pg_sleep(0.2);
    REFRESH MATERIALIZED VIEW CONCURRENTLY film_sales_mat;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_refresh_sales ON tickets;

CREATE TRIGGER trg_refresh_sales
AFTER INSERT OR UPDATE OR DELETE ON tickets
FOR EACH STATEMENT
EXECUTE FUNCTION refresh_sales_mat();

-- 4) ЛОГУВАННЯ ЗМІН У sessions
CREATE TABLE IF NOT EXISTS logs (
    id SERIAL PRIMARY KEY,
    table_name TEXT,
    operation TEXT,
    data JSONB,
    created_at TIMESTAMP DEFAULT now()
);

CREATE OR REPLACE FUNCTION log_sessions_changes()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO logs(table_name, operation, data)
        VALUES ('sessions','INSERT', row_to_json(NEW));
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO logs(table_name, operation, data)
        VALUES ('sessions','UPDATE', json_build_object('old',OLD,'new',NEW));
    ELSE
        INSERT INTO logs(table_name, operation, data)
        VALUES ('sessions','DELETE', row_to_json(OLD));
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_log_sessions ON sessions;

CREATE TRIGGER trg_log_sessions
AFTER INSERT OR UPDATE OR DELETE ON sessions
FOR EACH ROW
EXECUTE FUNCTION log_sessions_changes();

-- 5) ВАЛІДАЦІЯ films
CREATE OR REPLACE FUNCTION validate_film()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.duration <= 0 THEN
        RAISE EXCEPTION 'Duration must be > 0';
    END IF;
    IF NEW.price < 0 THEN
        RAISE EXCEPTION 'Price must be ≥ 0';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validate_film ON films;

CREATE TRIGGER trg_validate_film
BEFORE INSERT OR UPDATE ON films
FOR EACH ROW
EXECUTE FUNCTION validate_film();

-- 6) АУДИТ tickets
CREATE TABLE IF NOT EXISTS audit_log (
    id SERIAL PRIMARY KEY,
    table_name TEXT,
    operation TEXT,
    old_data JSONB,
    new_data JSONB,
    changed_by TEXT DEFAULT current_user,
    changed_at TIMESTAMP DEFAULT now()
);

CREATE OR REPLACE FUNCTION audit_tickets()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log(table_name, operation, new_data)
        VALUES ('tickets','INSERT', row_to_json(NEW));
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log(table_name, operation, old_data, new_data)
        VALUES ('tickets','UPDATE', row_to_json(OLD), row_to_json(NEW));
    ELSE
        INSERT INTO audit_log(table_name, operation, old_data)
        VALUES ('tickets','DELETE', row_to_json(OLD));
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_audit_tickets ON tickets;

CREATE TRIGGER trg_audit_tickets
AFTER INSERT OR UPDATE OR DELETE ON tickets
FOR EACH ROW
EXECUTE FUNCTION audit_tickets();
