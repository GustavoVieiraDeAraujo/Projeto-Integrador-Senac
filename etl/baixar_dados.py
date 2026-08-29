from __future__ import annotations

import argparse
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from utilitarios import PASTA_DADOS_PADRAO

URL_BASE = "https://raw.githubusercontent.com/olist/work-at-olist-data/master/datasets/"

ARQUIVOS = {
    "olist_orders_dataset.csv":              99441,
    "olist_order_items_dataset.csv":         112650,
    "olist_order_payments_dataset.csv":      103886,
    "olist_order_reviews_dataset.csv":       99224,
    "olist_customers_dataset.csv":           99441,
    "olist_products_dataset.csv":            32951,
    "olist_sellers_dataset.csv":             3095,
    "olist_geolocation_dataset.csv":         1000163,
    "product_category_name_translation.csv": 71,
}

def contar_registros(caminho: Path) -> int:
    import csv
    with caminho.open(encoding="utf-8", newline="") as f:
        return sum(1 for _ in csv.reader(f)) - 1

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Download da base Olist")
    parser.add_argument("--destino", type=Path, default=PASTA_DADOS_PADRAO)
    parser.add_argument("--forcar", action="store_true", help="baixa mesmo que o arquivo ja exista")
    args = parser.parse_args(argv)
    args.destino.mkdir(parents=True, exist_ok=True)

    for arquivo, esperado in ARQUIVOS.items():
        destino = args.destino / arquivo
        if destino.exists() and not args.forcar:
            print(f"{arquivo:40s} ja existe, pulando")
            continue
        print(f"{arquivo:40s} baixando...", end=" ", flush=True)
        urllib.request.urlretrieve(URL_BASE + arquivo, destino)
        registros = contar_registros(destino)
        situacao = "OK" if registros == esperado else f"ATENCAO (esperado {esperado})"
        print(f"{registros:>9,d} registros {situacao}".replace(",", "."))
    print(f"\nArquivos em {args.destino}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
