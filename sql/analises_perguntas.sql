USE TsqlProject;
GO

-- Composicao da carteira ------------------------------------------------
-- Pergunta: Quais ativos compoem a carteira e qual o peso de cada um?
SELECT
    c.peso,
    a.nome AS ativo_nome
FROM Carteira AS c
JOIN Ativos AS a
    ON a.ativo_id = c.ativo_id
WHERE c.carteira_definicao_id = 1
ORDER BY c.peso DESC;

-- Pergunta: Qual e a distribuicao setorial da carteira?
SELECT
    s.nome AS setor_nome,
    SUM(c.peso) AS peso_total_setor
FROM Carteira AS c
JOIN Ativos AS a
    ON a.ativo_id = c.ativo_id
LEFT JOIN Setores AS s
    ON s.setor_id = a.setor_id
WHERE c.carteira_definicao_id = 1
GROUP BY s.nome
ORDER BY peso_total_setor DESC;

-- Pergunta: Qual o preco atual de cada ativo da carteira?
SELECT
    a.nome AS ativo_nome,
    a.preco_atual
FROM Carteira AS c
JOIN Ativos AS a
    ON c.ativo_id = a.ativo_id
WHERE c.carteira_definicao_id = 1
ORDER BY a.nome;

-- Pergunta: Qual o valor total investido em cada ativo?
SELECT
    a.ativo_id,
    a.nome AS ativo_nome,
    SUM(c.valor_investido) AS valor_total_ativo
FROM Carteira AS c
JOIN Ativos AS a
    ON a.ativo_id = c.ativo_id
WHERE c.carteira_definicao_id = 1
GROUP BY a.ativo_id, a.nome
ORDER BY a.ativo_id DESC;

-- Pergunta: Qual o valor total investido na carteira?
SELECT
    SUM(c.valor_investido) AS valor_total_carteira
FROM Carteira AS c
WHERE c.carteira_definicao_id = 1;

-- Desempenho historico ---------------------------------------------------
-- Pergunta: Qual foi a variacao da carteira em janeiro de 2025?
WITH carteira_alvo AS (
    SELECT TOP 1 carteira_id
    FROM Carteira
    WHERE carteira_definicao_id = 1
    ORDER BY carteira_id
),
ultimos_30 AS (
    SELECT
        ch.data,
        ch.valor_total,
        ROW_NUMBER() OVER (ORDER BY ch.data DESC) AS rn_desc,
        ROW_NUMBER() OVER (ORDER BY ch.data ASC) AS rn_asc
    FROM Carteira_Historico AS ch
    CROSS JOIN carteira_alvo AS ca
        WHERE ch.carteira_id = ca.carteira_id
            AND ch.data BETWEEN '2025-01-01' AND '2025-01-31'
)
SELECT
    atual.valor_total AS valor_atual,
    inicial.valor_total AS valor_30_dias_atras,
    ((atual.valor_total / inicial.valor_total) - 1.0) * 100.0 AS variacao_percentual
FROM ultimos_30 AS atual
JOIN ultimos_30 AS inicial
    ON atual.rn_desc = 1
   AND inicial.rn_asc = 1;

-- Pergunta: Qual ativo da carteira 1 teve a maior alta em janeiro de 2025?
WITH precos AS (
    SELECT
        dh.ativo_id,
        dh.data,
        dh.preco,
        ROW_NUMBER() OVER (PARTITION BY dh.ativo_id ORDER BY dh.data DESC) AS rn_desc,
        ROW_NUMBER() OVER (PARTITION BY dh.ativo_id ORDER BY dh.data ASC) AS rn_asc
    FROM Desempenho_Historico AS dh
        WHERE dh.data BETWEEN '2025-01-01' AND '2025-01-31'
      AND dh.ativo_id IN (
          SELECT c.ativo_id
          FROM Carteira AS c
          WHERE c.carteira_definicao_id = 1
      )
),
variacoes AS (
    SELECT
        atual.ativo_id,
        (atual.preco / inicial.preco - 1.0) * 100.0 AS variacao_percentual
    FROM precos AS atual
    JOIN precos AS inicial
        ON atual.ativo_id = inicial.ativo_id
       AND atual.rn_desc = 1
       AND inicial.rn_asc = 1
)
SELECT TOP 1
    a.nome AS ativo_nome,
    v.variacao_percentual
