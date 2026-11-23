FROM python:3.12-slim
RUN pip install --no-cache-dir pandas==3.0.5 openpyxl==3.1.5 pyarrow==26.0.1 \
    sqlalchemy==2.1.9 psycopg2-binary==2.9.13 pymssql==2.4.6
COPY load_file.py mssql_to_pg.py /app/
WORKDIR /data
ENTRYPOINT ["python", "/app/load_file.py"]
