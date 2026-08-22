SET client_encoding = 'UTF8';

-- >>> O01 | Roll-up | Faturamento, pedidos e ticket médio por ano, trimestre e mês
SELECT CASE WHEN GROUPING(t.ano) = 1       THEN 'Total geral'
            WHEN GROUPING(t.trimestre) = 1 THEN 'Total ' || t.ano::TEXT
            WHEN GROUPING(t.mes) = 1       THEN 'Total ' || t.trimestre::TEXT || 'T' || t.ano::TEXT
            ELSE t.ano::TEXT END                                             AS ano,
       CASE WHEN GROUPING(t.trimestre) = 1 THEN NULL ELSE t.trimestre::TEXT || 'T' END AS trimestre,
       CASE WHEN GROUPING(t.mes) = 1 THEN NULL ELSE t.nome_mes END           AS mes,
       CASE WHEN GROUPING(t.ano) = 1 THEN 'Geral'
            WHEN GROUPING(t.trimestre) = 1 THEN 'Ano'
            WHEN GROUPING(t.mes) = 1 THEN 'Trimestre'
            ELSE 'Mês' END                                                    AS nivel,
       CASE WHEN GROUPING(t.mes) = 0 THEN MIN(t.ano_mes) END                  AS ano_mes,
       SUM(f.valor_item)                                                      AS faturamento,
       COUNT(DISTINCT f.order_id)                                             AS pedidos,
       ROUND(SUM(f.valor_item) / COUNT(DISTINCT f.order_id), 2)              AS ticket_medio
  FROM dw.fato_vendas f
  JOIN dw.dim_tempo   t ON t.sk_tempo  = f.sk_tempo
  JOIN dw.dim_status  s ON s.sk_status = f.sk_status
 WHERE s.flag_cancelado = FALSE
 GROUP BY ROLLUP (t.ano, t.trimestre, (t.mes, t.nome_mes))
 ORDER BY t.ano NULLS LAST, t.trimestre NULLS LAST, t.mes NULLS LAST;

-- >>> O02 | Drill-down | Faturamento por região e estado do cliente
SELECT CASE WHEN GROUPING(g.regiao) = 1 THEN 'Total geral' ELSE g.regiao END AS regiao,
       CASE WHEN GROUPING(g.estado) = 1 THEN '(subtotal)' ELSE g.estado END  AS estado,
       SUM(f.valor_item)                                                       AS faturamento,
       COUNT(DISTINCT f.order_id)                                              AS pedidos,
       ROUND(SUM(f.valor_item) / COUNT(DISTINCT f.order_id), 2)               AS ticket_medio,
       ROUND(100.0 * SUM(f.valor_item)
             / (SELECT SUM(v.valor_item) FROM dw.fato_vendas v
                  JOIN dw.dim_status x ON x.sk_status = v.sk_status
                 WHERE x.flag_cancelado = FALSE), 2)                          AS participacao_pct
  FROM dw.fato_vendas    f
  JOIN dw.dim_geografia  g ON g.sk_geografia = f.sk_geografia
  JOIN dw.dim_status     s ON s.sk_status    = f.sk_status
 WHERE s.flag_cancelado = FALSE
 GROUP BY ROLLUP (g.regiao, g.estado)
 ORDER BY GROUPING(g.regiao), g.regiao, GROUPING(g.estado), faturamento DESC;

-- >>> O03 | Drill-down | Faturamento das dez maiores cidades do estado de São Paulo
SELECT g.cidade,
       SUM(f.valor_item)                                                          AS faturamento,
       COUNT(DISTINCT f.order_id)                                                 AS pedidos,
       ROUND(SUM(f.valor_item) / COUNT(DISTINCT f.order_id), 2)                  AS ticket_medio,
       ROUND(100.0 * SUM(f.valor_item) / SUM(SUM(f.valor_item)) OVER (), 2)      AS participacao_no_estado_pct
  FROM dw.fato_vendas   f
  JOIN dw.dim_geografia g ON g.sk_geografia = f.sk_geografia
  JOIN dw.dim_status    s ON s.sk_status    = f.sk_status
 WHERE s.flag_cancelado = FALSE
   AND g.estado = 'SP'
 GROUP BY g.cidade
 ORDER BY faturamento DESC
 LIMIT 10;

