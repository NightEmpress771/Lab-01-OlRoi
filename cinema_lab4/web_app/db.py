import psycopg2

# Підключення до бази PostgreSQL
def get_connection():
    return psycopg2.connect(
        host="localhost",
        port="5432",
        database="cinema_lab4",  # твоя база
        user="postgres",
        password="4914"  # заміни на свій пароль
    )

# Виконати SELECT-запит і повернути всі результати
def fetch_all(query, params=None):
    conn = get_connection()
    cur = conn.cursor()
    cur.execute(query, params)
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return rows

# Виконати INSERT/UPDATE/DELETE
def execute_query(query, params=None):
    conn = get_connection()
    cur = conn.cursor()
    cur.execute(query, params)
    conn.commit()
    cur.close()
    conn.close()
