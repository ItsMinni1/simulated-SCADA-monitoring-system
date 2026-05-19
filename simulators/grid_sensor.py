import json
import time
import random
import argparse
import numpy as np
from kafka import KafkaProducer

KAFKA_BOOTSTRAP_SERVERS = 'localhost:9094'
TOPIC = 'sensor_stream'

SUBSTATION_CONFIGS = {
    'SUBSTATION_ALPHA_01': {'voltage_base': 230.0, 'freq_base': 50.0, 'current_base': 15.0},
    'SUBSTATION_BETA_02':  {'voltage_base': 230.0, 'freq_base': 50.0, 'current_base': 15.0},
    'SUBSTATION_GAMMA_03': {'voltage_base': 230.0, 'freq_base': 50.0, 'current_base': 15.0},
}

def generate_reading(sensor_id, normal_mode=False):
    """Generates a realistic electricity grid reading with noise and potential faults."""

    # Simulate missing value (10% chance)
    if random.random() < 0.10:
        return None

    config = SUBSTATION_CONFIGS.get(sensor_id, SUBSTATION_CONFIGS['SUBSTATION_ALPHA_01'])
    voltage_base = config['voltage_base']
    freq_base    = config['freq_base']
    current_base = config['current_base']

    # Add Gaussian Noise
    voltage   = np.random.normal(voltage_base, 0.5)
    frequency = np.random.normal(freq_base, 0.02)
    current   = np.random.normal(current_base, 0.2)

    # Fault Injection: Sudden spike (5% chance per substation)
    is_fault = False
    if not normal_mode and random.random() < 0.05:
        is_fault = True
        fault_type = random.choice(['OVERVOLTAGE', 'SURGE'])
        if fault_type == 'OVERVOLTAGE':
            voltage += random.uniform(50, 110)
        else:
            current += random.uniform(20, 50)

    reading = {
        'sensor_id': sensor_id,
        'timestamp': time.time(),
        'metrics': {
            'voltage':   round(voltage, 2),
            'frequency': round(frequency, 3),
            'current':   round(current, 2)
        },
        'status': 'FAULT' if is_fault else 'NORMAL'
    }
    return reading

def run_simulator(sensor_id, normal_mode=False, speed=1.0):
    print(f"--- Starting Electricity Grid Simulator [ID: {sensor_id}] ---")
    if normal_mode:
        print(">> MODE: NORMAL (Baseline Collection - No Faults)")
    if speed > 1.0:
        print(f">> SPEED: {speed}X Multiplier")

    try:
        producer = KafkaProducer(
            bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
            value_serializer=lambda v: json.dumps(v).encode('utf-8')
        )

        while True:
            reading = generate_reading(sensor_id, normal_mode)

            if reading:
                if speed <= 10.0:
                    print(f"[{sensor_id}] Publishing: {reading['status']} | "
                          f"V: {reading['metrics']['voltage']}V | "
                          f"I: {reading['metrics']['current']}A")

                producer.send(TOPIC, reading)
                producer.flush()

            base_sleep = random.uniform(1, 5)
            sleep_time = base_sleep / speed
            if sleep_time > 0:
                time.sleep(sleep_time)

    except KeyboardInterrupt:
        print(f"\n[{sensor_id}] Simulator stopped.")
    except Exception as e:
        print(f"Simulator Error [{sensor_id}]: {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Grid Sensor Simulator")
    parser.add_argument(
        "--name",
        type=str,
        default='ALL',
        choices=list(SUBSTATION_CONFIGS.keys()) + ['ALL'],
        help="Substation ID to simulate or 'ALL' for all substations. Default: ALL"
    )
    parser.add_argument("--normal", action="store_true", help="Disable fault injection for baseline collection")
    parser.add_argument("--speed", type=float, default=1.0, help="Speed multiplier (e.g., 50)")

    args = parser.parse_args()
    
    if args.name == 'ALL':
        import multiprocessing
        processes = []
        for name in SUBSTATION_CONFIGS.keys():
            p = multiprocessing.Process(target=run_simulator, args=(name, args.normal, args.speed))
            p.start()
            processes.append(p)
        try:
            for p in processes:
                p.join()
        except KeyboardInterrupt:
            for p in processes:
                p.terminate()
    else:
        run_simulator(sensor_id=args.name, normal_mode=args.normal, speed=args.speed)