-- >>> O04 | Slice | Dez categorias mais vendidas em 2018 (valor e quantidade)
SELECT p.categoria,
       p.categoria_en,
       SUM(f.valor_item)                                                      AS faturamento,
       COUNT(*)                                                               AS itens_vendidos,
       COUNT(DISTINCT f.order_id)                                             AS pedidos,
       ROUND(SUM(f.valor_item) / COUNT(DISTINCT f.order_id), 2)              AS ticket_medio,
       ROUND(100.0 * SUM(f.valor_item) / SUM(SUM(f.valor_item)) OVER (), 2)  AS participacao_pct
  FROM dw.fato_vendas  f
  JOIN dw.dim_tempo    t ON t.sk_tempo   = f.sk_tempo
  JOIN dw.dim_produto  p ON p.sk_produto = f.sk_produto
  JOIN dw.dim_status   s ON s.sk_status  = f.sk_status
 WHERE s.flag_cancelado = FALSE
   AND t.ano = 2018
 GROUP BY p.categoria, p.categoria_en
 ORDER BY faturamento DESC
 LIMIT 10;

-- >>> O05 | Dice | Ticket médio por região, tipo de pagamento e ano (Sul e Sudeste, 2017 e 2018)
SELECT t.ano,
       g.regiao,
       p.tipo_pagamento,
       SUM(f.valor_item)                                                      AS faturamento,
       COUNT(DISTINCT f.order_id)                                             AS pedidos,
       ROUND(SUM(f.valor_item) / COUNT(DISTINCT f.order_id), 2)              AS ticket_medio
  FROM dw.fato_vendas    f
  JOIN dw.dim_tempo      t ON t.sk_tempo     = f.sk_tempo
  JOIN dw.dim_geografia  g ON g.sk_geografia = f.sk_geografia
  JOIN dw.dim_pagamento  p ON p.sk_pagamento = f.sk_pagamento
  JOIN dw.dim_status     s ON s.sk_status    = f.sk_status
 WHERE s.flag_cancelado = FALSE
   AND t.ano IN (2017, 2018)
   AND g.regiao IN ('Sul', 'Sudeste')
   AND p.tipo_pagamento IN ('Boleto', 'Cartão de crédito')
 GROUP BY t.ano, g.regiao, p.tipo_pagamento
 ORDER BY t.ano, g.regiao, p.tipo_pagamento;

-- >>> O06 | Pivot | Faturamento por tipo de pagamento (linhas) x ano (colunas)
SELECT p.tipo_pagamento,
       COALESCE(SUM(f.valor_item) FILTER (WHERE t.ano = 2016), 0)            AS fat_2016,
       COALESCE(SUM(f.valor_item) FILTER (WHERE t.ano = 2017), 0)            AS fat_2017,
       COALESCE(SUM(f.valor_item) FILTER (WHERE t.ano = 2018), 0)            AS fat_2018,
       SUM(f.valor_item)                                                      AS fat_total,
       ROUND(100.0 * SUM(f.valor_item) / SUM(SUM(f.valor_item)) OVER (), 2)  AS participacao_pct
  FROM dw.fato_vendas    f
  JOIN dw.dim_tempo      t ON t.sk_tempo     = f.sk_tempo
  JOIN dw.dim_pagamento  p ON p.sk_pagamento = f.sk_pagamento
  JOIN dw.dim_status     s ON s.sk_status    = f.sk_status
 WHERE s.flag_cancelado = FALSE
 GROUP BY p.tipo_pagamento
 ORDER BY fat_total DESC;

