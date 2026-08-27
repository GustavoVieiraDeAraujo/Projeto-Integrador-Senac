from __future__ import annotations

import argparse
import io
import sys
import time
from pathlib import Path

import pandas as pd
import psycopg2

sys.path.insert(0, str(Path(__file__).resolve().parent))
from utilitarios import (
    PASTA_DADOS_PADRAO, Log, carregar_env, conectar, config_conexao,
    dividir_blocos, executar_consulta, ler_sql, tabela_texto,
)

ARQUIVOS = [
    ("olist_orders_dataset.csv",            "stg.olist_orders"),
    ("olist_order_items_dataset.csv",       "stg.olist_order_items"),
    ("olist_order_payments_dataset.csv",    "stg.olist_order_payments"),
    ("olist_order_reviews_dataset.csv",     "stg.olist_order_reviews"),
    ("olist_customers_dataset.csv",         "stg.olist_customers"),
    ("olist_products_dataset.csv",          "stg.olist_products"),
    ("olist_sellers_dataset.csv",           "stg.olist_sellers"),
    ("olist_geolocation_dataset.csv",       "stg.olist_geolocation"),
    ("product_category_name_translation.csv", "stg.product_category_name_translation"),
]

TAMANHO_LOTE = 200_000

def garantir_banco(log: Log) -> None:
    cfg = config_conexao()
    conn = conectar("postgres", autocommit=True)
    with conn.cursor() as cur:
        cur.execute("SELECT 1 FROM pg_database WHERE datname = %s", (cfg["dbname"],))
        if cur.fetchone() is None:
            log(f"Banco {cfg['dbname']} nao existe. Criando...")
            cur.execute(f'CREATE DATABASE "{cfg["dbname"]}" WITH ENCODING \'UTF8\' TEMPLATE template0')
    conn.close()

def executar_arquivo(conn, nome: str, log: Log):
    inicio = time.time()
    log(f"Executando sql/{nome} ...")
    with conn.cursor() as cur:
        cur.execute(ler_sql(nome))
        resultado = None
        if cur.description:
            resultado = ([d.name for d in cur.description], cur.fetchall())
    conn.commit()
    log(f"sql/{nome} concluido em {time.time() - inicio:.1f}s")
    return resultado

def colunas_da_tabela(conn, tabela: str) -> list[str]:
    schema, nome = tabela.split(".")
    _, linhas = executar_consulta(
        conn,
        f"SELECT column_name FROM information_schema.columns "
        f"WHERE table_schema = '{schema}' AND table_name = '{nome}' ORDER BY ordinal_position",
    )
    return [l[0] for l in linhas]

def extrair_e_carregar(conn, dados_dir: Path, log: Log) -> None:
    log("=" * 78)
    log("ETAPA 1/2. EXTRACAO DOS CSV (Pandas) E CARGA DO STAGING (COPY)")
    log("=" * 78)
    faltando = [a for a, _ in ARQUIVOS if not (dados_dir / a).exists()]
    if faltando:
        raise FileNotFoundError(
            f"Arquivos nao encontrados em {dados_dir}: {', '.join(faltando)}. "
            "Rode python etl/baixar_dados.py ou veja a secao 4 do README para obter a base Olist."
        )

    with conn.cursor() as cur:
        cur.execute("TRUNCATE TABLE stg.controle_carga RESTART IDENTITY")
    conn.commit()

    for arquivo, tabela in ARQUIVOS:
        caminho = dados_dir / arquivo
        inicio = time.time()
        colunas_tabela = colunas_da_tabela(conn, tabela)
        cabecalho = [c.strip() for c in pd.read_csv(caminho, nrows=0).columns]
        if set(cabecalho) != set(colunas_tabela):
            raise ValueError(
                f"{arquivo}: colunas do CSV {cabecalho} diferem das colunas de {tabela} {colunas_tabela}"
            )

        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO stg.controle_carga (arquivo, tabela_destino) VALUES (%s, %s) RETURNING id_carga",
                (arquivo, tabela),
            )
            id_carga = cur.fetchone()[0]
            cur.execute(f"TRUNCATE TABLE {tabela}")

            lidos = 0
            for lote in pd.read_csv(caminho, dtype=str, keep_default_na=False,
                                    chunksize=TAMANHO_LOTE, encoding="utf-8"):
                lidos += len(lote)
                buffer = io.StringIO()
                lote.to_csv(buffer, index=False, header=False, lineterminator="\n")
                buffer.seek(0)
                cur.copy_expert(
                    f"COPY {tabela} ({', '.join(cabecalho)}) FROM STDIN WITH (FORMAT csv, NULL '', ENCODING 'UTF8')",
                    buffer,
                )

            cur.execute(f"SELECT COUNT(*) FROM {tabela}")
            carregados = cur.fetchone()[0]
            situacao = "CONCLUIDA" if carregados == lidos else "DIVERGENTE"
            cur.execute(
                "UPDATE stg.controle_carga SET registros_lidos = %s, registros_carregados = %s, "
                "fim_carga = CURRENT_TIMESTAMP, situacao = %s WHERE id_carga = %s",
                (lidos, carregados, situacao, id_carga),
            )
        conn.commit()
        log(f"{arquivo:40s} lidos={lidos:>9,d}  carregados={carregados:>9,d}  "
            f"{situacao}  ({time.time() - inicio:.1f}s)".replace(",", "."))

    colunas, linhas = executar_consulta(
        conn, "SELECT arquivo, registros_lidos, registros_carregados, situacao FROM stg.controle_carga ORDER BY id_carga"
    )
    log.bloco(tabela_texto(colunas, linhas))

