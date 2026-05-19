import os
import pandas as pd
import numpy as np
import joblib
import sqlalchemy
from sklearn.preprocessing import StandardScaler
from sklearn.ensemble import IsolationForest
from sklearn.svm import OneClassSVM
import tensorflow as tf
from tensorflow.keras.models import Sequential
from tensorflow.keras.layers import LSTM, Dense, RepeatVector, TimeDistributed

# Database Connection
DB_URL = os.getenv("DB_URL", "postgresql://scada_user:scada_password@localhost:5432/scada_db")
MODELS_DIR = "./models"

if not os.path.exists(MODELS_DIR):
    os.makedirs(MODELS_DIR)

def load_data():
    print(f"Connecting to {DB_URL}...")
    engine = sqlalchemy.create_engine(DB_URL)
    query = "SELECT voltage, frequency, current FROM scada_training_data"
    with engine.connect() as conn:
        df = pd.read_sql(query, conn)
    print(f"Successfully loaded {len(df)} rows of training data.")
    return df

def train_isolation_forest(X):
    print("Training Isolation Forest...")
    model = IsolationForest(contamination=0.01, random_state=42)
    model.fit(X)
    joblib.dump(model, os.path.join(MODELS_DIR, 'isolation_forest.pkl'))
    print("Isolation Forest saved.")

def train_svm(X):
    print("Training One-Class SVM...")
    model = OneClassSVM(nu=0.01, kernel="rbf", gamma=0.1)
    model.fit(X)
    joblib.dump(model, os.path.join(MODELS_DIR, 'one_class_svm.pkl'))
    print("One-Class SVM saved.")

def train_lstm_autoencoder(X):
    print("Training LSTM Autoencoder...")
    # Reshape for LSTM [samples, timesteps, features]
    # Using a window of 10 timesteps
    window_size = 10
    X_reshaped = []
    for i in range(len(X) - window_size):
        X_reshaped.append(X[i:i + window_size])
    X_reshaped = np.array(X_reshaped)

    model = Sequential([
        LSTM(32, activation='relu', input_shape=(window_size, X.shape[1]), return_sequences=False),
        RepeatVector(window_size),
        LSTM(32, activation='relu', return_sequences=True),
        TimeDistributed(Dense(X.shape[1]))
    ])
    
    model.compile(optimizer='adam', loss='mae')
    model.fit(X_reshaped, X_reshaped, epochs=10, batch_size=32, verbose=1, validation_split=0.1)
    
    model.save(os.path.join(MODELS_DIR, 'lstm_autoencoder.h5'))
    print("LSTM Autoencoder saved.")

def main():
    # 1. Load Data
    data = load_data()
    
    if len(data) < 1000:
        print("Error: Not enough data points to train reliable models. Keep the simulator running!")
        return

    # 2. Pre-process
    scaler = StandardScaler()
    processed_data = scaler.fit_transform(data)
    joblib.dump(scaler, os.path.join(MODELS_DIR, 'scaler.pkl'))
    
    # 3. Train Models
    train_isolation_forest(processed_data)
    train_svm(processed_data)
    train_lstm_autoencoder(processed_data)
    
    print("\n--- Phase 2 Complete: All models trained and saved to /models ---")

if __name__ == "__main__":
    main()
