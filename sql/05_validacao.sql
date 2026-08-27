SET client_encoding = 'UTF8';

-- >>> V01 | Registros carregados no staging x volumetria esperada (Etapa 1, Tabela 1)
SELECT c.tabela_destino                                   AS tabela,
       c.registros_carregados                             AS carregados,
       e.esperado,
       CASE WHEN c.registros_carregados = e.esperado THEN 'OK' ELSE 'FALHA' END AS situacao
  FROM stg.controle_carga c
  JOIN (VALUES ('stg.olist_orders',                       99441),
               ('stg.olist_order_items',                  112650),
               ('stg.olist_order_payments',               103886),
               ('stg.olist_order_reviews',                99224),
               ('stg.olist_customers',                    99441),
               ('stg.olist_products',                     32951),
               ('stg.olist_sellers',                      3095),
               ('stg.olist_geolocation',                  1000163),
               ('stg.product_category_name_translation',  71)) AS e (tabela, esperado)
    ON e.tabela = c.tabela_destino
 ORDER BY c.id_carga;

-- >>> V02 | Registros por tabela do Data Warehouse
SELECT tabela, registros
  FROM (SELECT 1 AS ordem, 'dw.dim_tempo'     AS tabela, COUNT(*) AS registros FROM dw.dim_tempo     UNION ALL
        SELECT 2, 'dw.dim_cliente',   COUNT(*) FROM dw.dim_cliente   UNION ALL
        SELECT 3, 'dw.dim_produto',   COUNT(*) FROM dw.dim_produto   UNION ALL
        SELECT 4, 'dw.dim_vendedor',  COUNT(*) FROM dw.dim_vendedor  UNION ALL
        SELECT 5, 'dw.dim_geografia', COUNT(*) FROM dw.dim_geografia UNION ALL
        SELECT 6, 'dw.dim_pagamento', COUNT(*) FROM dw.dim_pagamento UNION ALL
        SELECT 7, 'dw.dim_status',    COUNT(*) FROM dw.dim_status    UNION ALL
        SELECT 8, 'dw.fato_pedido',   COUNT(*) FROM dw.fato_pedido   UNION ALL
        SELECT 9, 'dw.fato_vendas',   COUNT(*) FROM dw.fato_vendas) t
 ORDER BY ordem;

