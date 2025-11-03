--
-- Library management laboratory work (levels 1-3) - FINAL FIXED VERSION
-- SQL script for PostgreSQL
--
-- File: library_lab3_FIXED_FINAL_EXTENDED.sql
-- Created: Automated script (Correction and Extension)
-- Purpose: Implements all features, fixes syntax/logic errors, and includes more sample data.
--

-- Clean up existing objects (safe for re-run)
DROP TABLE IF EXISTS deferred_tasks CASCADE;
DROP TABLE IF EXISTS book_versions CASCADE;
DROP TABLE IF EXISTS change_history CASCADE;
DROP TABLE IF EXISTS reservations CASCADE;
DROP TABLE IF EXISTS loans CASCADE;
DROP TABLE IF EXISTS books CASCADE;
DROP TABLE IF EXISTS authors CASCADE;
DROP TABLE IF EXISTS readers CASCADE;
DROP FUNCTION IF EXISTS fn_checkout_book(INTEGER, INTEGER) CASCADE;
DROP FUNCTION IF EXISTS fn_return_book(INTEGER, INTEGER) CASCADE;
DROP FUNCTION IF EXISTS fn_process_deferred() CASCADE;
DROP FUNCTION IF EXISTS trg_log_changes() CASCADE;
DROP FUNCTION IF EXISTS trg_books_delete_archive() CASCADE;
DROP FUNCTION IF EXISTS trg_book_versioning() CASCADE;
DROP FUNCTION IF EXISTS fn_retry_process_deferred(INTEGER) CASCADE;
DROP FUNCTION IF EXISTS fn_revert_book_to_version(INTEGER, INTEGER) CASCADE;
DROP VIEW IF EXISTS vw_recent_changes;
DROP ROLE IF EXISTS librarian;
DROP ROLE IF EXISTS library_user;

-- =========================
-- Level 1: Basic schema
-- =========================

-- Authors table
CREATE TABLE authors (
    author_id SERIAL PRIMARY KEY,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    birth_date DATE,
    bio TEXT,
    CONSTRAINT uq_author_fullname UNIQUE (first_name, last_name)
);

-- Readers (patrons) table
CREATE TABLE readers (
    reader_id SERIAL PRIMARY KEY,
    full_name VARCHAR(200) NOT NULL,
    email VARCHAR(200) UNIQUE,
    phone VARCHAR(30),
    registered_at TIMESTAMP WITHOUT TIME ZONE DEFAULT now(),
    active BOOLEAN DEFAULT TRUE
);

-- Books table
CREATE TABLE books (
    book_id SERIAL PRIMARY KEY,
    title VARCHAR(300) NOT NULL,
    author_id INTEGER NOT NULL REFERENCES authors(author_id) ON DELETE RESTRICT,
    isbn VARCHAR(20) UNIQUE,
    published_year INTEGER,
    copies_total INTEGER NOT NULL DEFAULT 1 CHECK (copies_total >= 0),
    copies_available INTEGER NOT NULL DEFAULT 1 CHECK (copies_available >= 0),
    discontinued BOOLEAN DEFAULT FALSE,
    description TEXT
);

-- Loans table (book issues)
CREATE TABLE loans (
    loan_id SERIAL PRIMARY KEY,
    book_id INTEGER NOT NULL REFERENCES books(book_id) ON DELETE RESTRICT,
    reader_id INTEGER NOT NULL REFERENCES readers(reader_id) ON DELETE CASCADE,
    loan_date TIMESTAMP WITHOUT TIME ZONE DEFAULT now(),
    due_date DATE,
    return_date TIMESTAMP WITHOUT TIME ZONE,
    status VARCHAR(20) NOT NULL DEFAULT 'issued', -- issued, returned, lost
    CONSTRAINT chk_due_after_loan CHECK (due_date IS NULL OR due_date >= loan_date::date)
);

-- =========================
-- Level 2: Extended schema
-- =========================

-- Reservations table
CREATE TABLE reservations (
    reservation_id SERIAL PRIMARY KEY,
    book_id INTEGER NOT NULL REFERENCES books(book_id) ON DELETE CASCADE,
    reader_id INTEGER NOT NULL REFERENCES readers(reader_id) ON DELETE CASCADE,
    reserved_at TIMESTAMP WITHOUT TIME ZONE DEFAULT now(),
    expires_at TIMESTAMP WITHOUT TIME ZONE,
    fulfilled BOOLEAN DEFAULT FALSE,
    CONSTRAINT uq_reservation UNIQUE(book_id, reader_id)
);

