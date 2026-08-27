from __future__ import annotations

import sys
import time
from decimal import Decimal
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.colors import LinearSegmentedColormap
from matplotlib.ticker import FuncFormatter

sys.path.insert(0, str(Path(__file__).resolve().parent))
from utilitarios import (
    PASTA_OLAP, Log, carregar_env, conectar, dividir_blocos,
    executar_consulta, formatar_numero, ler_sql, tabela_texto,
)

SAIDA = PASTA_OLAP

SERIE = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300"]
SUPERFICIE = "#fcfcfb"
TINTA = "#0b0b0b"
TINTA_2 = "#52514e"
SUAVE = "#898781"
GRADE = "#e1e0d9"
EIXO = "#c3c2b7"
NEUTRO = "#f0efec"
RAMPA_AZUL = LinearSegmentedColormap.from_list("azul", ["#cde2fb", "#3987e5", "#0d366b"])

def _num(v, casas=0):
    return formatar_numero(float(v) if isinstance(v, Decimal) else v, casas)

def fmt_mil(v, _=None):
    return _num(v / 1000, 0)

def fmt_milhoes(v, _=None):
    return _num(v / 1_000_000, 1)

def fmt_pct(v, _=None):
    return _num(v, 1) + "%"

def fmt_int(v, _=None):
    return _num(v, 0)

def preparar(ax, grade="y"):
    ax.set_facecolor(SUPERFICIE)
    for lado in ("top", "right"):
        ax.spines[lado].set_visible(False)
    for lado in ("left", "bottom"):
        ax.spines[lado].set_color(EIXO)
        ax.spines[lado].set_linewidth(0.8)
    ax.tick_params(colors=TINTA_2, labelsize=8.5, length=0)
    if grade:
        ax.grid(axis=grade, color=GRADE, linewidth=0.6)
        ax.set_axisbelow(True)

def cabecalho(fig, titulo, subtitulo=None):
    altura = fig.get_figheight()
    fig.text(0.01, 1 - 0.12 / altura, titulo, ha="left", va="top", fontsize=12, fontweight="bold", color=TINTA)
    if subtitulo:
        fig.text(0.01, 1 - 0.40 / altura, subtitulo, ha="left", va="top", fontsize=8.5, color=TINTA_2)

def figura(titulo, subtitulo=None, largura=9.2, altura=4.6):
    fig, ax = plt.subplots(figsize=(largura, altura), dpi=150)
    fig.patch.set_facecolor(SUPERFICIE)
    cabecalho(fig, titulo, subtitulo)
    return fig, ax

def fechar(fig, caminho: Path, topo=None, base=None, esquerda=0.1):
    altura = fig.get_figheight()
    topo = topo if topo is not None else 1 - 0.75 / altura
    base = base if base is not None else 0.65 / altura
    fig.subplots_adjust(top=topo, bottom=base, left=esquerda, right=0.97)
    fig.savefig(caminho, facecolor=SUPERFICIE)
    plt.close(fig)

def barras_horizontais(df, rotulos, valores, titulo, subtitulo, formato, caminho, cor=SERIE[0], eixo_x=""):
    fig, ax = figura(titulo, subtitulo, altura=min(7.5, max(3.6, 0.3 * len(df) + 1.6)))
    preparar(ax, grade="x")
    y = np.arange(len(df))[::-1]
    ax.barh(y, valores, height=0.62, color=cor, edgecolor=SUPERFICIE, linewidth=1)
    ax.set_yticks(y, labels=rotulos)
    ax.xaxis.set_major_formatter(FuncFormatter(formato))
    ax.set_xlabel(eixo_x, color=TINTA_2, fontsize=8.5)
    maximo = max(valores)
    for yi, v in zip(y, valores):
        ax.text(v + maximo * 0.01, yi, formato(v), va="center", ha="left", fontsize=8, color=TINTA_2)
    ax.set_xlim(0, maximo * 1.15)
    ax.set_ylim(-0.7, len(df) - 0.3)
    maior_rotulo = max(len(r) for r in rotulos)
    fechar(fig, caminho, esquerda=0.3 if maior_rotulo > 22 else 0.22 if maior_rotulo > 12 else 0.1)

