SET client_encoding = 'UTF8';

CREATE INDEX IF NOT EXISTS ix_stg_orders_order_id       ON stg.olist_orders (order_id);
CREATE INDEX IF NOT EXISTS ix_stg_orders_customer_id    ON stg.olist_orders (customer_id);
CREATE INDEX IF NOT EXISTS ix_stg_items_order_id        ON stg.olist_order_items (order_id);
CREATE INDEX IF NOT EXISTS ix_stg_items_product_id      ON stg.olist_order_items (product_id);
CREATE INDEX IF NOT EXISTS ix_stg_items_seller_id       ON stg.olist_order_items (seller_id);
CREATE INDEX IF NOT EXISTS ix_stg_payments_order_id     ON stg.olist_order_payments (order_id);
CREATE INDEX IF NOT EXISTS ix_stg_reviews_order_id      ON stg.olist_order_reviews (order_id);
CREATE INDEX IF NOT EXISTS ix_stg_customers_customer_id ON stg.olist_customers (customer_id);
CREATE INDEX IF NOT EXISTS ix_stg_geolocation_zip       ON stg.olist_geolocation (geolocation_zip_code_prefix);
ANALYZE stg.olist_orders; ANALYZE stg.olist_order_items; ANALYZE stg.olist_order_payments;
ANALYZE stg.olist_order_reviews; ANALYZE stg.olist_customers; ANALYZE stg.olist_products;
ANALYZE stg.olist_sellers; ANALYZE stg.olist_geolocation; ANALYZE stg.product_category_name_translation;

TRUNCATE TABLE dw.fato_vendas, dw.fato_pedido,
               dw.dim_tempo, dw.dim_cliente, dw.dim_produto, dw.dim_vendedor,
               dw.dim_geografia, dw.dim_pagamento, dw.dim_status
               RESTART IDENTITY;

WITH limites AS (
    SELECT DATE_TRUNC('year', MIN(order_purchase_timestamp::TIMESTAMP))::DATE                  AS dt_ini,
           (DATE_TRUNC('year', GREATEST(MAX(order_estimated_delivery_date::TIMESTAMP),
                                        MAX(order_delivered_customer_date::TIMESTAMP)))
            + INTERVAL '1 year - 1 day')::DATE                                                AS dt_fim
      FROM stg.olist_orders
),
calendario AS (
    SELECT g.d::DATE AS data
      FROM limites l, GENERATE_SERIES(l.dt_ini, l.dt_fim, INTERVAL '1 day') AS g(d)
)
INSERT INTO dw.dim_tempo (sk_tempo, data, dia, mes, nome_mes, mes_abrev, trimestre, nome_trimestre,
                          semestre, ano, ano_mes, dia_semana, nome_dia_semana, fim_de_semana)
SELECT TO_CHAR(data, 'YYYYMMDD')::INTEGER                                            AS sk_tempo,
       data,
       EXTRACT(DAY FROM data)::SMALLINT                                              AS dia,
       EXTRACT(MONTH FROM data)::SMALLINT                                            AS mes,
       (ARRAY['Janeiro','Fevereiro','Março','Abril','Maio','Junho','Julho','Agosto',
              'Setembro','Outubro','Novembro','Dezembro'])[EXTRACT(MONTH FROM data)] AS nome_mes,
       (ARRAY['Jan','Fev','Mar','Abr','Mai','Jun','Jul','Ago',
              'Set','Out','Nov','Dez'])[EXTRACT(MONTH FROM data)]                   AS mes_abrev,
       EXTRACT(QUARTER FROM data)::SMALLINT                                          AS trimestre,
       EXTRACT(QUARTER FROM data)::TEXT || 'T' || EXTRACT(YEAR FROM data)::TEXT     AS nome_trimestre,
       CASE WHEN EXTRACT(MONTH FROM data) <= 6 THEN 1 ELSE 2 END::SMALLINT          AS semestre,
       EXTRACT(YEAR FROM data)::SMALLINT                                             AS ano,
       TO_CHAR(data, 'YYYY-MM')                                                      AS ano_mes,
       EXTRACT(DOW FROM data)::SMALLINT                                              AS dia_semana,
       (ARRAY['Domingo','Segunda-feira','Terça-feira','Quarta-feira','Quinta-feira',
              'Sexta-feira','Sábado'])[EXTRACT(DOW FROM data) + 1]                  AS nome_dia_semana,
       EXTRACT(DOW FROM data) IN (0, 6)                                              AS fim_de_semana
  FROM calendario;

