import os
import joblib
import pandas as pd
import numpy as np
import tensorflow as tf
from pyspark.sql import SparkSession
from pyspark.sql.functions import from_json, col, lit, when, expr
from pyspark.sql.types import StructType, StructField, StringType, DoubleType, TimestampType
from influxdb_client import InfluxDBClient, Point
from influxdb_client.client.write_api import SYNCHRONOUS

KAFKA_SERVER = os.getenv('KAFKA_SERVER', 'kafka:9092')
MODELS_DIR = "/opt/spark/work-dir/models"
# Use service name 'influxdb' inside docker
INFLUX_URL = os.getenv('INFLUXDB_URL', 'http://influxdb:8086')
INFLUX_TOKEN = os.getenv('INFLUXDB_TOKEN', 'my-super-secret-auth-token')
INFLUX_ORG = os.getenv('INFLUXDB_ORG', 'scada_org')
INFLUX_BUCKET = os.getenv('INFLUXDB_BUCKET', 'sensor_bucket')
POSTGRES_URL = "jdbc:postgresql://postgres:5432/scada_db"
POSTGRES_PROPERTIES = {"user": "scada_user", "password": "scada_password", "driver": "org.postgresql.Driver"}

SENSOR_SCHEMA = StructType([
    StructField("sensor_id", StringType(), True),
    StructField("timestamp", DoubleType(), True),
    StructField("metrics", StructType([
        StructField("voltage", DoubleType(), True),
        StructField("frequency", DoubleType(), True),
        StructField("current", DoubleType(), True)
    ])),
    StructField("status", StringType(), True)
])

MANUAL_SCHEMA = StructType([
    StructField("operator_id", StringType(), True),
    StructField("timestamp", DoubleType(), True),
    StructField("log_message", StringType(), True),
    StructField("type", StringType(), True)
])

LSTM_WINDOW_SIZE = 10
LSTM_THRESHOLD = 0.75

_ml_artifacts = None


def load_ml_artifacts():
    global _ml_artifacts
    if _ml_artifacts is not None:
        return _ml_artifacts

    iforest = joblib.load(f"{MODELS_DIR}/isolation_forest.pkl")
    svm = joblib.load(f"{MODELS_DIR}/one_class_svm.pkl")
    scaler = joblib.load(f"{MODELS_DIR}/scaler.pkl")

    try:
        lstm = tf.keras.models.load_model(f"{MODELS_DIR}/lstm_autoencoder.h5")
    except Exception:
        lstm = None

    _ml_artifacts = {
        "iforest": iforest,
        "svm": svm,
        "scaler": scaler,
        "lstm": lstm
    }
    return _ml_artifacts


def compute_lstm_flags(pdf):
    artifacts = load_ml_artifacts()
    lstm = artifacts["lstm"]
    scaler = artifacts["scaler"]

    flags = np.zeros(len(pdf), dtype=bool)
    if lstm is None or pdf.empty:
        return flags

    sorted_pdf = pdf.sort_values(["sensor_id", "event_time"])
    unique_rows = sorted_pdf.drop_duplicates(["sensor_id", "event_time"], keep="last")
    if len(unique_rows) < LSTM_WINDOW_SIZE:
        return flags

    features = unique_rows[["voltage_val", "freq_val", "curr_val"]].copy()
    features.columns = ["voltage", "frequency", "current"]

    scaled = scaler.transform(features)

    anomaly_positions = []
    for sensor_id, group in unique_rows.groupby("sensor_id"):
        indices = group.index.to_numpy()
        if len(indices) < LSTM_WINDOW_SIZE:
            continue

        group_scaled = scaled[indices]
        windows = np.array([group_scaled[i:i + LSTM_WINDOW_SIZE] for i in range(len(group_scaled) - LSTM_WINDOW_SIZE + 1)])
        reconstructions = lstm.predict(windows, verbose=0)
        errors = np.mean(np.abs(reconstructions - windows), axis=(1, 2))
        anomaly_positions.extend(indices[LSTM_WINDOW_SIZE - 1:][errors > LSTM_THRESHOLD].tolist())

    if anomaly_positions:
        flags[np.isin(sorted_pdf.index.to_numpy(), anomaly_positions)] = True
    return flags


