import os
import time
import psycopg2
from flask import Flask, jsonify

app = Flask(__name__)

# Read from environment variables (injected via K8s ConfigMap/Secret)
DB_HOST = os.environ.get('DB_HOST', 'localhost')
DB_NAME = os.environ.get('DB_NAME', 'tasks')
DB_USER = os.environ.get('DB_USER', 'postgres')
DB_PASSWORD = os.environ.get('DB_PASSWORD', 'password')

def get_db_connection():
    # Retry logic: RDS takes a minute to boot
    for i in range(5):
        try:
            conn = psycopg2.connect(
                host=DB_HOST, database=DB_NAME, user=DB_USER, password=DB_PASSWORD
            )
            return conn
        except psycopg2.OperationalError:
            print(f"Database not ready, retrying ({i+1}/5)...")
            time.sleep(5)
    return None

@app.route('/')
def hello():
    conn = get_db_connection()
    db_status = "Connected to RDS!" if conn else "Database unavailable"
    if conn:
        conn.close()
    return jsonify({
        "message": "Welcome to the Final Capstone!",
        "database": db_status,
        "hostname": os.uname()[1]
    })

@app.route('/health')
def health():
    return {"status": "healthy"}, 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
