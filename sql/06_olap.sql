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

-- >>> O07 | Ranking | Dez vendedores com maior faturamento
WITH vendedores AS (
    SELECT v.seller_id,
           v.cidade,
           v.estado,
           SUM(f.valor_item)          AS faturamento,
           COUNT(DISTINCT f.order_id) AS pedidos,
           COUNT(*)                   AS itens
      FROM dw.fato_vendas   f
      JOIN dw.dim_vendedor  v ON v.sk_vendedor = f.sk_vendedor
      JOIN dw.dim_status    s ON s.sk_status   = f.sk_status
     WHERE s.flag_cancelado = FALSE
     GROUP BY v.seller_id, v.cidade, v.estado
)
SELECT RANK() OVER (ORDER BY faturamento DESC)                                  AS posicao,
       seller_id,
       cidade,
       estado,
       faturamento,
       pedidos,
       itens,
       ROUND(faturamento / pedidos, 2)                                         AS ticket_medio,
       ROUND(100.0 * faturamento / SUM(faturamento) OVER (), 2)                AS participacao_pct,
       ROUND(100.0 * SUM(faturamento) OVER (ORDER BY faturamento DESC)
             / SUM(faturamento) OVER (), 2)                                    AS participacao_acumulada_pct
  FROM vendedores
 ORDER BY faturamento DESC
 LIMIT 10;

-- >>> O08 | Drill-down | Prazo médio de entrega e taxa de atraso por região e estado
SELECT CASE WHEN GROUPING(g.regiao) = 1 THEN 'Total geral' ELSE g.regiao END AS regiao,
       CASE WHEN GROUPING(g.estado) = 1 THEN '(subtotal)' ELSE g.estado END  AS estado,
       COUNT(*)                                                                AS pedidos_entregues,
       ROUND(AVG(f.prazo_entrega_dias), 1)                                     AS prazo_medio_dias,
       ROUND(AVG(f.prazo_estimado_dias), 1)                                    AS prazo_estimado_medio_dias,
       ROUND(AVG(f.atraso_entrega_dias), 1)                                    AS desvio_medio_vs_estimado_dias,
       ROUND(100.0 * COUNT(*) FILTER (WHERE f.flag_entregue_com_atraso) / COUNT(*), 2) AS taxa_atraso_pct
  FROM dw.fato_pedido   f
  JOIN dw.dim_geografia g ON g.sk_geografia = f.sk_geografia
 WHERE f.prazo_entrega_dias IS NOT NULL
 GROUP BY ROLLUP (g.regiao, g.estado)
 ORDER BY GROUPING(g.regiao), g.regiao, GROUPING(g.estado), prazo_medio_dias DESC;

-- >>> O09 | Ranking | Vendedores com maior taxa de atraso (mínimo de 200 pedidos entregues)
WITH pedidos_vendedor AS (
    SELECT DISTINCT f.order_id, f.sk_vendedor, f.prazo_entrega_dias, f.atraso_entrega_dias
      FROM dw.fato_vendas f
     WHERE f.prazo_entrega_dias IS NOT NULL
)
SELECT v.seller_id,
       v.cidade,
       v.estado,
       COUNT(*)                                                               AS pedidos_entregues,
       ROUND(AVG(pv.prazo_entrega_dias), 1)                                   AS prazo_medio_dias,
       ROUND(100.0 * COUNT(*) FILTER (WHERE pv.atraso_entrega_dias > 0) / COUNT(*), 2) AS taxa_atraso_pct
  FROM pedidos_vendedor pv
  JOIN dw.dim_vendedor  v ON v.sk_vendedor = pv.sk_vendedor
 GROUP BY v.seller_id, v.cidade, v.estado
HAVING COUNT(*) >= 200
 ORDER BY taxa_atraso_pct DESC, pedidos_entregues DESC
 LIMIT 10;

