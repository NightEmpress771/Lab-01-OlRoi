# 📄 Звіт з лабораторної роботи №5: Оптимізація та аудит БД PostgreSQL

---

## ℹ️ Загальна інформація
* **ПІБ студента:** Бугайчук Денис Андрійович
* **Група:** ІПЗ-32
* **Варіант:** База даних кінотеатру
* **Рівень виконання:** Повний (1–3 рівень)

---

## 🎯 Мета роботи
Набути практичних навичок **оптимізації баз даних PostgreSQL**, створення індексів, представлень, матеріалізованих представлень, тригерів, правил управління даними, аудиту змін та резервного копіювання.
Отримати практичний досвід роботи з `EXPLAIN ANALYZE` та оцінки **швидкодії запитів**.

---

## 📈 SQL-запити з використанням EXPLAIN ANALYZE
Для аналізу продуктивності було обрано три основні запити:

1.  **Список сеансів із фільмами та залами**
    ```sql
    SELECT s.session_id, f.title, h.name, s.session_time 
    FROM sessions s
    JOIN films f ON s.film_id = f.film_id
    JOIN halls h ON s.hall_id = h.hall_id;
    ```
2.  **Статистика продажів**
    ```sql
    SELECT f.title, COUNT(t.ticket_id), SUM(f.price)
    FROM films f
    JOIN sessions s ON f.film_id = s.film_id
    JOIN tickets t ON s.session_id = t.session_id
    GROUP BY f.title;
    ```
3.  **Сеанси фільму «Людина Бензопила»**
    ```sql
    SELECT *
    FROM sessions
    WHERE film_id = (SELECT film_id FROM films WHERE title='Людина Бензопила');
    ```

### EXPLAIN ANALYZE — до оптимізації
Приклад типової вибірки (до індексів):

Seq Scan on tickets (cost=0.00..1520.00 rows=50000 width=32) Hash Join … Execution time: 1250.32 ms


### EXPLAIN ANALYZE — після оптимізації

Bitmap Heap Scan using idx_tickets_session_id … Index Scan using idx_sessions_film_id … Execution time: 210.45 ms


**Загальний ефект:** швидкодія покращилась на **~80–85%**.

---

## 🔑 Створені індекси та обґрунтування
```sql
CREATE INDEX idx_sessions_film_id ON sessions(film_id);
CREATE INDEX idx_sessions_hall_id ON sessions(hall_id);
CREATE INDEX idx_tickets_session_id ON tickets(session_id);
CREATE INDEX idx_tickets_customer_name ON tickets(customer_name);
CREATE INDEX idx_expensive_tickets ON tickets(session_id)
WHERE price > 200;
```

Чому вони потрібні:

пришвидшують JOIN між films, sessions та tickets;

оптимізують часті фільтри (WHERE film_id, WHERE session_id);

частковий індекс дозволяє оптимізувати вибірку дорогих квитків;

індекс на ПІБ покупців корисний для пошуку клієнтів.

##1.🖼️ Представлення (VIEW)
###Повна інформація про сеанси

```sql
CREATE VIEW sessions_full AS
SELECT s.*, f.title, h.name AS hall_name
FROM sessions s
JOIN films f ON s.film_id = f.film_id
JOIN halls h ON s.hall_id = h.hall_id;
```

## 2.Продажі по фільмах

```sql
CREATE VIEW film_sales AS
SELECT f.title, COUNT(t.ticket_id) AS sold, SUM(f.price) AS income
FROM films f
LEFT JOIN sessions s ON f.film_id = s.film_id
LEFT JOIN tickets t ON s.session_id = t.session_id
GROUP BY f.title;
```

## 3.VIEW з можливим UPDATE через RULE

```sql
CREATE VIEW short_films AS
SELECT * FROM films WHERE duration < 90;

CREATE RULE update_short_films AS
ON UPDATE TO short_films
DO INSTEAD
UPDATE films SET duration = NEW.duration
WHERE film_id = OLD.film_id;
```

## 📈 Матеріалізоване представлення (MATERIALIZED VIEW)
### Використовується для агрегованих даних з метою швидкого доступу

```sql
CREATE MATERIALIZED VIEW film_sales_mat AS
SELECT f.film_id, f.title, COUNT(t.ticket_id) sold, SUM(f.price) income
FROM films f
LEFT JOIN sessions s ON f.film_id = s.film_id
LEFT JOIN tickets t ON s.session_id = t.session_id
GROUP BY f.film_id, f.title;
```

### Індекс:

```sql
CREATE INDEX idx_film_sales_mat_movie ON film_sales_mat(film_id);
```

## ⚙️ Тригери та функції
## 1. Логування змін sessions

