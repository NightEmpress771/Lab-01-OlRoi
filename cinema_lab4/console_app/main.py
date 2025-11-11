from database import execute_query, execute_non_query

# -----------------------------
# Консольне меню кінотеатру
# -----------------------------

def show_films():
    query = """
        SELECT film_id, title, genre, duration, price
        FROM films
        ORDER BY title;
    """
    films = execute_query(query)
    print("\n🎬 Список фільмів:")
    print("-" * 60)
    for f in films:
        print(f"ID: {f[0]} | Назва: {f[1]} | Жанр: {f[2]} | Тривалість: {f[3]} хв | Ціна: {f[4]} грн")


def show_sessions():
    query = """
        SELECT s.session_id, f.title, s.session_time, h.name
        FROM sessions s
        JOIN films f ON s.film_id = f.film_id
        JOIN halls h ON s.hall_id = h.hall_id
        ORDER BY s.session_time;
    """
    sessions = execute_query(query)
    print("\n🕐 Розклад сеансів:")
    print("-" * 60)
    for s in sessions:
        print(f"ID сеансу: {s[0]} | Фільм: {s[1]} | Час: {s[2]} | Зал: {s[3]}")


def buy_ticket():
    show_sessions()
    try:
        session_id = int(input("\nВведіть ID сеансу: "))
        customer_name = input("Введіть ім'я клієнта: ")

        query = """
            INSERT INTO tickets (session_id, customer_name)
            VALUES (%s, %s);
        """
        success = execute_non_query(query, (session_id, customer_name))
        if success:
            print("✅ Квиток успішно оформлено!")
        else:
            print("❌ Не вдалося оформити квиток.")
    except ValueError:
        print("⚠️ Невірний формат введення.")


def show_tickets():
    query = """
        SELECT t.ticket_id, f.title, s.session_time, t.customer_name
        FROM tickets t
        JOIN sessions s ON t.session_id = s.session_id
        JOIN films f ON s.film_id = f.film_id
        ORDER BY t.ticket_id;
    """
    tickets = execute_query(query)
    print("\n🎟️ Список проданих квитків:")
    print("-" * 60)
    for t in tickets:
        print(f"ID: {t[0]} | Фільм: {t[1]} | Сеанс: {t[2]} | Клієнт: {t[3]}")


def main_menu():
    while True:
        print("\n==========================")
        print("🎬 СИСТЕМА КІНОТЕАТРУ")
        print("==========================")
        print("1. Переглянути фільми")
        print("2. Переглянути сеанси")
        print("3. Продати квиток")
        print("4. Переглянути продані квитки")
        print("0. Вихід")

        choice = input("Оберіть дію: ")

        if choice == "1":
            show_films()
        elif choice == "2":
            show_sessions()
        elif choice == "3":
            buy_ticket()
        elif choice == "4":
            show_tickets()
        elif choice == "0":
            print("👋 До побачення!")
            break
        else:
            print("⚠️ Невірний вибір, спробуйте ще раз.")


if __name__ == "__main__":
    main_menu()
