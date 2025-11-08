"""Generate normalized CSVs for the TsqlProject schema using the raw inputs in csvs_usados.

The script builds a coherent 30-day wallet simulation relying on the available market
files (cotahist, carteira modelo, empresas, índices macro etc.).
It creates one CSV per table defined in sql/schema_tables.sql under generated_dataset/.
"""

from __future__ import annotations

import math
from pathlib import Path
from typing import Dict, Iterable, List, Tuple

import numpy as np
import pandas as pd

BASE_DIR = Path(__file__).resolve().parents[1]
CSV_DIR = BASE_DIR / "csvs_usados"
OUTPUT_DIR = BASE_DIR / "generated_dataset"

WINDOW_DAYS = 30
BASE_CAPITAL = 100_000.0
BENCHMARK_NAME = "IBOV"
RNG_SEED = 42

# Patch tickers that appear truncated or with alternate codes in the source CSVs.
TICKER_FIXES = {
    "VGIR1": "VGIR11",
    "VGIR1 ": "VGIR11",
}


def ensure_output_dir(path: Path) -> None:
    path.mkdir(exist_ok=True, parents=True)


def safe_float(value) -> float:
    if value is None:
        return math.nan
    if isinstance(value, str):
        value = value.replace("%", "").replace(",", ".")
        value = value.strip()
        if not value:
            return math.nan
    try:
        val = float(value)
    except (TypeError, ValueError):
        return math.nan
    if math.isnan(val):
        return math.nan
    return val


def load_carteira_modelo() -> pd.DataFrame:
    df = pd.read_csv(CSV_DIR / "carteira_investimentos_modelo_ativos_clean.csv")
    df["codigo_ativo"] = df["codigo_ativo"].str.upper().str.strip()
    df["codigo_ativo"] = df["codigo_ativo"].replace(TICKER_FIXES)
    df = df.dropna(subset=["codigo_ativo"])
    numeric_cols = [
        "preco_atual",
        "pl",
        "p_vp",
        "roe",
        "divida_ebitda",
        "dividend_yield",
        "proventos_mensal",
        "dividend_yield_historico",
    ]
    for col in numeric_cols:
        if col in df.columns:
            df[col] = df[col].apply(safe_float)
    return df


def load_renda_fixa() -> pd.DataFrame:
    path = CSV_DIR / "renda_fixa_taxas_clean.csv"
    if not path.exists():
        return pd.DataFrame()
    df = pd.read_csv(path, sep=";")
    df = df.dropna(subset=["nome"])
    df["codigo_ativo"] = [f"RF{idx:03d}" for idx in range(1, len(df) + 1)]
    df["Ticker"] = df["codigo_ativo"]
    df["Nome_do_Fundo"] = df["nome"].str.strip()
    df["Setor"] = df["setor"].fillna("Renda Fixa").str.strip()
    df["preco_atual"] = df["preco_atual"].apply(safe_float)
    df["nome"] = df["Nome_do_Fundo"]
    df["dividend_yield"] = 0.0
    df["proventos_mensal"] = 0.0
    df["dividend_yield_historico"] = 0.0
    df["pl"] = math.nan
    df["roe"] = math.nan
    df["divida_ebitda"] = math.nan
    df["CNPJ"] = ""
    return df[[
        "codigo_ativo",
        "Ticker",
        "nome",
    "Nome_do_Fundo",
        "Setor",
        "preco_atual",
        "pl",
        "roe",
        "divida_ebitda",
        "dividend_yield",
        "proventos_mensal",
        "dividend_yield_historico",
        "CNPJ",
    ]]


def load_empresas() -> pd.DataFrame:
    df = pd.read_csv(CSV_DIR / "empresas.csv")
    df["Ticker"] = df["Ticker"].str.upper().str.strip()
    df["Ticker"] = df["Ticker"].replace(TICKER_FIXES)
    df = df.dropna(subset=["Ticker"])
    return df


def load_price_history() -> pd.DataFrame:
    price_df = pd.read_csv(
        CSV_DIR / "cotahist(2)4m.csv",
        dtype={"Data": str, "Código": str},
    )
    price_df = price_df.rename(
        columns={
            "Data": "date",
            "Código": "ticker",
            "Preço Abertura": "open",
            "Preço Máximo": "high",
            "Preço Mínimo": "low",
            "Preço Médio": "avg",
            "Preço Fechamento": "close",
            "Volume": "volume",
        }
    )
    price_df["date"] = pd.to_datetime(price_df["date"], format="%Y%m%d")
    numeric_cols = ["open", "high", "low", "avg", "close", "volume"]
    price_df[numeric_cols] = price_df[numeric_cols].apply(pd.to_numeric, errors="coerce")
    price_df = price_df.dropna(subset=["close"])
    return price_df


