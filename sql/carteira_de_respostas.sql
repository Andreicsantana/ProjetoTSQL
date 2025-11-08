-- Parâmetros
DECLARE @carteira_id INT = 1;
DECLARE @dias INT = 30;
DECLARE @ano_ultimo INT = YEAR(GETDATE()) - 1;

-- 1.1 Composição da Carteira
SELECT
    c.ativo_id,
    a.nome AS ativo_nome,
    COALESCE(c.peso, 0) * 100.0 AS peso_percentual,
    a.preco_atual,
    c.quantidade_teorica,
    c.valor_investido
FROM Carteira c
JOIN Ativos a ON a.ativo_id = c.ativo_id
WHERE c.carteira_id = @carteira_id
ORDER BY c.valor_investido DESC;

-- 1.1 Total da carteira
SELECT @carteira_id AS carteira_id, SUM(valor_investido) AS total_investido
FROM Carteira
WHERE carteira_id = @carteira_id;

-- 1.2 Distribuição setorial
SELECT
    COALESCE(st.nome, 'Não informado') AS setor,
    SUM(c.valor_investido) AS valor_investido_setor,
    100.0 * SUM(c.valor_investido) / NULLIF((SELECT SUM(valor_investido) FROM Carteira WHERE carteira_id = @carteira_id),0) AS percentual_setor
FROM Carteira c
JOIN Ativos a ON a.ativo_id = c.ativo_id
LEFT JOIN Setores st ON st.setor_id = a.setor_id
WHERE c.carteira_id = @carteira_id
GROUP BY COALESCE(st.nome,'Não informado')
ORDER BY valor_investido_setor DESC;

-- 2.1 Valorização (últimos @dias)
SELECT
    ch_latest.data AS data_ultima,
    ch_latest.valor_total AS valor_ultima,
    ch_old.data AS data_antiga,
    ch_old.valor_total AS valor_antiga,
    CASE WHEN ch_old.valor_total IS NULL THEN NULL
         ELSE 100.0 * (ch_latest.valor_total / ch_old.valor_total - 1.0)
    END AS percentual_variacao
FROM
    (SELECT TOP(1) * FROM Carteira_Historico WHERE carteira_id = @carteira_id ORDER BY data DESC) ch_latest
OUTER APPLY
    (SELECT TOP(1) * FROM Carteira_Historico
     WHERE carteira_id = @carteira_id AND data <= DATEADD(DAY, -@dias, ch_latest.data)
     ORDER BY data DESC) ch_old;

-- 2.2 Ativo com maior alta (últimos @dias)
;WITH Ultimos AS (
    SELECT ativo_id, MAX(data) AS data_recente FROM Desempenho_Historico GROUP BY ativo_id
)
SELECT TOP(1)
    a.ativo_id,
    a.nome,
    recent.preco AS preco_recente,
    older.preco AS preco_30dias_atras,
    100.0 * (recent.preco / older.preco - 1.0) AS pct_variacao
FROM Ultimos u
JOIN Desempenho_Historico recent ON recent.ativo_id = u.ativo_id AND recent.data = u.data_recente
OUTER APPLY (
    SELECT TOP(1) preco FROM Desempenho_Historico dh2
    WHERE dh2.ativo_id = u.ativo_id AND dh2.data <= DATEADD(DAY, -@dias, u.data_recente)
    ORDER BY dh2.data DESC
) older(preco)
JOIN Ativos a ON a.ativo_id = u.ativo_id
WHERE older.preco IS NOT NULL
ORDER BY pct_variacao DESC;

-- 2.3 Retorno acumulado vs Ibovespa
SELECT TOP(1)
    cb.data,
    cb.retorno_carteira,
    cb.retorno_benchmark
FROM Comparativo_Benchmark cb
JOIN Benchmarks b ON b.benchmark_id = cb.benchmark_id AND b.nome = 'Ibovespa'
WHERE cb.carteira_id = @carteira_id
ORDER BY cb.data DESC;

-- 2.4 Dividend yield médio (último ano)
SELECT AVG(dy_percentual) AS dy_medio_simples
FROM Dividend_Yield_Historico
WHERE ano = @ano_ultimo;

SELECT
    SUM(dy.dy_percentual * c.valor_investido) / NULLIF(SUM(c.valor_investido),0) AS dy_medio_ponderado
FROM Dividend_Yield_Historico dy
JOIN Carteira c ON c.ativo_id = dy.ativo_id
WHERE dy.ano = @ano_ultimo AND c.carteira_id = @carteira_id;