def grafico_o01(df, caminho):
    meses = df[(df["nivel"] == "Mês") & (df["pedidos"].astype(int) >= 100)].copy()
    meses["faturamento"] = meses["faturamento"].astype(float)
    fig, ax = figura("Faturamento mensal (R$ mil)",
                     "Roll-up da Dim_Tempo. Pedidos não cancelados, valor dos itens sem frete. "
                     "Meses com pelo menos 100 pedidos.")
    preparar(ax)
    x = np.arange(len(meses))
    ax.plot(x, meses["faturamento"], color=SERIE[0], linewidth=2, marker="o", markersize=4.5)
    ax.yaxis.set_major_formatter(FuncFormatter(fmt_mil))
    ax.set_xticks(x[::3], labels=meses["ano_mes"].iloc[::3], rotation=45, ha="right")
    ax.set_ylim(0, meses["faturamento"].max() * 1.15)
    i = int(meses["faturamento"].values.argmax())
    ax.annotate(f"{meses['ano_mes'].iloc[i]}\nR$ {fmt_mil(meses['faturamento'].iloc[i])} mil",
                (x[i], meses["faturamento"].iloc[i]), textcoords="offset points", xytext=(0, 8),
                ha="center", fontsize=8, color=TINTA_2)
    fechar(fig, caminho)

def grafico_o02(df, caminho):
    d = df[df["estado"] != "(subtotal)"].copy()
    d["faturamento"] = d["faturamento"].astype(float)
    d = d.sort_values("faturamento", ascending=False)
    barras_horizontais(d, d["estado"].tolist(), d["faturamento"].tolist(),
                       "Faturamento por estado do cliente (R$ mil)",
                       "Drill-down região > estado. Pedidos não cancelados.",
                       fmt_mil, caminho)

def grafico_o04(df, caminho):
    d = df.copy()
    d["faturamento"] = d["faturamento"].astype(float)
    barras_horizontais(d, d["categoria"].tolist(), d["faturamento"].tolist(),
                       "Dez categorias mais vendidas em 2018 (R$ mil)",
                       "Slice do cubo em ano = 2018.", fmt_mil, caminho)

def grafico_o06(df, caminho):
    d = df[df["tipo_pagamento"] != "Não informado"].copy()
    anos = ["fat_2016", "fat_2017", "fat_2018"]
    fig, ax = figura("Faturamento por ano e tipo de pagamento (R$ milhões)",
                     "Pivot tipo de pagamento x ano. Pedidos não cancelados.")
    preparar(ax)
    x = np.arange(len(anos))
    base = np.zeros(len(anos))
    for i, (_, linha) in enumerate(d.iterrows()):
        valores = np.array([float(linha[a]) for a in anos])
        ax.bar(x, valores, bottom=base, width=0.55, color=SERIE[i % len(SERIE)],
               edgecolor=SUPERFICIE, linewidth=1.5, label=linha["tipo_pagamento"])
        base += valores
    for xi, total in zip(x, base):
        ax.text(xi, total, "R$ " + fmt_milhoes(total) + " mi", ha="center", va="bottom", fontsize=8.5, color=TINTA_2)
    ax.set_xticks(x, labels=["2016", "2017", "2018"])
    ax.yaxis.set_major_formatter(FuncFormatter(fmt_milhoes))
    ax.set_ylim(0, base.max() * 1.15)
    ax.legend(frameon=False, fontsize=8.5, loc="upper left", labelcolor=TINTA_2)
    fechar(fig, caminho)

def grafico_o07(df, caminho):
    d = df.copy()
    d["faturamento"] = d["faturamento"].astype(float)
    rotulos = [f"{r.seller_id[:8]}  ({r.cidade}/{r.estado})" for r in d.itertuples()]
    barras_horizontais(d, rotulos, d["faturamento"].tolist(),
                       "Dez vendedores com maior faturamento (R$ mil)",
                       "Ranking com funções de janela. Identificador abreviado (8 primeiros caracteres).",
                       fmt_mil, caminho)