def write_sensor_sink(batch_df, batch_id):
    pdf = batch_df.toPandas()
    if pdf.empty:
        return

    print(f"--- Processing Sensor Batch {batch_id} ({len(pdf)} rows) ---")

    artifacts = load_ml_artifacts()
    scaler = artifacts["scaler"]
    iforest = artifacts["iforest"]
    svm = artifacts["svm"]

    pdf["voltage_val"] = pdf["voltage_val"].astype(float)
    pdf["freq_val"] = pdf["freq_val"].astype(float)
    pdf["curr_val"] = pdf["curr_val"].astype(float)

    # Rename for ML models
    features = pdf[["voltage_val", "freq_val", "curr_val"]].copy()
    features.columns = ["voltage", "frequency", "current"]

    scaled = scaler.transform(features)

    pdf["anomaly_iforest"] = iforest.predict(scaled) == -1
    pdf["anomaly_svm"] = svm.predict(scaled) == -1
    pdf["anomaly_lstm"] = compute_lstm_flags(pdf)

    pdf["alert_votes"] = pdf[["anomaly_iforest", "anomaly_svm", "anomaly_lstm"]].sum(axis=1)
    pdf["severity"] = np.select(
        [pdf["alert_votes"] >= 2, pdf["alert_votes"] == 1],
        ["CRITICAL", "WARNING"],
        default="NORMAL"
    )

    pdf["correlated_log"] = ""
    pdf["has_manual_correlation"] = 0

    try:
        client = InfluxDBClient(url=INFLUX_URL, token=INFLUX_TOKEN, org=INFLUX_ORG)
        write_api = client.write_api(write_options=SYNCHRONOUS)
        
        points = []
        for _, row in pdf.iterrows():
            point = Point("grid_metrics") \
                .tag("sensor_id", row["sensor_id"]) \
                .tag("severity", row["severity"]) \
                .field("voltage", row["voltage_val"]) \
                .field("frequency", row["freq_val"]) \
                .field("current", row["curr_val"]) \
                .field("anomaly_iforest", bool(row["anomaly_iforest"])) \
                .field("anomaly_svm", bool(row["anomaly_svm"])) \
                .field("anomaly_lstm", bool(row["anomaly_lstm"])) \
                .field("alert_votes", int(row["alert_votes"])) \
                .field("has_manual_correlation", int(row["has_manual_correlation"])) \
                .time(row["event_time"])
            points.append(point)
        
        write_api.write(bucket=INFLUX_BUCKET, record=points)
        client.close()
    except Exception as e:
        print(f"Failed to write to InfluxDB: {e}")

    alerts = pdf[pdf["severity"] != "NORMAL"].copy()
    if not alerts.empty:
        alert_columns = ["sensor_id", "event_time", "voltage_val", "freq_val", "curr_val", "severity", "correlated_log"]
        alert_df = SparkSession.builder.getOrCreate().createDataFrame(alerts[alert_columns])
        alert_df.write.jdbc(url=POSTGRES_URL, table="scada_alerts", mode="append", properties=POSTGRES_PROPERTIES)


def run_analyzer():
    spark = SparkSession.builder.appName("SCADA_Hybrid_Analyzer") \
        .config("spark.jars.packages", "org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0,org.postgresql:postgresql:42.7.2") \
        .getOrCreate()
    spark.sparkContext.setLogLevel("ERROR")

    sensor_stream = spark.readStream.format("kafka") \
        .option("kafka.bootstrap.servers", KAFKA_SERVER) \
        .option("subscribe", "sensor_stream") \
        .option("startingOffsets", "latest") \
        .option("failOnDataLoss", "false") \
        .load() \
        .select(from_json(col("value").cast("string"), SENSOR_SCHEMA).alias("data")) \
        .select("data.*") \
        .withColumn("event_time", col("timestamp").cast(TimestampType())) \
        .withColumn("voltage_val", col("metrics.voltage")) \
        .withColumn("freq_val", col("metrics.frequency")) \
        .withColumn("curr_val", col("metrics.current"))

    manual_stream = spark.readStream.format("kafka") \
        .option("kafka.bootstrap.servers", KAFKA_SERVER) \
        .option("subscribe", "manual_data") \
        .option("startingOffsets", "latest") \
        .option("failOnDataLoss", "false") \
        .load() \
        .select(from_json(col("value").cast("string"), MANUAL_SCHEMA).alias("data")) \
        .select("data.*") \
        .withColumn("event_time", col("timestamp").cast(TimestampType()))

    # Process sensor stream
    query = sensor_stream.writeStream \
        .foreachBatch(write_sensor_sink) \
        .option("checkpointLocation", "/opt/spark/work-dir/app/checkpoints/scada_analyzer_v3") \
        .start()

    print("SCADA Hybrid Analyzer is LIVE. Streaming sensor data to InfluxDB v3...")
    spark.streams.awaitAnyTermination()


if __name__ == "__main__":
    run_analyzer()