-- 3.1 P/L e ROE médios ponderados
SELECT
    SUM(COALESCE(i.pl,0) * c.valor_investido) / NULLIF(SUM(c.valor_investido),0) AS pl_ponderado,
    SUM(COALESCE(i.roe,0) * c.valor_investido) / NULLIF(SUM(c.valor_investido),0) AS roe_ponderado
FROM Indicadores_Fundamentalistas i
JOIN Carteira c ON c.ativo_id = i.ativo_id
WHERE c.carteira_id = @carteira_id;

-- 3.2 Dividendos recentes (últimos @dias)
SELECT
    d.ativo_id,
    a.nome AS ativo_nome,
    d.data_pagamento,
    d.valor
FROM Dividendos d
JOIN Ativos a ON a.ativo_id = d.ativo_id
WHERE d.data_pagamento >= DATEADD(DAY, -@dias, GETDATE())
ORDER BY d.data_pagamento DESC;

-- 3.3 Maior Dívida/EBITDA
SELECT TOP(1)
    i.ativo_id,
    a.nome,
    i.divida_ebitda
FROM Indicadores_Fundamentalistas i
JOIN Ativos a ON a.ativo_id = i.ativo_id
ORDER BY i.divida_ebitda DESC;

-- 4.1 Simulação: +5% em cada ativo
SELECT
    SUM(c.valor_investido) AS total_atual,
    SUM(c.valor_investido * 1.05) AS total_com_5pct_acima,
    100.0 * (SUM(c.valor_investido * 1.05) / NULLIF(SUM(c.valor_investido),0) - 1.0) AS aumento_percentual
FROM Carteira c
WHERE c.carteira_id = @carteira_id;

-- 4.2 Exposição ao maior setor
;WITH setor_exp AS (
    SELECT
        COALESCE(st.nome,'Não informado') AS setor,
        SUM(c.valor_investido) AS valor_setor
    FROM Carteira c
    JOIN Ativos a ON a.ativo_id = c.ativo_id
    LEFT JOIN Setores st ON st.setor_id = a.setor_id
    WHERE c.carteira_id = @carteira_id
    GROUP BY COALESCE(st.nome,'Não informado')
)
SELECT TOP(1) setor, valor_setor,
       100.0 * valor_setor / NULLIF((SELECT SUM(valor_investido) FROM Carteira WHERE carteira_id = @carteira_id),0) AS percentual
FROM setor_exp
ORDER BY valor_setor DESC;

-- 4.3 Impacto: maior peso cair 10%
;WITH top_ativo AS (
    SELECT TOP(1) c.ativo_id, c.valor_investido, c.peso
    FROM Carteira c
    WHERE c.carteira_id = @carteira_id
    ORDER BY c.valor_investido DESC
)
SELECT
    (SELECT SUM(valor_investido) FROM Carteira WHERE carteira_id = @carteira_id) AS total_atual,
    ta.ativo_id AS ativo_mais_peso,
    ta.valor_investido AS valor_ativo,
    ta.valor_investido * 0.10 AS perda_10pct,
    (SELECT SUM(valor_investido) FROM Carteira WHERE carteira_id = @carteira_id) - ta.valor_investido * 0.10 AS novo_total_pos_perda
FROM top_ativo ta;

-- 4.4 Reinvestir dividendos do último ano
SELECT
    SUM(c.valor_investido) AS total_atual,
    SUM(ISNULL(d.total_dividendos_ano,0)) AS soma_dividendos_ultimo_ano,
    SUM(c.valor_investido) + SUM(ISNULL(d.total_dividendos_ano,0)) AS novo_total_reinvestindo_dividendos,
    CASE WHEN SUM(c.valor_investido) = 0 THEN NULL
         ELSE 100.0 * ( (SUM(c.valor_investido) + SUM(ISNULL(d.total_dividendos_ano,0))) / SUM(c.valor_investido) - 1.0)
    END AS ganho_percentual_por_reinvestir
FROM Carteira c
LEFT JOIN (
    SELECT ativo_id, SUM(valor) AS total_dividendos_ano
    FROM Dividendos
    WHERE data_pagamento >= DATEFROMPARTS(@ano_ultimo,1,1) AND data_pagamento < DATEFROMPARTS(@ano_ultimo+1,1,1)
    GROUP BY ativo_id
) d ON d.ativo_id = c.ativo_id
WHERE c.carteira_id = @carteira_id;

-- ...existing code...