def grafico_o08(df, caminho):
    d = df[(df["estado"] == "(subtotal)") & (df["regiao"] != "Total geral")].copy()
    d["prazo_medio_dias"] = d["prazo_medio_dias"].astype(float)
    d["taxa_atraso_pct"] = d["taxa_atraso_pct"].astype(float)
    d = d.sort_values("prazo_medio_dias", ascending=False)
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(9.2, 4.2), dpi=150)
    fig.patch.set_facecolor(SUPERFICIE)
    fig.text(0.01, 0.985, "Logística por região do cliente", ha="left", va="top", fontsize=12, fontweight="bold", color=TINTA)
    fig.text(0.01, 0.925, "Drill-down região > estado (subtotais por região). Pedidos entregues.", ha="left", va="top", fontsize=8.5, color=TINTA_2)
    for ax, coluna, titulo, formato in (
        (ax1, "prazo_medio_dias", "Prazo médio de entrega (dias)", lambda v, _=None: _num(v, 1)),
        (ax2, "taxa_atraso_pct", "Taxa de atraso (% dos pedidos entregues)", fmt_pct),
    ):
        preparar(ax)
        x = np.arange(len(d))
        ax.bar(x, d[coluna], width=0.6, color=SERIE[0], edgecolor=SUPERFICIE, linewidth=1)
        ax.set_xticks(x, labels=d["regiao"], rotation=20, ha="right")
        ax.set_title(titulo, fontsize=9.5, color=TINTA, loc="left")
        ax.yaxis.set_major_formatter(FuncFormatter(formato))
        for xi, v in zip(x, d[coluna]):
            ax.text(xi, v, formato(v), ha="center", va="bottom", fontsize=8, color=TINTA_2)
        ax.set_ylim(0, d[coluna].max() * 1.18)
    fig.subplots_adjust(top=0.8, bottom=0.2, left=0.07, right=0.98, wspace=0.25)
    fig.savefig(caminho, facecolor=SUPERFICIE)
    plt.close(fig)

def grafico_o11(df, caminho):
    d = df.copy()
    d["nota_media"] = d["nota_media"].astype(float)
    rotulos = [s.split(". ", 1)[1].replace(" da data estimada", "\nda data estimada").replace("Atraso de ", "Atraso de\n").replace("Atraso acima", "Atraso acima\n") for s in d["situacao_entrega"]]
    fig, ax = figura("Nota média de avaliação por situação da entrega",
                     "Drill-across logística x satisfação na fato_pedido. Escala de 1 a 5.")
    preparar(ax)
    x = np.arange(len(d))
    ax.bar(x, d["nota_media"], width=0.6, color=SERIE[0], edgecolor=SUPERFICIE, linewidth=1)
    for xi, v in zip(x, d["nota_media"]):
        ax.text(xi, v + 0.05, _num(v, 2), ha="center", va="bottom", fontsize=8.5, color=TINTA)
    rotulos = [f"{r}\n({fmt_int(n)} pedidos)" for r, n in zip(rotulos, d["pedidos"])]
    ax.set_xticks(x, labels=rotulos, fontsize=7.5)
    ax.set_ylim(0, 5.4)
    ax.set_yticks([0, 1, 2, 3, 4, 5])
    fechar(fig, caminho)

def grafico_o12(df, caminho):
    d = df.copy()
    d["nota_media"] = d["nota_media"].astype(float)
    fig, ax = figura("Categorias com melhores e piores avaliações",
                     "Ranking por nota média (mínimo de 300 avaliações). Escala de 1 a 5.",
                     altura=0.42 * len(d) + 1.8)
    preparar(ax, grade="x")
    y = np.arange(len(d))[::-1]
    cores = {"Melhores": SERIE[0], "Piores": SERIE[1]}
    for grupo, cor in cores.items():
        sel = d["grupo"] == grupo
        ax.hlines(y[sel.values], 1, d.loc[sel, "nota_media"], color=GRADE, linewidth=1.2)
        ax.scatter(d.loc[sel, "nota_media"], y[sel.values], s=64, color=cor, edgecolor=SUPERFICIE, linewidth=1.2, label=grupo, zorder=3)
    for yi, v in zip(y, d["nota_media"]):
        ax.text(v + 0.05, yi, _num(v, 2), va="center", ha="left", fontsize=8, color=TINTA_2)
    ax.set_yticks(y, labels=d["categoria"])
    ax.set_xlim(1, 5)
    ax.set_xticks([1, 2, 3, 4, 5])
    ax.legend(frameon=False, fontsize=8.5, loc="lower right", labelcolor=TINTA_2)
    fechar(fig, caminho, esquerda=0.24)

