# Data Warehouse Olist. Análise de desempenho comercial e logístico em e-commerce

Projeto Integrador do quinto semestre do Curso Superior de Tecnologia em Banco de Dados (Senac São Paulo, 2026). **Segunda etapa, implantação da solução** planejada na primeira etapa.

## Integrantes

| Integrante | GitHub | Frente principal (Quadro 7 da etapa 1) |
|---|---|---|
| Gustavo Vieira de Araújo | [@GustavoVieiraDeAraujo](https://github.com/GustavoVieiraDeAraujo) | Modelagem dimensional |

## Modelo dimensional (schema `dw`)

A etapa 1 deixou uma decisão em aberto (seção 5.5). Prazo de entrega, atraso e nota de avaliação existem no grão de pedido e não de item. A decisão desta etapa foi adotar um **esquema em constelação** com duas tabelas de fato compartilhando as mesmas dimensões.

* `fato_vendas`, grão **item de pedido** (112.650 linhas). Guarda as medidas aditivas de valor (item, frete e total) e as medidas do pedido replicadas de forma controlada (prazo, atraso e nota), que devem ser lidas com `AVG` e nunca com `SUM`. É a estrela principal, usada em toda análise que envolve produto, categoria ou vendedor.
* `fato_pedido`, grão **pedido** (99.441 linhas). Guarda a composição do pedido (itens, produtos distintos, vendedores), os valores, o pagamento, as medidas logísticas e a nota no grão natural. É a fonte dos KPIs de pedido (prazo médio, taxa de atraso, taxa de cancelamento, nota média), sem risco de dupla contagem.

As medidas replicadas em `fato_vendas` são copiadas de `fato_pedido` durante a carga, o que garante consistência entre as duas fatos.

```mermaid
erDiagram
    dim_tempo {
        int sk_tempo PK "AAAAMMDD"
        date data
        int dia
        int mes
        string nome_mes
        int trimestre
        string nome_trimestre
        int semestre
        int ano
        string ano_mes
        string nome_dia_semana
        bool fim_de_semana
    }
    dim_cliente {
        int sk_cliente PK
        string customer_unique_id "chave natural"
        string cep_prefixo
        string cidade
        string estado
        string regiao
        int qtd_pedidos
        bool flag_recorrente
    }
    dim_produto {
        int sk_produto PK
        string product_id "chave natural"
        string categoria "padronizada (pt)"
        string categoria_en "traduzida"
        int peso_g
        int volume_cm3
        string faixa_peso
    }
    dim_vendedor {
        int sk_vendedor PK
        string seller_id "chave natural"
        string cep_prefixo
        string cidade
        string estado
        string regiao
    }
    dim_geografia {
        int sk_geografia PK
        string cep_prefixo "chave natural"
        string cidade
        string estado
        string regiao
        decimal latitude_media
        decimal longitude_media
    }
    dim_pagamento {
        int sk_pagamento PK
        string tipo_pagamento
        int num_parcelas
        string faixa_parcelas
    }
    dim_status {
        int sk_status PK
        string status_original
        string status_descricao
        bool flag_entregue
        bool flag_cancelado
    }
    fato_vendas {
        string order_id PK "chave degenerada"
        int order_item_id PK
        int sk_tempo FK
        int sk_cliente FK
        int sk_produto FK
        int sk_vendedor FK
        int sk_geografia FK
        int sk_pagamento FK
        int sk_status FK
        decimal valor_item
        decimal valor_frete
        decimal valor_total_item
        int prazo_entrega_dias "replicada, usar AVG"
        int atraso_entrega_dias "replicada, usar AVG"
        int nota_avaliacao "replicada, usar AVG"
    }
    fato_pedido {
        string order_id PK "chave degenerada"
        int sk_tempo_compra FK
        int sk_tempo_entrega FK
        int sk_tempo_estimada FK
        int sk_cliente FK
        int sk_geografia FK
        int sk_pagamento FK
        int sk_status FK
        int qtd_itens
        int qtd_vendedores
        decimal valor_itens
        decimal valor_frete
        decimal valor_total
        decimal valor_pago
        decimal participacao_frete
        int prazo_entrega_dias
        int prazo_estimado_dias
        int atraso_entrega_dias
        bool flag_entregue_com_atraso
        int nota_avaliacao
    }
    dim_tempo ||--o{ fato_vendas : "sk_tempo"
    dim_cliente ||--o{ fato_vendas : "sk_cliente"
    dim_produto ||--o{ fato_vendas : "sk_produto"
    dim_vendedor ||--o{ fato_vendas : "sk_vendedor"
    dim_geografia ||--o{ fato_vendas : "sk_geografia"
    dim_pagamento ||--o{ fato_vendas : "sk_pagamento"
    dim_status ||--o{ fato_vendas : "sk_status"
    dim_tempo ||--o{ fato_pedido : "compra, entrega, estimada"
    dim_cliente ||--o{ fato_pedido : "sk_cliente"
    dim_geografia ||--o{ fato_pedido : "sk_geografia"
    dim_pagamento ||--o{ fato_pedido : "sk_pagamento"
    dim_status ||--o{ fato_pedido : "sk_status"
```

(O mesmo diagrama em imagem está em [`docs/modelo_dimensional.png`](docs/modelo_dimensional.png). A `dim_vendedor` também se liga à `fato_pedido` de forma indireta, pela `fato_vendas`, já que um pedido pode ter mais de um vendedor.)
