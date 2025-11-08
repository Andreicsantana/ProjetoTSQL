USE TsqlProject;
GO

IF OBJECT_ID('dbo.usp_ImportCarteiraCompleta', 'P') IS NOT NULL
BEGIN
    DROP PROCEDURE dbo.usp_ImportCarteiraCompleta;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_ImportCarteiraCompleta
    @FilePath NVARCHAR(4000),
    @SnapshotLabel NVARCHAR(100) = NULL,
    @SnapshotDate DATE = NULL,
    @DividendYieldYear INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @FilePath IS NULL OR LTRIM(RTRIM(@FilePath)) = ''
    BEGIN
        RAISERROR ('File path cannot be null or empty.', 16, 1);
        RETURN;
    END;

    DECLARE @EffectiveLabel NVARCHAR(100) = ISNULL(@SnapshotLabel, CONCAT('Carteira ', CONVERT(CHAR(8), SYSUTCDATETIME(), 112)));
    DECLARE @EffectiveDate DATE = ISNULL(@SnapshotDate, CAST(SYSUTCDATETIME() AS DATE));
    DECLARE @EffectiveYear INT = ISNULL(@DividendYieldYear, YEAR(@EffectiveDate));

    DECLARE @NormalizedFilePath NVARCHAR(4000) = REPLACE(@FilePath, '/', '\');

    IF OBJECT_ID('dbo.Carteira_Indicadores', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.Carteira_Indicadores
        (
            ativo_id INT PRIMARY KEY,
            categoria NVARCHAR(20) NOT NULL,
            nome NVARCHAR(200) NULL,
            cnpj NVARCHAR(20) NULL,
            setor NVARCHAR(200) NULL,
            preco_atual DECIMAL(18,4) NULL,
            pl DECIMAL(18,4) NULL,
            p_vp DECIMAL(18,4) NULL,
            roe DECIMAL(18,4) NULL,
            divida_ebitda DECIMAL(18,4) NULL,
            dividend_yield DECIMAL(18,4) NULL,
            proventos_mensal DECIMAL(18,6) NULL,
            dividend_yield_historico DECIMAL(18,4) NULL,
            fonte_preco NVARCHAR(100) NULL,
            fonte_pl NVARCHAR(100) NULL,
            fonte_p_vp NVARCHAR(100) NULL,
            fonte_roe NVARCHAR(100) NULL,
            fonte_divida_ebitda NVARCHAR(100) NULL,
            fonte_dividend_yield NVARCHAR(100) NULL,
            fonte_proventos NVARCHAR(100) NULL,
            snapshot_label NVARCHAR(100) NULL,
            snapshot_date DATE NULL,
            ultima_atualizacao DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME()
        );
    END;

    IF OBJECT_ID('tempdb..#CarteiraRaw') IS NOT NULL DROP TABLE #CarteiraRaw;

    CREATE TABLE #CarteiraRaw
    (
        categoria NVARCHAR(50) NULL,
        codigo_ativo NVARCHAR(50) NULL,
        nome NVARCHAR(255) NULL,
        cnpj NVARCHAR(30) NULL,
        setor NVARCHAR(255) NULL,
        preco_atual NVARCHAR(50) NULL,
        pl NVARCHAR(50) NULL,
        p_vp NVARCHAR(50) NULL,
        roe NVARCHAR(50) NULL,
        divida_ebitda NVARCHAR(50) NULL,
        dividend_yield NVARCHAR(50) NULL,
        proventos_mensal NVARCHAR(50) NULL,
        dividend_yield_historico NVARCHAR(50) NULL,
        fonte_preco NVARCHAR(100) NULL,
        fonte_pl NVARCHAR(100) NULL,
        fonte_p_vp NVARCHAR(100) NULL,
        fonte_roe NVARCHAR(100) NULL,
        fonte_divida_ebitda NVARCHAR(100) NULL,
        fonte_dividend_yield NVARCHAR(100) NULL,
        fonte_proventos NVARCHAR(100) NULL
    );

    DECLARE @HostPlatform NVARCHAR(32) = (SELECT TOP (1) host_platform FROM sys.dm_os_host_info);
    DECLARE @MajorVersion INT = TRY_CONVERT(INT, SERVERPROPERTY('ProductMajorVersion'));
    DECLARE @SupportsCsvFormat BIT = CASE WHEN @MajorVersion IS NOT NULL AND @MajorVersion >= 16 THEN 1 ELSE 0 END;
    DECLARE @BulkOptions NVARCHAR(MAX);

    IF @SupportsCsvFormat = 1
    BEGIN
        SET @BulkOptions = 'FORMAT = ''CSV'', FIRSTROW = 2, FIELDQUOTE = ''"'', ROWTERMINATOR = ''0x0a'', TABLOCK';
    END
    ELSE
    BEGIN
        SET @BulkOptions = 'FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'', TABLOCK';
    END;

    IF @HostPlatform = 'Windows'
        SET @BulkOptions = @BulkOptions + ', CODEPAGE = ''65001''';

    DECLARE @BulkSql NVARCHAR(MAX) = N'BULK INSERT #CarteiraRaw
        FROM ''' + REPLACE(@NormalizedFilePath, '''', '''''') + N'''
        WITH (' + @BulkOptions + ');';

    EXEC sys.sp_executesql @BulkSql;

    IF NOT EXISTS (SELECT 1 FROM #CarteiraRaw)
    BEGIN
        RAISERROR ('The CSV file did not return any rows.', 16, 1);
        RETURN;
    END;

    ;WITH Normalized AS
    (
        SELECT
            categoria = UPPER(NULLIF(LTRIM(RTRIM(categoria)), '')),
            codigo_ativo = UPPER(NULLIF(LTRIM(RTRIM(codigo_ativo)), '')),
            nome = NULLIF(LTRIM(RTRIM(nome)), ''),
            cnpj = NULLIF(LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(cnpj, '.', ''), '-', ''), '/', ''))), ''),
            setor = NULLIF(LTRIM(RTRIM(setor)), ''),
            preco_atual = TRY_CONVERT(DECIMAL(18,4), NULLIF(REPLACE(REPLACE(REPLACE(preco_atual, 'R$', ''), '%', ''), ',', '.'), '')),
            pl = TRY_CONVERT(DECIMAL(18,4), NULLIF(REPLACE(REPLACE(pl, '%', ''), ',', '.'), '')),
            p_vp = TRY_CONVERT(DECIMAL(18,4), NULLIF(REPLACE(REPLACE(p_vp, '%', ''), ',', '.'), '')),
            roe = TRY_CONVERT(DECIMAL(18,4), NULLIF(REPLACE(REPLACE(roe, '%', ''), ',', '.'), '')),
            divida_ebitda = TRY_CONVERT(DECIMAL(18,4), NULLIF(REPLACE(REPLACE(divida_ebitda, '%', ''), ',', '.'), '')),
            dividend_yield = TRY_CONVERT(DECIMAL(18,4), NULLIF(REPLACE(REPLACE(dividend_yield, '%', ''), ',', '.'), '')),
            proventos_mensal = TRY_CONVERT(DECIMAL(18,6), NULLIF(REPLACE(REPLACE(proventos_mensal, '%', ''), ',', '.'), '')),
            dividend_yield_historico = TRY_CONVERT(DECIMAL(18,4), NULLIF(REPLACE(REPLACE(dividend_yield_historico, '%', ''), ',', '.'), '')),
            fonte_preco = NULLIF(LTRIM(RTRIM(fonte_preco)), ''),
            fonte_pl = NULLIF(LTRIM(RTRIM(fonte_pl)), ''),
            fonte_p_vp = NULLIF(LTRIM(RTRIM(fonte_p_vp)), ''),
            fonte_roe = NULLIF(LTRIM(RTRIM(fonte_roe)), ''),
            fonte_divida_ebitda = NULLIF(LTRIM(RTRIM(fonte_divida_ebitda)), ''),
            fonte_dividend_yield = NULLIF(LTRIM(RTRIM(fonte_dividend_yield)), ''),
            fonte_proventos = NULLIF(LTRIM(RTRIM(fonte_proventos)), '')
        FROM #CarteiraRaw
    ),
    Filtered AS
    (
        SELECT
            categoria = ISNULL(categoria, 'DESCONHECIDO'),
            codigo_ativo,
            nome,
            cnpj,
            setor,
            preco_atual,
            pl,
            p_vp,
            roe,
            divida_ebitda,
            dividend_yield,
            proventos_mensal,
            dividend_yield_historico,
            fonte_preco,
            fonte_pl,
            fonte_p_vp,
            fonte_roe,
            fonte_divida_ebitda,
            fonte_dividend_yield,
            fonte_proventos
        FROM Normalized
        WHERE codigo_ativo IS NOT NULL
    )
    SELECT * INTO #CarteiraClean FROM Filtered;

    IF NOT EXISTS (SELECT 1 FROM #CarteiraClean)
    BEGIN
        RAISERROR ('No valid asset codes were found in the CSV.', 16, 1);
        RETURN;
    END;

    BEGIN TRAN;
    BEGIN TRY
        INSERT INTO Setores (nome)
        SELECT DISTINCT c.setor
        FROM #CarteiraClean c
        WHERE c.setor IS NOT NULL
          AND NOT EXISTS (
                SELECT 1
                FROM Setores st
                WHERE st.nome = c.setor
            );

        IF OBJECT_ID('tempdb..#EmpresaFonte') IS NOT NULL DROP TABLE #EmpresaFonte;

        SELECT
            nome,
            cnpj,
            setor_id,
            rn
        INTO #EmpresaFonte
        FROM (
            SELECT
                c.nome,
                c.cnpj,
                st.setor_id,
                ROW_NUMBER() OVER (PARTITION BY COALESCE(c.cnpj, c.nome) ORDER BY (SELECT 0)) AS rn
            FROM #CarteiraClean c
            LEFT JOIN Setores st ON st.nome = c.setor
            WHERE c.nome IS NOT NULL
        ) AS ef;

        INSERT INTO Empresas (nome, cnpj, setor_id)
        SELECT ef.nome, ef.cnpj, ef.setor_id
        FROM #EmpresaFonte ef
        WHERE ef.rn = 1
          AND ef.setor_id IS NOT NULL
          AND NOT EXISTS (
                SELECT 1
                FROM Empresas em
                WHERE (ef.cnpj IS NOT NULL AND em.cnpj = ef.cnpj)
                   OR em.nome = ef.nome
            );

        UPDATE em
        SET em.nome = COALESCE(ef.nome, em.nome),
            em.setor_id = COALESCE(ef.setor_id, em.setor_id)
        FROM Empresas em
        INNER JOIN #EmpresaFonte ef
            ON (
                ef.rn = 1
                AND (
                    (ef.cnpj IS NOT NULL AND em.cnpj = ef.cnpj)
                    OR (ef.cnpj IS NULL AND em.nome = ef.nome)
                )
            )
        WHERE ef.setor_id IS NOT NULL;

        MERGE Ativos AS tgt
        USING (
            SELECT DISTINCT
                c.codigo_ativo,
                st.setor_id,
                c.preco_atual
            FROM #CarteiraClean c
            LEFT JOIN Setores st ON st.nome = c.setor
        ) AS src
        ON tgt.nome = src.codigo_ativo
        WHEN MATCHED THEN
            UPDATE SET
                tgt.setor_id = COALESCE(src.setor_id, tgt.setor_id),
                tgt.preco_atual = CASE WHEN src.preco_atual IS NOT NULL THEN src.preco_atual ELSE tgt.preco_atual END
        WHEN NOT MATCHED THEN
            INSERT (nome, setor_id, preco_atual)
            VALUES (src.codigo_ativo, src.setor_id, src.preco_atual);

        MERGE Indicadores_Fundamentalistas AS tgt
        USING (
            SELECT
                a.ativo_id,
                c.pl,
                c.roe,
                c.divida_ebitda
            FROM #CarteiraClean c
            INNER JOIN Ativos a ON a.nome = c.codigo_ativo
        ) AS src
        ON tgt.ativo_id = src.ativo_id
        WHEN MATCHED THEN
            UPDATE SET
                pl = COALESCE(src.pl, tgt.pl),
                roe = COALESCE(src.roe, tgt.roe),
                divida_ebitda = COALESCE(src.divida_ebitda, tgt.divida_ebitda)
        WHEN NOT MATCHED THEN
            INSERT (ativo_id, pl, roe, divida_ebitda)
            VALUES (src.ativo_id, src.pl, src.roe, src.divida_ebitda);

        MERGE Dividend_Yield_Historico AS tgt
        USING (
            SELECT
                a.ativo_id,
                ano = @EffectiveYear,
                dy_percentual = c.dividend_yield_historico
            FROM #CarteiraClean c
            INNER JOIN Ativos a ON a.nome = c.codigo_ativo
            WHERE c.dividend_yield_historico IS NOT NULL
        ) AS src
        ON tgt.ativo_id = src.ativo_id AND tgt.ano = src.ano
        WHEN MATCHED THEN
            UPDATE SET tgt.dy_percentual = src.dy_percentual
        WHEN NOT MATCHED THEN
            INSERT (ativo_id, ano, dy_percentual)
            VALUES (src.ativo_id, src.ano, src.dy_percentual);

        MERGE dbo.Carteira_Indicadores AS tgt
        USING (
            SELECT
                a.ativo_id,
                c.categoria,
                c.nome,
                c.cnpj,
                c.setor,
                c.preco_atual,
                c.pl,
                c.p_vp,
                c.roe,
                c.divida_ebitda,
                c.dividend_yield,
                c.proventos_mensal,
                c.dividend_yield_historico,
                c.fonte_preco,
                c.fonte_pl,
                c.fonte_p_vp,
                c.fonte_roe,
                c.fonte_divida_ebitda,
                c.fonte_dividend_yield,
                c.fonte_proventos
            FROM #CarteiraClean c
            INNER JOIN Ativos a ON a.nome = c.codigo_ativo
        ) AS src
        ON tgt.ativo_id = src.ativo_id
        WHEN MATCHED THEN
            UPDATE SET
                categoria = src.categoria,
                nome = COALESCE(src.nome, tgt.nome),
                cnpj = COALESCE(src.cnpj, tgt.cnpj),
                setor = COALESCE(src.setor, tgt.setor),
                preco_atual = COALESCE(src.preco_atual, tgt.preco_atual),
                pl = COALESCE(src.pl, tgt.pl),
                p_vp = COALESCE(src.p_vp, tgt.p_vp),
                roe = COALESCE(src.roe, tgt.roe),
                divida_ebitda = COALESCE(src.divida_ebitda, tgt.divida_ebitda),
                dividend_yield = COALESCE(src.dividend_yield, tgt.dividend_yield),
                proventos_mensal = COALESCE(src.proventos_mensal, tgt.proventos_mensal),
                dividend_yield_historico = COALESCE(src.dividend_yield_historico, tgt.dividend_yield_historico),
                fonte_preco = COALESCE(src.fonte_preco, tgt.fonte_preco),
                fonte_pl = COALESCE(src.fonte_pl, tgt.fonte_pl),
                fonte_p_vp = COALESCE(src.fonte_p_vp, tgt.fonte_p_vp),
                fonte_roe = COALESCE(src.fonte_roe, tgt.fonte_roe),
                fonte_divida_ebitda = COALESCE(src.fonte_divida_ebitda, tgt.fonte_divida_ebitda),
                fonte_dividend_yield = COALESCE(src.fonte_dividend_yield, tgt.fonte_dividend_yield),
                fonte_proventos = COALESCE(src.fonte_proventos, tgt.fonte_proventos),
                snapshot_label = @EffectiveLabel,
                snapshot_date = @EffectiveDate,
                ultima_atualizacao = SYSUTCDATETIME()
        WHEN NOT MATCHED THEN
            INSERT (
                ativo_id, categoria, nome, cnpj, setor, preco_atual, pl, p_vp, roe,
                divida_ebitda, dividend_yield, proventos_mensal, dividend_yield_historico,
                fonte_preco, fonte_pl, fonte_p_vp, fonte_roe, fonte_divida_ebitda,
                fonte_dividend_yield, fonte_proventos, snapshot_label, snapshot_date
            )
            VALUES (
                src.ativo_id, src.categoria, src.nome, src.cnpj, src.setor, src.preco_atual,
                src.pl, src.p_vp, src.roe, src.divida_ebitda, src.dividend_yield,
                src.proventos_mensal, src.dividend_yield_historico,
                src.fonte_preco, src.fonte_pl, src.fonte_p_vp, src.fonte_roe,
                src.fonte_divida_ebitda, src.fonte_dividend_yield, src.fonte_proventos,
                @EffectiveLabel, @EffectiveDate
            );

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;

        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);
    END CATCH;

    SELECT
        SnapshotLabel = @EffectiveLabel,
        SnapshotDate = @EffectiveDate,
        TotalAtivos = (SELECT COUNT(*) FROM #CarteiraClean);
END;
GO
