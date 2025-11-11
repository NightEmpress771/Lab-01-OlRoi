-- --------------------------------------------
-- LAB 4: Cinema Database (Level 2–3)
-- File: 04_create_procedures.sql
-- Purpose: Create stored procedures and functions
-- --------------------------------------------

-- Якщо функції вже існують — видалимо
DROP FUNCTION IF EXISTS buy_ticket(INT, VARCHAR);
DROP FUNCTION IF EXISTS search_films_by_genre(VARCHAR);
DROP FUNCTION IF EXISTS get_income_by_film(INT);

-- ==========================================================
-- 1️⃣ Функція покупки квитка
--    - Вставляє новий запис у таблицю tickets
--    - Зменшує кількість доступних місць у таблиці sessions
-- ==========================================================
CREATE OR REPLACE FUNCTION buy_ticket(p_session_id INT, p_customer_name VARCHAR)
RETURNS VARCHAR AS $$
DECLARE
    v_available INT;
BEGIN
    -- Перевіряємо наявність місць
    SELECT available_seats INTO v_available FROM sessions WHERE session_id = p_session_id;
    
    IF v_available IS NULL THEN
        RETURN '❌ Помилка: сеанс не знайдено';
    ELSIF v_available <= 0 THEN
        RETURN '⚠️ Немає вільних місць';
    END IF;

    -- Додаємо квиток
    INSERT INTO tickets (session_id, customer_name, purchase_time)
    VALUES (p_session_id, p_customer_name, NOW());

    -- Зменшуємо кількість вільних місць
    UPDATE sessions
    SET available_seats = available_seats - 1
    WHERE session_id = p_session_id;

    RETURN '✅ Квиток успішно оформлено!';
END;
$$ LANGUAGE plpgsql;


-- ==========================================================
-- 2️⃣ Функція пошуку фільмів за жанром
-- ==========================================================
CREATE OR REPLACE FUNCTION search_films_by_genre(p_genre VARCHAR)
RETURNS TABLE (
    film_id INT,
    title VARCHAR,
    genre VARCHAR,
    duration INT,
    price NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT f.film_id, f.title, f.genre, f.duration, f.price
    FROM films f
    WHERE LOWER(f.genre) LIKE LOWER('%' || p_genre || '%')
    ORDER BY f.title;
END;
$$ LANGUAGE plpgsql;


-- ==========================================================
-- 3️⃣ Функція підрахунку доходу по фільму
-- ==========================================================
CREATE OR REPLACE FUNCTION get_income_by_film(p_film_id INT)
RETURNS NUMERIC AS $$
DECLARE
    v_income NUMERIC;
BEGIN
    SELECT COUNT(t.ticket_id) * f.price
    INTO v_income
    FROM films f
    JOIN sessions s ON f.film_id = s.film_id
    LEFT JOIN tickets t ON s.session_id = t.session_id
    WHERE f.film_id = p_film_id
    GROUP BY f.price;

    RETURN COALESCE(v_income, 0);
END;
$$ LANGUAGE plpgsql;


-- ==========================================================
-- 🔍 Приклади використання:
-- ==========================================================
-- SELECT buy_ticket(1, 'Петро Синиця');
-- SELECT * FROM search_films_by_genre('Комедія');
-- SELECT get_income_by_film(1);