def select_target_assets(
    ref_df: pd.DataFrame, empresas_df: pd.DataFrame, prices_df: pd.DataFrame
) -> pd.DataFrame:
    universe = set(prices_df["ticker"].unique())
    ref_df = ref_df[ref_df["codigo_ativo"].isin(universe)]
    ref_df = ref_df.reset_index(drop=True)
    empresas_subset = empresas_df[empresas_df["Ticker"].isin(ref_df["codigo_ativo"])].copy()
    empresas_subset = empresas_subset.drop_duplicates(subset=["Ticker"])
    merged = ref_df.merge(
        empresas_subset,
        left_on="codigo_ativo",
        right_on="Ticker",
        how="inner",
        suffixes=("_ref", "_emp"),
    )
    # Keep a manageable core list (10 assets max) for the simulated carteira.
    merged = merged.sort_values("codigo_ativo").head(10).reset_index(drop=True)
    return merged


def determine_window(prices_df: pd.DataFrame, tickers: Iterable[str]) -> Tuple[pd.Timestamp, pd.Timestamp]:
    tickers = list(set(tickers))
    per_ticker_last = prices_df[prices_df["ticker"].isin(tickers)].groupby("ticker")["date"].max()
    if per_ticker_last.empty:
        raise RuntimeError("No price data available for the selected tickers.")
    # Use the minimum last date to guarantee coverage for every asset.
    end_date = per_ticker_last.min()
    start_date = end_date - pd.Timedelta(days=WINDOW_DAYS - 1)
    return start_date, end_date


def filter_price_window(prices_df: pd.DataFrame, tickers: Iterable[str], start_date: pd.Timestamp, end_date: pd.Timestamp) -> pd.DataFrame:
    mask = (
        prices_df["ticker"].isin(set(tickers))
        & (prices_df["date"] >= start_date)
        & (prices_df["date"] <= end_date)
    )
    window_df = prices_df.loc[mask].copy()
    window_df.sort_values(["ticker", "date"], inplace=True)
    # Drop tickers that still miss the end_date observation.
    valid = []
    for ticker, group in window_df.groupby("ticker"):
        if end_date in set(group["date"]):
            valid.append(ticker)
    window_df = window_df[window_df["ticker"].isin(valid)]
    return window_df


def generate_renda_fixa_prices(
    renda_df: pd.DataFrame,
    start_date: pd.Timestamp,
    end_date: pd.Timestamp,
) -> pd.DataFrame:
    if renda_df.empty:
        return pd.DataFrame(columns=["date", "ticker", "open", "high", "low", "avg", "close", "volume"])
    dates = pd.date_range(start=start_date, end=end_date, freq="D")
    rng = np.random.default_rng(RNG_SEED)
    records: List[Dict[str, object]] = []
    for row in renda_df.itertuples(index=False):
        base_price = row.preco_atual if not math.isnan(row.preco_atual) else 1_000.0
        shocks = rng.normal(loc=0.0001, scale=0.0005, size=len(dates))
        prices = base_price * np.cumprod(1 + shocks)
        volumes = rng.normal(loc=5_000, scale=1_000, size=len(dates))
        volumes = np.clip(volumes, 1_000, None)
        for dt, price, vol in zip(dates, prices, volumes):
            price = float(price)
            records.append(
                {
                    "date": dt,
                    "ticker": row.codigo_ativo,
                    "open": price,
                    "high": price * 1.0005,
                    "low": price * 0.9995,
                    "avg": price,
                    "close": price,
                    "volume": float(vol),
                }
            )
    return pd.DataFrame(records)


def build_setores(empresas_subset: pd.DataFrame) -> Tuple[pd.DataFrame, Dict[str, int]]:
    setores = (
        empresas_subset["Setor"].fillna("Setor Indefinido").str.strip().drop_duplicates().sort_values()
    )
    records = []
    setor_map: Dict[str, int] = {}
    for idx, nome in enumerate(setores, start=1):
        setor_map[nome] = idx
        records.append({"setor_id": idx, "nome": nome})
    return pd.DataFrame(records), setor_map


def build_empresas(
    empresas_subset: pd.DataFrame, setor_map: Dict[str, int]
) -> pd.DataFrame:
    records: List[Dict[str, object]] = []
    for idx, row in enumerate(empresas_subset.itertuples(index=False), start=1):
        setor = row.Setor.strip() if isinstance(row.Setor, str) else "Setor Indefinido"
        nome_candidates = [
            getattr(row, "Nome_do_Fundo", None),
            getattr(row, "nome", None),
            getattr(row, "Ticker", None),
            getattr(row, "codigo_ativo", None),
        ]
        nome_escolhido = ""
        for candidato in nome_candidates:
            if isinstance(candidato, str):
                candidato = candidato.strip()
                if candidato:
                    nome_escolhido = candidato
                    break
        if not nome_escolhido:
            nome_escolhido = f"Empresa {idx}"
        cnpj_raw = getattr(row, "CNPJ", "")
        cnpj_txt = "".join(ch for ch in str(cnpj_raw) if ch.isdigit())
        cnpj_txt = cnpj_txt.zfill(14) if cnpj_txt else ""
        records.append(
            {
                "empresa_id": idx,
                "nome": nome_escolhido,
                "cnpj": cnpj_txt,
                "setor_id": setor_map.get(setor, setor_map[next(iter(setor_map))]),
            }
        )
    empresas_df = pd.DataFrame(records)
    empresas_df.rename(columns={"nome": "nome"}, inplace=True)
    return empresas_df