-- >>> V03 | Conferencia de totais, integridade referencial e regras de qualidade
WITH verificacoes AS (
    SELECT 1 AS ordem, 'Itens de pedido na origem = linhas da fato_vendas' AS verificacao,
           (SELECT COUNT(*) FROM stg.olist_order_items)::TEXT AS esperado,
           (SELECT COUNT(*) FROM dw.fato_vendas)::TEXT        AS obtido
    UNION ALL
    SELECT 2, 'Pedidos na origem = linhas da fato_pedido',
           (SELECT COUNT(*) FROM stg.olist_orders)::TEXT,
           (SELECT COUNT(*) FROM dw.fato_pedido)::TEXT
    UNION ALL
    SELECT 3, 'Soma de price (origem) = soma de valor_item (fato_vendas)',
           (SELECT SUM(price::NUMERIC) FROM stg.olist_order_items)::TEXT,
           (SELECT SUM(valor_item) FROM dw.fato_vendas)::TEXT
    UNION ALL
    SELECT 4, 'Soma de freight_value (origem) = soma de valor_frete (fato_vendas)',
           (SELECT SUM(freight_value::NUMERIC) FROM stg.olist_order_items)::TEXT,
           (SELECT SUM(valor_frete) FROM dw.fato_vendas)::TEXT
    UNION ALL
    SELECT 5, 'Soma de payment_value (origem) = soma de valor_pago (fato_pedido)',
           (SELECT SUM(payment_value::NUMERIC) FROM stg.olist_order_payments)::TEXT,
           (SELECT SUM(valor_pago) FROM dw.fato_pedido)::TEXT
    UNION ALL
    SELECT 6, 'Pedidos distintos na fato_vendas = pedidos com itens na origem',
           (SELECT COUNT(DISTINCT order_id) FROM stg.olist_order_items)::TEXT,
           (SELECT COUNT(DISTINCT order_id) FROM dw.fato_vendas)::TEXT
    UNION ALL
    SELECT 7, 'Pedidos cujo valor de itens difere entre fato_vendas e fato_pedido',
           '0',
           (SELECT COUNT(*)
              FROM dw.fato_pedido fp
              JOIN (SELECT order_id, SUM(valor_item) AS v FROM dw.fato_vendas GROUP BY order_id) fv
                ON fv.order_id = fp.order_id
             WHERE fv.v <> fp.valor_itens)::TEXT
    UNION ALL
    SELECT 8,  'fato_vendas sem dim_tempo',     '0', (SELECT COUNT(*) FROM dw.fato_vendas f LEFT JOIN dw.dim_tempo d     ON d.sk_tempo     = f.sk_tempo     WHERE d.sk_tempo     IS NULL)::TEXT UNION ALL
    SELECT 9,  'fato_vendas sem dim_cliente',   '0', (SELECT COUNT(*) FROM dw.fato_vendas f LEFT JOIN dw.dim_cliente d   ON d.sk_cliente   = f.sk_cliente   WHERE d.sk_cliente   IS NULL)::TEXT UNION ALL
    SELECT 10, 'fato_vendas sem dim_produto',   '0', (SELECT COUNT(*) FROM dw.fato_vendas f LEFT JOIN dw.dim_produto d   ON d.sk_produto   = f.sk_produto   WHERE d.sk_produto   IS NULL)::TEXT UNION ALL
    SELECT 11, 'fato_vendas sem dim_vendedor',  '0', (SELECT COUNT(*) FROM dw.fato_vendas f LEFT JOIN dw.dim_vendedor d  ON d.sk_vendedor  = f.sk_vendedor  WHERE d.sk_vendedor  IS NULL)::TEXT UNION ALL
    SELECT 12, 'fato_vendas sem dim_geografia', '0', (SELECT COUNT(*) FROM dw.fato_vendas f LEFT JOIN dw.dim_geografia d ON d.sk_geografia = f.sk_geografia WHERE d.sk_geografia IS NULL)::TEXT UNION ALL
    SELECT 13, 'fato_vendas sem dim_pagamento', '0', (SELECT COUNT(*) FROM dw.fato_vendas f LEFT JOIN dw.dim_pagamento d ON d.sk_pagamento = f.sk_pagamento WHERE d.sk_pagamento IS NULL)::TEXT UNION ALL
    SELECT 14, 'fato_vendas sem dim_status',    '0', (SELECT COUNT(*) FROM dw.fato_vendas f LEFT JOIN dw.dim_status d    ON d.sk_status    = f.sk_status    WHERE d.sk_status    IS NULL)::TEXT UNION ALL
    SELECT 15, 'fato_pedido sem dim_tempo (compra ou estimada)', '0',
           (SELECT COUNT(*) FROM dw.fato_pedido f
             LEFT JOIN dw.dim_tempo tc ON tc.sk_tempo = f.sk_tempo_compra
             LEFT JOIN dw.dim_tempo te ON te.sk_tempo = f.sk_tempo_estimada
            WHERE tc.sk_tempo IS NULL OR te.sk_tempo IS NULL)::TEXT
    UNION ALL
    SELECT 16, 'product_id duplicado em dim_produto',            '0', (SELECT COUNT(*) - COUNT(DISTINCT product_id)         FROM dw.dim_produto)::TEXT   UNION ALL
    SELECT 17, 'seller_id duplicado em dim_vendedor',            '0', (SELECT COUNT(*) - COUNT(DISTINCT seller_id)          FROM dw.dim_vendedor)::TEXT  UNION ALL
    SELECT 18, 'customer_unique_id duplicado em dim_cliente',    '0', (SELECT COUNT(*) - COUNT(DISTINCT customer_unique_id) FROM dw.dim_cliente)::TEXT   UNION ALL
    SELECT 19, 'cep_prefixo duplicado em dim_geografia',         '0', (SELECT COUNT(*) - COUNT(DISTINCT cep_prefixo)        FROM dw.dim_geografia)::TEXT UNION ALL
    SELECT 20, 'data duplicada em dim_tempo',                    '0', (SELECT COUNT(*) - COUNT(DISTINCT data)               FROM dw.dim_tempo)::TEXT     UNION ALL
    SELECT 21, 'Itens com valor_item nulo ou negativo',          '0', (SELECT COUNT(*) FROM dw.fato_vendas WHERE valor_item IS NULL OR valor_item < 0)::TEXT UNION ALL
    SELECT 22, 'Pedidos entregues com prazo de entrega negativo','0', (SELECT COUNT(*) FROM dw.fato_pedido WHERE prazo_entrega_dias < 0)::TEXT UNION ALL
    SELECT 23, 'Notas de avaliacao fora do intervalo 1 a 5',     '0', (SELECT COUNT(*) FROM dw.fato_pedido WHERE nota_avaliacao NOT BETWEEN 1 AND 5)::TEXT UNION ALL
    SELECT 24, 'Pedidos nao entregues com prazo preenchido',     '0',
           (SELECT COUNT(*) FROM dw.fato_pedido f JOIN dw.dim_status s ON s.sk_status = f.sk_status
             WHERE f.sk_tempo_entrega IS NULL AND f.prazo_entrega_dias IS NOT NULL)::TEXT UNION ALL
    SELECT 25, 'Produtos sem categoria tratados como "Nao informado"',
           (SELECT COUNT(*) FROM stg.olist_products WHERE NULLIF(TRIM(product_category_name), '') IS NULL)::TEXT,
           (SELECT COUNT(*) FROM dw.dim_produto WHERE categoria = 'Não informado')::TEXT UNION ALL
    SELECT 26, 'Prefixos de CEP de clientes/vendedores sem coordenadas (tratados na dim_geografia)',
           (SELECT COUNT(*) FROM dw.dim_geografia WHERE origem = 'clientes/vendedores')::TEXT,
           (SELECT COUNT(*) FROM dw.dim_geografia WHERE latitude_media IS NULL)::TEXT
)
SELECT ordem, verificacao, esperado, obtido,
       CASE WHEN esperado = obtido THEN 'OK' ELSE 'FALHA' END AS situacao
  FROM verificacoes
 ORDER BY ordem;

