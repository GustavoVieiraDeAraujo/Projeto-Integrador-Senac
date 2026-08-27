\echo '>>> Carga do staging a partir de data/raw'

TRUNCATE TABLE stg.olist_orders, stg.olist_order_items, stg.olist_order_payments,
               stg.olist_order_reviews, stg.olist_customers, stg.olist_products,
               stg.olist_sellers, stg.olist_geolocation,
               stg.product_category_name_translation, stg.controle_carga
               RESTART IDENTITY;

\copy stg.olist_orders                        FROM 'data/raw/olist_orders_dataset.csv'            WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8')
\copy stg.olist_order_items                   FROM 'data/raw/olist_order_items_dataset.csv'       WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8')
\copy stg.olist_order_payments                FROM 'data/raw/olist_order_payments_dataset.csv'    WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8')
\copy stg.olist_order_reviews                 FROM 'data/raw/olist_order_reviews_dataset.csv'     WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8')
\copy stg.olist_customers                     FROM 'data/raw/olist_customers_dataset.csv'         WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8')
\copy stg.olist_products                      FROM 'data/raw/olist_products_dataset.csv'          WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8')
\copy stg.olist_sellers                       FROM 'data/raw/olist_sellers_dataset.csv'           WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8')
\copy stg.olist_geolocation                   FROM 'data/raw/olist_geolocation_dataset.csv'       WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8')
\copy stg.product_category_name_translation   FROM 'data/raw/product_category_name_translation.csv' WITH (FORMAT csv, HEADER true, NULL '', ENCODING 'UTF8')

INSERT INTO stg.controle_carga (arquivo, tabela_destino, registros_lidos, registros_carregados, fim_carga, situacao)
SELECT 'olist_orders_dataset.csv',            'stg.olist_orders',            COUNT(*), COUNT(*), CURRENT_TIMESTAMP, 'CONCLUIDA' FROM stg.olist_orders UNION ALL
SELECT 'olist_order_items_dataset.csv',       'stg.olist_order_items',       COUNT(*), COUNT(*), CURRENT_TIMESTAMP, 'CONCLUIDA' FROM stg.olist_order_items UNION ALL
SELECT 'olist_order_payments_dataset.csv',    'stg.olist_order_payments',    COUNT(*), COUNT(*), CURRENT_TIMESTAMP, 'CONCLUIDA' FROM stg.olist_order_payments UNION ALL
SELECT 'olist_order_reviews_dataset.csv',     'stg.olist_order_reviews',     COUNT(*), COUNT(*), CURRENT_TIMESTAMP, 'CONCLUIDA' FROM stg.olist_order_reviews UNION ALL
SELECT 'olist_customers_dataset.csv',         'stg.olist_customers',         COUNT(*), COUNT(*), CURRENT_TIMESTAMP, 'CONCLUIDA' FROM stg.olist_customers UNION ALL
SELECT 'olist_products_dataset.csv',          'stg.olist_products',          COUNT(*), COUNT(*), CURRENT_TIMESTAMP, 'CONCLUIDA' FROM stg.olist_products UNION ALL
SELECT 'olist_sellers_dataset.csv',           'stg.olist_sellers',           COUNT(*), COUNT(*), CURRENT_TIMESTAMP, 'CONCLUIDA' FROM stg.olist_sellers UNION ALL
SELECT 'olist_geolocation_dataset.csv',       'stg.olist_geolocation',       COUNT(*), COUNT(*), CURRENT_TIMESTAMP, 'CONCLUIDA' FROM stg.olist_geolocation UNION ALL
SELECT 'product_category_name_translation.csv', 'stg.product_category_name_translation', COUNT(*), COUNT(*), CURRENT_TIMESTAMP, 'CONCLUIDA' FROM stg.product_category_name_translation;

\echo '>>> Registros carregados por arquivo'
SELECT arquivo, tabela_destino, registros_carregados, situacao
  FROM stg.controle_carga
 ORDER BY id_carga;