-- >>> O10 | Slice | Participação do frete no valor do pedido por categoria (dez maiores)
SELECT p.categoria,
       COUNT(*)                                                                AS itens,
       SUM(f.valor_item)                                                       AS valor_itens,
       SUM(f.valor_frete)                                                      AS valor_frete,
       ROUND(100.0 * SUM(f.valor_frete) / SUM(f.valor_total_item), 2)         AS participacao_frete_pct,
       ROUND(AVG(f.valor_frete), 2)                                            AS frete_medio_por_item
  FROM dw.fato_vendas f
  JOIN dw.dim_produto p ON p.sk_produto = f.sk_produto
  JOIN dw.dim_status  s ON s.sk_status  = f.sk_status
 WHERE s.flag_cancelado = FALSE
 GROUP BY p.categoria
HAVING COUNT(*) >= 500
 ORDER BY participacao_frete_pct DESC
 LIMIT 10;

-- >>> O11 | Drill-across | Nota média de avaliação por situação da entrega
SELECT CASE WHEN f.prazo_entrega_dias IS NULL  THEN '6. Não entregue'
            WHEN f.atraso_entrega_dias < 0     THEN '1. Entregue antes da data estimada'
            WHEN f.atraso_entrega_dias = 0     THEN '2. Entregue na data estimada'
            WHEN f.atraso_entrega_dias <= 7    THEN '3. Atraso de 1 a 7 dias'
            WHEN f.atraso_entrega_dias <= 15   THEN '4. Atraso de 8 a 15 dias'
            ELSE                                    '5. Atraso acima de 15 dias' END AS situacao_entrega,
       COUNT(*)                                                                 AS pedidos,
       COUNT(f.nota_avaliacao)                                                  AS pedidos_avaliados,
       ROUND(AVG(f.nota_avaliacao), 2)                                          AS nota_media,
       ROUND(100.0 * COUNT(*) FILTER (WHERE f.nota_avaliacao <= 2) / NULLIF(COUNT(f.nota_avaliacao), 0), 2) AS pct_notas_1_e_2,
       ROUND(100.0 * COUNT(*) FILTER (WHERE f.nota_avaliacao = 5)  / NULLIF(COUNT(f.nota_avaliacao), 0), 2) AS pct_nota_5
  FROM dw.fato_pedido f
 GROUP BY 1
 ORDER BY 1;

-- >>> O12 | Ranking | Categorias com as melhores e as piores avaliações (mínimo de 300 avaliações)
WITH categorias AS (
    SELECT p.categoria,
           COUNT(f.nota_avaliacao)             AS avaliacoes,
           ROUND(AVG(f.nota_avaliacao), 2)     AS nota_media,
           ROUND(100.0 * COUNT(*) FILTER (WHERE f.nota_avaliacao <= 2) / COUNT(f.nota_avaliacao), 2) AS pct_notas_1_e_2
      FROM dw.fato_vendas f
      JOIN dw.dim_produto p ON p.sk_produto = f.sk_produto
     WHERE f.nota_avaliacao IS NOT NULL
     GROUP BY p.categoria
    HAVING COUNT(f.nota_avaliacao) >= 300
),
ranqueadas AS (
    SELECT c.*,
           RANK() OVER (ORDER BY nota_media DESC, avaliacoes DESC) AS posicao_melhor,
           RANK() OVER (ORDER BY nota_media ASC,  avaliacoes DESC) AS posicao_pior
      FROM categorias c
)
SELECT CASE WHEN posicao_melhor <= 5 THEN 'Melhores' ELSE 'Piores' END AS grupo,
       categoria,
       avaliacoes,
       nota_media,
       pct_notas_1_e_2
  FROM ranqueadas
 WHERE posicao_melhor <= 5 OR posicao_pior <= 5
 ORDER BY nota_media DESC, avaliacoes DESC;

-- >>> O13 | Roll-up | Clientes recorrentes por região
SELECT CASE WHEN GROUPING(regiao) = 1 THEN 'Total geral' ELSE regiao END    AS regiao,
       COUNT(*)                                                               AS clientes,
       COUNT(*) FILTER (WHERE flag_recorrente)                                AS clientes_recorrentes,
       ROUND(100.0 * COUNT(*) FILTER (WHERE flag_recorrente) / COUNT(*), 2)   AS pct_recorrentes,
       ROUND(AVG(qtd_pedidos), 3)                                             AS pedidos_por_cliente
  FROM dw.dim_cliente
 GROUP BY ROLLUP (regiao)
 ORDER BY GROUPING(regiao), pct_recorrentes DESC;

