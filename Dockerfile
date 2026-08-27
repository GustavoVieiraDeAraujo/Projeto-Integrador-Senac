FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

RUN useradd --uid 1000 --create-home etl && chown -R etl:etl /app
USER etl

CMD ["sh", "-c", "python etl/baixar_dados.py && python etl/run_etl.py"]
