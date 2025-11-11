-- --------------------------------------------
-- LAB 4: Cinema Database (Level 2)
-- File: 03_create_views.sql
-- Purpose: Create useful views for analysis
-- --------------------------------------------

-- Якщо потрібно оновити представлення — спочатку видаляємо старі
DROP VIEW IF EXISTS v_popular_films CASCADE;
DROP VIEW IF EXISTS v_schedule CASCADE;
DROP VIEW IF EXISTS v_income_by_film CASCADE;

-- ---------------------
-- 1. Популярні фільми (кількість проданих квитків)
-- ---------------------
CREATE VIEW v_popular_films AS
SELECT 
    f.film_id,
    f.title AS film_title,
    COUNT(t.ticket_id) AS tickets_sold,
    SUM(f.price) AS total_income
FROM films f
LEFT JOIN sessions s ON f.film_id = s.film_id
LEFT JOIN tickets t ON s.session_id = t.session_id
GROUP BY f.film_id, f.title
ORDER BY tickets_sold DESC;

-- ---------------------
-- 2. Розклад сеансів (фільм, зал, час, кількість місць)
-- ---------------------
CREATE VIEW v_schedule AS
SELECT 
    s.session_id,
    f.title AS film_title,
    h.name AS hall_name,
    s.session_time,
    s.available_seats
FROM sessions s
JOIN films f ON s.film_id = f.film_id
JOIN halls h ON s.hall_id = h.hall_id
ORDER BY s.session_time;

-- ---------------------
-- 3. Доходи по фільмах (сума квитків * кількість)
-- ---------------------
CREATE VIEW v_income_by_film AS
SELECT 
    f.title AS film_title,
    COUNT(t.ticket_id) AS total_tickets,
    COUNT(t.ticket_id) * f.price AS total_income
FROM films f
LEFT JOIN sessions s ON f.film_id = s.film_id
LEFT JOIN tickets t ON s.session_id = t.session_id
GROUP BY f.title, f.price
ORDER BY total_income DESC;

-- ---------------------
-- Перевірка створення
-- ---------------------
-- SELECT * FROM v_popular_films;
-- SELECT * FROM v_schedule;
-- SELECT * FROM v_income_by_film;