def grafico_o13(df, caminho):
    d = df[df["regiao"] != "Total geral"].copy()
    total = float(df.loc[df["regiao"] == "Total geral", "pct_recorrentes"].iloc[0])
    d["pct_recorrentes"] = d["pct_recorrentes"].astype(float)
    fig, ax = figura("Clientes recorrentes por região (% de clientes com mais de um pedido)",
                     "Roll-up da Dim_Cliente. Cliente identificado por customer_unique_id.")
    preparar(ax)
    x = np.arange(len(d))
    ax.bar(x, d["pct_recorrentes"], width=0.6, color=SERIE[0], edgecolor=SUPERFICIE, linewidth=1)
    ax.axhline(total, color=SUAVE, linewidth=1, linestyle="--")
    ax.text(len(d) - 0.5, total + 0.05, f"Total geral {fmt_pct(total)}", ha="right", va="bottom", fontsize=8, color=TINTA_2)
    for xi, v in zip(x, d["pct_recorrentes"]):
        ax.text(xi, v + 0.12, fmt_pct(v), ha="center", va="bottom", fontsize=8.5, color=TINTA)
    ax.set_xticks(x, labels=d["regiao"])
    ax.yaxis.set_major_formatter(FuncFormatter(fmt_pct))
    ax.set_ylim(0, d["pct_recorrentes"].max() * 1.3)
    fechar(fig, caminho)

def grafico_o14(df, caminho):
    d = df[df["pedidos"].astype(int) >= 100].copy()
    d["taxa"] = d["taxa_cancelamento_pct"].astype(float)
    fig, ax = figura("Taxa de cancelamento por mês (% dos pedidos)",
                     "Slice no tempo. Meses com pelo menos 100 pedidos.")
    preparar(ax)
    x = np.arange(len(d))
    ax.plot(x, d["taxa"], color=SERIE[0], linewidth=2, marker="o", markersize=4.5)
    ax.set_xticks(x[::2], labels=d["ano_mes"].iloc[::2], rotation=45, ha="right")
    ax.yaxis.set_major_formatter(FuncFormatter(fmt_pct))
    ax.set_ylim(0, d["taxa"].max() * 1.25)
    i = int(d["taxa"].values.argmax())
    ax.annotate(f"{d['ano_mes'].iloc[i]}  {fmt_pct(d['taxa'].iloc[i])}", (x[i], d["taxa"].iloc[i]),
                textcoords="offset points", xytext=(10, 2), ha="left", fontsize=8, color=TINTA_2)
    fechar(fig, caminho)