INSERT INTO dw.dim_status (status_original, status_descricao, flag_entregue, flag_cancelado, ordem_ciclo)
SELECT s.status_original,
       COALESCE(m.descricao, INITCAP(s.status_original)),
       COALESCE(m.flag_entregue, FALSE),
       COALESCE(m.flag_cancelado, FALSE),
       COALESCE(m.ordem, 99)
  FROM (SELECT DISTINCT LOWER(TRIM(order_status)) AS status_original
          FROM stg.olist_orders
         WHERE order_status IS NOT NULL) s
  LEFT JOIN (VALUES ('created',     'Criado',           FALSE, FALSE, 1),
                    ('approved',    'Aprovado',         FALSE, FALSE, 2),
                    ('invoiced',    'Faturado',         FALSE, FALSE, 3),
                    ('processing',  'Em processamento', FALSE, FALSE, 4),
                    ('shipped',     'Enviado',          FALSE, FALSE, 5),
                    ('delivered',   'Entregue',         TRUE,  FALSE, 6),
                    ('unavailable', 'Indisponível',     FALSE, FALSE, 7),
                    ('canceled',    'Cancelado',        FALSE, TRUE,  8)
            ) AS m (status, descricao, flag_entregue, flag_cancelado, ordem)
         ON m.status = s.status_original
 ORDER BY COALESCE(m.ordem, 99), s.status_original;

INSERT INTO dw.dim_pagamento (sk_pagamento, tipo_pagamento_original, tipo_pagamento, num_parcelas, faixa_parcelas)
VALUES (0, 'nao_informado', 'Não informado', 0, 'Não informado');

INSERT INTO dw.dim_pagamento (tipo_pagamento_original, tipo_pagamento, num_parcelas, faixa_parcelas)
SELECT DISTINCT
       LOWER(TRIM(payment_type))                                               AS tipo_pagamento_original,
       CASE LOWER(TRIM(payment_type))
            WHEN 'credit_card' THEN 'Cartão de crédito'
            WHEN 'boleto'      THEN 'Boleto'
            WHEN 'voucher'     THEN 'Voucher'
            WHEN 'debit_card'  THEN 'Cartão de débito'
            WHEN 'not_defined' THEN 'Não definido'
            ELSE INITCAP(REPLACE(TRIM(payment_type), '_', ' '))
       END                                                                     AS tipo_pagamento,
       payment_installments::INTEGER                                           AS num_parcelas,
       CASE WHEN payment_installments::INTEGER <= 1  THEN 'À vista'
            WHEN payment_installments::INTEGER <= 3  THEN '2 a 3 parcelas'
            WHEN payment_installments::INTEGER <= 6  THEN '4 a 6 parcelas'
            WHEN payment_installments::INTEGER <= 12 THEN '7 a 12 parcelas'
            ELSE 'Acima de 12 parcelas'
       END                                                                     AS faixa_parcelas
  FROM stg.olist_order_payments
 WHERE payment_type IS NOT NULL
 ORDER BY 1, 3;

INSERT INTO dw.dim_produto (product_id, categoria_original, categoria, categoria_en,
                            peso_g, comprimento_cm, altura_cm, largura_cm, volume_cm3,
                            faixa_peso, qtd_fotos, tamanho_nome, tamanho_descricao)