def build_ativos(
    assets_df: pd.DataFrame,
    setor_map: Dict[str, int],
    price_window: pd.DataFrame,
) -> Tuple[pd.DataFrame, Dict[str, int]]:
    records: List[Dict[str, object]] = []
    ticker_to_ativo: Dict[str, int] = {}
    last_prices = (
        price_window.sort_values("date").groupby("ticker").last()["close"].to_dict()
    )
    for idx, row in enumerate(assets_df.itertuples(index=False), start=1):
        ticker = row.codigo_ativo
        setor = row.Setor.strip() if isinstance(row.Setor, str) else "Setor Indefinido"
        preco_col = getattr(row, "preco_atual", math.nan)
        preco_val = safe_float(preco_col)
        preco_atual = (
            float(preco_val) if not math.isnan(preco_val) else float(last_prices.get(ticker, 0))
        )
        if preco_atual == 0:
            preco_atual = float(last_prices.get(ticker, 0))
        base_nome = getattr(row, "Nome_do_Fundo", None)
        if base_nome is None or (isinstance(base_nome, float) and math.isnan(base_nome)):
            base_nome = getattr(row, "nome", None)
        if base_nome is None or (isinstance(base_nome, float) and math.isnan(base_nome)):
            base_nome = ticker
        nome = f"{ticker} - {base_nome}"
        records.append(
            {
                "ativo_id": idx,
                "ticker": ticker,
                "nome": nome,
                "setor_id": setor_map.get(setor, setor_map[next(iter(setor_map))]),
                "preco_atual": round(preco_atual, 2),
            }
        )
        ticker_to_ativo[ticker] = idx
    ativos_df = pd.DataFrame(records)
    return ativos_df, ticker_to_ativo


def build_carteira_definicao(end_date: pd.Timestamp) -> pd.DataFrame:
    return pd.DataFrame(
        [
            {
                "carteira_definicao_id": 1,
                "nome": "Carteira Referencial",
                "data_referencia": end_date.date().isoformat(),
                "origem": "Simulacao 30d",
            }
        ]
    )


def build_carteira(
    ativos_df: pd.DataFrame,
    price_window: pd.DataFrame,
    end_date: pd.Timestamp,
) -> Tuple[pd.DataFrame, Dict[int, float]]:
    quantities: Dict[int, float] = {}
    if ativos_df.empty:
        return pd.DataFrame(), quantities
    rng = np.random.default_rng(RNG_SEED)
    min_weight = 1_000 / BASE_CAPITAL
    weights = rng.dirichlet(np.ones(len(ativos_df)))
    attempts = 0
    while (weights < min_weight).any() and attempts < 1_000:
        weights = rng.dirichlet(np.ones(len(ativos_df)))
        attempts += 1
    if (weights < min_weight).any():
        weights = np.maximum(weights, min_weight)
        weights = weights / weights.sum()
    records: List[Dict[str, object]] = []
    for idx, (ativo_row, peso) in enumerate(zip(ativos_df.itertuples(index=False), weights), start=1):
        close_series = price_window[(price_window["ticker"] == ativo_row.ticker) & (price_window["date"] == end_date)]["close"]
        if close_series.empty:
            close_series = price_window[
                (price_window["ticker"] == ativo_row.ticker) & (price_window["date"] <= end_date)
            ].sort_values("date")["close"].tail(1)
        close_price = close_series.iloc[0]
        valor = BASE_CAPITAL * float(peso)
        quantidade = round(valor / close_price, 4)
        valor_investido = round(quantidade * close_price, 2)
        quantities[ativo_row.ativo_id] = quantidade
        records.append(
            {
                "carteira_id": idx,
                "carteira_definicao_id": 1,
                "ativo_id": ativo_row.ativo_id,
                "quantidade_teorica": quantidade,
                "peso": round(float(peso), 4),
                "valor_investido": valor_investido,
            }
        )
    return pd.DataFrame(records), quantities


def build_desempenho(price_window: pd.DataFrame, ticker_to_ativo: Dict[str, int]) -> pd.DataFrame:
    records: List[Dict[str, object]] = []
    for row in price_window.itertuples(index=False):
        records.append(
            {
                "ativo_id": ticker_to_ativo[row.ticker],
                "data": row.date.date().isoformat(),
                "preco": round(float(row.close), 4),
            }
        )
    return pd.DataFrame(records)