def grafico_o16(df, caminho):
    d = df[df["regiao_vendedor"] != "Todas as regiões"].copy()
    colunas = ["para_norte", "para_nordeste", "para_centro_oeste", "para_sudeste", "para_sul"]
    nomes = ["Norte", "Nordeste", "Centro-Oeste", "Sudeste", "Sul"]
    matriz = d[colunas].astype(float).to_numpy()
    fig, ax = figura("Prazo médio de entrega (dias) por região do vendedor x região do cliente",
                     "Pivot origem x destino. Pedidos entregues, deduplicados por pedido.", altura=5.0)
    ax.set_facecolor(SUPERFICIE)
    mascara = np.ma.masked_invalid(matriz)
    im = ax.imshow(mascara, cmap=RAMPA_AZUL, aspect="auto")
    im.cmap.set_bad(NEUTRO)
    ax.set_xticks(range(len(nomes)), labels=nomes)
    ax.set_yticks(range(len(d)), labels=d["regiao_vendedor"])
    ax.set_xlabel("Região do cliente (destino)", color=TINTA_2, fontsize=8.5)
    ax.set_ylabel("Região do vendedor (origem)", color=TINTA_2, fontsize=8.5)
    ax.tick_params(colors=TINTA_2, labelsize=8.5, length=0)
    for lado in ax.spines.values():
        lado.set_visible(False)
    limite = np.nanmax(matriz)
    for i in range(matriz.shape[0]):
        for j in range(matriz.shape[1]):
            v = matriz[i, j]
            if np.isnan(v):
                ax.text(j, i, "n/d", ha="center", va="center", fontsize=8, color=SUAVE)
            else:
                ax.text(j, i, _num(v, 1), ha="center", va="center", fontsize=9,
                        color="white" if v > 0.6 * limite else TINTA)
    barra = fig.colorbar(im, ax=ax, fraction=0.035, pad=0.02)
    barra.ax.tick_params(colors=TINTA_2, labelsize=8, length=0)
    barra.outline.set_visible(False)
    fechar(fig, caminho, esquerda=0.17, base=0.16)

def grafico_o17(df, caminho):
    d = df.head(10).copy()
    barras_horizontais(d, [f"{r.estado} ({r.regiao})" for r in d.itertuples()], d["vendedores"].astype(int).tolist(),
                       "Vendedores cadastrados por estado (dez maiores)",
                       "Roll-up da Dim_Vendedor.", fmt_int, caminho)

GRAFICOS = {
    "O01": grafico_o01, "O02": grafico_o02, "O04": grafico_o04, "O06": grafico_o06,
    "O07": grafico_o07, "O08": grafico_o08, "O11": grafico_o11, "O12": grafico_o12,
    "O13": grafico_o13, "O14": grafico_o14, "O16": grafico_o16, "O17": grafico_o17,
}

def gerar(conn, log: Log | None = None, saida: Path = SAIDA) -> list[dict]:
    log = log or Log()
    saida_csv = saida / "csv"
    saida_graficos = saida / "graficos"
    saida_csv.mkdir(parents=True, exist_ok=True)
    saida_graficos.mkdir(parents=True, exist_ok=True)
    for antigo in saida_csv.glob("O*_*.csv"):
        antigo.unlink()
    for antigo in saida_graficos.glob("O*_*.png"):
        antigo.unlink()
    blocos = dividir_blocos(ler_sql("06_olap.sql"))
    indice = []
    for bloco in blocos:
        inicio = time.time()
        colunas, linhas = executar_consulta(conn, bloco.sql)
        df = pd.DataFrame(linhas, columns=colunas)
        base = f"{bloco.codigo}_{bloco.slug}"
        df.to_csv(saida_csv / f"{base}.csv", index=False, encoding="utf-8")

        grafico = None
        if bloco.codigo in GRAFICOS:
            grafico = f"{base}.png"
            GRAFICOS[bloco.codigo](df, saida_graficos / grafico)

        log.bloco("")
        log.bloco(f"{bloco.codigo}. {bloco.titulo} [{bloco.operacao}]")
        if bloco.descricao:
            log.bloco(" ".join(bloco.descricao))
        log.bloco("Consulta:")
        log.bloco(bloco.sql + ";")
        log.bloco("Resultado:")
        log.bloco(tabela_texto(colunas, linhas))

        indice.append({"codigo": bloco.codigo, "operacao": bloco.operacao, "titulo": bloco.titulo,
                       "linhas": len(df), "csv": f"csv/{base}.csv", "png": f"graficos/{grafico}" if grafico else None})
        log(f"{bloco.codigo} {bloco.operacao:12s} {len(df):>3d} linhas  {'grafico' if grafico else '       '}  "
            f"{bloco.titulo} ({time.time() - inicio:.1f}s)")

    log(f"{len(indice)} operacoes OLAP exportadas para {saida.name}/csv e {saida.name}/graficos")
    return indice

if __name__ == "__main__":
    carregar_env()
    conexao = conectar()
    try:
        gerar(conexao)
    finally:
        conexao.close()
