USE TsqlProject;
GO

    
  -- recebe os dados da simulação --
	
CREATE OR ALTER PROCEDURE usp_SimularInvestimento
	@AtivoId INT,
	@CarteiraDefinicaoId INT,
	@ValorInvestido DECIMAL(18,2),
	@DataOperacao DATE = NULL,
	@TipoTransacao NVARCHAR(20) = 'APORTE'
AS
BEGIN
	SET NOCOUNT ON;

   --validação dos parâmetros--

	IF @AtivoId IS NULL OR @AtivoId <= 0
	BEGIN
		RAISERROR('AtivoId invalido.', 16, 1);
		RETURN;
	END;

	IF @CarteiraDefinicaoId IS NULL OR @CarteiraDefinicaoId <= 0
	BEGIN
		RAISERROR('CarteiraDefinicaoId invalido.', 16, 1);
		RETURN;
	END;

	IF @ValorInvestido IS NULL OR @ValorInvestido <= 0
	BEGIN
		RAISERROR('ValorInvestido deve ser maior que zero.', 16, 1);
		RETURN;
	END;

    --define a data da operação--

	SET @DataOperacao = COALESCE(@DataOperacao, CAST(GETDATE() AS DATE));

   -- verifica ou cria a carteira --  

	DECLARE @CarteiraId INT;
	SELECT @CarteiraId = c.carteira_id
	FROM Carteira c
	WHERE c.ativo_id = @AtivoId
	  AND c.carteira_definicao_id = @CarteiraDefinicaoId;

	IF @CarteiraId IS NULL
	BEGIN
		INSERT INTO Carteira (carteira_definicao_id, ativo_id, quantidade_teorica, peso, valor_investido)
		VALUES (@CarteiraDefinicaoId, @AtivoId, NULL, NULL, @ValorInvestido);
		SET @CarteiraId = SCOPE_IDENTITY();
	END;

   -- busca o preço do ativo --

	DECLARE @PrecoAbertura DECIMAL(18,4);
	DECLARE @PrecoFechamento DECIMAL(18,4);
	SELECT TOP (1)
		@PrecoAbertura = COALESCE(preco_abertura, preco_fechamento),
		@PrecoFechamento = COALESCE(preco_fechamento, preco_abertura)
	FROM Cotacoes_Diarias
	WHERE ativo_id = @AtivoId
	ORDER BY data DESC;

	IF @PrecoFechamento IS NULL
		SELECT @PrecoFechamento = preco_atual FROM Ativos WHERE ativo_id = @AtivoId;

	IF @PrecoAbertura IS NULL SET @PrecoAbertura = @PrecoFechamento;

   -- quantidade comprada --

	DECLARE @Quantidade DECIMAL(18,4) = CASE WHEN @PrecoFechamento IS NOT NULL AND @PrecoFechamento > 0
											  THEN @ValorInvestido / @PrecoFechamento ELSE NULL END;
   -- registra a transação --

	INSERT INTO Transacoes (carteira_id, ativo_id, data, tipo, quantidade, preco)
	VALUES (@CarteiraId, @AtivoId, @DataOperacao, @TipoTransacao, @Quantidade, @ValorInvestido);

   -- atualiza o valor --

	DECLARE @TotalCarteira DECIMAL(18,2);
	SELECT @TotalCarteira = SUM(preco)
	FROM Transacoes
	WHERE carteira_id = @CarteiraId;

	UPDATE Carteira
	SET valor_investido = @TotalCarteira
	WHERE carteira_id = @CarteiraId;

	MERGE Carteira_Historico AS tgt
	USING (SELECT @CarteiraId AS carteira_id, @DataOperacao AS data, @TotalCarteira AS valor_total) AS src
	ON tgt.carteira_id = src.carteira_id AND tgt.data = src.data
	WHEN MATCHED THEN
		UPDATE SET valor_total = src.valor_total
	WHEN NOT MATCHED THEN
		INSERT (carteira_id, data, valor_total)
		VALUES (src.carteira_id, src.data, src.valor_total);
    
   -- calcula variação do ativo --

	DECLARE @Variacao DECIMAL(18,4);
	IF @PrecoAbertura IS NOT NULL AND @PrecoAbertura > 0 AND @PrecoFechamento IS NOT NULL
		SET @Variacao = ((@PrecoFechamento - @PrecoAbertura) / @PrecoAbertura) * 100;

	DECLARE @LimiteAlta DECIMAL(18,4) = 5.0;
	DECLARE @LimiteBaixa DECIMAL(18,4) = -5.0;

   -- gera alertas e riscos --

	IF @Variacao IS NOT NULL
	BEGIN
		IF @Variacao >= @LimiteAlta
		BEGIN
			INSERT INTO Alertas (carteira_id, ativo_id, condicao, data_criacao)
			VALUES (@CarteiraId, @AtivoId, CONCAT('Alta variacao: ', FORMAT(@Variacao, 'N2'), '%'), @DataOperacao);

			DECLARE @Beta DECIMAL(10,2) = ROUND(@Variacao / 10.0, 2);
			DECLARE @Volatilidade DECIMAL(10,2) = ROUND(ABS(@Variacao), 2);
			DECLARE @VaR DECIMAL(18,2) = ROUND(@ValorInvestido * ABS(@Variacao) / 100.0, 2);

			MERGE Riscos AS tgt
			USING (SELECT @AtivoId AS ativo_id, @Beta AS beta, @Volatilidade AS volatilidade, @VaR AS var) AS src
			ON tgt.ativo_id = src.ativo_id
			WHEN MATCHED THEN
				UPDATE SET beta = src.beta, volatilidade = src.volatilidade, var = src.var
			WHEN NOT MATCHED THEN
				INSERT (ativo_id, beta, volatilidade, var)
				VALUES (src.ativo_id, src.beta, src.volatilidade, src.var);
		END
		ELSE IF @Variacao <= @LimiteBaixa
		BEGIN
			INSERT INTO Alertas (carteira_id, ativo_id, condicao, data_criacao)
			VALUES (@CarteiraId, @AtivoId, CONCAT('Baixa variacao: ', FORMAT(@Variacao, 'N2'), '%'), @DataOperacao);
		END;
	END;

   -- calcula retorno da carteira --

	DECLARE @ValorAnterior DECIMAL(18,2);
	SELECT TOP (1) @ValorAnterior = valor_total
	FROM Carteira_Historico
	WHERE carteira_id = @CarteiraId AND data < @DataOperacao
	ORDER BY data DESC;

	DECLARE @RetornoCarteira DECIMAL(10,2);
	IF @ValorAnterior IS NOT NULL AND @ValorAnterior > 0
		SET @RetornoCarteira = ROUND(((@TotalCarteira - @ValorAnterior) / @ValorAnterior) * 100, 2);
	ELSE IF @Variacao IS NOT NULL
		SET @RetornoCarteira = ROUND(@Variacao, 2);

   -- compara com benchmarks --

	DECLARE @Benchmarks TABLE (Nome NVARCHAR(100));
	INSERT INTO @Benchmarks (Nome) VALUES ('ISEE'), ('BVSP');

	DECLARE @BenchmarkNome NVARCHAR(100);
	DECLARE BenchCursor CURSOR FAST_FORWARD FOR SELECT Nome FROM @Benchmarks;
	OPEN BenchCursor;
	FETCH NEXT FROM BenchCursor INTO @BenchmarkNome;
	WHILE @@FETCH_STATUS = 0
	BEGIN
		DECLARE @BenchmarkId INT;
		SELECT @BenchmarkId = benchmark_id FROM Benchmarks WHERE nome = @BenchmarkNome;

		DECLARE @BenchmarkAtivoId INT;
		SELECT @BenchmarkAtivoId = ativo_id FROM Ativos WHERE nome = @BenchmarkNome;

		DECLARE @RetornoBenchmark DECIMAL(10,2);
		IF @BenchmarkAtivoId IS NOT NULL
		BEGIN
			DECLARE @BenchAber DECIMAL(18,4);
			DECLARE @BenchFech DECIMAL(18,4);
			SELECT TOP (1)
				@BenchAber = COALESCE(preco_abertura, preco_fechamento),
				@BenchFech = COALESCE(preco_fechamento, preco_abertura)
			FROM Cotacoes_Diarias
			WHERE ativo_id = @BenchmarkAtivoId
			ORDER BY data DESC;

			IF @BenchFech IS NULL
				SELECT @BenchFech = valor_atual FROM Benchmarks WHERE benchmark_id = @BenchmarkId;

			IF @BenchAber IS NULL SET @BenchAber = @BenchFech;

			IF @BenchAber IS NOT NULL AND @BenchAber > 0 AND @BenchFech IS NOT NULL
				SET @RetornoBenchmark = ROUND(((@BenchFech - @BenchAber) / @BenchAber) * 100, 2);
		END;

		IF @BenchmarkId IS NOT NULL AND @RetornoCarteira IS NOT NULL AND @RetornoBenchmark IS NOT NULL
		BEGIN
			MERGE Comparativo_Benchmark AS tgt
			USING (
				SELECT @CarteiraId AS carteira_id,
					   @BenchmarkId AS benchmark_id,
					   @DataOperacao AS data,
					   @RetornoCarteira AS retorno_carteira,
					   @RetornoBenchmark AS retorno_benchmark
			) AS src
			ON tgt.carteira_id = src.carteira_id AND tgt.benchmark_id = src.benchmark_id AND tgt.data = src.data
			WHEN MATCHED THEN
				UPDATE SET retorno_carteira = src.retorno_carteira,
						   retorno_benchmark = src.retorno_benchmark
			WHEN NOT MATCHED THEN
				INSERT (carteira_id, benchmark_id, data, retorno_carteira, retorno_benchmark)
				VALUES (src.carteira_id, src.benchmark_id, src.data, src.retorno_carteira, src.retorno_benchmark);
		END;

		FETCH NEXT FROM BenchCursor INTO @BenchmarkNome;
	END;
	CLOSE BenchCursor;
	DEALLOCATE BenchCursor;
END;
GO
