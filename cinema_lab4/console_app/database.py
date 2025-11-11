import psycopg2

# Функція підключення до бази даних PostgreSQL
def get_connection():
    try:
        conn = psycopg2.connect(
            host="localhost",       # або IP, якщо сервер віддалений
            port="5432",
            database="library_lab4",  # заміни на назву своєї БД, наприклад cinema_lab4
            user="postgres",
            password="your_password"  # заміни на свій пароль
        )
        return conn
    except Exception as e:
        print("❌ Помилка підключення до бази даних:", e)
        return None


# Функція виконання SELECT-запиту і повернення результатів
def execute_query(query, params=None):
    conn = get_connection()
    if conn is None:
        return []
    try:
        with conn.cursor() as cur:
            cur.execute(query, params)
            result = cur.fetchall()
        conn.close()
        return result
    except Exception as e:
        print("❌ Помилка виконання запиту:", e)
        return []


# Функція виконання INSERT/UPDATE/DELETE
def execute_non_query(query, params=None):
    conn = get_connection()
    if conn is None:
        return False
    try:
        with conn.cursor() as cur:
            cur.execute(query, params)
        conn.commit()
        conn.close()
        return True
    except Exception as e:
        print("❌ Помилка виконання операції:", e)
        return False
