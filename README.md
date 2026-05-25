# SCADA Monitoring & Anomaly Detection System

A comprehensive SCADA (Supervisory Control and Data Acquisition) system built with a modern microservices architecture for real-time monitoring and anomaly detection in industrial grids.

This project has won the IEEE Department Innovation Challenge 2026, at Bahria University Islamabad.

## Architecture Overview

The system consists of several integrated components:

- **Simulators**: Python-based grid sensor simulators that generate realistic telemetry (voltage, frequency, current) and push it to Kafka.
- **Kafka**: Acts as the central message bus for real-time data streaming.
- **Spark (Anomaly Detection)**: A PySpark application that consumes data from Kafka, applies machine learning models (LSTM Autoencoder, Isolation Forest, One-Class SVM) to detect anomalies, and persists results to PostgreSQL.
- **InfluxDB v3**: High-performance time-series database used for storing granular telemetry data.
- **PostgreSQL**: Used for storing system metadata, historical training data, and detected alerts/anomalies.
- **FastAPI Backend**: Provides a REST and WebSocket API for the HMI. It consumes real-time data from Kafka and queries historical data from Postgres and InfluxDB.
- **Flutter HMI**: A cross-platform web application for real-time visualization of grid status, historical trends, and anomaly alerts.
- **Grafana**: Integrated for advanced dashboarding and data exploration.

## System Components & Ports

| Component | Technology | Port |
|-----------|------------|------|
| HMI (Web) | Flutter | 8080 |
| Backend API | FastAPI | 8000 |
| InfluxDB | v3 (Edge) | 8181 |
| Grafana | Dashboard | 3000 |
| Kafka | Broker | 9092/9094 |
| Postgres | Database | 5432 |

## Getting Started

### Prerequisites

- Docker and Docker Compose
- Python 3.11+
- Flutter SDK
- InfluxDB v3 binary (locally installed)

### Running the System

To start all services, the user can use the script:

```bash
./start_scada.sh
```

A single script that orchestrates the following:
1. Starts Docker containers (Kafka, Postgres, Grafana, Spark).
2. Launches local InfluxDB v3.
3. Starts the FastAPI backend.
4. Initializes grid simulators.
5. Runs the Flutter web application.

## Overview

- The system uses a **Lambda Architecture** approach: real-time streaming for HMI updates and batch/micro-batch processing via Spark for anomaly detection.
- **Anomaly Detection**: Uses multiple ML models located in the `models/` directory, including a scaler and pre-trained LSTM/SVM models.
- **Real-time Flow**: Simulator -> Kafka -> Backend -> WebSocket -> HMI.
- **Analytics Flow**: Simulator -> Kafka -> Spark -> Postgres -> Backend -> HMI.
- **HMI Features**: Provides live telemetry cards, historical trend charts, and an alert list with severity levels.

# Screenshots

## Grafana Dashboard
<img width="1824" height="962" alt="Screenshot from 2026-05-09 14-50-19" src="https://github.com/user-attachments/assets/97dec9b3-98a1-4c9c-a320-198976ba00b4" />

## Flutter HMI Application

### Main Dashboard (Three substations: Alpha, Beta and Gamma)

<img width="414" height="787" alt="Screenshot from 2026-05-24 08-27-42" src="https://github.com/user-attachments/assets/aaba632f-fe55-414a-86bc-d032c0fb2ede" />

<img width="414" height="787" alt="Screenshot from 2026-05-24 08-27-50" src="https://github.com/user-attachments/assets/a03e04a5-c04b-4ecd-9bd4-9bc3c7c26f1f" />

<img width="414" height="787" alt="Screenshot from 2026-05-24 08-28-02" src="https://github.com/user-attachments/assets/cab434f4-7003-476a-95d3-d6d7ebc794b2" />

### Alerts Log Screen

<img width="546" height="963" alt="Screenshot from 2026-05-13 05-39-01" src="https://github.com/user-attachments/assets/c3264e4e-cb48-45f4-834b-3598992704bd" />

