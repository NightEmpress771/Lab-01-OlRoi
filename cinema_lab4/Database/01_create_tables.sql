-- --------------------------------------------
-- LAB 4: Database of a Cinema (Level 1–3)
-- File: 01_create_tables.sql
-- Purpose: Create all tables for the cinema DB
-- --------------------------------------------

-- Якщо база створюється вперше — можна очистити попередню схему
DROP TABLE IF EXISTS tickets CASCADE;
DROP TABLE IF EXISTS sessions CASCADE;
DROP TABLE IF EXISTS films CASCADE;
DROP TABLE IF EXISTS halls CASCADE;

-- ---------------------
-- Таблиця: Зали
-- ---------------------
CREATE TABLE halls (
    hall_id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    capacity INT NOT NULL CHECK (capacity > 0)
);

-- ---------------------
-- Таблиця: Фільми
-- ---------------------
CREATE TABLE films (
    film_id SERIAL PRIMARY KEY,
    title VARCHAR(100) NOT NULL,
    genre VARCHAR(50),
    duration INT CHECK (duration > 0),
    price NUMERIC(6,2) CHECK (price >= 0),
    release_year INT CHECK (release_year >= 1900)
);

-- ---------------------
-- Таблиця: Сеанси
-- ---------------------
CREATE TABLE sessions (
    session_id SERIAL PRIMARY KEY,
    film_id INT NOT NULL REFERENCES films(film_id) ON DELETE CASCADE,
    hall_id INT NOT NULL REFERENCES halls(hall_id) ON DELETE CASCADE,
    session_time TIMESTAMP NOT NULL,
    available_seats INT NOT NULL CHECK (available_seats >= 0)
);

-- ---------------------
-- Таблиця: Квитки
-- ---------------------
CREATE TABLE tickets (
    ticket_id SERIAL PRIMARY KEY,
    session_id INT NOT NULL REFERENCES sessions(session_id) ON DELETE CASCADE,
    customer_name VARCHAR(100) NOT NULL,
    purchase_time TIMESTAMP DEFAULT NOW()
);

-- ---------------------
-- Додаткові індекси
-- ---------------------
CREATE INDEX idx_sessions_film ON sessions(film_id);
CREATE INDEX idx_tickets_session ON tickets(session_id);

-- ---------------------
-- Перевірка структури
-- ---------------------
-- SELECT table_name FROM information_schema.tables WHERE table_schema='public';
