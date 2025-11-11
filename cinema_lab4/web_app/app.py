from flask import Flask, render_template, request, redirect, url_for
from db import fetch_all, execute_query

app = Flask(__name__)

# -------------------------------
# Головна сторінка
# -------------------------------
@app.route('/')
def index():
    return render_template('index.html')

# -------------------------------
# Перегляд фільмів
# -------------------------------
@app.route('/films', methods=['GET', 'POST'])
def films():
    if request.method == 'POST':
        genre_filter = request.form.get('genre')
        query = """
            SELECT film_id, title, genre, duration, price, release_year
            FROM films
            WHERE LOWER(genre) LIKE LOWER(%s)
            ORDER BY title;
        """
        films_data = fetch_all(query, ('%' + genre_filter + '%',))
    else:
        query = """
            SELECT film_id, title, genre, duration, price, release_year
            FROM films
            ORDER BY title;
        """
        films_data = fetch_all(query)

    return render_template('films.html', films=films_data)


# -------------------------------
# Розклад сеансів
# -------------------------------
@app.route('/tickets', methods=['GET', 'POST'])
def tickets():
    if request.method == 'POST':
        session_id = request.form['session_id']
        customer_name = request.form['customer_name']
        query = "INSERT INTO tickets (session_id, customer_name) VALUES (%s, %s);"
        execute_query(query, (session_id, customer_name))
        return redirect(url_for('tickets'))

    query = """
        SELECT s.session_id, f.title, h.name, s.session_time, s.available_seats
        FROM sessions s
        JOIN films f ON s.film_id = f.film_id
        JOIN halls h ON s.hall_id = h.hall_id
        ORDER BY s.session_time;
    """
    sessions = fetch_all(query)
    return render_template('tickets.html', sessions=sessions)

# -------------------------------
# Статистика (представлення)
# -------------------------------
@app.route('/stats')
def stats():
    query = "SELECT * FROM v_popular_films;"
    stats_data = fetch_all(query)
    return render_template('stats.html', stats=stats_data)

@app.route('/clients')
def clients():
    query = """
        SELECT 
            t.ticket_id,
            t.customer_name,
            f.title AS film_title,
            h.name AS hall_name,
            s.session_time
        FROM tickets t
        JOIN sessions s ON t.session_id = s.session_id
        JOIN films f ON s.film_id = f.film_id
        JOIN halls h ON s.hall_id = h.hall_id
        ORDER BY t.ticket_id;
    """
    clients_data = fetch_all(query)
    return render_template('clients.html', clients=clients_data)


# -------------------------------
# Запуск сервера
# -------------------------------
if __name__ == '__main__':
    app.run(debug=True)

