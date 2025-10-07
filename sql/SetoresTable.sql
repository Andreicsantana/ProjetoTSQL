USE TsqlProject;
GO

IF OBJECT_ID('Setores', 'U') IS NULL
BEGIN
    CREATE TABLE Setores (
        setor_id INT IDENTITY(1,1) PRIMARY KEY,
        nome NVARCHAR(100) NOT NULL
    );
END

IF OBJECT_ID('tempdb..#TempFundos') IS NOT NULL
    DROP TABLE #TempFundos;

CREATE TABLE #TempFundos (
    Ticker NVARCHAR(50),
    NomeDoFundo NVARCHAR(255),
    Administrador NVARCHAR(255),
    Segmento NVARCHAR(100),
    Setor NVARCHAR(100),
    DataInicio DATE,
    PatrimonioLiquido NVARCHAR(50),
    CNPJ NVARCHAR(20)
);

BULK INSERT #TempFundos
FROM '/var/opt/mssql/data/empresas.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    TABLOCK
);

IF OBJECT_ID('dbo.RemoveAcentos', 'FN') IS NOT NULL
    DROP FUNCTION dbo.RemoveAcentos;
GO

CREATE FUNCTION dbo.RemoveAcentos(@texto NVARCHAR(255))
RETURNS NVARCHAR(255)
AS
BEGIN
    DECLARE @res NVARCHAR(255) = @texto;

    SET @res = REPLACE(@res, 'á','a');
    SET @res = REPLACE(@res, 'à','a');
    SET @res = REPLACE(@res, 'ã','a');
    SET @res = REPLACE(@res, 'â','a');
    SET @res = REPLACE(@res, 'é','e');
    SET @res = REPLACE(@res, 'ê','e');
    SET @res = REPLACE(@res, 'í','i');
    SET @res = REPLACE(@res, 'ó','o');
    SET @res = REPLACE(@res, 'ô','o');
    SET @res = REPLACE(@res, 'õ','o');
    SET @res = REPLACE(@res, 'ú','u');
    SET @res = REPLACE(@res, 'ç','c');

    SET @res = REPLACE(@res, 'Á','A');
    SET @res = REPLACE(@res, 'À','A');
    SET @res = REPLACE(@res, 'Ã','A');
    SET @res = REPLACE(@res, 'Â','A');
    SET @res = REPLACE(@res, 'É','E');
    SET @res = REPLACE(@res, 'Ê','E');
    SET @res = REPLACE(@res, 'Í','I');
    SET @res = REPLACE(@res, 'Ó','O');
    SET @res = REPLACE(@res, 'Ô','O');
    SET @res = REPLACE(@res, 'Õ','O');
    SET @res = REPLACE(@res, 'Ú','U');
    SET @res = REPLACE(@res, 'Ç','C');

    SET @res = REPLACE(@res, '+º', 'o');
    SET @res = REPLACE(@res, '+¬', 'a');
    SET @res = REPLACE(@res, '+¡', 'i');
    SET @res = REPLACE(@res, '+¦', 'e');
    SET @res = REPLACE(@res, '+ú', 'o');
    SET @res = REPLACE(@res, '+í', 'i');
    SET @res = REPLACE(@res, '+ís', 'is');
    SET @res = REPLACE(@res, '?', '');

    RETURN @res;
END;
GO

INSERT INTO Setores (nome)
SELECT DISTINCT dbo.RemoveAcentos(LTRIM(RTRIM(Setor)))
FROM #TempFundos
WHERE Setor IS NOT NULL
  AND LTRIM(RTRIM(Setor)) <> '';

IF NOT EXISTS (
    SELECT * FROM sys.objects 
    WHERE object_id = OBJECT_ID(N'UQ_Setores_Nome') 
      AND type = 'UQ'
)
BEGIN
    ALTER TABLE Setores
    ADD CONSTRAINT UQ_Setores_Nome UNIQUE (nome);
END

SELECT * FROM Setores ORDER BY nome;