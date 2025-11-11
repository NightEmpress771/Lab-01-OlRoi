-- --------------------------------------------
-- LAB 4: Cinema Database (Level 3)
-- File: 05_create_triggers.sql
-- Purpose: Create triggers for automatic actions
-- --------------------------------------------

-- Якщо існують попередні тригери — видаляємо
DROP TABLE IF EXISTS ticket_log CASCADE;
DROP FUNCTION IF EXISTS log_ticket_action() CASCADE;
DROP FUNCTION IF EXISTS update_available_seats() CASCADE;
DROP TRIGGER IF EXISTS trg_log_ticket_action ON tickets;
DROP TRIGGER IF EXISTS trg_update_available_seats ON tickets;

-- ==========================================================
-- 1️⃣ Таблиця журналу дій (логування)
-- ==========================================================
CREATE TABLE ticket_log (
    log_id SERIAL PRIMARY KEY,
    action_type VARCHAR(20),         -- INSERT / DELETE
    ticket_id INT,
    customer_name VARCHAR(100),
    session_id INT,
    action_time TIMESTAMP DEFAULT NOW()
);

-- ==========================================================
-- 2️⃣ Функція логування змін у таблиці tickets
-- ==========================================================
CREATE OR REPLACE FUNCTION log_ticket_action()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        INSERT INTO ticket_log (action_type, ticket_id, customer_name, session_id)
        VALUES ('INSERT', NEW.ticket_id, NEW.customer_name, NEW.session_id);
        RETURN NEW;

    ELSIF (TG_OP = 'DELETE') THEN
        INSERT INTO ticket_log (action_type, ticket_id, customer_name, session_id)
        VALUES ('DELETE', OLD.ticket_id, OLD.customer_name, OLD.session_id);
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- ==========================================================
-- 3️⃣ Функція оновлення кількості місць після продажу/видалення
-- ==========================================================
CREATE OR REPLACE FUNCTION update_available_seats()
RETURNS TRIGGER AS $$
BEGIN
    -- Якщо квиток додається — зменшуємо кількість місць
    IF (TG_OP = 'INSERT') THEN
        UPDATE sessions
        SET available_seats = available_seats - 1
        WHERE session_id = NEW.session_id;

    -- Якщо квиток видаляється — повертаємо місце назад
    ELSIF (TG_OP = 'DELETE') THEN
        UPDATE sessions
        SET available_seats = available_seats + 1
        WHERE session_id = OLD.session_id;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- ==========================================================
-- 4️⃣ Створюємо тригери для таблиці tickets
-- ==========================================================
CREATE TRIGGER trg_log_ticket_action
AFTER INSERT OR DELETE ON tickets
FOR EACH ROW
EXECUTE FUNCTION log_ticket_action();

CREATE TRIGGER trg_update_available_seats
AFTER INSERT OR DELETE ON tickets
FOR EACH ROW
EXECUTE FUNCTION update_available_seats();

-- ==========================================================
-- 🔍 Перевірка роботи тригерів
-- ==========================================================
-- Додаємо новий квиток → автоматично зменшуються місця і створюється запис у лог
-- INSERT INTO tickets (session_id, customer_name) VALUES (1, 'Тестовий користувач');

-- Видаляємо квиток → автоматично повертається місце і лог пишеться
-- DELETE FROM tickets WHERE customer_name = 'Тестовий користувач';

-- Перевірити журнал:
-- SELECT * FROM ticket_log ORDER BY log_id DESC;
