FROM apache/beam_python3.11_sdk:latest

WORKDIR /app

COPY beam_pipeline/requirements.txt .
RUN pip install -r requirements.txt

COPY beam_pipeline/beam_pipeline.py .