FROM variacoes AS v
JOIN Ativos AS a
    ON a.ativo_id = v.ativo_id
ORDER BY v.variacao_percentual DESC;

-- Pergunta: Qual ativo da carteira 1 teve a maior queda em janeiro de 2025?
WITH precos AS (
    SELECT
        dh.ativo_id,
        dh.data,
        dh.preco,
        ROW_NUMBER() OVER (PARTITION BY dh.ativo_id ORDER BY dh.data DESC) AS rn_desc,
        ROW_NUMBER() OVER (PARTITION BY dh.ativo_id ORDER BY dh.data ASC) AS rn_asc
    FROM Desempenho_Historico AS dh
        WHERE dh.data BETWEEN '2025-01-01' AND '2025-01-31'
      AND dh.ativo_id IN (
          SELECT c.ativo_id
          FROM Carteira AS c
          WHERE c.carteira_definicao_id = 1
      )
),
variacoes AS (
    SELECT
        atual.ativo_id,
        (atual.preco / inicial.preco - 1.0) * 100.0 AS variacao_percentual
    FROM precos AS atual
    JOIN precos AS inicial
        ON atual.ativo_id = inicial.ativo_id
       AND atual.rn_desc = 1
       AND inicial.rn_asc = 1
)
SELECT TOP 1
    a.nome AS ativo_nome,
    v.variacao_percentual
FROM variacoes AS v
JOIN Ativos AS a
    ON a.ativo_id = v.ativo_id
ORDER BY v.variacao_percentual ASC;

-- Pergunta: Como o retorno diario da carteira 1 se comparou ao IBOV em janeiro de 2025?
SELECT
    cb.data,
    cb.retorno_carteira,
    cb.retorno_benchmark,
    (cb.retorno_carteira - cb.retorno_benchmark) AS diferenca,
    b.nome AS benchmark_nome
FROM Comparativo_Benchmark AS cb
JOIN Benchmarks AS b
    ON b.benchmark_id = cb.benchmark_id
WHERE cb.carteira_id = (
        SELECT TOP 1 carteira_id
        FROM Carteira
        WHERE carteira_definicao_id = 1
        ORDER BY carteira_id
    )
    AND UPPER(b.nome) LIKE 'IBOV%'
    AND cb.data BETWEEN '2025-01-01' AND '2025-01-31'
ORDER BY cb.data;

-- Pergunta: Qual foi o dividend yield registrado pela carteira 1 em janeiro de 2025?
WITH carteira_alvo AS (
    SELECT TOP 1 carteira_id
    FROM Carteira
    WHERE carteira_definicao_id = 1
    ORDER BY carteira_id
),
dividendos_12m AS (
    SELECT
        d.ativo_id,
        SUM(d.valor) AS total_dividendos
    FROM Dividendos AS d
        WHERE d.data_pagamento BETWEEN '2025-01-01' AND '2025-01-31'
      AND d.ativo_id IN (
          SELECT c.ativo_id
          FROM Carteira AS c
          WHERE c.carteira_definicao_id = 1
      )
    GROUP BY d.ativo_id
),
valor_medio_carteira AS (
    SELECT AVG(ch.valor_total) AS valor_medio
    FROM Carteira_Historico AS ch
    CROSS JOIN carteira_alvo AS ca
        WHERE ch.carteira_id = ca.carteira_id
            AND ch.data BETWEEN '2025-01-01' AND '2025-01-31'
)
SELECT
    SUM(dividendos_12m.total_dividendos) / MAX(valor_medio.valor_medio) * 100.0 AS dividend_yield_medio_percent
FROM dividendos_12m
CROSS JOIN valor_medio_carteira AS valor_medio;

-- Indicadores fundamentalistas -------------------------------------------
-- Pergunta: Qual e o PL medio ponderado da carteira?
SELECT
    SUM(c.peso * i.pl) / SUM(c.peso) AS pl_medio_ponderado
FROM Carteira AS c
JOIN Indicadores_Fundamentalistas AS i
    ON i.ativo_id = c.ativo_id
WHERE c.carteira_definicao_id = 1;