-- Change history table for auditing (simple)
CREATE TABLE change_history (
    history_id SERIAL PRIMARY KEY,
    entity_name TEXT NOT NULL,
    entity_id INTEGER,
    operation VARCHAR(10) NOT NULL, -- INSERT, UPDATE, DELETE
    changed_by TEXT,
    changed_at TIMESTAMP WITHOUT TIME ZONE DEFAULT now(),
    change_data JSONB
);

-- Book versions (versioning of records)
CREATE TABLE book_versions (
    version_id SERIAL PRIMARY KEY,
    book_id INTEGER NOT NULL,
    version_number INTEGER NOT NULL,
    title VARCHAR(300),
    author_id INTEGER,
    isbn VARCHAR(20),
    published_year INTEGER,
    copies_total INTEGER,
    copies_available INTEGER,
    changed_at TIMESTAMP WITHOUT TIME ZONE DEFAULT now(),
    changed_by TEXT
);

CREATE UNIQUE INDEX uq_book_version ON book_versions(book_id, version_number);

-- Deferred tasks table (for delayed operations)
CREATE TABLE deferred_tasks (
    task_id SERIAL PRIMARY KEY,
    task_name TEXT NOT NULL,
    payload JSONB,
    scheduled_at TIMESTAMP WITHOUT TIME ZONE,
    processed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT now()
);

-- =========================
-- Triggers and functions for audit & versioning
-- =========================

-- Trigger function to log changes to change_history
CREATE OR REPLACE FUNCTION trg_log_changes()
RETURNS TRIGGER AS $$
DECLARE
    rec JSONB;
    op TEXT := TG_OP;
    pk_value INTEGER;
BEGIN
    -- Determine the Primary Key value based on the table name
    IF op = 'INSERT' OR op = 'UPDATE' THEN
        CASE TG_TABLE_NAME
            WHEN 'authors' THEN pk_value := NEW.author_id;
            WHEN 'books' THEN pk_value := NEW.book_id;
            WHEN 'readers' THEN pk_value := NEW.reader_id;
            WHEN 'loans' THEN pk_value := NEW.loan_id;
            WHEN 'reservations' THEN pk_value := NEW.reservation_id;
            ELSE pk_value := NULL;
        END CASE;
    ELSE -- DELETE
        CASE TG_TABLE_NAME
            WHEN 'authors' THEN pk_value := OLD.author_id;
            WHEN 'books' THEN pk_value := OLD.book_id;
            WHEN 'readers' THEN pk_value := OLD.reader_id;
            WHEN 'loans' THEN pk_value := OLD.loan_id;
            WHEN 'reservations' THEN pk_value := OLD.reservation_id;
            ELSE pk_value := NULL;
        END CASE;
    END IF;

    IF op = 'INSERT' THEN
        rec := to_jsonb(NEW);
    ELSIF op = 'UPDATE' THEN
        rec := jsonb_build_object('old', to_jsonb(OLD), 'new', to_jsonb(NEW));
    ELSE -- DELETE
        rec := to_jsonb(OLD);
    END IF;

    INSERT INTO change_history(entity_name, entity_id, operation, changed_by, change_data)
    VALUES (TG_TABLE_NAME, pk_value, op, current_user, rec);

    IF op = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Attach audit trigger
CREATE TRIGGER trg_authors_changes
AFTER INSERT OR UPDATE OR DELETE ON authors
FOR EACH ROW EXECUTE FUNCTION trg_log_changes();

CREATE TRIGGER trg_books_changes
AFTER INSERT OR UPDATE OR DELETE ON books
FOR EACH ROW EXECUTE FUNCTION trg_log_changes();

CREATE TRIGGER trg_readers_changes
AFTER INSERT OR UPDATE OR DELETE ON readers
FOR EACH ROW EXECUTE FUNCTION trg_log_changes();

CREATE TRIGGER trg_loans_changes
AFTER INSERT OR UPDATE OR DELETE ON loans
FOR EACH ROW EXECUTE FUNCTION trg_log_changes();

CREATE TRIGGER trg_reservations_changes
AFTER INSERT OR UPDATE OR DELETE ON reservations
FOR EACH ROW EXECUTE FUNCTION trg_log_changes();

-- Trigger to maintain book_versions on books UPDATE
CREATE OR REPLACE FUNCTION trg_book_versioning()
RETURNS TRIGGER AS $$
DECLARE
    v_number INTEGER;
BEGIN
    SELECT COALESCE(MAX(version_number),0) + 1 INTO v_number FROM book_versions WHERE book_id = OLD.book_id;
    INSERT INTO book_versions(book_id, version_number, title, author_id, isbn, published_year, copies_total, copies_available, changed_at, changed_by)
    VALUES (OLD.book_id, v_number, OLD.title, OLD.author_id, OLD.isbn, OLD.published_year, OLD.copies_total, OLD.copies_available, now(), current_user);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_books_version
