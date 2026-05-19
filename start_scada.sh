#!/bin/bash

# Navigate to project root
cd "$(dirname "$0")"

# Load environment variables
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

echo "--- SCADA Monitoring System Startup ---"

echo "Stopping existing services..."
docker compose down
pkill -f "simulators/grid_sensor.py"
pkill -f "flutter" || true
pkill -f "dart" || true
fuser -k 8080/tcp || true

echo "Starting Infrastructure (Kafka, Postgres, InfluxDB, Grafana, Spark, Backend)..."
if ! docker compose up -d --build; then
    echo "ERROR: Docker Compose failed to start services. Check the logs above."
    exit 1
fi

echo "Waiting for services to initialize..."
# Wait for InfluxDB to be ready
until curl -s http://localhost:8086/health > /dev/null; do
    echo "Waiting for InfluxDB..."
    sleep 5
done

echo "Starting Simulators..."
source venv/bin/activate
nohup python simulators/grid_sensor.py --name ALL > logs/simulator.log 2>&1 &
SIM_PID=$!
echo "Simulators started with PID $SIM_PID"

echo "Starting Flutter HMI (Web Server)..."
cd hmi/scada_hmi_flooter
nohup flutter run -d web-server --web-port $HMI_PORT > ../../logs/flutter.log 2>&1 &
FLUTTER_PID=$!
echo "Flutter HMI started on port $HMI_PORT"

echo "------------------------------------------------"
echo "System is LIVE!"
echo "- Grafana: http://localhost:3000 (admin/admin)"
echo "- Flutter HMI: http://localhost:$HMI_PORT"
echo "- Backend API: http://localhost:$BACKEND_PORT"
echo "- InfluxDB: http://localhost:8086"
echo "------------------------------------------------"
echo "To stop everything, run: docker compose down && kill $SIM_PID $FLUTTER_PID"