SELECT p.product_id,
       COALESCE(NULLIF(TRIM(p.product_category_name), ''), 'nao_informado')                 AS categoria_original,
       COALESCE(dw.fn_padroniza_texto(REPLACE(p.product_category_name, '_', ' ')),
                'Não informado')                                                            AS categoria,
       COALESCE(dw.fn_padroniza_texto(REPLACE(t.product_category_name_english, '_', ' ')),
                dw.fn_padroniza_texto(REPLACE(p.product_category_name, '_', ' ')),
                'Not informed')                                                             AS categoria_en,
       NULLIF(TRIM(p.product_weight_g), '')::NUMERIC::INTEGER                               AS peso_g,
       NULLIF(TRIM(p.product_length_cm), '')::NUMERIC::SMALLINT                             AS comprimento_cm,
       NULLIF(TRIM(p.product_height_cm), '')::NUMERIC::SMALLINT                             AS altura_cm,
       NULLIF(TRIM(p.product_width_cm), '')::NUMERIC::SMALLINT                              AS largura_cm,
       (NULLIF(TRIM(p.product_length_cm), '')::NUMERIC
        * NULLIF(TRIM(p.product_height_cm), '')::NUMERIC
        * NULLIF(TRIM(p.product_width_cm), '')::NUMERIC)::INTEGER                           AS volume_cm3,
       CASE WHEN NULLIF(TRIM(p.product_weight_g), '') IS NULL          THEN 'Não informado'
            WHEN p.product_weight_g::NUMERIC <= 500                     THEN 'Até 500 g'
            WHEN p.product_weight_g::NUMERIC <= 2000                    THEN '501 g a 2 kg'
            WHEN p.product_weight_g::NUMERIC <= 10000                   THEN '2 kg a 10 kg'
            ELSE                                                             'Acima de 10 kg'
       END                                                                                  AS faixa_peso,
       NULLIF(TRIM(p.product_photos_qty), '')::NUMERIC::SMALLINT                            AS qtd_fotos,
       NULLIF(TRIM(p.product_name_lenght), '')::NUMERIC::SMALLINT                           AS tamanho_nome,
       NULLIF(TRIM(p.product_description_lenght), '')::NUMERIC::SMALLINT                    AS tamanho_descricao
  FROM (SELECT DISTINCT ON (product_id) *
          FROM stg.olist_products
         WHERE product_id IS NOT NULL
         ORDER BY product_id) p
  LEFT JOIN stg.product_category_name_translation t
         ON t.product_category_name = p.product_category_name;

INSERT INTO dw.dim_vendedor (seller_id, cep_prefixo, cidade, estado, nome_estado, regiao)
SELECT s.seller_id,
       LPAD(TRIM(s.seller_zip_code_prefix), 5, '0')      AS cep_prefixo,
       dw.fn_padroniza_texto(s.seller_city)              AS cidade,
       UPPER(TRIM(s.seller_state))                       AS estado,
       r.nome_estado,
       r.regiao
  FROM (SELECT DISTINCT ON (seller_id) *
          FROM stg.olist_sellers
         WHERE seller_id IS NOT NULL
         ORDER BY seller_id) s
  LEFT JOIN dw.aux_uf_regiao r ON r.uf = UPPER(TRIM(s.seller_state));

WITH pedidos_cliente AS (
    SELECT c.customer_unique_id,
           c.customer_zip_code_prefix,
           c.customer_city,
           c.customer_state,
           o.order_purchase_timestamp::TIMESTAMP AS dt_compra
      FROM stg.olist_customers c
      LEFT JOIN stg.olist_orders o ON o.customer_id = c.customer_id
),
ultimo_pedido AS (
    SELECT DISTINCT ON (customer_unique_id)
           customer_unique_id, customer_zip_code_prefix, customer_city, customer_state
      FROM pedidos_cliente
     ORDER BY customer_unique_id, dt_compra DESC NULLS LAST
),
contagem AS (
    SELECT customer_unique_id, COUNT(dt_compra) AS qtd_pedidos
      FROM pedidos_cliente
     GROUP BY customer_unique_id
)
INSERT INTO dw.dim_cliente (customer_unique_id, cep_prefixo, cidade, estado, nome_estado, regiao,
                            qtd_pedidos, flag_recorrente)
