import os
import time
from flask import Flask, jsonify, request

app = Flask(__name__)

MODEL_VERSION = os.getenv("MODEL_VERSION", "blue-v1")
STARTUP_DELAY_SECONDS = float(os.getenv("STARTUP_DELAY_SECONDS", "0"))
MODEL_LOAD_FAIL = os.getenv("MODEL_LOAD_FAIL", "false").lower() == "true"

# Simulate model initialization at process startup.
time.sleep(max(0, STARTUP_DELAY_SECONDS))
MODEL_READY = not MODEL_LOAD_FAIL

@app.get("/healthz")
def healthz():
    """Liveness: the Flask process is responding."""
    return jsonify(status="ok", version=MODEL_VERSION), 200

@app.get("/readyz")
def readyz():
    """Readiness: simulated model has finished loading successfully."""
    if not MODEL_READY:
        return jsonify(status="not_ready", version=MODEL_VERSION), 503
    return jsonify(status="ready", version=MODEL_VERSION), 200

@app.get("/version")
def version():
    return jsonify(version=MODEL_VERSION), 200

@app.post("/predict")
def predict():
    if not MODEL_READY:
        return jsonify(error="model_not_ready", version=MODEL_VERSION), 503

    payload = request.get_json(silent=True) or {}
    try:
        # Simple deterministic simulation, not a real lending model.
        income = float(payload.get("annual_income", 50000))
        debt = float(payload.get("existing_debt", 10000))
        payment_history = float(payload.get("payment_history_score", 0.8))
        if income < 0 or debt < 0 or not 0 <= payment_history <= 1:
            raise ValueError("income/debt must be non-negative and payment_history_score must be 0..1")
    except (TypeError, ValueError) as exc:
        return jsonify(error="invalid_input", details=str(exc)), 400

    debt_ratio = debt / max(income, 1.0)
    risk_score = max(0.0, min(1.0, 0.15 + 0.75 * debt_ratio + 0.45 * (1.0 - payment_history)))
    risk_band = "high" if risk_score >= 0.65 else ("medium" if risk_score >= 0.35 else "low")
    return jsonify(
        version=MODEL_VERSION,
        risk_score=round(risk_score, 4),
        risk_band=risk_band,
        disclaimer="Simulated score for deployment testing only; not for real credit decisions."
    ), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
