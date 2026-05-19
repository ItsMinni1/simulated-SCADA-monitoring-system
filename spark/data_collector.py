import os
from pyspark.sql import SparkSession
from pyspark.sql.functions import from_json, col
from pyspark.sql.types import StructType, StructField, StringType, DoubleType

# Configuration
KAFKA_SERVER = os.getenv('KAFKA_SERVER', 'kafka:9092')
POSTGRES_URL = "jdbc:postgresql://postgres:5432/scada_db"
POSTGRES_PROPERTIES = {
    "user": "scada_user",
    "password": "scada_password",
    "driver": "org.postgresql.Driver"
}

def run_collector():
    print(f"--- Starting SCADA Training Data Collector ---")
    
    spark = SparkSession.builder \
        .appName("SCADA_Data_Collector") \
        .getOrCreate()

    spark.sparkContext.setLogLevel("WARN")

    # Define Schema matching grid_sensor.py
    schema = StructType([
        StructField("sensor_id", StringType(), True),
        StructField("timestamp", DoubleType(), True),
        StructField("metrics", StructType([
            StructField("voltage", DoubleType(), True),
            StructField("frequency", DoubleType(), True),
            StructField("current", DoubleType(), True)
        ])),
        StructField("status", StringType(), True)
    ])

    # Read from Kafka
    df = spark \
        .readStream \
        .format("kafka") \
        .option("kafka.bootstrap.servers", KAFKA_SERVER) \
        .option("subscribe", "sensor_stream") \
        .option("startingOffsets", "latest") \
        .load()

    # Parse and Flatten
    processed_df = df.selectExpr("CAST(value AS STRING)") \
        .select(from_json(col("value"), schema).alias("data")) \
        .select(
            col("data.sensor_id"),
            col("data.timestamp"),
            col("data.metrics.voltage"),
            col("data.metrics.frequency"),
            col("data.metrics.current"),
            col("data.status")
        )

    # Sink to PostgreSQL using foreachBatch
    def write_to_postgres(batch_df, batch_id):
        if batch_df.count() > 0:
            print(f"Writing batch {batch_id} ({batch_df.count()} rows) to PostgreSQL...")
            batch_df.write.jdbc(
                url=POSTGRES_URL,
                table="scada_training_data",
                mode="append",
                properties=POSTGRES_PROPERTIES
            )

    query = processed_df.writeStream \
        .foreachBatch(write_to_postgres) \
        .option("checkpointLocation", "/opt/spark/work-dir/checkpoints/data_collector") \
        .start()

    print("Data Collector is active. Collecting baseline training data...")
    query.awaitTermination()

if __name__ == "__main__":
    run_collector()