SELECT u.customer_unique_id,
       LPAD(TRIM(u.customer_zip_code_prefix), 5, '0'),
       dw.fn_padroniza_texto(u.customer_city),
       UPPER(TRIM(u.customer_state)),
       r.nome_estado,
       r.regiao,
       ct.qtd_pedidos,
       ct.qtd_pedidos > 1
  FROM ultimo_pedido u
  JOIN contagem ct USING (customer_unique_id)
  LEFT JOIN dw.aux_uf_regiao r ON r.uf = UPPER(TRIM(u.customer_state));

WITH geo AS (
    SELECT LPAD(TRIM(geolocation_zip_code_prefix), 5, '0')  AS cep_prefixo,
           geolocation_lat::NUMERIC                          AS lat,
           geolocation_lng::NUMERIC                          AS lng,
           dw.fn_padroniza_texto(geolocation_city)           AS cidade,
           UPPER(TRIM(geolocation_state))                    AS estado
      FROM stg.olist_geolocation
     WHERE geolocation_lat::NUMERIC BETWEEN -33.75 AND 5.27
       AND geolocation_lng::NUMERIC BETWEEN -73.99 AND -34.79
),
geo_agg AS (
    SELECT cep_prefixo,
           AVG(lat)                                     AS latitude_media,
           AVG(lng)                                     AS longitude_media,
           COUNT(*)                                     AS qtd_registros,
           MODE() WITHIN GROUP (ORDER BY cidade)        AS cidade,
           MODE() WITHIN GROUP (ORDER BY estado)        AS estado
      FROM geo
     GROUP BY cep_prefixo
),
cep_transacional AS (
    SELECT LPAD(TRIM(customer_zip_code_prefix), 5, '0') AS cep_prefixo,
           dw.fn_padroniza_texto(customer_city)         AS cidade,
           UPPER(TRIM(customer_state))                  AS estado
      FROM stg.olist_customers
    UNION ALL
    SELECT LPAD(TRIM(seller_zip_code_prefix), 5, '0'),
           dw.fn_padroniza_texto(seller_city),
           UPPER(TRIM(seller_state))
      FROM stg.olist_sellers
),
cep_transacional_agg AS (
    SELECT cep_prefixo,
           MODE() WITHIN GROUP (ORDER BY cidade) AS cidade,
           MODE() WITHIN GROUP (ORDER BY estado) AS estado
      FROM cep_transacional
     GROUP BY cep_prefixo
)
INSERT INTO dw.dim_geografia (cep_prefixo, cidade, estado, nome_estado, regiao,
                              latitude_media, longitude_media, qtd_registros_origem, origem)
SELECT COALESCE(t.cep_prefixo, g.cep_prefixo)                       AS cep_prefixo,
       COALESCE(t.cidade, g.cidade)                                 AS cidade,
       COALESCE(t.estado, g.estado)                                 AS estado,
       r.nome_estado,
       r.regiao,
       ROUND(g.latitude_media, 6),
       ROUND(g.longitude_media, 6),
       COALESCE(g.qtd_registros, 0),
       CASE WHEN g.cep_prefixo IS NOT NULL THEN 'geolocation' ELSE 'clientes/vendedores' END
  FROM geo_agg g
  FULL OUTER JOIN cep_transacional_agg t ON t.cep_prefixo = g.cep_prefixo
  LEFT JOIN dw.aux_uf_regiao r ON r.uf = COALESCE(t.estado, g.estado);