def build_cotacoes(price_window: pd.DataFrame, ticker_to_ativo: Dict[str, int]) -> pd.DataFrame:
    records: List[Dict[str, object]] = []
    for row in price_window.itertuples(index=False):
        records.append(
            {
                "ativo_id": ticker_to_ativo[row.ticker],
                "data": row.date.date().isoformat(),
                "preco_abertura": round(float(row.open), 4),
                "preco_fechamento": round(float(row.close), 4),
                "volume": round(float(row.volume or 0), 4),
            }
        )
    return pd.DataFrame(records)


def build_carteira_historico(
    carteiras_df: pd.DataFrame,
    price_window: pd.DataFrame,
    transacoes_df: pd.DataFrame,
    ticker_to_ativo: Dict[str, int],
) -> pd.DataFrame:
    records: List[Dict[str, object]] = []
    carteiras_by_ativo = {row.ativo_id: row.carteira_id for row in carteiras_df.itertuples(index=False)}
    tx = transacoes_df.copy()
    if not tx.empty:
        tx["data"] = pd.to_datetime(tx["data"])
        tx["qty_delta"] = np.where(
            tx["tipo"].str.upper().str.contains("VENDA"),
            -tx["quantidade"],
            tx["quantidade"],
        )
    for ticker, group in price_window.groupby("ticker"):
        ativo_id = ticker_to_ativo.get(ticker)
        if ativo_id is None or ativo_id not in carteiras_by_ativo:
            continue
        carteira_id = carteiras_by_ativo[ativo_id]
        group_sorted = group.sort_values("date")
        tx_asset = pd.DataFrame()
        qty_cumsum = pd.Series(dtype="float64")
        if not tx.empty:
            tx_asset = tx[tx["carteira_id"] == carteira_id].sort_values("data")
            if not tx_asset.empty:
                qty_cumsum = tx_asset.set_index("data")["qty_delta"].cumsum()
        for row in group_sorted.itertuples(index=False):
            dt = row.date
            quantidade = 0.0
            if not qty_cumsum.empty:
                relevant = qty_cumsum[qty_cumsum.index <= dt]
                if not relevant.empty:
                    quantidade = float(relevant.iloc[-1])
            valor = round(float(row.close) * quantidade, 2)
            records.append(
                {
                    "carteira_id": carteira_id,
                    "data": dt.date().isoformat(),
                    "valor_total": valor,
                }
            )
    return pd.DataFrame(records)


def parse_pt_number(value: str) -> float:
    if value is None or (isinstance(value, float) and math.isnan(value)):
        return math.nan
    if isinstance(value, (int, float)):
        return float(value)
    txt = str(value).strip().replace(".", "").replace("%", "")
    multiplier = 1.0
    if txt.endswith("M"):
        multiplier = 1_000_000.0
        txt = txt[:-1]
    if txt.endswith("K"):
        multiplier = 1_000.0
        txt = txt[:-1]
    txt = txt.replace(",", ".")
    try:
        return float(txt) * multiplier
    except ValueError:
        return math.nan


def load_benchmark(start_date: pd.Timestamp, end_date: pd.Timestamp) -> pd.DataFrame:
    df = pd.read_csv(CSV_DIR / "bvsp.csv")
    df["Data"] = pd.to_datetime(df["Data"], format="%d.%m.%Y")
    df["close"] = df["Último"].apply(parse_pt_number)
    df["open"] = df["Abertura"].apply(parse_pt_number)
    df = df.sort_values("Data")
    window_df = df[(df["Data"] >= start_date) & (df["Data"] <= end_date)].copy()
    if window_df.empty:
        window_df = df.tail(WINDOW_DAYS).copy()
    window_df = window_df.dropna(subset=["close"])
    return window_df[["Data", "open", "close"]]


def build_benchmarks(benchmark_df: pd.DataFrame) -> pd.DataFrame:
    latest_value = benchmark_df["close"].iloc[-1]
    return pd.DataFrame(
        [
            {
                "benchmark_id": 1,
                "nome": BENCHMARK_NAME,
                "valor_atual": round(float(latest_value), 2),
            }
        ]
    )