BEFORE UPDATE ON books
FOR EACH ROW EXECUTE FUNCTION trg_book_versioning();

-- =========================
-- Stored procedures for business logic
-- =========================

-- Checkout a book (issue)
CREATE OR REPLACE FUNCTION fn_checkout_book(p_book_id INTEGER, p_reader_id INTEGER)
RETURNS TABLE(result TEXT) AS $$
DECLARE
    v_available INTEGER;
BEGIN
    PERFORM pg_advisory_xact_lock(p_book_id);

    SELECT copies_available INTO v_available FROM books WHERE book_id = p_book_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'ERROR: Book not found';
        RETURN;
    END IF;

    IF v_available <= 0 THEN
        RETURN QUERY SELECT 'ERROR: No copies available';
        RETURN;
    END IF;

    IF EXISTS (SELECT 1 FROM loans WHERE book_id = p_book_id AND reader_id = p_reader_id AND status = 'issued') THEN
        RETURN QUERY SELECT 'ERROR: Reader already has an active loan for this book';
        RETURN;
    END IF;

    UPDATE books SET copies_available = copies_available - 1 WHERE book_id = p_book_id;

    INSERT INTO loans(book_id, reader_id, loan_date, due_date, status)
    VALUES (p_book_id, p_reader_id, now(), (now() + INTERVAL '14 days')::date, 'issued');

    -- Mark reservation as fulfilled for this reader if exists
    UPDATE reservations SET fulfilled = TRUE WHERE book_id = p_book_id AND reader_id = p_reader_id AND fulfilled = FALSE;

    RETURN QUERY SELECT 'OK: Book checked out';
END;
$$ LANGUAGE plpgsql;

-- Return a book
CREATE OR REPLACE FUNCTION fn_return_book(p_loan_id INTEGER, p_reader_id INTEGER)
RETURNS TABLE(result TEXT) AS $$
DECLARE
    v_book_id INTEGER;
    v_loan RECORD;
BEGIN
    SELECT * INTO v_loan FROM loans WHERE loan_id = p_loan_id AND reader_id = p_reader_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'ERROR: Loan not found or does not belong to reader';
        RETURN;
    END IF;

    IF v_loan.status = 'returned' THEN
        RETURN QUERY SELECT 'ERROR: Book already returned';
        RETURN;
    END IF;

    v_book_id := v_loan.book_id;

    UPDATE loans SET return_date = now(), status = 'returned' WHERE loan_id = p_loan_id;
    UPDATE books SET copies_available = copies_available + 1 WHERE book_id = v_book_id;

    RETURN QUERY SELECT 'OK: Book returned';
END;
$$ LANGUAGE plpgsql;

-- Process deferred tasks
CREATE OR REPLACE FUNCTION fn_process_deferred()
RETURNS VOID AS $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT * FROM deferred_tasks WHERE processed = FALSE AND scheduled_at <= now() FOR UPDATE LOOP
        IF r.task_name = 'cancel_expired_reservations' THEN
            UPDATE reservations
            SET fulfilled = TRUE -- Marking as fulfilled to prevent future use, but cancelling logically
            WHERE expires_at IS NOT NULL AND expires_at <= now() AND fulfilled = FALSE;
        END IF;
        UPDATE deferred_tasks SET processed = TRUE WHERE task_id = r.task_id;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- =========================
-- Roles and permissions (basic)
-- =========================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'librarian') THEN
        CREATE ROLE librarian NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'library_user') THEN
        CREATE ROLE library_user NOLOGIN;
    END IF;
END$$;

GRANT SELECT, INSERT, UPDATE, DELETE ON authors, books, readers, loans, reservations TO librarian;
GRANT USAGE, SELECT ON SEQUENCE authors_author_id_seq, books_book_id_seq, readers_reader_id_seq, loans_loan_id_seq, reservations_reservation_id_seq TO librarian;

GRANT SELECT ON authors, books, readers TO library_user;

-- =========================
-- Sample data insertion
-- =========================

BEGIN;

-- Add authors (5 авторів)
INSERT INTO authors(first_name, last_name, birth_date)
VALUES 
('Тарас', 'Шевченко', '1814-03-09'),
('Леся', 'Українка', '1871-02-25'),
('Іван', 'Франко', '1856-08-27'),
('Михайло', 'Коцюбинський', '1864-09-17'),
('Ольга', 'Кобилянська', '1863-11-27');