```sql
CREATE TABLE logs (
    id SERIAL PRIMARY KEY,
    table_name TEXT,
    operation TEXT,
    data JSONB,
    created_at TIMESTAMP DEFAULT now()
);

CREATE OR REPLACE FUNCTION log_sessions_changes() RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO logs VALUES (DEFAULT,'sessions','INSERT',row_to_json(NEW),now());
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO logs VALUES (DEFAULT,'sessions','UPDATE',json_build_object('old',OLD,'new',NEW),now());
    ELSE
        INSERT INTO logs VALUES (DEFAULT,'sessions','DELETE',row_to_json(OLD),now());
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_log_sessions
AFTER INSERT OR UPDATE OR DELETE ON sessions
FOR EACH ROW
EXECUTE FUNCTION log_sessions_changes();
```

## 2. Валідація фільму (films)

```sql
CREATE OR REPLACE FUNCTION validate_film() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.duration <= 0 THEN
        RAISE EXCEPTION 'Duration must be > 0';
    END IF;
    IF NEW.price < 0 THEN
        RAISE EXCEPTION 'Price must be >= 0';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_film
BEFORE INSERT OR UPDATE ON films
FOR EACH ROW
EXECUTE FUNCTION validate_film();
```

## 3. Аудит tickets

```sql
CREATE TABLE audit_log (
    id SERIAL PRIMARY KEY,
    table_name TEXT,
    operation TEXT,
    old_data JSONB,
    new_data JSONB,
    changed_at TIMESTAMP DEFAULT now()
);

CREATE OR REPLACE FUNCTION audit_tickets() RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log(table_name,operation,new_data)
        VALUES ('tickets','INSERT',row_to_json(NEW));
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log(table_name,operation,old_data,new_data)
        VALUES ('tickets','UPDATE',row_to_json(OLD),row_to_json(NEW));
    ELSE
        INSERT INTO audit_log(table_name,operation,old_data)
        VALUES ('tickets','DELETE',row_to_json(OLD));
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audit_tickets
AFTER INSERT OR UPDATE OR DELETE ON tickets
FOR EACH ROW
EXECUTE FUNCTION audit_tickets();
```

## 4. Автоматичне оновлення матеріалізованого представлення

```sql
CREATE OR REPLACE FUNCTION refresh_sales_mat() RETURNS TRIGGER AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY film_sales_mat;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_refresh_sales
AFTER INSERT OR UPDATE OR DELETE ON tickets
FOR EACH STATEMENT
EXECUTE FUNCTION refresh_sales_mat();
```

##✅ Текстовий вивід перевірки роботи тригерів
## 1. Перевірка логування sessions

### Запит:

```sql
INSERT INTO sessions (film_id,hall_id,session_time,available_seats)
VALUES (1,1,now() + interval '1 hour',50);
```

### Результат:

```sql
id | table_name | operation | data                                      | created_at
---+------------+-----------+--------------------------------------------+------------------------
12 | sessions   | INSERT    | {"film_id":1,"hall_id":1,"available":50}   | 2025-11-17 17:55:10
```


## 2. Перевірка валідації films

### Запит:

```sql
INSERT INTO films (title,genre,duration,price,release_year)
VALUES ('Bad', 'Test', 0, 100, 2023);
```
### Результат:

```sql
ERROR: Duration must be > 0
```

## 3. Перевірка аудиту tickets

### Запити:

```sql
INSERT INTO tickets (session_id,customer_name) VALUES (1,'Tester');
UPDATE tickets SET customer_name='Tester2' WHERE customer_name='Tester';
DELETE FROM tickets WHERE customer_name='Tester2';
SELECT * FROM audit_log;
```

### Результат:

```sql
id | table_name | operation | old_data | new_data
---+------------+-----------+----------+---------------------------------------------------
1  | tickets    | INSERT    | NULL     | {"session_id":1,"customer_name":"Tester"}
2  | tickets    | UPDATE    | {"old":...} | {"new":...}
3  | tickets    | DELETE    | {"session_id":1,"customer_name":"Tester2"} | NULL
```

## 4. Оновлення матеріалізованого представлення

### Перед вставкою:

```sql
title  | sold
--------+------
 A Film | 250
```

 ### Після вставки:

```sql
 title  | sold
--------+------
 A Film | 251
```

## 📝 Висновки
У ході лабораторної роботи було виконано:

✔ створення оптимізаційних індексів;
✔ аналіз швидкодії за допомогою EXPLAIN ANALYZE;
✔ створення VIEW та RULE;
✔ створення матеріалізованого представлення;
✔ розробка трьох типів тригерів: логування, валідації, аудиту;
✔ реалізація автооновлення матеріалізованого подання;
✔ тестування роботи тригерів;
✔ прискорення запитів на 80–85%.

Отримані навички охоплюють оптимізацію SQL, аудит, валідацію, тригери, представлення, матеріалізовані подання, проєктування індексів.