WITH pagamentos AS (
    SELECT order_id,
           SUM(payment_value::NUMERIC) AS valor_pago,
           COUNT(*)                    AS qtd_pagamentos
      FROM stg.olist_order_payments
     GROUP BY order_id
),
pagamento_principal AS (
    SELECT DISTINCT ON (order_id)
           order_id,
           LOWER(TRIM(payment_type))    AS tipo_pagamento_original,
           payment_installments::INTEGER AS num_parcelas
      FROM stg.olist_order_payments
     ORDER BY order_id, payment_value::NUMERIC DESC, payment_sequential::INTEGER
),
itens AS (
    SELECT order_id,
           COUNT(*)                    AS qtd_itens,
           COUNT(DISTINCT product_id)  AS qtd_produtos_distintos,
           COUNT(DISTINCT seller_id)   AS qtd_vendedores,
           SUM(price::NUMERIC)         AS valor_itens,
           SUM(freight_value::NUMERIC) AS valor_frete
      FROM stg.olist_order_items
     GROUP BY order_id
),
avaliacao AS (
    SELECT DISTINCT ON (order_id)
           order_id,
           review_score::SMALLINT AS nota_avaliacao
      FROM stg.olist_order_reviews
     WHERE review_score IS NOT NULL
     ORDER BY order_id,
              review_answer_timestamp::TIMESTAMP DESC NULLS LAST,
              review_creation_date::TIMESTAMP DESC NULLS LAST
),
pedidos AS (
    SELECT o.order_id,
           o.customer_id,
           LOWER(TRIM(o.order_status))                        AS status_original,
           o.order_purchase_timestamp::TIMESTAMP              AS dt_compra,
           o.order_approved_at::TIMESTAMP                     AS dt_aprovacao,
           o.order_delivered_customer_date::TIMESTAMP         AS dt_entrega,
           o.order_estimated_delivery_date::TIMESTAMP         AS dt_estimada
      FROM stg.olist_orders o
)
INSERT INTO dw.fato_pedido (order_id, sk_tempo_compra, sk_tempo_aprovacao, sk_tempo_entrega, sk_tempo_estimada,
                            sk_cliente, sk_geografia, sk_pagamento, sk_status,
                            qtd_itens, qtd_produtos_distintos, qtd_vendedores,
                            valor_itens, valor_frete, valor_total, valor_pago, qtd_pagamentos, participacao_frete,
                            prazo_entrega_dias, prazo_estimado_dias, atraso_entrega_dias, flag_entregue_com_atraso,
                            nota_avaliacao)
SELECT p.order_id,
       TO_CHAR(p.dt_compra,    'YYYYMMDD')::INTEGER                                   AS sk_tempo_compra,
       TO_CHAR(p.dt_aprovacao, 'YYYYMMDD')::INTEGER                                   AS sk_tempo_aprovacao,
       TO_CHAR(p.dt_entrega,   'YYYYMMDD')::INTEGER                                   AS sk_tempo_entrega,
       TO_CHAR(p.dt_estimada,  'YYYYMMDD')::INTEGER                                   AS sk_tempo_estimada,
       dc.sk_cliente,
       dg.sk_geografia,
       COALESCE(dpg.sk_pagamento, 0)                                                  AS sk_pagamento,
       ds.sk_status,
       COALESCE(i.qtd_itens, 0),
       COALESCE(i.qtd_produtos_distintos, 0),
       COALESCE(i.qtd_vendedores, 0),
       COALESCE(i.valor_itens, 0),
       COALESCE(i.valor_frete, 0),
       COALESCE(i.valor_itens, 0) + COALESCE(i.valor_frete, 0)                       AS valor_total,
       pg.valor_pago,
       COALESCE(pg.qtd_pagamentos, 0),
       CASE WHEN COALESCE(i.valor_itens, 0) + COALESCE(i.valor_frete, 0) > 0
            THEN ROUND(i.valor_frete / (i.valor_itens + i.valor_frete), 4) END       AS participacao_frete,
       (p.dt_entrega::DATE - p.dt_compra::DATE)::SMALLINT                             AS prazo_entrega_dias,
       (p.dt_estimada::DATE - p.dt_compra::DATE)::SMALLINT                            AS prazo_estimado_dias,
       (p.dt_entrega::DATE - p.dt_estimada::DATE)::SMALLINT                           AS atraso_entrega_dias,
       CASE WHEN p.dt_entrega IS NULL THEN NULL
            ELSE p.dt_entrega::DATE > p.dt_estimada::DATE END                         AS flag_entregue_com_atraso,
       av.nota_avaliacao
  FROM pedidos p
  JOIN stg.olist_customers c    ON c.customer_id = p.customer_id
  JOIN dw.dim_cliente dc        ON dc.customer_unique_id = c.customer_unique_id
  JOIN dw.dim_geografia dg      ON dg.cep_prefixo = LPAD(TRIM(c.customer_zip_code_prefix), 5, '0')
  JOIN dw.dim_status ds         ON ds.status_original = p.status_original
  LEFT JOIN itens i             ON i.order_id = p.order_id
  LEFT JOIN pagamentos pg       ON pg.order_id = p.order_id
  LEFT JOIN pagamento_principal pp ON pp.order_id = p.order_id
  LEFT JOIN dw.dim_pagamento dpg ON dpg.tipo_pagamento_original = pp.tipo_pagamento_original
                                AND dpg.num_parcelas = pp.num_parcelas
  LEFT JOIN avaliacao av        ON av.order_id = p.order_id;

