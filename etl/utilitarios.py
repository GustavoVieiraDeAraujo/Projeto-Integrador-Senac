from __future__ import annotations

import os
import re
import time
from dataclasses import dataclass, field
from datetime import datetime
from decimal import Decimal
from pathlib import Path

import psycopg2

RAIZ = Path(__file__).resolve().parent.parent
PASTA_SQL = RAIZ / "sql"
PASTA_OLAP = RAIZ / "olap"
PASTA_DADOS_PADRAO = RAIZ / "data" / "raw"

def carregar_env(caminho: Path | None = None) -> None:
    caminho = caminho or (RAIZ / ".env")
    if not caminho.exists():
        return
    for linha in caminho.read_text(encoding="utf-8").splitlines():
        linha = linha.strip()
        if not linha or linha.startswith("#") or "=" not in linha:
            continue
        chave, valor = linha.split("=", 1)
        os.environ.setdefault(chave.strip(), valor.strip().strip('"').strip("'"))

def config_conexao(dbname: str | None = None) -> dict:
    return {
        "host": os.getenv("PGHOST", "localhost"),
        "port": int(os.getenv("PGPORT", "5432")),
        "dbname": dbname or os.getenv("PGDATABASE", "dw_olist"),
        "user": os.getenv("PGUSER", "postgres"),
        "password": os.getenv("PGPASSWORD", "postgres"),
    }

def conectar(dbname: str | None = None, autocommit: bool = False):
    conn = psycopg2.connect(**config_conexao(dbname))
    conn.set_client_encoding("UTF8")
    conn.autocommit = autocommit
    return conn

def ler_sql(nome_arquivo: str) -> str:
    return (PASTA_SQL / nome_arquivo).read_text(encoding="utf-8")

@dataclass
class Bloco:
    codigo: str
    operacao: str
    titulo: str
    descricao: list[str] = field(default_factory=list)
    sql: str = ""

    @property
    def slug(self) -> str:
        texto = self.titulo.lower()
        texto = re.sub(r"[áàâãä]", "a", texto)
        texto = re.sub(r"[éèêë]", "e", texto)
        texto = re.sub(r"[íìîï]", "i", texto)
        texto = re.sub(r"[óòôõö]", "o", texto)
        texto = re.sub(r"[úùûü]", "u", texto)
        texto = texto.replace("ç", "c")
        texto = re.sub(r"[^a-z0-9]+", "_", texto).strip("_")
        if len(texto) > 60:
            texto = texto[:60].rsplit("_", 1)[0]
        return texto

def dividir_blocos(texto_sql: str) -> list[Bloco]:
    blocos: list[Bloco] = []
    atual: Bloco | None = None
    linhas_sql: list[str] = []
    lendo_descricao = False

    def fechar():
        if atual is not None:
            atual.sql = "\n".join(linhas_sql).strip().rstrip(";").strip()
            blocos.append(atual)

    for linha in texto_sql.splitlines():
        if linha.startswith("-- >>> "):
            fechar()
            partes = [p.strip() for p in linha[7:].split("|")]
            if len(partes) == 2:
                codigo, operacao, titulo = partes[0], "", partes[1]
            else:
                codigo, operacao, titulo = partes[0], partes[1], " | ".join(partes[2:])
            atual = Bloco(codigo=codigo, operacao=operacao, titulo=titulo)
            linhas_sql = []
            lendo_descricao = True
            continue
        if atual is None:
            continue
        if lendo_descricao and linha.startswith("--"):
            atual.descricao.append(linha[2:].strip())
            continue
        lendo_descricao = False
        linhas_sql.append(linha)
    fechar()
    return blocos

def executar_consulta(conn, sql: str):
    with conn.cursor() as cur:
        cur.execute(sql)
        colunas = [d.name for d in cur.description] if cur.description else []
        linhas = cur.fetchall() if cur.description else []
    return colunas, linhas

def formatar_numero(valor, casas: int | None = None) -> str:
    if valor is None:
        return ""
    if isinstance(valor, bool):
        return "Sim" if valor else "Não"
    if isinstance(valor, Decimal):
        expoente = valor.as_tuple().exponent
        if casas is None:
            casas = 0 if expoente >= 0 else min(-expoente, 4)
        valor = float(valor)
    elif isinstance(valor, float):
        if casas is None:
            casas = 0 if valor.is_integer() else 2
    elif isinstance(valor, int):
        casas = 0 if casas is None else casas
    else:
        return str(valor)
    texto = f"{valor:,.{casas}f}"
    return texto.replace(",", "X").replace(".", ",").replace("X", ".")

def _eh_numerico(valor) -> bool:
    return isinstance(valor, (int, float, Decimal)) and not isinstance(valor, bool)

def tabela_texto(colunas: list[str], linhas: list[tuple], max_linhas: int = 60) -> str:
    if not linhas:
        return "(sem resultados)"
    dados = [[("" if v is None else formatar_numero(v) if _eh_numerico(v) else str(v)) for v in l] for l in linhas[:max_linhas]]
    larguras = [max(len(str(c)), *(len(d[i]) for d in dados)) for i, c in enumerate(colunas)]
    fmt = "  ".join("{:<" + str(w) + "}" for w in larguras)
    saida = [fmt.format(*colunas), fmt.format(*["-" * w for w in larguras])]
    saida += [fmt.format(*d) for d in dados]
    if len(linhas) > max_linhas:
        saida.append(f"... ({len(linhas) - max_linhas} linhas omitidas)")
    return "\n".join(saida)

class Log:
    def __init__(self, caminho: Path | None = None):
        self.caminho = caminho
        self.inicio = time.time()
        if caminho is not None:
            caminho.parent.mkdir(parents=True, exist_ok=True)
            caminho.write_text("", encoding="utf-8")

    def __call__(self, mensagem: str = "") -> None:
        carimbo = datetime.now().strftime("%H:%M:%S")
        linha = f"[{carimbo}] {mensagem}" if mensagem else ""
        print(linha, flush=True)
        if self.caminho is not None:
            with self.caminho.open("a", encoding="utf-8") as f:
                f.write(linha + "\n")

    def bloco(self, texto: str) -> None:
        print(texto, flush=True)
        if self.caminho is not None:
            with self.caminho.open("a", encoding="utf-8") as f:
                f.write(texto + "\n")

    def decorrido(self) -> str:
        return f"{time.time() - self.inicio:.1f}s"