def build_comparativo(
    carteira_hist_df: pd.DataFrame,
    benchmark_df: pd.DataFrame,
) -> pd.DataFrame:
    if carteira_hist_df.empty:
        return pd.DataFrame()
    carteira_hist_df = carteira_hist_df.copy()
    carteira_hist_df["data"] = pd.to_datetime(carteira_hist_df["data"])
    carteira_daily = (
        carteira_hist_df.groupby("data")["valor_total"].sum().sort_index()
    )
    carteira_returns = carteira_daily.pct_change().fillna(0.0)
    benchmark_df = benchmark_df.sort_values("Data").set_index("Data")
    benchmark_returns = benchmark_df["close"].pct_change().fillna(0.0)
    benchmark_aligned = benchmark_returns.reindex(carteira_returns.index, method="ffill").fillna(0.0)
    aligned = pd.DataFrame(
        {
            "retorno_carteira": carteira_returns,
            "retorno_benchmark": benchmark_aligned,
        }
    ).reset_index()
    records: List[Dict[str, object]] = []
    for row in aligned.itertuples(index=False):
        records.append(
            {
                "carteira_id": 1,
                "benchmark_id": 1,
                "data": row.data.date().isoformat(),
                "retorno_carteira": round(float(row.retorno_carteira), 6),
                "retorno_benchmark": round(float(row.retorno_benchmark), 6),
            }
        )
    return pd.DataFrame(records)


def build_dividendos(
    ativos_df: pd.DataFrame,
    carteiras_df: pd.DataFrame,
    quantities: Dict[int, float],
    end_date: pd.Timestamp,
) -> Tuple[pd.DataFrame, pd.DataFrame]:
    records_dividendos: List[Dict[str, object]] = []
    records_proventos: List[Dict[str, object]] = []
    pagamento = (end_date - pd.Timedelta(days=15)).date().isoformat()
    for ativo in ativos_df.itertuples(index=False):
        quantidade = quantities.get(ativo.ativo_id, 0.0)
        mensal = safe_float(getattr(ativo, "proventos_mensal", math.nan))
        dy = safe_float(getattr(ativo, "dividend_yield", math.nan))
        valor_unitario = float(mensal) if not math.isnan(mensal) else 0.0
        if valor_unitario == 0.0 and not math.isnan(dy):
            valor_unitario = ativo.preco_atual * (dy / 100.0) / 12.0
        valor_total = round(quantidade * valor_unitario, 4)
        if valor_total <= 0:
            continue
        records_dividendos.append(
            {
                "ativo_id": ativo.ativo_id,
                "data_pagamento": pagamento,
                "valor": valor_total,
            }
        )
        records_proventos.append(
            {
                "ativo_id": ativo.ativo_id,
                "data": pagamento,
                "tipo": "Dividendo",
                "valor": valor_total,
            }
        )
    return pd.DataFrame(records_dividendos), pd.DataFrame(records_proventos)


def build_indicadores_fundamentalistas(ativos_df: pd.DataFrame) -> pd.DataFrame:
    records: List[Dict[str, object]] = []
    for ativo in ativos_df.itertuples(index=False):
        pl = safe_float(getattr(ativo, "pl", math.nan))
        roe = safe_float(getattr(ativo, "roe", math.nan))
        de = safe_float(getattr(ativo, "divida_ebitda", math.nan))
        records.append(
            {
                "ativo_id": ativo.ativo_id,
                "pl": round(float(pl), 2) if not math.isnan(pl) else 0.0,
                "roe": round(float(roe), 2) if not math.isnan(roe) else 0.0,
                "divida_ebitda": round(float(de), 2) if not math.isnan(de) else 0.0,
            }
        )
    return pd.DataFrame(records)


def build_dividend_yield_historico(ativos_df: pd.DataFrame, end_date: pd.Timestamp) -> pd.DataFrame:
    ano = end_date.year - 1
    records: List[Dict[str, object]] = []
    for ativo in ativos_df.itertuples(index=False):
        dy_hist = safe_float(getattr(ativo, "dividend_yield_historico", math.nan))
        if math.isnan(dy_hist):
            continue
        records.append(
            {
                "ativo_id": ativo.ativo_id,
                "ano": ano,
                "dy_percentual": round(float(dy_hist), 2),
            }
        )
    return pd.DataFrame(records)


