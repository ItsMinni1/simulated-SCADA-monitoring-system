import asyncio
import json
import logging
import os
import pandas as pd
from typing import List

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import asyncpg
from aiokafka import AIOKafkaConsumer
import firebase_admin
from firebase_admin import credentials, messaging
from influxdb_client import InfluxDBClient, Point
from influxdb_client.client.write_api import ASYNCHRONOUS

app = FastAPI(title="SCADA HMI Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

logger = logging.getLogger("scada_backend")
logger.setLevel(logging.INFO)

# InfluxDB Config from Environment
INFLUXDB_URL = os.environ.get("INFLUXDB_URL", "http://localhost:8086")
INFLUXDB_TOKEN = os.environ.get("INFLUXDB_TOKEN", "my-super-secret-auth-token")
INFLUXDB_ORG = os.environ.get("INFLUXDB_ORG", "scada_org")
INFLUXDB_BUCKET = os.environ.get("INFLUXDB_BUCKET", "sensor_bucket")

influx_client = InfluxDBClient(url=INFLUXDB_URL, token=INFLUXDB_TOKEN, org=INFLUXDB_ORG)
query_api = influx_client.query_api()

POSTGRES_DSN = os.environ.get("DB_URL", "postgresql://scada_user:scada_password@localhost:5432/scada_db")
KAFKA_SERVER = os.environ.get("KAFKA_SERVER", "localhost:9094")
KAFKA_TOPIC = "sensor_stream"

class NotifyRequest(BaseModel):
    sensor_id: str
    severity: str
    message: str

class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        self.active_connections.remove(websocket)

    async def broadcast_json(self, message: dict):
        for connection in self.active_connections:
            try:
                await connection.send_json(message)
            except Exception as e:
                logger.error(f"Error sending message to client: {e}")

manager = ConnectionManager()

# Background Kafka consumer task
async def consume_kafka():
    consumer = AIOKafkaConsumer(
        KAFKA_TOPIC,
        bootstrap_servers=KAFKA_SERVER,
        group_id="fastapi_group",
        value_deserializer=lambda m: json.loads(m.decode('utf-8'))
    )
    
    # Simple retry loop for startup coordination
    max_retries = 10
    retry_count = 0
    while retry_count < max_retries:
        try:
            await consumer.start()
            logger.info("Connected to Kafka!")
            break
        except Exception as e:
            retry_count += 1
            logger.warning(f"Kafka connection attempt {retry_count}/{max_retries}: {e}")
            if retry_count >= max_retries:
                logger.error("Failed to connect to Kafka after retries. API will operate without Kafka stream.")
                return
            await asyncio.sleep(5)

    try:
        async for msg in consumer:
            # Pushing new sensor readings to the app every 2 seconds
            # The kafka stream might be faster, but for HMI we push exactly what we receive that is latest
            await manager.broadcast_json(msg.value)
            await asyncio.sleep(2) # rate limiting to 1 update per 2 seconds approx
    except asyncio.CancelledError:
        logger.info("Kafka consumer task cancelled")
    except Exception as e:
        logger.error(f"Kafka consumer error: {e}")
    finally:
        try:
            await consumer.stop()
        except Exception:
            pass

@app.on_event("startup")
async def startup_event():
    asyncio.create_task(consume_kafka())

@app.get("/api/history")
async def get_history():
    """
    Fetches the last 24 hours of sensor readings from PostgreSQL.
    """
    try:
        # We query the scada_training_data for normal telemetry
        conn = await asyncpg.connect(POSTGRES_DSN)
        # Using epoch minus 24 hours (86400 seconds)
        query = """
            SELECT sensor_id, timestamp, "metrics.voltage", "metrics.frequency", "metrics.current", status
            FROM scada_training_data
            WHERE timestamp >= (EXTRACT(EPOCH FROM NOW()) - 86400)
            ORDER BY timestamp DESC
            LIMIT 1000
        """
        rows = await conn.fetch(query)
        await conn.close()
        
        # Convert to list of dicts
        result = [dict(r) for r in rows]
        return {"data": result}
    except Exception as e:
        logger.error(f"Error fetching history: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/alerts")
async def get_alerts():
    """
    A chronological list of all detected anomalies from PostgreSQL.
    """
    try:
        conn = await asyncpg.connect(POSTGRES_DSN)
        query = """
            SELECT sensor_id, event_time, voltage_val, freq_val, curr_val, severity, correlated_log
            FROM scada_alerts
            ORDER BY event_time DESC
        """
        rows = await conn.fetch(query)
        await conn.close()
        
        result = [dict(r) for r in rows]
        # Some column types mapping
        for r in result:
            if 'event_time' in r and r['event_time']:
                r['event_time'] = r['event_time'].isoformat()
                
        return {"data": result}
    except Exception as e:
        logger.error(f"Error fetching alerts: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/telemetry/history/{sensor_id}")
async def get_sensor_history(sensor_id: str, minutes: int = 60):
    """
    Fetches historical telemetry for a specific sensor from InfluxDB v2 using Flux.
    """
    query = f'''
    from(bucket: "{INFLUXDB_BUCKET}")
      |> range(start: -{minutes}m)
      |> filter(fn: (r) => r["_measurement"] == "grid_metrics")
      |> filter(fn: (r) => r["sensor_id"] == "{sensor_id}")
      |> pivot(rowKey:["_time"], columnKey: ["_field"], valueColumn: "_value")
      |> sort(columns: ["_time"], desc: false)
    '''
    try:
        tables = query_api.query(query, org=INFLUXDB_ORG)
        
        data = []
        for table in tables:
            for record in table.records:
                data.append({
                    "time": record.get_time().isoformat(),
                    "voltage": float(record.values.get("voltage", 0.0)),
                    "current": float(record.values.get("current", 0.0)),
                    "frequency": float(record.values.get("frequency", 0.0))
                })
        return {"data": data}
    except Exception as e:
        logger.error(f"Error querying InfluxDB: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if not firebase_admin._apps:
    cred_path = os.path.join(os.path.dirname(__file__), "..", "firebase-adminsdk.json")
    cred = credentials.Certificate(cred_path)
    firebase_admin.initialize_app(cred)

@app.post("/api/notify")
async def send_push_notification(request: NotifyRequest):
    message = messaging.Message(
        notification=messaging.Notification(
            title='Critical Anomaly Detected!',
            body=f'Sensor {request.sensor_id} detected a {request.severity} anomaly: {request.message}'
        ),
        topic='scada_alerts' 
    )
    
    response = messaging.send(message)
    return {"status": "Success", "message_id": response}
@app.websocket("/ws/live")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        while True:
            # We don't expect messages from client but connection must be kept open
            _ = await websocket.receive_text()
    except WebSocketDisconnect:
        manager.disconnect(websocket)