-- >>> V04 | Cobertura das medidas de pedido (quanto do universo cada KPI consegue enxergar)
SELECT cobertura, pedidos, percentual
  FROM (SELECT 1 AS ordem, 'Pedidos com itens' AS cobertura,
               COUNT(*) FILTER (WHERE qtd_itens > 0) AS pedidos,
               ROUND(100.0 * COUNT(*) FILTER (WHERE qtd_itens > 0) / COUNT(*), 2) AS percentual
          FROM dw.fato_pedido
        UNION ALL
        SELECT 2, 'Pedidos com pagamento registrado',
               COUNT(*) FILTER (WHERE sk_pagamento <> 0),
               ROUND(100.0 * COUNT(*) FILTER (WHERE sk_pagamento <> 0) / COUNT(*), 2)
          FROM dw.fato_pedido
        UNION ALL
        SELECT 3, 'Pedidos com avaliacao',
               COUNT(*) FILTER (WHERE nota_avaliacao IS NOT NULL),
               ROUND(100.0 * COUNT(*) FILTER (WHERE nota_avaliacao IS NOT NULL) / COUNT(*), 2)
          FROM dw.fato_pedido
        UNION ALL
        SELECT 4, 'Pedidos entregues (com prazo calculado)',
               COUNT(*) FILTER (WHERE prazo_entrega_dias IS NOT NULL),
               ROUND(100.0 * COUNT(*) FILTER (WHERE prazo_entrega_dias IS NOT NULL) / COUNT(*), 2)
          FROM dw.fato_pedido
        UNION ALL
        SELECT 5, 'Pedidos com coordenadas geograficas',
               COUNT(*) FILTER (WHERE g.latitude_media IS NOT NULL),
               ROUND(100.0 * COUNT(*) FILTER (WHERE g.latitude_media IS NOT NULL) / COUNT(*), 2)
          FROM dw.fato_pedido f
          JOIN dw.dim_geografia g ON g.sk_geografia = f.sk_geografia) t
 ORDER BY ordem;
