USE TsqlProject;
GO

CREATE OR ALTER PROCEDURE usp_ImportarDataset
    @DatasetType NVARCHAR(50),
    @FilePath NVARCHAR(4000),
    @CarteiraNome NVARCHAR(200) = NULL,
    @DataReferencia DATE = NULL,
    @TargetTicker NVARCHAR(50) = NULL,
    @Ano INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @FilePath IS NULL OR LTRIM(RTRIM(@FilePath)) = ''
    BEGIN
        RAISERROR('FilePath is required.', 16, 1);
        RETURN;
    END;

    DECLARE @path NVARCHAR(4000) = REPLACE(@FilePath, '''', '''''');
    DECLARE @sql NVARCHAR(MAX);

    BEGIN TRY
        IF @DatasetType = 'EMPRESAS'
        BEGIN
            IF OBJECT_ID('tempdb..#EmpresasStage') IS NOT NULL DROP TABLE #EmpresasStage;

            CREATE TABLE #EmpresasStage (
                Ticker NVARCHAR(50) NULL,
                NomeFundo NVARCHAR(200) NULL,
                Administrador NVARCHAR(200) NULL,
                Segmento NVARCHAR(200) NULL,
                Setor NVARCHAR(200) NULL,
                DataInicio NVARCHAR(30) NULL,
                Patrimonio NVARCHAR(50) NULL,
                CNPJ NVARCHAR(20) NULL
            );

            SET @sql = N'BULK INSERT #EmpresasStage
                         FROM ''' + @path + N'''
                         WITH (
                             FORMAT = ''CSV'',
                             FIRSTROW = 2,
                             TABLOCK
                         );';
            EXEC (@sql);

            INSERT INTO Setores (nome)
            SELECT DISTINCT s.setor
            FROM (
                SELECT LTRIM(RTRIM(REPLACE(Setor, CHAR(13), ''))) AS setor
                FROM #EmpresasStage
                WHERE LTRIM(RTRIM(REPLACE(Setor, CHAR(13), ''))) <> ''
            ) s
            WHERE NOT EXISTS (SELECT 1 FROM Setores st WHERE st.nome = s.setor);

            INSERT INTO Empresas (nome, cnpj, setor_id)
            SELECT e.nome,
                   NULLIF(e.cnpj, '') AS cnpj,
                   st.setor_id
            FROM (
                SELECT
                    LTRIM(RTRIM(REPLACE(NomeFundo, CHAR(13), ''))) AS nome,
                    LTRIM(RTRIM(REPLACE(CNPJ, CHAR(13), ''))) AS cnpj,
                    LTRIM(RTRIM(REPLACE(Setor, CHAR(13), ''))) AS setor
                FROM #EmpresasStage
                WHERE LTRIM(RTRIM(REPLACE(NomeFundo, CHAR(13), ''))) <> ''
            ) e
            INNER JOIN Setores st ON st.nome = e.setor
            WHERE NOT EXISTS (SELECT 1 FROM Empresas em WHERE em.nome = e.nome);

            INSERT INTO Ativos (nome, setor, preco_atual)
            SELECT a.ticker, a.setor, NULL
            FROM (
                SELECT DISTINCT
                    LTRIM(RTRIM(REPLACE(Ticker, CHAR(13), ''))) AS ticker,
                    LTRIM(RTRIM(REPLACE(Setor, CHAR(13), ''))) AS setor
                FROM #EmpresasStage
                WHERE LTRIM(RTRIM(REPLACE(Ticker, CHAR(13), ''))) <> ''
            ) a
            WHERE NOT EXISTS (SELECT 1 FROM Ativos atv WHERE atv.nome = a.ticker);

            UPDATE atv
            SET setor = src.setor
            FROM Ativos atv
            INNER JOIN (
                SELECT DISTINCT
                    LTRIM(RTRIM(REPLACE(Ticker, CHAR(13), ''))) AS ticker,
                    LTRIM(RTRIM(REPLACE(Setor, CHAR(13), ''))) AS setor
                FROM #EmpresasStage
                WHERE LTRIM(RTRIM(REPLACE(Ticker, CHAR(13), ''))) <> ''
                  AND LTRIM(RTRIM(REPLACE(Setor, CHAR(13), ''))) <> ''
            ) src ON src.ticker = atv.nome
            WHERE (atv.setor IS NULL OR atv.setor = '');

            RETURN;
        END;

        IF @DatasetType = 'ISEE_CARTEIRA'
        BEGIN
            IF @CarteiraNome IS NULL OR @DataReferencia IS NULL
            BEGIN
                RAISERROR('CarteiraNome and DataReferencia are required for ISEE_CARTEIRA.', 16, 1);
                RETURN;
            END;

            IF OBJECT_ID('tempdb..#CarteiraStage') IS NOT NULL DROP TABLE #CarteiraStage;

            CREATE TABLE #CarteiraStage (
                Codigo NVARCHAR(40) NULL,
                NomeAcao NVARCHAR(200) NULL,
                Tipo NVARCHAR(100) NULL,
                QtdeTeorica NVARCHAR(50) NULL,
                PartPercent NVARCHAR(50) NULL,
                Extra NVARCHAR(50) NULL
            );

            SET @sql = N'BULK INSERT #CarteiraStage
                         FROM ''' + @path + N'''
                         WITH (
                             FIRSTROW = 3,
                             FIELDTERMINATOR = '';'',
                             ROWTERMINATOR = ''0x0a'',
                             KEEPNULLS,
                             TABLOCK
                         );';
            EXEC (@sql);

            IF OBJECT_ID('tempdb..#CarteiraClean') IS NOT NULL DROP TABLE #CarteiraClean;

            CREATE TABLE #CarteiraClean (
                Codigo NVARCHAR(40) NOT NULL,
                NomeAcao NVARCHAR(200) NULL,
                QuantidadeTeorica DECIMAL(18,4) NULL,
                Peso DECIMAL(18,6) NULL
            );

            INSERT INTO #CarteiraClean (Codigo, NomeAcao, QuantidadeTeorica, Peso)
            SELECT
                LTRIM(RTRIM(REPLACE(Codigo, CHAR(13), ''))) AS Codigo,
                NULLIF(LTRIM(RTRIM(REPLACE(NomeAcao, CHAR(13), ''))), '') AS NomeAcao,
                TRY_CONVERT(DECIMAL(18,4),
                    NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(QtdeTeorica, CHAR(13), ''), '.', ''), ',', '.'), ' ', ''), '')
                ) AS QuantidadeTeorica,
                TRY_CONVERT(DECIMAL(18,6),
                    NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(PartPercent, CHAR(13), ''), '%', ''), '.', ''), ',', '.'), ' ', ''), '')
                ) / 100 AS Peso
            FROM #CarteiraStage
            WHERE Codigo IS NOT NULL
              AND LTRIM(RTRIM(REPLACE(Codigo, CHAR(13), ''))) <> ''
              AND Codigo NOT LIKE 'Quantidade%'
              AND Codigo NOT LIKE 'Redutor%'
              AND Codigo NOT LIKE 'ISEE%'
              AND Codigo NOT LIKE 'M%NIMO%';

            INSERT INTO Ativos (nome, setor, preco_atual)
            SELECT c.Codigo, NULL, NULL
            FROM #CarteiraClean c
            WHERE NOT EXISTS (SELECT 1 FROM Ativos a WHERE a.nome = c.Codigo);

            DECLARE @CarteiraDefId INT;

            SELECT @CarteiraDefId = carteira_definicao_id
            FROM Carteira_Definicao
            WHERE nome = @CarteiraNome
              AND data_referencia = @DataReferencia;

            IF @CarteiraDefId IS NULL
            BEGIN
                INSERT INTO Carteira_Definicao (nome, data_referencia, origem)
                VALUES (@CarteiraNome, @DataReferencia, 'ISEE');
                SET @CarteiraDefId = SCOPE_IDENTITY();
            END
            ELSE
            BEGIN
                DELETE FROM Carteira WHERE carteira_definicao_id = @CarteiraDefId;
            END;

            INSERT INTO Carteira (carteira_definicao_id, ativo_id, quantidade_teorica, peso, valor_investido)
            SELECT
                @CarteiraDefId,
                a.ativo_id,
                c.QuantidadeTeorica,
                c.Peso,
                NULL
            FROM #CarteiraClean c
            INNER JOIN Ativos a ON a.nome = c.Codigo;

            RETURN;
        END;

        IF @DatasetType = 'ISEE_EVOLUCAO_MENSAL'
        BEGIN
            IF OBJECT_ID('tempdb..#EvolucaoMensal') IS NOT NULL DROP TABLE #EvolucaoMensal;

            CREATE TABLE #EvolucaoMensal (
                Mes NVARCHAR(10) NULL,
                Ano NVARCHAR(10) NULL,
                Valor NVARCHAR(30) NULL
            );

            SET @sql = N'BULK INSERT #EvolucaoMensal
                         FROM ''' + @path + N'''
                         WITH (
                             FIRSTROW = 3,
                             FIELDTERMINATOR = '';'',
                             ROWTERMINATOR = ''0x0a'',
                             KEEPNULLS,
                             TABLOCK
                         );';
            EXEC (@sql);

            IF @TargetTicker IS NULL SET @TargetTicker = 'ISEE';

            IF NOT EXISTS (SELECT 1 FROM Ativos WHERE nome = @TargetTicker)
                INSERT INTO Ativos (nome, setor, preco_atual) VALUES (@TargetTicker, 'Indice', NULL);

            DECLARE @AtivoMensalId INT = (SELECT ativo_id FROM Ativos WHERE nome = @TargetTicker);

            IF OBJECT_ID('tempdb..#EvolucaoMensalClean') IS NOT NULL DROP TABLE #EvolucaoMensalClean;

            CREATE TABLE #EvolucaoMensalClean (
                DataRef DATE PRIMARY KEY,
                ValorNumerico DECIMAL(18,4)
            );

            INSERT INTO #EvolucaoMensalClean (DataRef, ValorNumerico)
            SELECT
                DATEFROMPARTS(AnoNumero, MesNumero, 1) AS DataRef,
                ValorNumerico
            FROM (
                SELECT
                    TRY_CONVERT(INT, Mes) AS MesNumero,
                    TRY_CONVERT(INT, Ano) AS AnoNumero,
                    TRY_CONVERT(DECIMAL(18,4),
                        NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(Valor, CHAR(13), ''), '.', ''), ',', '.'), ' ', ''), '')
                    ) AS ValorNumerico
                FROM #EvolucaoMensal
            ) s
            WHERE MesNumero BETWEEN 1 AND 12
              AND AnoNumero IS NOT NULL
              AND ValorNumerico IS NOT NULL;

            MERGE Desempenho_Historico AS tgt
            USING #EvolucaoMensalClean AS src
            ON tgt.ativo_id = @AtivoMensalId AND tgt.data = src.DataRef
            WHEN MATCHED THEN
                UPDATE SET tgt.preco = src.ValorNumerico
            WHEN NOT MATCHED THEN
                INSERT (ativo_id, data, preco)
                VALUES (@AtivoMensalId, src.DataRef, src.ValorNumerico);

            DECLARE @UltimoMensal DECIMAL(18,4) = (
                SELECT TOP (1) ValorNumerico FROM #EvolucaoMensalClean ORDER BY DataRef DESC
            );

            IF @UltimoMensal IS NOT NULL
            BEGIN
                UPDATE Ativos SET preco_atual = @UltimoMensal WHERE ativo_id = @AtivoMensalId;

                IF EXISTS (SELECT 1 FROM Benchmarks WHERE nome = @TargetTicker)
                    UPDATE Benchmarks SET valor_atual = @UltimoMensal WHERE nome = @TargetTicker;
                ELSE
                    INSERT INTO Benchmarks (nome, valor_atual) VALUES (@TargetTicker, @UltimoMensal);
            END;

            RETURN;
        END;

        IF @DatasetType = 'ISEE_EVOLUCAO_DIARIA'
        BEGIN
            IF @Ano IS NULL
            BEGIN
                RAISERROR('Ano is required for ISEE_EVOLUCAO_DIARIA.', 16, 1);
                RETURN;
            END;

            IF OBJECT_ID('tempdb..#EvolucaoDiaria') IS NOT NULL DROP TABLE #EvolucaoDiaria;

            CREATE TABLE #EvolucaoDiaria (
                Dia NVARCHAR(10) NULL,
                Jan NVARCHAR(20) NULL,
                Fev NVARCHAR(20) NULL,
                Mar NVARCHAR(20) NULL,
                Abr NVARCHAR(20) NULL,
                Mai NVARCHAR(20) NULL,
                Jun NVARCHAR(20) NULL,
                Jul NVARCHAR(20) NULL,
                Ago NVARCHAR(20) NULL,
                [Set] NVARCHAR(20) NULL,
                Out NVARCHAR(20) NULL,
                Nov NVARCHAR(20) NULL,
                Dez NVARCHAR(20) NULL
            );

            SET @sql = N'BULK INSERT #EvolucaoDiaria
                         FROM ''' + @path + N'''
                         WITH (
                             FIRSTROW = 3,
                             FIELDTERMINATOR = '';'',
                             ROWTERMINATOR = ''0x0a'',
                             KEEPNULLS,
                             TABLOCK
                         );';
            EXEC (@sql);

            IF @TargetTicker IS NULL SET @TargetTicker = 'ISEE';

            IF NOT EXISTS (SELECT 1 FROM Ativos WHERE nome = @TargetTicker)
                INSERT INTO Ativos (nome, setor, preco_atual) VALUES (@TargetTicker, 'Indice', NULL);

            DECLARE @AtivoDiarioId INT = (SELECT ativo_id FROM Ativos WHERE nome = @TargetTicker);

            IF OBJECT_ID('tempdb..#EvolucaoDiariaClean') IS NOT NULL DROP TABLE #EvolucaoDiariaClean;

            CREATE TABLE #EvolucaoDiariaClean (
                DataRef DATE PRIMARY KEY,
                ValorNumerico DECIMAL(18,4)
            );

            INSERT INTO #EvolucaoDiariaClean (DataRef, ValorNumerico)
            SELECT
                DATEFROMPARTS(@Ano, MesNumero, DiaNumero) AS DataRef,
                ValorNumerico
            FROM (
                SELECT
                    TRY_CONVERT(INT, Dia) AS DiaNumero,
                    CASE UPPER(MesAbrev)
                        WHEN 'JAN' THEN 1
                        WHEN 'FEV' THEN 2
                        WHEN 'MAR' THEN 3
                        WHEN 'ABR' THEN 4
                        WHEN 'MAI' THEN 5
                        WHEN 'JUN' THEN 6
                        WHEN 'JUL' THEN 7
                        WHEN 'AGO' THEN 8
                        WHEN 'SET' THEN 9
                        WHEN 'OUT' THEN 10
                        WHEN 'NOV' THEN 11
                        WHEN 'DEZ' THEN 12
                        ELSE NULL
                    END AS MesNumero,
                    TRY_CONVERT(DECIMAL(18,4),
                        NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(Valor, CHAR(13), ''), '.', ''), ',', '.'), ' ', ''), '')
                    ) AS ValorNumerico
                FROM (
                    SELECT *
                    FROM #EvolucaoDiaria
                    WHERE TRY_CONVERT(INT, Dia) IS NOT NULL
                ) src
                UNPIVOT (
                    Valor FOR MesAbrev IN (Jan, Fev, Mar, Abr, Mai, Jun, Jul, Ago, [Set], [Out], Nov, Dez)
                ) u
            ) prepared
            WHERE DiaNumero BETWEEN 1 AND 31
              AND MesNumero IS NOT NULL
              AND ValorNumerico IS NOT NULL;

            MERGE Cotacoes_Diarias AS tgt
            USING #EvolucaoDiariaClean AS src
            ON tgt.ativo_id = @AtivoDiarioId AND tgt.data = src.DataRef
            WHEN MATCHED THEN
                UPDATE SET tgt.preco_fechamento = src.ValorNumerico
            WHEN NOT MATCHED THEN
                INSERT (ativo_id, data, preco_abertura, preco_fechamento, volume)
                VALUES (@AtivoDiarioId, src.DataRef, NULL, src.ValorNumerico, NULL);

            DECLARE @UltimoDiario DECIMAL(18,4) = (
                SELECT TOP (1) ValorNumerico FROM #EvolucaoDiariaClean ORDER BY DataRef DESC
            );

            IF @UltimoDiario IS NOT NULL
            BEGIN
                UPDATE Ativos SET preco_atual = @UltimoDiario WHERE ativo_id = @AtivoDiarioId;

                IF EXISTS (SELECT 1 FROM Benchmarks WHERE nome = @TargetTicker)
                    UPDATE Benchmarks SET valor_atual = @UltimoDiario WHERE nome = @TargetTicker;
                ELSE
                    INSERT INTO Benchmarks (nome, valor_atual) VALUES (@TargetTicker, @UltimoDiario);
            END;

            RETURN;
        END;

        IF @DatasetType = 'ATIVO_HISTORICO'
        BEGIN
            IF @TargetTicker IS NULL
            BEGIN
                RAISERROR('TargetTicker is required for ATIVO_HISTORICO.', 16, 1);
                RETURN;
            END;

            IF OBJECT_ID('tempdb..#AtivoHistorico') IS NOT NULL DROP TABLE #AtivoHistorico;

            CREATE TABLE #AtivoHistorico (
                DataBruta NVARCHAR(20) NULL,
                Ultimo NVARCHAR(30) NULL,
                Abertura NVARCHAR(30) NULL,
                Maxima NVARCHAR(30) NULL,
                Minima NVARCHAR(30) NULL,
                Volume NVARCHAR(30) NULL,
                Variacao NVARCHAR(30) NULL
            );

            SET @sql = N'BULK INSERT #AtivoHistorico
                         FROM ''' + @path + N'''
                         WITH (
                             FORMAT = ''CSV'',
                             FIRSTROW = 2,
                             TABLOCK
                         );';
            EXEC (@sql);

            IF NOT EXISTS (SELECT 1 FROM Ativos WHERE nome = @TargetTicker)
                INSERT INTO Ativos (nome, setor, preco_atual) VALUES (@TargetTicker, NULL, NULL);

            DECLARE @AtivoHistId INT = (SELECT ativo_id FROM Ativos WHERE nome = @TargetTicker);

            IF OBJECT_ID('tempdb..#AtivoHistoricoClean') IS NOT NULL DROP TABLE #AtivoHistoricoClean;

            CREATE TABLE #AtivoHistoricoClean (
                DataRef DATE PRIMARY KEY,
                PrecoAbertura DECIMAL(18,4),
                PrecoFechamento DECIMAL(18,4),
                PrecoMaximo DECIMAL(18,4),
                PrecoMinimo DECIMAL(18,4),
                VolumeNumerico DECIMAL(18,4)
            );

            INSERT INTO #AtivoHistoricoClean (DataRef, PrecoAbertura, PrecoFechamento, PrecoMaximo, PrecoMinimo, VolumeNumerico)
            SELECT
                TRY_CONVERT(DATE, REPLACE(DataBruta, CHAR(13), ''), 104) AS DataRef,
                TRY_CONVERT(DECIMAL(18,4),
                    NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(Abertura, CHAR(13), ''), '.', ''), ',', '.'), ' ', ''), '')
                ) AS PrecoAbertura,
                TRY_CONVERT(DECIMAL(18,4),
                    NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(Ultimo, CHAR(13), ''), '.', ''), ',', '.'), ' ', ''), '')
                ) AS PrecoFechamento,
                TRY_CONVERT(DECIMAL(18,4),
                    NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(Maxima, CHAR(13), ''), '.', ''), ',', '.'), ' ', ''), '')
                ) AS PrecoMaximo,
                TRY_CONVERT(DECIMAL(18,4),
                    NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(Minima, CHAR(13), ''), '.', ''), ',', '.'), ' ', ''), '')
                ) AS PrecoMinimo,
                CASE
                    WHEN Volume IS NULL OR LTRIM(RTRIM(REPLACE(Volume, CHAR(13), ''))) = '' THEN NULL
                    WHEN RIGHT(LTRIM(RTRIM(REPLACE(Volume, CHAR(13), ''))), 1) IN ('K', 'M', 'B') THEN
                        TRY_CONVERT(DECIMAL(18,6),
                            NULLIF(REPLACE(REPLACE(REPLACE(LEFT(LTRIM(RTRIM(REPLACE(Volume, CHAR(13), ''))), LEN(LTRIM(RTRIM(REPLACE(Volume, CHAR(13), '')))) - 1), '.', ''), ',', '.'), ' ', ''), '')
                        ) * CASE RIGHT(LTRIM(RTRIM(REPLACE(Volume, CHAR(13), ''))), 1)
                                WHEN 'K' THEN 1000
                                WHEN 'M' THEN 1000000
                                WHEN 'B' THEN 1000000000
                            END
                    ELSE
                        TRY_CONVERT(DECIMAL(18,6),
                            NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(Volume, CHAR(13), ''), '.', ''), ',', '.'), ' ', ''), '')
                        )
                END AS VolumeNumerico
            FROM #AtivoHistorico
            WHERE TRY_CONVERT(DATE, REPLACE(DataBruta, CHAR(13), ''), 104) IS NOT NULL;

            MERGE Cotacoes_Diarias AS tgt
            USING #AtivoHistoricoClean AS src
            ON tgt.ativo_id = @AtivoHistId AND tgt.data = src.DataRef
            WHEN MATCHED THEN
                UPDATE SET
                    tgt.preco_abertura = src.PrecoAbertura,
                    tgt.preco_fechamento = src.PrecoFechamento,
                    tgt.volume = src.VolumeNumerico
            WHEN NOT MATCHED THEN
                INSERT (ativo_id, data, preco_abertura, preco_fechamento, volume)
                VALUES (@AtivoHistId, src.DataRef, src.PrecoAbertura, src.PrecoFechamento, src.VolumeNumerico);

            MERGE Desempenho_Historico AS tgt
            USING #AtivoHistoricoClean AS src
            ON tgt.ativo_id = @AtivoHistId AND tgt.data = src.DataRef
            WHEN MATCHED THEN
                UPDATE SET tgt.preco = src.PrecoFechamento
            WHEN NOT MATCHED THEN
                INSERT (ativo_id, data, preco)
                VALUES (@AtivoHistId, src.DataRef, src.PrecoFechamento);

            DECLARE @UltimoFechamento DECIMAL(18,4) = (
                SELECT TOP (1) PrecoFechamento FROM #AtivoHistoricoClean ORDER BY DataRef DESC
            );

            IF @UltimoFechamento IS NOT NULL
                UPDATE Ativos SET preco_atual = @UltimoFechamento WHERE ativo_id = @AtivoHistId;

            RETURN;
        END;

        IF @DatasetType = 'TAXA_CRESCIMENTO'
        BEGIN
            IF OBJECT_ID('tempdb..#TaxaCrescimento') IS NOT NULL DROP TABLE #TaxaCrescimento;

            CREATE TABLE #TaxaCrescimento (
                Ano NVARCHAR(10) NULL,
                C2015 NVARCHAR(20) NULL,
                C2016 NVARCHAR(20) NULL,
                C2017 NVARCHAR(20) NULL,
                C2018 NVARCHAR(20) NULL,
                C2019 NVARCHAR(20) NULL,
                C2020 NVARCHAR(20) NULL,
                C2021 NVARCHAR(20) NULL,
                C2022 NVARCHAR(20) NULL,
                C2023 NVARCHAR(20) NULL,
                C2024 NVARCHAR(20) NULL,
                Anual NVARCHAR(20) NULL
            );

            SET @sql = N'BULK INSERT #TaxaCrescimento
                         FROM ''' + @path + N'''
                         WITH (
                             FIRSTROW = 3,
                             FIELDTERMINATOR = '';'',
                             ROWTERMINATOR = ''0x0a'',
                             KEEPNULLS,
                             TABLOCK
                         );';
            EXEC (@sql);

            MERGE Indicadores_Macroeconomicos AS tgt
            USING (
                SELECT
                    CONCAT('ISEE Valor ', AnoNumero) AS nome,
                    ValorFinal AS valor_atual,
                    DATEFROMPARTS(AnoNumero, 12, 31) AS data_atualizacao
                FROM (
                    SELECT
                        TRY_CONVERT(INT, Ano) AS AnoNumero,
                        TRY_CONVERT(DECIMAL(18,4),
                            NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(Anual, CHAR(13), ''), '.', ''), ',', '.'), ' ', ''), '')
                        ) AS ValorFinal
                    FROM #TaxaCrescimento
                ) s
                WHERE AnoNumero IS NOT NULL
                  AND ValorFinal IS NOT NULL
            ) src
            ON tgt.nome = src.nome
            WHEN MATCHED THEN
                UPDATE SET tgt.valor_atual = src.valor_atual,
                           tgt.data_atualizacao = src.data_atualizacao
            WHEN NOT MATCHED THEN
                INSERT (nome, valor_atual, data_atualizacao)
                VALUES (src.nome, src.valor_atual, src.data_atualizacao);

            RETURN;
        END;

        IF @DatasetType = 'BENCHMARK_HISTORICO'
        BEGIN
            IF @TargetTicker IS NULL
            BEGIN
                RAISERROR('TargetTicker is required for BENCHMARK_HISTORICO.', 16, 1);
                RETURN;
            END;

            IF OBJECT_ID('tempdb..#BenchmarkStage') IS NOT NULL DROP TABLE #BenchmarkStage;

            CREATE TABLE #BenchmarkStage (
                DataRaw NVARCHAR(20) NULL,
                Ultimo NVARCHAR(30) NULL,
                Abertura NVARCHAR(30) NULL,
                Maxima NVARCHAR(30) NULL,
                Minima NVARCHAR(30) NULL,
                Volume NVARCHAR(30) NULL,
                Variacao NVARCHAR(30) NULL
            );

            SET @sql = N'BULK INSERT #BenchmarkStage
                         FROM ''' + @path + N'''
                         WITH (
                             FORMAT = ''CSV'',
                             FIRSTROW = 2,
                             TABLOCK
                         );';
            EXEC (@sql);

            IF NOT EXISTS (SELECT 1 FROM Ativos WHERE nome = @TargetTicker)
                INSERT INTO Ativos (nome, setor, preco_atual) VALUES (@TargetTicker, 'Benchmark', NULL);

            DECLARE @BenchmarkAtivoId INT = (SELECT ativo_id FROM Ativos WHERE nome = @TargetTicker);

            IF OBJECT_ID('tempdb..#BenchmarkClean') IS NOT NULL DROP TABLE #BenchmarkClean;

            CREATE TABLE #BenchmarkClean (
                DataRef DATE PRIMARY KEY,
                PrecoAbertura DECIMAL(18,4),
                PrecoFechamento DECIMAL(18,4),
                PrecoMaximo DECIMAL(18,4),
                PrecoMinimo DECIMAL(18,4),
                VolumeNumerico DECIMAL(18,6)
            );

            INSERT INTO #BenchmarkClean (DataRef, PrecoAbertura, PrecoFechamento, PrecoMaximo, PrecoMinimo, VolumeNumerico)
            SELECT
                TRY_CONVERT(DATE, REPLACE(DataRaw, CHAR(13), ''), 104) AS DataRef,
                TRY_CONVERT(DECIMAL(18,4),
                    NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(Abertura, CHAR(13), ''), '.', ''), ',', '.'), ' ', ''), '')
                ) AS PrecoAbertura,
                TRY_CONVERT(DECIMAL(18,4),
                    NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(Ultimo, CHAR(13), ''), '.', ''), ',', '.'), ' ', ''), '')
                ) AS PrecoFechamento,
                TRY_CONVERT(DECIMAL(18,4),
                    NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(Maxima, CHAR(13), ''), '.', ''), ',', '.'), ' ', ''), '')
                ) AS PrecoMaximo,
                TRY_CONVERT(DECIMAL(18,4),
                    NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(Minima, CHAR(13), ''), '.', ''), ',', '.'), ' ', ''), '')
                ) AS PrecoMinimo,
                CASE
                    WHEN Volume IS NULL OR LTRIM(RTRIM(REPLACE(Volume, CHAR(13), ''))) = '' THEN NULL
                    WHEN RIGHT(LTRIM(RTRIM(REPLACE(Volume, CHAR(13), ''))), 1) IN ('K', 'M', 'B') THEN
                        TRY_CONVERT(DECIMAL(18,6),
                            NULLIF(REPLACE(REPLACE(REPLACE(LEFT(LTRIM(RTRIM(REPLACE(Volume, CHAR(13), ''))), LEN(LTRIM(RTRIM(REPLACE(Volume, CHAR(13), '')))) - 1), '.', ''), ',', '.'), ' ', ''), '')
                        ) * CASE RIGHT(LTRIM(RTRIM(REPLACE(Volume, CHAR(13), ''))), 1)
                                WHEN 'K' THEN 1000
                                WHEN 'M' THEN 1000000
                                WHEN 'B' THEN 1000000000
                            END
                    ELSE
                        TRY_CONVERT(DECIMAL(18,6),
                            NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(Volume, CHAR(13), ''), '.', ''), ',', '.'), ' ', ''), '')
                        )
                END AS VolumeNumerico
            FROM #BenchmarkStage
            WHERE TRY_CONVERT(DATE, REPLACE(DataRaw, CHAR(13), ''), 104) IS NOT NULL;

            MERGE Cotacoes_Diarias AS tgt
            USING #BenchmarkClean AS src
            ON tgt.ativo_id = @BenchmarkAtivoId AND tgt.data = src.DataRef
            WHEN MATCHED THEN
                UPDATE SET
                    tgt.preco_abertura = src.PrecoAbertura,
                    tgt.preco_fechamento = src.PrecoFechamento,
                    tgt.volume = src.VolumeNumerico
            WHEN NOT MATCHED THEN
                INSERT (ativo_id, data, preco_abertura, preco_fechamento, volume)
                VALUES (@BenchmarkAtivoId, src.DataRef, src.PrecoAbertura, src.PrecoFechamento, src.VolumeNumerico);

            MERGE Desempenho_Historico AS tgt
            USING #BenchmarkClean AS src
            ON tgt.ativo_id = @BenchmarkAtivoId AND tgt.data = src.DataRef
            WHEN MATCHED THEN
                UPDATE SET tgt.preco = src.PrecoFechamento
            WHEN NOT MATCHED THEN
                INSERT (ativo_id, data, preco)
                VALUES (@BenchmarkAtivoId, src.DataRef, src.PrecoFechamento);

            DECLARE @BenchmarkUltimo DECIMAL(18,4) = (
                SELECT TOP (1) PrecoFechamento FROM #BenchmarkClean ORDER BY DataRef DESC
            );

            IF @BenchmarkUltimo IS NOT NULL
            BEGIN
                UPDATE Ativos SET preco_atual = @BenchmarkUltimo WHERE ativo_id = @BenchmarkAtivoId;

                IF EXISTS (SELECT 1 FROM Benchmarks WHERE nome = @TargetTicker)
                    UPDATE Benchmarks SET valor_atual = @BenchmarkUltimo WHERE nome = @TargetTicker;
                ELSE
                    INSERT INTO Benchmarks (nome, valor_atual) VALUES (@TargetTicker, @BenchmarkUltimo);
            END;

            RETURN;
        END;

        IF @DatasetType = 'COTAHIST_MULTI'
        BEGIN
            IF OBJECT_ID('tempdb..#CotahistStage') IS NOT NULL DROP TABLE #CotahistStage;

            CREATE TABLE #CotahistStage (
                DataRaw NVARCHAR(20) NULL,
                Codigo NVARCHAR(40) NULL,
                NomeAtivo NVARCHAR(200) NULL,
                PrecoAbertura NVARCHAR(30) NULL,
                PrecoMaximo NVARCHAR(30) NULL,
                PrecoMinimo NVARCHAR(30) NULL,
                PrecoMedio NVARCHAR(30) NULL,
                PrecoFechamento NVARCHAR(30) NULL,
                Volume NVARCHAR(40) NULL
            );

            SET @sql = N'BULK INSERT #CotahistStage
                         FROM ''' + @path + N'''
                         WITH (
                             FORMAT = ''CSV'',
                             FIRSTROW = 2,
                             TABLOCK
                         );';
            EXEC (@sql);

            IF OBJECT_ID('tempdb..#CotahistClean') IS NOT NULL DROP TABLE #CotahistClean;

            CREATE TABLE #CotahistClean (
                Codigo NVARCHAR(40) NOT NULL,
                DataRef DATE NOT NULL,
                PrecoAbertura DECIMAL(18,4) NULL,
                PrecoFechamento DECIMAL(18,4) NULL,
                PrecoMaximo DECIMAL(18,4) NULL,
                PrecoMinimo DECIMAL(18,4) NULL,
                VolumeNumerico DECIMAL(18,4) NULL,
                PRIMARY KEY (Codigo, DataRef)
            );

            INSERT INTO #CotahistClean (Codigo, DataRef, PrecoAbertura, PrecoFechamento, PrecoMaximo, PrecoMinimo, VolumeNumerico)
            SELECT
                LTRIM(RTRIM(REPLACE(Codigo, CHAR(13), ''))),
                TRY_CONVERT(DATE, REPLACE(DataRaw, CHAR(13), ''), 112),
                TRY_CONVERT(DECIMAL(18,4),
                    NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(PrecoAbertura, CHAR(13), ''), '.', ''), ',', '.'), ' ', ''), '')
                ),
                TRY_CONVERT(DECIMAL(18,4),
                    NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(PrecoFechamento, CHAR(13), ''), '.', ''), ',', '.'), ' ', ''), '')
                ),
                TRY_CONVERT(DECIMAL(18,4),
                    NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(PrecoMaximo, CHAR(13), ''), '.', ''), ',', '.'), ' ', ''), '')
                ),
                TRY_CONVERT(DECIMAL(18,4),
                    NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(PrecoMinimo, CHAR(13), ''), '.', ''), ',', '.'), ' ', ''), '')
                ),
                TRY_CONVERT(DECIMAL(18,4),
                    NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(Volume, CHAR(13), ''), '.', ''), ',', '.'), ' ', ''), '')
                )
            FROM #CotahistStage
            WHERE TRY_CONVERT(DATE, REPLACE(DataRaw, CHAR(13), ''), 112) IS NOT NULL
              AND LTRIM(RTRIM(REPLACE(Codigo, CHAR(13), ''))) <> '';

            INSERT INTO Ativos (nome, setor, preco_atual)
            SELECT DISTINCT Codigo, NULL, NULL
            FROM #CotahistClean src
            WHERE NOT EXISTS (SELECT 1 FROM Ativos a WHERE a.nome = src.Codigo);

            MERGE Cotacoes_Diarias AS tgt
            USING (
                SELECT a.ativo_id, c.DataRef, c.PrecoAbertura, c.PrecoFechamento, c.VolumeNumerico
                FROM #CotahistClean c
                INNER JOIN Ativos a ON a.nome = c.Codigo
            ) AS src
            ON tgt.ativo_id = src.ativo_id AND tgt.data = src.DataRef
            WHEN MATCHED THEN
                UPDATE SET
                    tgt.preco_abertura = COALESCE(src.PrecoAbertura, tgt.preco_abertura),
                    tgt.preco_fechamento = COALESCE(src.PrecoFechamento, tgt.preco_fechamento),
                    tgt.volume = COALESCE(src.VolumeNumerico, tgt.volume)
            WHEN NOT MATCHED THEN
                INSERT (ativo_id, data, preco_abertura, preco_fechamento, volume)
                VALUES (src.ativo_id, src.DataRef, src.PrecoAbertura, src.PrecoFechamento, src.VolumeNumerico);

            MERGE Desempenho_Historico AS tgt
            USING (
                SELECT a.ativo_id, c.DataRef, c.PrecoFechamento
                FROM #CotahistClean c
                INNER JOIN Ativos a ON a.nome = c.Codigo
                WHERE c.PrecoFechamento IS NOT NULL
            ) AS src
            ON tgt.ativo_id = src.ativo_id AND tgt.data = src.DataRef
            WHEN MATCHED THEN
                UPDATE SET tgt.preco = src.PrecoFechamento
            WHEN NOT MATCHED THEN
                INSERT (ativo_id, data, preco)
                VALUES (src.ativo_id, src.DataRef, src.PrecoFechamento);

            UPDATE a
            SET a.preco_atual = s.PrecoFechamento
            FROM Ativos a
            INNER JOIN (
                SELECT c.Codigo, c.PrecoFechamento
                FROM #CotahistClean c
                INNER JOIN (
                    SELECT Codigo, MAX(DataRef) AS UltimaData
                    FROM #CotahistClean
                    GROUP BY Codigo
                ) ult ON ult.Codigo = c.Codigo AND ult.UltimaData = c.DataRef
            ) s ON s.Codigo = a.nome
            WHERE s.PrecoFechamento IS NOT NULL;

            RETURN;
        END;

        IF @DatasetType = 'IPCA_MENSAL'
        BEGIN
            IF OBJECT_ID('tempdb..#IpcaStage') IS NOT NULL DROP TABLE #IpcaStage;

            CREATE TABLE #IpcaStage (
                Periodo NVARCHAR(50) NULL,
                Valor NVARCHAR(30) NULL
            );

            SET @sql = N'BULK INSERT #IpcaStage
                         FROM ''' + @path + N'''
                         WITH (
                             FORMAT = ''CSV'',
                             FIRSTROW = 2,
                             TABLOCK
                         );';
            EXEC (@sql);

            MERGE Indicadores_Macroeconomicos AS tgt
            USING (
                SELECT
                    CONCAT('IPCA ', CONVERT(CHAR(7), DATEFROMPARTS(AnoNumero, MesNumero, 1), 126)) AS nome,
                    ValorNumerico AS valor_atual,
                    DATEFROMPARTS(AnoNumero, MesNumero, 1) AS data_atualizacao
                FROM (
                    SELECT
                        CASE UPPER(LEFT(PeriodoTrim, CHARINDEX(' ', PeriodoTrim + ' ') - 1))
                            WHEN 'JAN' THEN 1
                            WHEN 'FEV' THEN 2
                            WHEN 'MAR' THEN 3
                            WHEN 'ABR' THEN 4
                            WHEN 'MAI' THEN 5
                            WHEN 'JUN' THEN 6
                            WHEN 'JUL' THEN 7
                            WHEN 'AGO' THEN 8
                            WHEN 'SET' THEN 9
                            WHEN 'OUT' THEN 10
                            WHEN 'NOV' THEN 11
                            WHEN 'DEZ' THEN 12
                            ELSE NULL
                        END AS MesNumero,
                        TRY_CONVERT(INT, RIGHT(PeriodoTrim, 4)) AS AnoNumero,
                        TRY_CONVERT(DECIMAL(18,4),
                            NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(Valor, CHAR(13), ''), '.', ''), ',', '.'), ' ', ''), '')
                        ) AS ValorNumerico
                    FROM (
                        SELECT
                            LTRIM(RTRIM(REPLACE(Periodo, CHAR(13), ''))) AS PeriodoTrim,
                            Valor
                        FROM #IpcaStage
                    ) raw
                ) dados
                WHERE MesNumero BETWEEN 1 AND 12
                  AND AnoNumero IS NOT NULL
                  AND ValorNumerico IS NOT NULL
            ) AS src
            ON tgt.nome = src.nome
            WHEN MATCHED THEN
                UPDATE SET tgt.valor_atual = src.valor_atual,
                           tgt.data_atualizacao = src.data_atualizacao
            WHEN NOT MATCHED THEN
                INSERT (nome, valor_atual, data_atualizacao)
                VALUES (src.nome, src.valor_atual, src.data_atualizacao);

            RETURN;
        END;

        IF @DatasetType = 'PIB_PER_CAPITA'
        BEGIN
            IF OBJECT_ID('tempdb..#PibPerCapitaStage') IS NOT NULL DROP TABLE #PibPerCapitaStage;

            CREATE TABLE #PibPerCapitaStage (
                Periodo NVARCHAR(10) NULL,
                Valor NVARCHAR(30) NULL
            );

            SET @sql = N'BULK INSERT #PibPerCapitaStage
                         FROM ''' + @path + N'''
                         WITH (
                             FORMAT = ''CSV'',
                             FIRSTROW = 2,
                             TABLOCK
                         );';
            EXEC (@sql);

            MERGE Indicadores_Macroeconomicos AS tgt
            USING (
                SELECT
                    CONCAT('PIB Per Capita ', AnoNumero) AS nome,
                    ValorNumerico AS valor_atual,
                    DATEFROMPARTS(AnoNumero, 12, 31) AS data_atualizacao
                FROM (
                    SELECT
                        TRY_CONVERT(INT, LTRIM(RTRIM(REPLACE(Periodo, CHAR(13), '')))) AS AnoNumero,
                        TRY_CONVERT(DECIMAL(18,4),
                            NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(Valor, CHAR(13), ''), '.', ''), ',', '.'), ' ', ''), '')
                        ) AS ValorNumerico
                    FROM #PibPerCapitaStage
                ) dados
                WHERE AnoNumero IS NOT NULL
                  AND ValorNumerico IS NOT NULL
            ) AS src
            ON tgt.nome = src.nome
            WHEN MATCHED THEN
                UPDATE SET tgt.valor_atual = src.valor_atual,
                           tgt.data_atualizacao = src.data_atualizacao
            WHEN NOT MATCHED THEN
                INSERT (nome, valor_atual, data_atualizacao)
                VALUES (src.nome, src.valor_atual, src.data_atualizacao);

            RETURN;
        END;

        IF @DatasetType = 'PIB_VARIACAO_TRIMESTRAL'
        BEGIN
            IF OBJECT_ID('tempdb..#PibTrimestralStage') IS NOT NULL DROP TABLE #PibTrimestralStage;

            CREATE TABLE #PibTrimestralStage (
                Periodo NVARCHAR(30) NULL,
                Valor NVARCHAR(30) NULL
            );

            SET @sql = N'BULK INSERT #PibTrimestralStage
                         FROM ''' + @path + N'''
                         WITH (
                             FORMAT = ''CSV'',
                             FIRSTROW = 2,
                             TABLOCK
                         );';
            EXEC (@sql);

            MERGE Indicadores_Macroeconomicos AS tgt
            USING (
                SELECT
                    CONCAT('PIB Variacao ', AnoNumero, 'Q', TrimestreNumero) AS nome,
                    ValorNumerico AS valor_atual,
                    DATEFROMPARTS(AnoNumero, ((TrimestreNumero - 1) * 3) + 1, 1) AS data_atualizacao
                FROM (
                    SELECT
                        TRY_CONVERT(INT, LEFT(PeriodoLimpo, CHARINDEX(' ', PeriodoLimpo + ' ') - 1)) AS TrimestreNumero,
                        TRY_CONVERT(INT, RIGHT(PeriodoLimpo, 4)) AS AnoNumero,
                        TRY_CONVERT(DECIMAL(18,4),
                            NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(Valor, CHAR(13), ''), '.', ''), ',', '.'), ' ', ''), '')
                        ) AS ValorNumerico
                    FROM (
                        SELECT
                            LTRIM(RTRIM(REPLACE(REPLACE(Periodo, CHAR(13), ''), NCHAR(186), ''))) AS PeriodoLimpo,
                            Valor
                        FROM #PibTrimestralStage
                    ) base
                ) dados
                WHERE TrimestreNumero BETWEEN 1 AND 4
                  AND AnoNumero IS NOT NULL
                  AND ValorNumerico IS NOT NULL
            ) AS src
            ON tgt.nome = src.nome
            WHEN MATCHED THEN
                UPDATE SET tgt.valor_atual = src.valor_atual,
                           tgt.data_atualizacao = src.data_atualizacao
            WHEN NOT MATCHED THEN
                INSERT (nome, valor_atual, data_atualizacao)
                VALUES (src.nome, src.valor_atual, src.data_atualizacao);

            RETURN;
        END;

        IF @DatasetType = 'SELIC_META'
        BEGIN
            IF OBJECT_ID('tempdb..#SelicStage') IS NOT NULL DROP TABLE #SelicStage;

            CREATE TABLE #SelicStage (
                DataRaw NVARCHAR(30) NULL,
                Valor NVARCHAR(30) NULL
            );

            SET @sql = N'BULK INSERT #SelicStage
                         FROM ''' + @path + N'''
                         WITH (
                             FIELDTERMINATOR = '';'',
                             ROWTERMINATOR = ''0x0a'',
                             FIRSTROW = 2,
                             TABLOCK
                         );';
            EXEC (@sql);

            MERGE Indicadores_Macroeconomicos AS tgt
            USING (
                SELECT
                    CONCAT('Selic Meta ', CONVERT(CHAR(10), DataRef, 126)) AS nome,
                    ValorNumerico AS valor_atual,
                    DataRef AS data_atualizacao
                FROM (
                    SELECT
                        TRY_CONVERT(DATE, REPLACE(DataRaw, '"', ''), 120) AS DataRef,
                        TRY_CONVERT(DECIMAL(18,4),
                            NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(Valor, '"', ''), CHAR(13), ''), '.', ''), ',', '.'), ' ', ''), '')
                        ) AS ValorNumerico
                    FROM #SelicStage
                ) dados
                WHERE DataRef IS NOT NULL
                  AND ValorNumerico IS NOT NULL
            ) AS src
            ON tgt.nome = src.nome
            WHEN MATCHED THEN
                UPDATE SET tgt.valor_atual = src.valor_atual,
                           tgt.data_atualizacao = src.data_atualizacao
            WHEN NOT MATCHED THEN
                INSERT (nome, valor_atual, data_atualizacao)
                VALUES (src.nome, src.valor_atual, src.data_atualizacao);

            RETURN;
        END;

        IF @DatasetType = 'VOLATILIDADE_MENSAL'
        BEGIN
            IF OBJECT_ID('tempdb..#VolatilidadeStage') IS NOT NULL DROP TABLE #VolatilidadeStage;

            CREATE TABLE #VolatilidadeStage (
                Mes NVARCHAR(10) NULL,
                Ano NVARCHAR(10) NULL,
                Valor NVARCHAR(30) NULL
            );

            SET @sql = N'BULK INSERT #VolatilidadeStage
                         FROM ''' + @path + N'''
                         WITH (
                             FIELDTERMINATOR = '';'',
                             ROWTERMINATOR = ''0x0a'',
                             FIRSTROW = 4,
                             TABLOCK
                         );';
            EXEC (@sql);

            MERGE Indicadores_Macroeconomicos AS tgt
            USING (
                SELECT
                    CONCAT('Volatilidade ISEE ', CONVERT(CHAR(7), DATEFROMPARTS(AnoNumero, MesNumero, 1), 126)) AS nome,
                    ValorNumerico AS valor_atual,
                    DATEFROMPARTS(AnoNumero, MesNumero, 1) AS data_atualizacao
                FROM (
                    SELECT
                        TRY_CONVERT(INT, Mes) AS MesNumero,
                        TRY_CONVERT(INT, Ano) AS AnoNumero,
                        TRY_CONVERT(DECIMAL(18,4),
                            NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(Valor, CHAR(13), ''), '.', ''), ',', '.'), ' ', ''), '')
                        ) AS ValorNumerico
                    FROM #VolatilidadeStage
                ) dados
                WHERE MesNumero BETWEEN 1 AND 12
                  AND AnoNumero IS NOT NULL
                  AND ValorNumerico IS NOT NULL
            ) AS src
            ON tgt.nome = src.nome
            WHEN MATCHED THEN
                UPDATE SET tgt.valor_atual = src.valor_atual,
                           tgt.data_atualizacao = src.data_atualizacao
            WHEN NOT MATCHED THEN
                INSERT (nome, valor_atual, data_atualizacao)
                VALUES (src.nome, src.valor_atual, src.data_atualizacao);

            RETURN;
        END;

        RAISERROR('DatasetType %s is not supported.', 16, 1, @DatasetType);
    END TRY
    BEGIN CATCH
        DECLARE @err NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @severity INT = ERROR_SEVERITY();
        DECLARE @state INT = ERROR_STATE();
        RAISERROR(@err, @severity, @state);
    END CATCH;
END;
GO