INSERT INTO dw.fato_vendas (sk_tempo, sk_cliente, sk_produto, sk_vendedor, sk_geografia, sk_pagamento, sk_status,
                            order_id, order_item_id, valor_item, valor_frete, valor_total_item,
                            prazo_entrega_dias, atraso_entrega_dias, nota_avaliacao)
SELECT fp.sk_tempo_compra                                        AS sk_tempo,
       fp.sk_cliente,
       dp.sk_produto,
       dv.sk_vendedor,
       fp.sk_geografia,
       fp.sk_pagamento,
       fp.sk_status,
       i.order_id,
       i.order_item_id::SMALLINT,
       i.price::NUMERIC(10,2)                                    AS valor_item,
       i.freight_value::NUMERIC(10,2)                            AS valor_frete,
       (i.price::NUMERIC + i.freight_value::NUMERIC)::NUMERIC(10,2) AS valor_total_item,
       fp.prazo_entrega_dias,
       fp.atraso_entrega_dias,
       fp.nota_avaliacao
  FROM stg.olist_order_items i
  JOIN dw.fato_pedido fp  ON fp.order_id = i.order_id
  JOIN dw.dim_produto dp  ON dp.product_id = i.product_id
  JOIN dw.dim_vendedor dv ON dv.seller_id = i.seller_id;

ANALYZE dw.dim_tempo; ANALYZE dw.dim_cliente; ANALYZE dw.dim_produto; ANALYZE dw.dim_vendedor;
ANALYZE dw.dim_geografia; ANALYZE dw.dim_pagamento; ANALYZE dw.dim_status;
ANALYZE dw.fato_vendas; ANALYZE dw.fato_pedido;

SELECT 'dw.dim_tempo'      AS tabela, COUNT(*) AS registros FROM dw.dim_tempo      UNION ALL
SELECT 'dw.dim_cliente',                COUNT(*)              FROM dw.dim_cliente    UNION ALL
SELECT 'dw.dim_produto',                COUNT(*)              FROM dw.dim_produto    UNION ALL
SELECT 'dw.dim_vendedor',               COUNT(*)              FROM dw.dim_vendedor   UNION ALL
SELECT 'dw.dim_geografia',              COUNT(*)              FROM dw.dim_geografia  UNION ALL
SELECT 'dw.dim_pagamento',              COUNT(*)              FROM dw.dim_pagamento  UNION ALL
SELECT 'dw.dim_status',                 COUNT(*)              FROM dw.dim_status     UNION ALL
SELECT 'dw.fato_pedido',                COUNT(*)              FROM dw.fato_pedido    UNION ALL
SELECT 'dw.fato_vendas',                COUNT(*)              FROM dw.fato_vendas;