-- Add readers (5 читачів)
INSERT INTO readers(full_name, email, phone)
VALUES 
('Петренко Іван', 'ivan.petrenko@example.com', '+380501112233'),
('Іванова Марія', 'm.ivanova@example.com', '+380502223344'),
('Сидоренко Олег', 'oleg.sy@example.com', '+380675556677'),
('Кравчук Анна', 'anna.kr@example.com', '+380961234567'),
('Мельник Володимир', 'v.melnyk@example.com', '+380739876543');

-- Add books (7 книг)
INSERT INTO books(title, author_id, isbn, published_year, copies_total, copies_available)
VALUES
('Кобзар', 1, '978-1-00000-000-1', 1840, 3, 3),
('Лісова пісня', 2, '978-1-00000-000-2', 1911, 2, 2),
('Захар Беркут', 3, '978-1-00000-000-3', 1883, 1, 1),
('Тіні забутих предків', 4, '978-1-00000-000-4', 1911, 4, 4), -- Автор 4: Коцюбинський
('Intermezzo', 4, '978-1-00000-000-5', 1908, 2, 2),
('Земля', 5, '978-1-00000-000-6', 1901, 3, 3), -- Автор 5: Кобилянська
('Contra spem spero!', 2, '978-1-00000-000-7', 1890, 1, 1);

COMMIT;

-- =========================
-- Transactions + ROLLBACK demonstration
-- =========================

-- Functional call example (internally uses transactions and locks)
SELECT * FROM fn_checkout_book(1, 2); -- Reader 2 checks out book 1.

-- Savepoint demo for partial rollback
BEGIN;
    SAVEPOINT before_changes;

    UPDATE readers SET full_name = 'Петренко Іван Миколайович' WHERE reader_id = 1;

    SAVEPOINT nested;
    UPDATE books SET title = 'Кобзар (Ювілейне видання)' WHERE book_id = 1;
    -- Example of rolling back a specific change
    ROLLBACK TO SAVEPOINT nested;

    -- Commit only the first change (reader update)
COMMIT;


-- =========================
-- Level 3: Advanced features (Retry/Revert)
-- =========================

-- Stored procedure for auto recovery / retries (simplified)
CREATE OR REPLACE FUNCTION fn_retry_process_deferred(max_attempts INTEGER DEFAULT 3)
RETURNS VOID AS $$
DECLARE
    attempt INTEGER := 0;
BEGIN
    LOOP
        BEGIN
            PERFORM fn_process_deferred();
            EXIT;
        EXCEPTION WHEN OTHERS THEN
            attempt := attempt + 1;
            IF attempt >= max_attempts THEN
                RAISE NOTICE 'Processing deferred tasks failed after % attempts: %', attempt, SQLERRM;
                EXIT;
            END IF;
            PERFORM pg_sleep(1);
        END;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Simple stored procedure to rollback to a previous version of a book
CREATE OR REPLACE FUNCTION fn_revert_book_to_version(p_book_id INTEGER, p_version_number INTEGER)
RETURNS TEXT AS $$
DECLARE
    v_row RECORD;
BEGIN
    SELECT * INTO v_row FROM book_versions WHERE book_id = p_book_id AND version_number = p_version_number;
    IF NOT FOUND THEN
        RETURN 'ERROR: version not found';
    END IF;

    -- The BEFORE UPDATE trigger will save the CURRENT state as a NEW version before this update applies.
    UPDATE books
    SET title = v_row.title,
        author_id = v_row.author_id,
        isbn = v_row.isbn,
        published_year = v_row.published_year,
        copies_total = v_row.copies_total,
        copies_available = v_row.copies_available
    WHERE book_id = p_book_id;

    RETURN 'OK: Reverted';
END;
$$ LANGUAGE plpgsql;

-- Interface for viewing recent changes
CREATE OR REPLACE VIEW vw_recent_changes AS
SELECT history_id, entity_name, entity_id, operation, changed_by, changed_at, change_data
FROM change_history
ORDER BY changed_at DESC
LIMIT 100;

-- Insert a sample deferred task scheduled to run immediately
INSERT INTO deferred_tasks(task_name, payload, scheduled_at)
VALUES ('cancel_expired_reservations', '{}'::jsonb, now());

-- =========================
-- Final status summary selects
-- =========================
SELECT 'Library DB created (levels 1-3) - objects below:' as status;
SELECT 'authors' as entity, count(*) FROM authors
UNION ALL SELECT 'books', count(*) FROM books
UNION ALL SELECT 'readers', count(*) FROM readers
UNION ALL SELECT 'loans', count(*) FROM loans
UNION ALL SELECT 'reservations', count(*) FROM reservations
UNION ALL SELECT 'book_versions', count(*) FROM book_versions
UNION ALL SELECT 'change_history', count(*) FROM change_history
UNION ALL SELECT 'deferred_tasks', count(*) FROM deferred_tasks;

-- End of script