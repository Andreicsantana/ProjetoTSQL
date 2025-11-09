USE TsqlProject;
GO

IF OBJECT_ID('dbo.usp_LoadGeneratedDataset', 'P') IS NOT NULL
BEGIN
    DROP PROCEDURE dbo.usp_LoadGeneratedDataset;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_LoadGeneratedDataset
    @BasePath NVARCHAR(4000) = N'/var/generated_dataset_utf8',
    @ForceLegacyCsv BIT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @BasePath IS NULL OR LTRIM(RTRIM(@BasePath)) = ''
    BEGIN
        RAISERROR('Base path cannot be null or empty.', 16, 1);
        RETURN;
    END;

    DECLARE @NormalizedBase NVARCHAR(4000) = LTRIM(RTRIM(@BasePath));

    WHILE LEN(@NormalizedBase) > 1 AND RIGHT(@NormalizedBase, 1) IN ('/', '\\')
    BEGIN
        SET @NormalizedBase = LEFT(@NormalizedBase, LEN(@NormalizedBase) - 1);
    END;

    IF @NormalizedBase = ''
    BEGIN
        SET @NormalizedBase = N'/';
    END;

    SET @NormalizedBase = REPLACE(@NormalizedBase, '\\', '/');

    DECLARE @AdHocEnabled INT = (
        SELECT CAST(value_in_use AS INT)
        FROM sys.configurations
        WHERE name = 'Ad Hoc Distributed Queries'
    );

    IF @AdHocEnabled IS NULL OR @AdHocEnabled = 0
    BEGIN
        RAISERROR('Ad Hoc Distributed Queries is disabled. Enable it with: EXEC sp_configure ''show advanced options'', 1; RECONFIGURE; EXEC sp_configure ''Ad Hoc Distributed Queries'', 1; RECONFIGURE;', 16, 1);
        RETURN;
    END;

    DECLARE @sql NVARCHAR(MAX);
    DECLARE @FilePath NVARCHAR(4000);
    DECLARE @MajorVersion INT = TRY_CONVERT(INT, SERVERPROPERTY('ProductMajorVersion'));
    DECLARE @SupportsCsvFormat BIT = CASE WHEN @ForceLegacyCsv = 1 THEN 0
                                  WHEN @ForceLegacyCsv = 0 THEN 1
                                  WHEN @MajorVersion IS NOT NULL AND @MajorVersion >= 16 THEN 1
                                  ELSE 0
                              END;
    DECLARE @CsvOptions NVARCHAR(200) = CASE WHEN @SupportsCsvFormat = 1
                                    THEN N'FORMAT=''CSV'', FIRSTROW=2'
                                    ELSE N'FIRSTROW=2, FIELDTERMINATOR='','', ROWTERMINATOR=''0x0a'''
                                END;
    DECLARE @Utf8CollationSuffix NVARCHAR(120) = CASE WHEN @SupportsCsvFormat = 1 THEN N'' ELSE N' COLLATE Latin1_General_100_CI_AI_SC_UTF8' END;

    IF @SupportsCsvFormat = 0 AND (@MajorVersion IS NULL OR @MajorVersion < 15)
    BEGIN
        RAISERROR('UTF-8 bulk loading is not supported on SQL Server versions prior to 2019 when running on Linux. Use @ForceLegacyCsv = 0 if FORMAT=''CSV'' is available or convert the files to UTF-16 before loading.', 16, 1);
        RETURN;
    END;

    DECLARE @Summary TABLE
    (
        TableName SYSNAME NOT NULL,
        RowsLoaded BIGINT NOT NULL
    );

    BEGIN TRAN;
    BEGIN TRY
        -- Setores
        SET @FilePath = REPLACE(@NormalizedBase + N'/Setores.csv', '''', '''''');
        SET @sql = N'SET IDENTITY_INSERT dbo.Setores ON;
BEGIN TRY
    INSERT INTO dbo.Setores (setor_id, nome)
    SELECT setor_id, CAST(nome AS NVARCHAR(100))
    FROM OPENROWSET(
            BULK ''' + @FilePath + N''',
            ' + @CsvOptions + N'
        ) WITH (
            setor_id INT,
            nome VARCHAR(100)' + @Utf8CollationSuffix + N'
        ) AS src;
END TRY
BEGIN CATCH
    SET IDENTITY_INSERT dbo.Setores OFF;
    THROW;
END CATCH;
SET IDENTITY_INSERT dbo.Setores OFF;';
        EXEC sys.sp_executesql @sql;

        DECLARE @maxSetorId INT = (SELECT ISNULL(MAX(setor_id), 0) FROM dbo.Setores);
        DBCC CHECKIDENT ('dbo.Setores', RESEED, @maxSetorId) WITH NO_INFOMSGS;
        IF NOT EXISTS (SELECT 1 FROM dbo.Setores)
        BEGIN
            RAISERROR('No rows were inserted into dbo.Setores.', 16, 1);
        END;
    INSERT INTO @Summary SELECT 'Setores', COUNT(*) FROM dbo.Setores;

        -- Empresas
        SET @FilePath = REPLACE(@NormalizedBase + N'/Empresas.csv', '''', '''''');
        SET @sql = N'SET IDENTITY_INSERT dbo.Empresas ON;
BEGIN TRY
    INSERT INTO dbo.Empresas (empresa_id, nome, cnpj, setor_id)
    SELECT empresa_id, CAST(nome AS NVARCHAR(200)), CAST(cnpj AS NVARCHAR(30)), setor_id
    FROM OPENROWSET(
            BULK ''' + @FilePath + N''',
            ' + @CsvOptions + N'
        ) WITH (
            empresa_id INT,
            nome VARCHAR(200)' + @Utf8CollationSuffix + N',
            cnpj VARCHAR(30)' + @Utf8CollationSuffix + N',
            setor_id INT
        ) AS src;
END TRY
BEGIN CATCH
    SET IDENTITY_INSERT dbo.Empresas OFF;
    THROW;
END CATCH;
SET IDENTITY_INSERT dbo.Empresas OFF;';
        EXEC sys.sp_executesql @sql;

        DECLARE @maxEmpresaId INT = (SELECT ISNULL(MAX(empresa_id), 0) FROM dbo.Empresas);
        DBCC CHECKIDENT ('dbo.Empresas', RESEED, @maxEmpresaId) WITH NO_INFOMSGS;
        IF NOT EXISTS (SELECT 1 FROM dbo.Empresas)
        BEGIN
            RAISERROR('No rows were inserted into dbo.Empresas.', 16, 1);
        END;
    INSERT INTO @Summary SELECT 'Empresas', COUNT(*) FROM dbo.Empresas;

        -- Ativos
        SET @FilePath = REPLACE(@NormalizedBase + N'/Ativos.csv', '''', '''''');
        SET @sql = N'SET IDENTITY_INSERT dbo.Ativos ON;
BEGIN TRY
    INSERT INTO dbo.Ativos (ativo_id, nome, setor_id, preco_atual)
    SELECT ativo_id,
           LEFT(CAST(nome AS NVARCHAR(200)), 100) AS nome,
           setor_id,
           preco_atual
    FROM OPENROWSET(
            BULK ''' + @FilePath + N''',
            ' + @CsvOptions + N'
        ) WITH (
            ativo_id INT,
            ticker VARCHAR(50)' + @Utf8CollationSuffix + N',
            nome VARCHAR(200)' + @Utf8CollationSuffix + N',
            setor_id INT,
            preco_atual DECIMAL(18,2)
        ) AS src;
END TRY
BEGIN CATCH
    SET IDENTITY_INSERT dbo.Ativos OFF;
    THROW;
END CATCH;
SET IDENTITY_INSERT dbo.Ativos OFF;';
        EXEC sys.sp_executesql @sql;

        DECLARE @maxAtivoId INT = (SELECT ISNULL(MAX(ativo_id), 0) FROM dbo.Ativos);
        DBCC CHECKIDENT ('dbo.Ativos', RESEED, @maxAtivoId) WITH NO_INFOMSGS;
        IF NOT EXISTS (SELECT 1 FROM dbo.Ativos)
        BEGIN
            RAISERROR('No rows were inserted into dbo.Ativos.', 16, 1);
        END;
    INSERT INTO @Summary SELECT 'Ativos', COUNT(*) FROM dbo.Ativos;

        -- Indicadores_Fundamentalistas
        SET @FilePath = REPLACE(@NormalizedBase + N'/Indicadores_Fundamentalistas.csv', '''', '''''');
        SET @sql = N'INSERT INTO dbo.Indicadores_Fundamentalistas (ativo_id, pl, roe, divida_ebitda)
    SELECT ativo_id, pl, roe, divida_ebitda
    FROM OPENROWSET(
            BULK ''' + @FilePath + N''',
            ' + @CsvOptions + N'
        ) WITH (
            ativo_id INT,
            pl DECIMAL(10,4),
            roe DECIMAL(10,4),
            divida_ebitda DECIMAL(10,4)
        ) AS src;';
        EXEC sys.sp_executesql @sql;

    INSERT INTO @Summary SELECT 'Indicadores_Fundamentalistas', COUNT(*) FROM dbo.Indicadores_Fundamentalistas;

        -- Dividend_Yield_Historico
        SET @FilePath = REPLACE(@NormalizedBase + N'/Dividend_Yield_Historico.csv', '''', '''''');
        SET @sql = N'INSERT INTO dbo.Dividend_Yield_Historico (ativo_id, ano, dy_percentual)
    SELECT ativo_id, ano, dy_percentual
    FROM OPENROWSET(
            BULK ''' + @FilePath + N''',
            ' + @CsvOptions + N'
        ) WITH (
            ativo_id INT,
            ano INT,
            dy_percentual DECIMAL(10,4)
        ) AS src;';
        EXEC sys.sp_executesql @sql;

    INSERT INTO @Summary SELECT 'Dividend_Yield_Historico', COUNT(*) FROM dbo.Dividend_Yield_Historico;

        -- Carteira_Definicao
        SET @FilePath = REPLACE(@NormalizedBase + N'/Carteira_Definicao.csv', '''', '''''');
        SET @sql = N'SET IDENTITY_INSERT dbo.Carteira_Definicao ON;
BEGIN TRY
    INSERT INTO dbo.Carteira_Definicao (carteira_definicao_id, nome, data_referencia, origem)
    SELECT carteira_definicao_id,
           LEFT(CAST(nome AS NVARCHAR(200)), 200),
           data_referencia,
           LEFT(CAST(origem AS NVARCHAR(100)), 100)
    FROM OPENROWSET(
            BULK ''' + @FilePath + N''',
            ' + @CsvOptions + N'
        ) WITH (
            carteira_definicao_id INT,
            nome VARCHAR(200)' + @Utf8CollationSuffix + N',
            data_referencia DATE,
            origem VARCHAR(100)' + @Utf8CollationSuffix + N'
        ) AS src;
END TRY
BEGIN CATCH
    SET IDENTITY_INSERT dbo.Carteira_Definicao OFF;
    THROW;
END CATCH;
SET IDENTITY_INSERT dbo.Carteira_Definicao OFF;';
        EXEC sys.sp_executesql @sql;

        DECLARE @maxCarteiraDefId INT = (SELECT ISNULL(MAX(carteira_definicao_id), 0) FROM dbo.Carteira_Definicao);
        DBCC CHECKIDENT ('dbo.Carteira_Definicao', RESEED, @maxCarteiraDefId) WITH NO_INFOMSGS;
    INSERT INTO @Summary SELECT 'Carteira_Definicao', COUNT(*) FROM dbo.Carteira_Definicao;

        -- Carteira
        SET @FilePath = REPLACE(@NormalizedBase + N'/Carteira.csv', '''', '''''');
        SET @sql = N'SET IDENTITY_INSERT dbo.Carteira ON;
BEGIN TRY
    INSERT INTO dbo.Carteira (carteira_id, carteira_definicao_id, ativo_id, quantidade_teorica, peso, valor_investido)
    SELECT carteira_id,
           carteira_definicao_id,
           ativo_id,
           quantidade_teorica,
           peso,
           valor_investido
    FROM OPENROWSET(
            BULK ''' + @FilePath + N''',
            ' + @CsvOptions + N'
        ) WITH (
            carteira_id INT,
            carteira_definicao_id INT,
            ativo_id INT,
            quantidade_teorica DECIMAL(18,4),
            peso DECIMAL(10,4),
            valor_investido DECIMAL(18,4)
        ) AS src;
END TRY
BEGIN CATCH
    SET IDENTITY_INSERT dbo.Carteira OFF;
    THROW;
END CATCH;
SET IDENTITY_INSERT dbo.Carteira OFF;';
        EXEC sys.sp_executesql @sql;

        DECLARE @maxCarteiraId INT = (SELECT ISNULL(MAX(carteira_id), 0) FROM dbo.Carteira);
        DBCC CHECKIDENT ('dbo.Carteira', RESEED, @maxCarteiraId) WITH NO_INFOMSGS;
    INSERT INTO @Summary SELECT 'Carteira', COUNT(*) FROM dbo.Carteira;

        -- Carteira_Historico
        SET @FilePath = REPLACE(@NormalizedBase + N'/Carteira_Historico.csv', '''', '''''');
        SET @sql = N'INSERT INTO dbo.Carteira_Historico (carteira_id, data, valor_total)
    SELECT carteira_id, data, valor_total
    FROM OPENROWSET(
            BULK ''' + @FilePath + N''',
            ' + @CsvOptions + N'
        ) WITH (
            carteira_id INT,
            data DATE,
            valor_total DECIMAL(18,4)
        ) AS src;';
        EXEC sys.sp_executesql @sql;

    INSERT INTO @Summary SELECT 'Carteira_Historico', COUNT(*) FROM dbo.Carteira_Historico;

        -- Transacoes
        SET @FilePath = REPLACE(@NormalizedBase + N'/Transacoes.csv', '''', '''''');
        SET @sql = N'SET IDENTITY_INSERT dbo.Transacoes ON;
BEGIN TRY
    INSERT INTO dbo.Transacoes (transacao_id, carteira_id, ativo_id, data, tipo, quantidade, preco)
    SELECT transacao_id,
           carteira_id,
           ativo_id,
           data,
           LEFT(CAST(tipo AS NVARCHAR(50)), 20),
           quantidade,
           preco
    FROM OPENROWSET(
            BULK ''' + @FilePath + N''',
            ' + @CsvOptions + N'
        ) WITH (
            transacao_id INT,
            carteira_id INT,
            ativo_id INT,
            data DATE,
            tipo VARCHAR(50)' + @Utf8CollationSuffix + N',
            quantidade DECIMAL(18,4),
            preco DECIMAL(18,4)
        ) AS src;
END TRY
BEGIN CATCH
    SET IDENTITY_INSERT dbo.Transacoes OFF;
    THROW;
END CATCH;
SET IDENTITY_INSERT dbo.Transacoes OFF;';
        EXEC sys.sp_executesql @sql;

        DECLARE @maxTransacaoId INT = (SELECT ISNULL(MAX(transacao_id), 0) FROM dbo.Transacoes);
        DBCC CHECKIDENT ('dbo.Transacoes', RESEED, @maxTransacaoId) WITH NO_INFOMSGS;
    INSERT INTO @Summary SELECT 'Transacoes', COUNT(*) FROM dbo.Transacoes;

        -- Desempenho_Historico
        SET @FilePath = REPLACE(@NormalizedBase + N'/Desempenho_Historico.csv', '''', '''''');
        SET @sql = N'INSERT INTO dbo.Desempenho_Historico (ativo_id, data, preco)
    SELECT ativo_id, data, preco
    FROM OPENROWSET(
            BULK ''' + @FilePath + N''',
            ' + @CsvOptions + N'
        ) WITH (
            ativo_id INT,
            data DATE,
            preco DECIMAL(18,4)
        ) AS src;';
        EXEC sys.sp_executesql @sql;

    INSERT INTO @Summary SELECT 'Desempenho_Historico', COUNT(*) FROM dbo.Desempenho_Historico;

        -- Cotacoes_Diarias
        SET @FilePath = REPLACE(@NormalizedBase + N'/Cotacoes_Diarias.csv', '''', '''''');
        SET @sql = N'INSERT INTO dbo.Cotacoes_Diarias (ativo_id, data, preco_abertura, preco_fechamento, volume)
    SELECT ativo_id, data, preco_abertura, preco_fechamento, volume
    FROM OPENROWSET(
            BULK ''' + @FilePath + N''',
            ' + @CsvOptions + N'
        ) WITH (
            ativo_id INT,
            data DATE,
            preco_abertura DECIMAL(18,4),
            preco_fechamento DECIMAL(18,4),
            volume DECIMAL(18,4)
        ) AS src;';
        EXEC sys.sp_executesql @sql;

    INSERT INTO @Summary SELECT 'Cotacoes_Diarias', COUNT(*) FROM dbo.Cotacoes_Diarias;

        -- Dividendos
        SET @FilePath = REPLACE(@NormalizedBase + N'/Dividendos.csv', '''', '''''');
        SET @sql = N'INSERT INTO dbo.Dividendos (ativo_id, data_pagamento, valor)
    SELECT ativo_id, data_pagamento, valor
    FROM OPENROWSET(
            BULK ''' + @FilePath + N''',
            ' + @CsvOptions + N'
        ) WITH (
            ativo_id INT,
            data_pagamento DATE,
            valor DECIMAL(18,4)
        ) AS src;';
        EXEC sys.sp_executesql @sql;

    INSERT INTO @Summary SELECT 'Dividendos', COUNT(*) FROM dbo.Dividendos;

        -- Proventos
        SET @FilePath = REPLACE(@NormalizedBase + N'/Proventos.csv', '''', '''''');
        SET @sql = N'INSERT INTO dbo.Proventos (ativo_id, data, tipo, valor)
        SELECT ativo_id, data, LEFT(CAST(tipo AS NVARCHAR(100)), 50), valor
    FROM OPENROWSET(
            BULK ''' + @FilePath + N''',
            ' + @CsvOptions + N'
        ) WITH (
            ativo_id INT,
            data DATE,
            tipo VARCHAR(100)' + @Utf8CollationSuffix + N',
            valor DECIMAL(18,4)
        ) AS src;';
        EXEC sys.sp_executesql @sql;

    INSERT INTO @Summary SELECT 'Proventos', COUNT(*) FROM dbo.Proventos;

        -- Benchmarks
        SET @FilePath = REPLACE(@NormalizedBase + N'/Benchmarks.csv', '''', '''''');
        SET @sql = N'SET IDENTITY_INSERT dbo.Benchmarks ON;
BEGIN TRY
    INSERT INTO dbo.Benchmarks (benchmark_id, nome, valor_atual)
    SELECT benchmark_id, LEFT(CAST(nome AS NVARCHAR(100)), 100), valor_atual
    FROM OPENROWSET(
            BULK ''' + @FilePath + N''',
            ' + @CsvOptions + N'
        ) WITH (
            benchmark_id INT,
            nome VARCHAR(100)' + @Utf8CollationSuffix + N',
            valor_atual DECIMAL(18,2)
        ) AS src;
END TRY
BEGIN CATCH
    SET IDENTITY_INSERT dbo.Benchmarks OFF;
    THROW;
END CATCH;
SET IDENTITY_INSERT dbo.Benchmarks OFF;';
        EXEC sys.sp_executesql @sql;

        DECLARE @maxBenchmarkId INT = (SELECT ISNULL(MAX(benchmark_id), 0) FROM dbo.Benchmarks);
        DBCC CHECKIDENT ('dbo.Benchmarks', RESEED, @maxBenchmarkId) WITH NO_INFOMSGS;
    INSERT INTO @Summary SELECT 'Benchmarks', COUNT(*) FROM dbo.Benchmarks;

        -- Comparativo_Benchmark
        SET @FilePath = REPLACE(@NormalizedBase + N'/Comparativo_Benchmark.csv', '''', '''''');
        SET @sql = N'INSERT INTO dbo.Comparativo_Benchmark (carteira_id, benchmark_id, data, retorno_carteira, retorno_benchmark)
    SELECT carteira_id, benchmark_id, data, retorno_carteira, retorno_benchmark
    FROM OPENROWSET(
            BULK ''' + @FilePath + N''',
            ' + @CsvOptions + N'
        ) WITH (
            carteira_id INT,
            benchmark_id INT,
            data DATE,
            retorno_carteira DECIMAL(10,6),
            retorno_benchmark DECIMAL(10,6)
        ) AS src;';
        EXEC sys.sp_executesql @sql;

    INSERT INTO @Summary SELECT 'Comparativo_Benchmark', COUNT(*) FROM dbo.Comparativo_Benchmark;

        -- Riscos
        SET @FilePath = REPLACE(@NormalizedBase + N'/Riscos.csv', '''', '''''');
        SET @sql = N'INSERT INTO dbo.Riscos (ativo_id, beta, volatilidade, var)
    SELECT ativo_id, beta, volatilidade, var
    FROM OPENROWSET(
            BULK ''' + @FilePath + N''',
            ' + @CsvOptions + N'
        ) WITH (
            ativo_id INT,
            beta DECIMAL(10,4),
            volatilidade DECIMAL(10,4),
            var DECIMAL(18,4)
        ) AS src;';
        EXEC sys.sp_executesql @sql;

    INSERT INTO @Summary SELECT 'Riscos', COUNT(*) FROM dbo.Riscos;

        -- Simulacoes
        SET @FilePath = REPLACE(@NormalizedBase + N'/Simulacoes.csv', '''', '''''');
        SET @sql = N'SET IDENTITY_INSERT dbo.Simulacoes ON;
BEGIN TRY
    INSERT INTO dbo.Simulacoes (simulacao_id, carteira_id, descricao, data_execucao)
    SELECT simulacao_id, carteira_id, LEFT(CAST(descricao AS NVARCHAR(255)), 255), data_execucao
    FROM OPENROWSET(
            BULK ''' + @FilePath + N''',
            ' + @CsvOptions + N'
        ) WITH (
            simulacao_id INT,
            carteira_id INT,
            descricao VARCHAR(255)' + @Utf8CollationSuffix + N',
            data_execucao DATE
        ) AS src;
END TRY
BEGIN CATCH
    SET IDENTITY_INSERT dbo.Simulacoes OFF;
    THROW;
END CATCH;
SET IDENTITY_INSERT dbo.Simulacoes OFF;';
        EXEC sys.sp_executesql @sql;

        DECLARE @maxSimulacaoId INT = (SELECT ISNULL(MAX(simulacao_id), 0) FROM dbo.Simulacoes);
        DBCC CHECKIDENT ('dbo.Simulacoes', RESEED, @maxSimulacaoId) WITH NO_INFOMSGS;
    INSERT INTO @Summary SELECT 'Simulacoes', COUNT(*) FROM dbo.Simulacoes;

        -- Simulacao_Resultados
        SET @FilePath = REPLACE(@NormalizedBase + N'/Simulacao_Resultados.csv', '''', '''''');
        SET @sql = N'INSERT INTO dbo.Simulacao_Resultados (simulacao_id, ativo_id, novo_valor, impacto_total)
    SELECT simulacao_id, ativo_id, novo_valor, impacto_total
    FROM OPENROWSET(
            BULK ''' + @FilePath + N''',
            ' + @CsvOptions + N'
        ) WITH (
            simulacao_id INT,
            ativo_id INT,
            novo_valor DECIMAL(18,4),
            impacto_total DECIMAL(18,4)
        ) AS src;';
        EXEC sys.sp_executesql @sql;

    INSERT INTO @Summary SELECT 'Simulacao_Resultados', COUNT(*) FROM dbo.Simulacao_Resultados;

        -- Alocacao_Setorial
        SET @FilePath = REPLACE(@NormalizedBase + N'/Alocacao_Setorial.csv', '''', '''''');
        SET @sql = N'INSERT INTO dbo.Alocacao_Setorial (carteira_id, setor_id, peso_setor)
    SELECT carteira_id, setor_id, peso_setor
    FROM OPENROWSET(
            BULK ''' + @FilePath + N''',
            ' + @CsvOptions + N'
        ) WITH (
            carteira_id INT,
            setor_id INT,
            peso_setor DECIMAL(5,2)
        ) AS src;';
        EXEC sys.sp_executesql @sql;

    INSERT INTO @Summary SELECT 'Alocacao_Setorial', COUNT(*) FROM dbo.Alocacao_Setorial;

        -- Alertas
        SET @FilePath = REPLACE(@NormalizedBase + N'/Alertas.csv', '''', '''''');
        SET @sql = N'SET IDENTITY_INSERT dbo.Alertas ON;
BEGIN TRY
    INSERT INTO dbo.Alertas (alerta_id, carteira_id, ativo_id, condicao, data_criacao)
    SELECT alerta_id, carteira_id, ativo_id, LEFT(CAST(condicao AS NVARCHAR(255)), 255), data_criacao
    FROM OPENROWSET(
            BULK ''' + @FilePath + N''',
            ' + @CsvOptions + N'
        ) WITH (
            alerta_id INT,
            carteira_id INT,
            ativo_id INT,
            condicao VARCHAR(255)' + @Utf8CollationSuffix + N',
            data_criacao DATE
        ) AS src;
END TRY
BEGIN CATCH
    SET IDENTITY_INSERT dbo.Alertas OFF;
    THROW;
END CATCH;
SET IDENTITY_INSERT dbo.Alertas OFF;';
        EXEC sys.sp_executesql @sql;

        DECLARE @maxAlertaId INT = (SELECT ISNULL(MAX(alerta_id), 0) FROM dbo.Alertas);
        DBCC CHECKIDENT ('dbo.Alertas', RESEED, @maxAlertaId) WITH NO_INFOMSGS;
    INSERT INTO @Summary SELECT 'Alertas', COUNT(*) FROM dbo.Alertas;

        -- Metas_Investimento
        SET @FilePath = REPLACE(@NormalizedBase + N'/Metas_Investimento.csv', '''', '''''');
        SET @sql = N'SET IDENTITY_INSERT dbo.Metas_Investimento ON;
BEGIN TRY
    INSERT INTO dbo.Metas_Investimento (meta_id, carteira_id, descricao, valor_alvo, prazo)
    SELECT meta_id, carteira_id, LEFT(CAST(descricao AS NVARCHAR(255)), 255), valor_alvo, prazo
    FROM OPENROWSET(
            BULK ''' + @FilePath + N''',
            ' + @CsvOptions + N'
        ) WITH (
            meta_id INT,
            carteira_id INT,
            descricao VARCHAR(255)' + @Utf8CollationSuffix + N',
            valor_alvo DECIMAL(18,4),
            prazo DATE
        ) AS src;
END TRY
BEGIN CATCH
    SET IDENTITY_INSERT dbo.Metas_Investimento OFF;
    THROW;
END CATCH;
SET IDENTITY_INSERT dbo.Metas_Investimento OFF;';
        EXEC sys.sp_executesql @sql;

        DECLARE @maxMetaId INT = (SELECT ISNULL(MAX(meta_id), 0) FROM dbo.Metas_Investimento);
        DBCC CHECKIDENT ('dbo.Metas_Investimento', RESEED, @maxMetaId) WITH NO_INFOMSGS;
    INSERT INTO @Summary SELECT 'Metas_Investimento', COUNT(*) FROM dbo.Metas_Investimento;

        -- Indicadores_Macroeconomicos
        SET @FilePath = REPLACE(@NormalizedBase + N'/Indicadores_Macroeconomicos.csv', '''', '''''');
        SET @sql = N'SET IDENTITY_INSERT dbo.Indicadores_Macroeconomicos ON;
BEGIN TRY
    INSERT INTO dbo.Indicadores_Macroeconomicos (indicador_id, nome, valor_atual, data_atualizacao)
    SELECT indicador_id, LEFT(CAST(nome AS NVARCHAR(100)), 100), valor_atual, data_atualizacao
    FROM OPENROWSET(
            BULK ''' + @FilePath + N''',
            ' + @CsvOptions + N'
        ) WITH (
            indicador_id INT,
            nome VARCHAR(100)' + @Utf8CollationSuffix + N',
            valor_atual DECIMAL(18,4),
            data_atualizacao DATE
        ) AS src;
END TRY
BEGIN CATCH
    SET IDENTITY_INSERT dbo.Indicadores_Macroeconomicos OFF;
    THROW;
END CATCH;
SET IDENTITY_INSERT dbo.Indicadores_Macroeconomicos OFF;';
        EXEC sys.sp_executesql @sql;

        DECLARE @maxIndicadorId INT = (SELECT ISNULL(MAX(indicador_id), 0) FROM dbo.Indicadores_Macroeconomicos);
        DBCC CHECKIDENT ('dbo.Indicadores_Macroeconomicos', RESEED, @maxIndicadorId) WITH NO_INFOMSGS;
    INSERT INTO @Summary SELECT 'Indicadores_Macroeconomicos', COUNT(*) FROM dbo.Indicadores_Macroeconomicos;

        -- Custos_Operacionais
        SET @FilePath = REPLACE(@NormalizedBase + N'/Custos_Operacionais.csv', '''', '''''');
        SET @sql = N'SET IDENTITY_INSERT dbo.Custos_Operacionais ON;
BEGIN TRY
    INSERT INTO dbo.Custos_Operacionais (custo_id, carteira_id, descricao, valor, data)
    SELECT custo_id, carteira_id, LEFT(CAST(descricao AS NVARCHAR(255)), 255), valor, data
    FROM OPENROWSET(
            BULK ''' + @FilePath + N''',
            ' + @CsvOptions + N'
        ) WITH (
            custo_id INT,
            carteira_id INT,
            descricao VARCHAR(255)' + @Utf8CollationSuffix + N',
            valor DECIMAL(18,4),
            data DATE
        ) AS src;
END TRY
BEGIN CATCH
    SET IDENTITY_INSERT dbo.Custos_Operacionais OFF;
    THROW;
END CATCH;
SET IDENTITY_INSERT dbo.Custos_Operacionais OFF;';
        EXEC sys.sp_executesql @sql;

        DECLARE @maxCustoId INT = (SELECT ISNULL(MAX(custo_id), 0) FROM dbo.Custos_Operacionais);
        DBCC CHECKIDENT ('dbo.Custos_Operacionais', RESEED, @maxCustoId) WITH NO_INFOMSGS;
    INSERT INTO @Summary SELECT 'Custos_Operacionais', COUNT(*) FROM dbo.Custos_Operacionais;

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;

        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
        RETURN;
    END CATCH;

    SELECT TableName, RowsLoaded
    FROM @Summary
    ORDER BY TableName;
END;
GO