-- Pergunta: Qual e o ROE medio ponderado da carteira?
SELECT
    SUM(c.peso * i.roe) / SUM(c.peso) AS roe_medio_ponderado
FROM Carteira AS c
JOIN Indicadores_Fundamentalistas AS i
    ON i.ativo_id = c.ativo_id
WHERE c.carteira_definicao_id = 1;

-- Pergunta: Quais dividendos os ativos da carteira 1 receberam em janeiro de 2025?
SELECT
    a.nome AS ativo_nome,
    d.data_pagamento,
    d.valor
FROM Dividendos AS d
JOIN Ativos AS a
    ON a.ativo_id = d.ativo_id
WHERE d.data_pagamento BETWEEN '2025-01-01' AND '2025-01-31'
  AND d.ativo_id IN (
      SELECT c.ativo_id
      FROM Carteira AS c
      WHERE c.carteira_definicao_id = 1
  )
ORDER BY d.data_pagamento DESC;

-- Pergunta: Qual ativo possui o maior indice Divida sobre EBITDA?
SELECT TOP 1
    a.nome AS ativo_nome,
    i.divida_ebitda
FROM Indicadores_Fundamentalistas AS i
JOIN Ativos AS a
    ON a.ativo_id = i.ativo_id
WHERE i.ativo_id IN (
    SELECT c.ativo_id
    FROM Carteira AS c
    WHERE c.carteira_definicao_id = 1
)
ORDER BY i.divida_ebitda DESC;

-- Simulacoes e cenarios --------------------------------------------------
-- Pergunta: Se cada ativo subir 5 por cento qual sera o novo valor da carteira?
SELECT
    SUM(c.valor_investido * 1.05) AS valor_total_simulado
FROM Carteira AS c
WHERE c.carteira_definicao_id = 1;

-- Pergunta: Qual setor concentra a maior parcela da carteira?
WITH pesos_setor AS (
    SELECT
        s.nome AS setor_nome,
        SUM(c.peso) AS peso_total_setor
    FROM Carteira AS c
    JOIN Ativos AS a
        ON a.ativo_id = c.ativo_id
    LEFT JOIN Setores AS s
        ON s.setor_id = a.setor_id
    WHERE c.carteira_definicao_id = 1
    GROUP BY s.nome
)
SELECT TOP 1
    setor_nome,
    peso_total_setor
FROM pesos_setor
ORDER BY peso_total_setor DESC;

-- Pergunta: Qual o impacto de uma queda de 10 por cento no ativo mais pesado?
WITH maior_peso AS (
    SELECT TOP 1
        c.ativo_id,
        c.peso,
        c.valor_investido
    FROM Carteira AS c
    WHERE c.carteira_definicao_id = 1
    ORDER BY c.peso DESC
),
valor_total AS (
    SELECT SUM(valor_investido) AS valor_atual
    FROM Carteira
    WHERE carteira_definicao_id = 1
)
SELECT
    valor_total.valor_atual,
    valor_total.valor_atual - (maior_peso.valor_investido * 0.10) AS valor_pos_queda,
    ((valor_total.valor_atual - (maior_peso.valor_investido * 0.10)) / valor_total.valor_atual - 1.0) * 100.0 AS variacao_percentual
FROM maior_peso
CROSS JOIN valor_total;

-- Pergunta: Qual o retorno ao reinvestir os dividendos recebidos em janeiro de 2025?
WITH dividendos_totais AS (
    SELECT
        SUM(d.valor) AS total_dividendos
    FROM Dividendos AS d
    WHERE d.ativo_id IN (
        SELECT c.ativo_id
        FROM Carteira AS c
    WHERE c.carteira_definicao_id = 1
    )
    AND d.data_pagamento BETWEEN '2025-01-01' AND '2025-01-31'
),
valor_atual AS (
    SELECT SUM(valor_investido) AS valor_total
    FROM Carteira
    WHERE carteira_definicao_id = 1
)
SELECT
    valor_atual.valor_total AS valor_atual,
    valor_atual.valor_total + dividendos_totais.total_dividendos AS valor_reinvestido,
    ((valor_atual.valor_total + dividendos_totais.total_dividendos) / valor_atual.valor_total - 1.0) * 100.0 AS retorno_total_percent
FROM valor_atual
CROSS JOIN dividendos_totais;
