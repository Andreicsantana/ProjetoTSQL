USE TsqlProject;
GO

IF OBJECT_ID('dbo.usp_SincronizarAtivosSetores', 'P') IS NOT NULL
BEGIN
    DROP PROCEDURE dbo.usp_SincronizarAtivosSetores;
END;
GO

IF COL_LENGTH('dbo.Ativos', 'setor_id') IS NULL
BEGIN
    ALTER TABLE dbo.Ativos ADD setor_id INT NULL;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_SincronizarAtivosSetores
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF COL_LENGTH('dbo.Ativos', 'setor_id') IS NULL
    BEGIN
        RAISERROR ('Nao foi possivel adicionar a coluna setor_id em dbo.Ativos.', 16, 1);
        RETURN;
    END;

    DECLARE @HasSetorColumn BIT = CASE WHEN COL_LENGTH('dbo.Ativos', 'setor') IS NOT NULL THEN 1 ELSE 0 END;
    DECLARE @Unmatched INT = 0;

    DECLARE @HasForeignKey BIT = CASE
                                     WHEN EXISTS (
                                         SELECT 1
                                         FROM sys.foreign_keys
                                         WHERE name = 'fk_ativos_setores'
                                           AND parent_object_id = OBJECT_ID('dbo.Ativos')
                                     ) THEN 1 ELSE 0 END;

    BEGIN TRAN;
    BEGIN TRY
        IF @HasSetorColumn = 1
        BEGIN
            DECLARE @SqlUpdate NVARCHAR(MAX) = N'
                UPDATE a
                SET setor_id = st.setor_id
                FROM dbo.Ativos a
                LEFT JOIN dbo.Setores st
                    ON UPPER(LTRIM(RTRIM(a.setor))) = UPPER(LTRIM(RTRIM(st.nome)));
            ';
            EXEC sys.sp_executesql @SqlUpdate;

            SELECT @Unmatched = COUNT(*)
            FROM dbo.Ativos
            WHERE setor IS NOT NULL AND setor_id IS NULL;

            EXEC('ALTER TABLE dbo.Ativos DROP COLUMN setor');

            SET @HasSetorColumn = 0;
        END
        ELSE
        BEGIN
            SELECT @Unmatched = COUNT(*)
            FROM dbo.Ativos
            WHERE setor_id IS NULL;
        END;

        IF @HasForeignKey = 0
        BEGIN
            DECLARE @SqlFk NVARCHAR(MAX) = N'
                ALTER TABLE dbo.Ativos
                    WITH CHECK ADD CONSTRAINT fk_ativos_setores
                    FOREIGN KEY (setor_id) REFERENCES dbo.Setores(setor_id);

                ALTER TABLE dbo.Ativos
                    CHECK CONSTRAINT fk_ativos_setores;
            ';
            EXEC sys.sp_executesql @SqlFk;
        END;

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;

        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);
        RETURN;
    END CATCH;

    SELECT
        TotalAtivos = COUNT(*),
        Vinculados = SUM(CASE WHEN setor_id IS NOT NULL THEN 1 ELSE 0 END),
        SemCorrespondencia = @Unmatched
    FROM dbo.Ativos;
END;
GO