def build_transacoes(
    carteiras_df: pd.DataFrame,
    price_window: pd.DataFrame,
    ticker_to_ativo: Dict[str, int],
    start_date: pd.Timestamp,
) -> Tuple[pd.DataFrame, Dict[int, float], Dict[int, float]]:
    rng = np.random.default_rng(RNG_SEED)
    records: List[Dict[str, object]] = []
    quantity_totals: Dict[int, float] = {}
    invested_totals: Dict[int, float] = {}
    transacao_id = 1
    for carteira in carteiras_df.itertuples(index=False):
        ticker = carteira.ticker
        grupo_precos = price_window[price_window["ticker"] == ticker].sort_values("date")
        if grupo_precos.empty:
            continue
        primeira_data = grupo_precos["date"].min()
        preco_compra = grupo_precos.loc[grupo_precos["date"] == primeira_data, "close"].iloc[0]
        base_quantidade = float(carteira.quantidade_teorica)
        records.append(
            {
                "transacao_id": transacao_id,
                "carteira_id": carteira.carteira_id,
                "ativo_id": carteira.ativo_id,
                "data": primeira_data.date().isoformat(),
                "tipo": "COMPRA",
                "quantidade": round(base_quantidade, 4),
                "preco": round(float(preco_compra), 4),
            }
        )
        transacao_id += 1
        invested = base_quantidade * float(preco_compra)
        extra_amount = rng.uniform(1_000, 5_000)
        extra_date = primeira_data + pd.Timedelta(days=rng.integers(5, WINDOW_DAYS - 2))
        extra_date = min(extra_date, grupo_precos["date"].max())
        extra_price = (
            grupo_precos.loc[grupo_precos["date"] >= extra_date, "close"].iloc[0]
            if not grupo_precos.loc[grupo_precos["date"] >= extra_date].empty
            else grupo_precos["close"].iloc[-1]
        )
        extra_quantidade = round(float(extra_amount / extra_price), 4)
        if extra_quantidade > 0:
            records.append(
                {
                    "transacao_id": transacao_id,
                    "carteira_id": carteira.carteira_id,
                    "ativo_id": carteira.ativo_id,
                    "data": extra_date.date().isoformat(),
                    "tipo": "COMPRA",
                    "quantidade": extra_quantidade,
                    "preco": round(float(extra_price), 4),
                }
            )
            transacao_id += 1
            invested += extra_quantidade * float(extra_price)
            base_quantidade += extra_quantidade

        rebalance_date = start_date + pd.Timedelta(days=WINDOW_DAYS // 2)
        if rebalance_date > grupo_precos["date"].max():
            rebalance_date = grupo_precos["date"].max()
        mid_price = grupo_precos.loc[grupo_precos["date"] >= rebalance_date, "close"].iloc[0]
        records.append(
            {
                "transacao_id": transacao_id,
                "carteira_id": carteira.carteira_id,
                "ativo_id": carteira.ativo_id,
                "data": rebalance_date.date().isoformat(),
                "tipo": "REBALANCEAMENTO",
                "quantidade": 0.0,
                "preco": round(float(mid_price), 4),
            }
        )
        transacao_id += 1
        quantity_totals[carteira.ativo_id] = round(base_quantidade, 4)
        invested_totals[carteira.carteira_id] = round(float(invested), 2)
    return pd.DataFrame(records), quantity_totals, invested_totals


def build_riscos(
    price_window: pd.DataFrame,
    ticker_to_ativo: Dict[str, int],
    benchmark_df: pd.DataFrame,
) -> pd.DataFrame:
    benchmark_returns = benchmark_df.set_index("Data")["close"].pct_change().dropna()
    records: List[Dict[str, object]] = []
    for ticker, group in price_window.groupby("ticker"):
        ativo_id = ticker_to_ativo[ticker]
        closes = group.set_index("date")["close"].sort_index()
        returns = closes.pct_change().dropna()
        if returns.empty:
            beta = 1.0
            volatility = 0.0
            var = 0.0
        else:
            aligned = returns.align(benchmark_returns, join="inner")[0].dropna()
            bench_aligned = returns.align(benchmark_returns, join="inner")[1].dropna()
            if len(aligned) > 1 and bench_aligned.var() > 0:
                beta = aligned.cov(bench_aligned) / bench_aligned.var()
            else:
                beta = 1.0
            volatility = returns.std() * math.sqrt(252)
            var = returns.quantile(0.05) * closes.iloc[-1]
        records.append(
            {
                "ativo_id": ativo_id,
                "beta": round(float(beta), 4),
                "volatilidade": round(float(volatility), 4),
                "var": round(float(var), 4),
            }
        )
    return pd.DataFrame(records)


def build_simulacoes(carteira_id: int, end_date: pd.Timestamp) -> pd.DataFrame:
    return pd.DataFrame(
        [
            {
                "simulacao_id": 1,
                "carteira_id": carteira_id,
                "descricao": "Stress +5% no patrimônio",
                "data_execucao": end_date.date().isoformat(),
            }
        ]
    )


def build_simulacao_resultados(
    simulacao_df: pd.DataFrame,
    carteiras_df: pd.DataFrame,
    price_window: pd.DataFrame,
) -> pd.DataFrame:
    records: List[Dict[str, object]] = []
    end_date = price_window["date"].max()
    for carteira in carteiras_df.itertuples(index=False):
        close_price = price_window[
            (price_window["ticker"] == carteira.ticker) & (price_window["date"] == end_date)
        ]["close"].iloc[0]
        valor_atual = close_price * carteira.quantidade_teorica
        novo_valor = valor_atual * 1.05
        impacto = novo_valor - valor_atual
        records.append(
            {
                "simulacao_id": 1,
                "ativo_id": carteira.ativo_id,
                "novo_valor": round(float(novo_valor), 2),
                "impacto_total": round(float(impacto), 2),
            }
        )
    return pd.DataFrame(records)


def build_alocacao_setorial(
    carteiras_df: pd.DataFrame,
    ativos_df: pd.DataFrame,
) -> pd.DataFrame:
    merged = carteiras_df.merge(ativos_df[["ativo_id", "setor_id"]], on="ativo_id")
    setor_weights = merged.groupby("setor_id")["peso"].sum().reset_index()
    records: List[Dict[str, object]] = []
    for row in setor_weights.itertuples(index=False):
        records.append(
            {
                "carteira_id": 1,
                "setor_id": row.setor_id,
                "peso_setor": round(float(row.peso) * 100, 2),
            }
        )
    return pd.DataFrame(records)


def build_alertas(carteiras_df: pd.DataFrame, start_date: pd.Timestamp) -> pd.DataFrame:
    records: List[Dict[str, object]] = []
    for idx, carteira in enumerate(carteiras_df.itertuples(index=False), start=1):
        records.append(
            {
                "alerta_id": idx,
                "carteira_id": carteira.carteira_id,
                "ativo_id": carteira.ativo_id,
                "condicao": f"{carteira.ticker} variacao > 5%",
                "data_criacao": start_date.date().isoformat(),
            }
        )
    return pd.DataFrame(records)


def build_metas(end_date: pd.Timestamp) -> pd.DataFrame:
    prazo = (end_date + pd.Timedelta(days=365)).date().isoformat()
    return pd.DataFrame(
        [
            {
                "meta_id": 1,
                "carteira_id": 1,
                "descricao": "Crescer patrimônio em 15%",
                "valor_alvo": round(BASE_CAPITAL * 1.15, 2),
                "prazo": prazo,
            }
        ]
    )


def build_indicadores_macroeconomicos(end_date: pd.Timestamp) -> pd.DataFrame:
    indicadores: List[Dict[str, object]] = []
    ipca_df = pd.read_csv(CSV_DIR / "ipca.csv")
    ipca_df = ipca_df.dropna()
    ipca_periodo = ipca_df.iloc[-1]["periodo"]
    ipca_valor = float(str(ipca_df.iloc[-1]["valor"]).replace(",", "."))
    indicadores.append(
        {
            "indicador_id": 1,
            "nome": "IPCA",
            "valor_atual": round(ipca_valor, 4),
            "data_atualizacao": end_date.date().isoformat(),
        }
    )
    selic_df = pd.read_csv(CSV_DIR / "meta-para-a-taxa-selic.csv", sep=";")
    selic_df["DateTime"] = pd.to_datetime(selic_df["DateTime"], format="%Y-%m-%d")
    selic_df = selic_df.sort_values("DateTime")
    selic_valor = parse_pt_number(selic_df.iloc[-1]["Meta para a taxa Selic"])
    indicadores.append(
        {
            "indicador_id": 2,
            "nome": "SELIC Meta",
            "valor_atual": round(float(selic_valor), 4),
            "data_atualizacao": selic_df.iloc[-1]["DateTime"].date().isoformat(),
        }
    )
    pib_df = pd.read_csv(CSV_DIR / "pib-per-capita-r.csv")
    indicadores.append(
        {
            "indicador_id": 3,
            "nome": "PIB Per Capita",
            "valor_atual": round(float(pib_df.iloc[-1]["valor"]), 2),
            "data_atualizacao": f"{int(pib_df.iloc[-1]["periodo"])}-12-31",
        }
    )
    return pd.DataFrame(indicadores)


def build_custos_operacionais(end_date: pd.Timestamp) -> pd.DataFrame:
    records = [
        {
            "custo_id": 1,
            "carteira_id": 1,
            "descricao": "Taxa de administração",
            "valor": 120.0,
            "data": (end_date - pd.Timedelta(days=7)).date().isoformat(),
        },
        {
            "custo_id": 2,
            "carteira_id": 1,
            "descricao": "Custódia",
            "valor": 45.0,
            "data": (end_date - pd.Timedelta(days=21)).date().isoformat(),
        },
    ]
    return pd.DataFrame(records)


def save_table(df: pd.DataFrame, name: str) -> None:
    if df.empty:
        return
    path = OUTPUT_DIR / f"{name}.csv"
    df.to_csv(path, index=False)


def main() -> None:
    ensure_output_dir(OUTPUT_DIR)

    carteira_modelo = load_carteira_modelo()
    empresas_raw = load_empresas()
    prices_raw = load_price_history()
    assets = select_target_assets(carteira_modelo, empresas_raw, prices_raw)
    tickers_equity = assets["codigo_ativo"].tolist()

    start_date, end_date = determine_window(prices_raw, tickers_equity)
    price_window = filter_price_window(prices_raw, tickers_equity, start_date, end_date)

    renda_fixa_assets = load_renda_fixa()
    if not renda_fixa_assets.empty:
        assets = pd.concat([assets, renda_fixa_assets], ignore_index=True, sort=False)
        renda_prices = generate_renda_fixa_prices(renda_fixa_assets, start_date, end_date)
        if not renda_prices.empty:
            price_window = pd.concat([price_window, renda_prices], ignore_index=True)
    price_window.sort_values(["ticker", "date"], inplace=True)

    setores_df, setor_map = build_setores(assets)
    empresas_base = assets.copy()
    empresas_base["CNPJ"] = empresas_base["CNPJ"].fillna("").astype(str)
    empresas_equity = (
        empresas_base[empresas_base["CNPJ"].str.strip() != ""]
        .drop_duplicates(subset=["Ticker"])
        .reset_index(drop=True)
    )
    empresas_df = build_empresas(empresas_equity, setor_map)
    ativos_df, ticker_to_ativo = build_ativos(assets, setor_map, price_window)

    # Merge supplemental fields from carteira_modelo into ativos_df for later use.
    ativos_df = ativos_df.merge(
        assets[
            [
                "codigo_ativo",
                "pl",
                "roe",
                "divida_ebitda",
                "dividend_yield",
                "proventos_mensal",
                "dividend_yield_historico",
            ]
        ],
        left_on="ticker",
        right_on="codigo_ativo",
        how="left",
    )

    carteira_definicao_df = build_carteira_definicao(end_date)
    carteiras_df, base_quantities = build_carteira(ativos_df, price_window, end_date)
    carteiras_df = carteiras_df.merge(ativos_df[["ativo_id", "ticker"]], on="ativo_id", how="left")

    transacoes_df, quantity_totals, invested_totals = build_transacoes(
        carteiras_df, price_window, ticker_to_ativo, start_date
    )
    carteiras_df["quantidade_teorica"] = (
        carteiras_df["ativo_id"].map(quantity_totals).fillna(0.0).round(4)
    )
    carteiras_df["valor_investido"] = (
        carteiras_df["carteira_id"].map(invested_totals).fillna(0.0).round(2)
    )
    total_invested = carteiras_df["valor_investido"].sum()
    if total_invested > 0:
        carteiras_df["peso"] = (carteiras_df["valor_investido"] / total_invested).round(4)

    desempenho_df = build_desempenho(price_window, ticker_to_ativo)
    cotacoes_df = build_cotacoes(price_window, ticker_to_ativo)
    carteira_hist_df = build_carteira_historico(carteiras_df, price_window, transacoes_df, ticker_to_ativo)

    benchmark_df = load_benchmark(start_date, end_date)
    benchmarks_df = build_benchmarks(benchmark_df)
    comparativo_df = build_comparativo(carteira_hist_df, benchmark_df)

    dividendos_df, proventos_df = build_dividendos(ativos_df, carteiras_df, quantity_totals, end_date)
    indicadores_f_df = build_indicadores_fundamentalistas(ativos_df)
    dy_hist_df = build_dividend_yield_historico(ativos_df, end_date)
    riscos_df = build_riscos(price_window, ticker_to_ativo, benchmark_df)
    simulacoes_df = build_simulacoes(1, end_date)
    simulacao_resultados_df = build_simulacao_resultados(simulacoes_df, carteiras_df, price_window)
    alocacao_df = build_alocacao_setorial(carteiras_df, ativos_df)
    alertas_df = build_alertas(carteiras_df, start_date)
    metas_df = build_metas(end_date)
    indicadores_macro_df = build_indicadores_macroeconomicos(end_date)
    custos_df = build_custos_operacionais(end_date)

    save_table(setores_df, "Setores")
    save_table(empresas_df, "Empresas")
    save_table(ativos_df.drop(columns=["codigo_ativo", "pl", "roe", "divida_ebitda", "dividend_yield", "proventos_mensal", "dividend_yield_historico"]), "Ativos")
    save_table(carteira_definicao_df, "Carteira_Definicao")
    save_table(carteiras_df.drop(columns=["ticker"]), "Carteira")
    save_table(desempenho_df, "Desempenho_Historico")
    save_table(dividendos_df, "Dividendos")
    save_table(indicadores_f_df, "Indicadores_Fundamentalistas")
    save_table(cotacoes_df, "Cotacoes_Diarias")
    save_table(proventos_df, "Proventos")
    save_table(carteira_hist_df, "Carteira_Historico")
    save_table(benchmarks_df, "Benchmarks")
    save_table(comparativo_df, "Comparativo_Benchmark")
    save_table(transacoes_df, "Transacoes")
    save_table(riscos_df, "Riscos")
    save_table(simulacoes_df, "Simulacoes")
    save_table(simulacao_resultados_df, "Simulacao_Resultados")
    save_table(dy_hist_df, "Dividend_Yield_Historico")
    save_table(alocacao_df, "Alocacao_Setorial")
    save_table(alertas_df, "Alertas")
    save_table(metas_df, "Metas_Investimento")
    save_table(indicadores_macro_df, "Indicadores_Macroeconomicos")
    save_table(custos_df, "Custos_Operacionais")


if __name__ == "__main__":
    main()
