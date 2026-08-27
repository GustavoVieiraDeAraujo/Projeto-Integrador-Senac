SELECT pg_terminate_backend(pid)
  FROM pg_stat_activity
 WHERE datname = 'dw_olist'
   AND pid <> pg_backend_pid();

DROP DATABASE IF EXISTS dw_olist;

CREATE DATABASE dw_olist
    WITH ENCODING = 'UTF8'
         TEMPLATE = template0;

COMMENT ON DATABASE dw_olist IS
    'Data Warehouse para analise de desempenho comercial e logistico em e-commerce (base publica Olist)';
