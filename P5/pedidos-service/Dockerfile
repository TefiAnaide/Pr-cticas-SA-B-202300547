# ---- Stage "dev": usada por docker-compose (hot-reload con --reload) ----
FROM python:3.12-slim AS dev
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8000
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]

# ---- Stage "builder": solo dependencias de produccion ----
FROM python:3.12-slim AS builder
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---- Stage "runtime": imagen final para Kubernetes (target por defecto) ----
FROM python:3.12-slim AS runtime
WORKDIR /app
# Parchea paquetes del sistema operativo (perl-base, etc.) heredados de la
# imagen base que traen CVEs CRITICAL no relacionadas con el codigo Python.
RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*
RUN groupadd -r app && useradd -r -g app app
COPY --from=builder /install /usr/local
COPY src ./src
# Sin esto, Python bufferea stdout cuando no hay una TTY (siempre el caso
# en un contenedor) — los logs pueden no aparecer nunca en `kubectl logs`.
ENV PYTHONUNBUFFERED=1
USER app
EXPOSE 8000
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]