def transformar_e_carregar(conn, log: Log) -> None:
    log("=" * 78)
    log("ETAPA 3. TRANSFORMACAO (regras do Quadro 4) E CARGA DO MODELO DIMENSIONAL")
    log("=" * 78)
    executar_arquivo(conn, "02_ddl_dw.sql", log)
    resultado = executar_arquivo(conn, "04_dml_carga_dw.sql", log)
    if resultado:
        log.bloco(tabela_texto(*resultado))

def validar(conn, log: Log) -> int:
    log("=" * 78)
    log("ETAPA 4. VALIDACOES POS-CARGA")
    log("=" * 78)
    blocos = dividir_blocos(ler_sql("05_validacao.sql"))
    falhas = 0
    for bloco in blocos:
        colunas, linhas = executar_consulta(conn, bloco.sql)
        if "situacao" in colunas:
            idx = colunas.index("situacao")
            falhas += sum(1 for l in linhas if l[idx] == "FALHA")
        log(f"{bloco.codigo}. {bloco.titulo}")
        log.bloco(tabela_texto(colunas, linhas))

    resumo = ("Todas as verificações passaram." if falhas == 0
              else f"ATENÇÃO. {falhas} verificação(ões) com FALHA.")
    log(resumo)
    return falhas

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="ETL do Data Warehouse Olist (Etapa 2 do PI)")
    parser.add_argument("--dados", type=Path, default=PASTA_DADOS_PADRAO,
                        help="pasta com os CSV da base Olist (padrao: data/raw)")
    parser.add_argument("--etapas", nargs="+", default=["extracao", "transformacao", "validacao", "olap"],
                        choices=["extracao", "transformacao", "validacao", "olap"],
                        help="etapas a executar (padrao: todas, em ordem)")
    parser.add_argument("--sem-evidencias", action="store_true",
                        help="nao gerar as evidencias OLAP ao final")
    args = parser.parse_args(argv)

    carregar_env()
    log = Log()
    cfg = config_conexao()
    log(f"Conexao: {cfg['user']}@{cfg['host']}:{cfg['port']}/{cfg['dbname']}")
    try:
        pasta = args.dados.resolve().relative_to(Path.cwd())
    except ValueError:
        pasta = args.dados
    log(f"Pasta de dados: {pasta}")

    try:
        garantir_banco(log)
        conn = conectar()
    except psycopg2.OperationalError as erro:
        log(f"Nao foi possivel conectar ao PostgreSQL: {erro}")
        return 2

    falhas = 0
    try:
        if "extracao" in args.etapas:
            executar_arquivo(conn, "01_ddl_staging.sql", log)
            extrair_e_carregar(conn, args.dados, log)
        if "transformacao" in args.etapas:
            transformar_e_carregar(conn, log)
        if "validacao" in args.etapas:
            falhas = validar(conn, log)
        if "olap" in args.etapas and not args.sem_evidencias:
            log("=" * 78)
            log("ETAPA 5. OPERACOES OLAP E EVIDENCIAS")
            log("=" * 78)
            import gerar_evidencias
            gerar_evidencias.gerar(conn, log)
    except Exception as erro:
        conn.rollback()
        log(f"ERRO: {erro}")
        raise
    finally:
        conn.close()

    log(f"Pipeline finalizado em {log.decorrido()}. Falhas de validacao: {falhas}")
    return 1 if falhas else 0

if __name__ == "__main__":
    sys.exit(main())
