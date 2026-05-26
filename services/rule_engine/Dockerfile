# Build stage
FROM python:3.12-slim as builder

WORKDIR /app
COPY services/rule_engine/requirements.txt .
RUN pip install --upgrade pip setuptools wheel && pip install --user --no-cache-dir -r requirements.txt

# Runtime stage
FROM python:3.12-slim

WORKDIR /app
COPY --from=builder /root/.local /root/.local
COPY services/rule_engine/ .

ENV PATH=/root/.local/bin:$PATH
ENV PYTHONUNBUFFERED=1

EXPOSE 8080

CMD ["python", "app.py"]
