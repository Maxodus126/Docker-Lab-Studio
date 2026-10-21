import os
import time
from contextlib import contextmanager

import mysql.connector
from mysql.connector import Error, IntegrityError
from flask import Flask, flash, jsonify, redirect, render_template, request, url_for

app = Flask(__name__)
app.secret_key = os.getenv("FLASK_SECRET_KEY", "local-lab-only-change-me")

DB_CONFIG = {
    "host": os.getenv("DB_HOST", "db"),
    "port": int(os.getenv("DB_PORT", "3306")),
    "database": os.getenv("DB_NAME", "studentdb"),
    "user": os.getenv("DB_USER", "studentapp"),
    "password": os.getenv("DB_PASSWORD", ""),
    "connection_timeout": 3,
}


def get_connection():
    return mysql.connector.connect(**DB_CONFIG)


def initialize_database():
    """Wait briefly for MySQL and create the table if it does not exist."""
    last_error = None
    for attempt in range(1, 31):
        try:
            connection = get_connection()
            cursor = connection.cursor()
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS students (
                    id INT AUTO_INCREMENT PRIMARY KEY,
                    name VARCHAR(120) NOT NULL,
                    nim VARCHAR(30) NOT NULL UNIQUE,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                """
            )
            connection.commit()
            cursor.close()
            connection.close()
            print("Database siap; tabel students tersedia.")
            return
        except Error as exc:
            last_error = exc
            print(f"Menunggu MySQL ({attempt}/30): {exc}")
            time.sleep(2)
    raise RuntimeError(f"MySQL tidak siap setelah beberapa percobaan: {last_error}")


def read_students():
    connection = get_connection()
    try:
        cursor = connection.cursor(dictionary=True)
        cursor.execute(
            "SELECT id, name, nim, created_at FROM students ORDER BY id DESC"
        )
        rows = cursor.fetchall()
        cursor.close()
        return rows
    finally:
        connection.close()


def count_students():
    connection = get_connection()
    try:
        cursor = connection.cursor()
        cursor.execute("SELECT COUNT(*) FROM students")
        count = cursor.fetchone()[0]
        cursor.close()
        return int(count)
    finally:
        connection.close()


@app.get("/live")
def live():
    """Liveness endpoint: proves the Flask process is responding."""
    return jsonify({"status": "alive", "service": "flask-web"}), 200


@app.get("/health")
def health():
    """Application/database readiness status used by the local dashboard."""
    try:
        total = count_students()
        return jsonify(
            {
                "status": "ok",
                "database": "connected",
                "students": total,
                "service": "flask-web",
            }
        ), 200
    except Error:
        return jsonify(
            {
                "status": "degraded",
                "database": "unavailable",
                "students": None,
                "service": "flask-web",
                "message": "MySQL belum tersedia atau sedang dipulihkan.",
            }
        ), 200


@app.get("/")
def index():
    db_available = True
    students = []
    try:
        students = read_students()
    except Error:
        db_available = False

    return render_template(
        "index.html",
        students=students,
        db_available=db_available,
    )


@app.post("/students")
def add_student():
    name = (request.form.get("name") or "").strip()
    nim = (request.form.get("nim") or "").strip()

    if not name or not nim:
        flash("Nama dan NIM wajib diisi.", "warning")
        return redirect(url_for("index"))

    if len(name) > 120:
        flash("Nama maksimal 120 karakter.", "warning")
        return redirect(url_for("index"))

    if len(nim) > 30:
        flash("NIM maksimal 30 karakter.", "warning")
        return redirect(url_for("index"))

    connection = None
    try:
        connection = get_connection()
        cursor = connection.cursor()
        cursor.execute(
            "INSERT INTO students (name, nim) VALUES (%s, %s)",
            (name, nim),
        )
        connection.commit()
        cursor.close()
        flash(f"Data {name} berhasil ditambahkan.", "success")
    except IntegrityError:
        flash("NIM tersebut sudah terdaftar. Gunakan NIM yang berbeda.", "warning")
    except Error:
        flash("Database belum tersedia. Coba lagi setelah MySQL sehat.", "error")
    finally:
        if connection is not None and connection.is_connected():
            connection.close()

    return redirect(url_for("index"))


@app.post("/students/<int:student_id>/delete")
def delete_student(student_id):
    connection = None
    try:
        connection = get_connection()
        cursor = connection.cursor()
        cursor.execute("DELETE FROM students WHERE id = %s", (student_id,))
        deleted = cursor.rowcount
        connection.commit()
        cursor.close()
        if deleted:
            flash("Data mahasiswa berhasil dihapus.", "success")
        else:
            flash("Data mahasiswa tidak ditemukan.", "warning")
    except Error:
        flash("Database belum tersedia. Data belum dihapus.", "error")
    finally:
        if connection is not None and connection.is_connected():
            connection.close()

    return redirect(url_for("index"))


@app.errorhandler(404)
def not_found(_error):
    return render_template(
        "error.html",
        title="Halaman tidak ditemukan",
        message="Alamat yang kamu buka tidak tersedia.",
    ), 404


if __name__ == "__main__":
    initialize_database()
    app.run(host="0.0.0.0", port=5000, debug=False)
