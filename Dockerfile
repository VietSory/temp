FROM python:3.13-alpine

WORKDIR /app

RUN pip install --no-cache-dir flask prometheus-flask-exporter

COPY app.py /app/app.py

ENV FLASK_APP=app.py
ENV VERSION=v0.0.1
ENV ERROR_RATE=0

EXPOSE 8080

CMD ["python", "app.py"]
