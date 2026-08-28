SET client_encoding = 'UTF8';

DROP SCHEMA IF EXISTS stg CASCADE;
CREATE SCHEMA stg;
COMMENT ON SCHEMA stg IS 'Area de preparacao (staging). Copia bruta dos arquivos CSV da base Olist.';

CREATE TABLE stg.controle_carga (
    id_carga            SERIAL PRIMARY KEY,
    arquivo             VARCHAR(100) NOT NULL,
    tabela_destino      VARCHAR(100) NOT NULL,
    registros_lidos     INTEGER,
    registros_carregados INTEGER,
    inicio_carga        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fim_carga           TIMESTAMP,
    situacao            VARCHAR(20) NOT NULL DEFAULT 'EM ANDAMENTO',
    observacao          TEXT
);
COMMENT ON TABLE stg.controle_carga IS 'Log de controle da etapa de extracao (registros lidos por arquivo).';

CREATE TABLE stg.olist_orders (
    order_id                      TEXT,
    customer_id                   TEXT,
    order_status                  TEXT,
    order_purchase_timestamp      TEXT,
    order_approved_at             TEXT,
    order_delivered_carrier_date  TEXT,
    order_delivered_customer_date TEXT,
    order_estimated_delivery_date TEXT
);
COMMENT ON TABLE stg.olist_orders IS 'Pedidos, status e datas (compra, aprovacao, envio, entrega e estimativa).';

CREATE TABLE stg.olist_order_items (
    order_id            TEXT,
    order_item_id       TEXT,
    product_id          TEXT,
    seller_id           TEXT,
    shipping_limit_date TEXT,
    price               TEXT,
    freight_value       TEXT
);
COMMENT ON TABLE stg.olist_order_items IS 'Itens de cada pedido, com preco e frete.';

CREATE TABLE stg.olist_order_payments (
    order_id             TEXT,
    payment_sequential   TEXT,
    payment_type         TEXT,
    payment_installments TEXT,
    payment_value        TEXT
);
COMMENT ON TABLE stg.olist_order_payments IS 'Formas e valores de pagamento de cada pedido.';

CREATE TABLE stg.olist_order_reviews (
    review_id               TEXT,
    order_id                TEXT,
    review_score            TEXT,
    review_comment_title    TEXT,
    review_comment_message  TEXT,
    review_creation_date    TEXT,
    review_answer_timestamp TEXT
);
COMMENT ON TABLE stg.olist_order_reviews IS 'Avaliacoes e notas atribuidas pelos clientes.';

CREATE TABLE stg.olist_customers (
    customer_id              TEXT,
    customer_unique_id       TEXT,
    customer_zip_code_prefix TEXT,
    customer_city            TEXT,
    customer_state           TEXT
);
COMMENT ON TABLE stg.olist_customers IS 'Clientes (um registro por pedido) e sua localizacao.';

CREATE TABLE stg.olist_products (
    product_id                 TEXT,
    product_category_name      TEXT,
    product_name_lenght        TEXT,
    product_description_lenght TEXT,
    product_photos_qty         TEXT,
    product_weight_g           TEXT,
    product_length_cm          TEXT,
    product_height_cm          TEXT,
    product_width_cm           TEXT
);
COMMENT ON TABLE stg.olist_products IS 'Produtos e seus atributos fisicos.';

CREATE TABLE stg.olist_sellers (
    seller_id              TEXT,
    seller_zip_code_prefix TEXT,
    seller_city            TEXT,
    seller_state           TEXT
);
COMMENT ON TABLE stg.olist_sellers IS 'Vendedores e sua localizacao.';

CREATE TABLE stg.olist_geolocation (
    geolocation_zip_code_prefix TEXT,
    geolocation_lat             TEXT,
    geolocation_lng             TEXT,
    geolocation_city            TEXT,
    geolocation_state           TEXT
);
COMMENT ON TABLE stg.olist_geolocation IS 'Prefixos de CEP e coordenadas geograficas (varios registros por prefixo).';

CREATE TABLE stg.product_category_name_translation (
    product_category_name         TEXT,
    product_category_name_english TEXT
);
COMMENT ON TABLE stg.product_category_name_translation IS 'Traducao dos nomes das categorias de produto.';

