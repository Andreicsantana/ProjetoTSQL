CREATE DATABASE CarteiraRef;
GO

USE CarteiraRef;
GO

CREATE TABLE Setores (
    setor_id INT IDENTITY(1,1) PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    descricao VARCHAR(255)
);

CREATE TABLE Empresas (
    empresa_id INT IDENTITY(1,1) PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    cnpj VARCHAR(20),
    setor_id INT NOT NULL,
    CONSTRAINT fk_empresa_setor FOREIGN KEY (setor_id)
        REFERENCES Setores(setor_id)
);

CREATE TABLE Ativos (
    ativo_id INT IDENTITY(1,1) PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    setor VARCHAR(100),
    preco_atual DECIMAL(18,2)
);

CREATE TABLE Carteira (
    carteira_id INT IDENTITY(1,1) PRIMARY KEY,
    ativo_id INT NOT NULL,
    peso DECIMAL(5,2),
    valor_investido DECIMAL(18,2),
    CONSTRAINT fk_carteira_ativo FOREIGN KEY (ativo_id)
        REFERENCES Ativos(ativo_id)
);

CREATE TABLE Desempenho_Historico (
    ativo_id INT NOT NULL,
    data DATE NOT NULL,
    preco DECIMAL(18,2),
    PRIMARY KEY (ativo_id, data),
    CONSTRAINT fk_desempenho_ativo FOREIGN KEY (ativo_id)
        REFERENCES Ativos(ativo_id)
);

CREATE TABLE Dividendos (
    ativo_id INT NOT NULL,
    data_pagamento DATE NOT NULL,
    valor DECIMAL(18,2),
    PRIMARY KEY (ativo_id, data_pagamento),
    CONSTRAINT fk_dividendo_ativo FOREIGN KEY (ativo_id)
        REFERENCES Ativos(ativo_id)
);

CREATE TABLE Indicadores_Fundamentalistas (
    ativo_id INT PRIMARY KEY,
    pl DECIMAL(10,2),
    roe DECIMAL(10,2),
    divida_ebitda DECIMAL(10,2),
    CONSTRAINT fk_indicador_ativo FOREIGN KEY (ativo_id)
        REFERENCES Ativos(ativo_id)
);

CREATE TABLE Cotacoes_Diarias (
    ativo_id INT NOT NULL,
    data DATE NOT NULL,
    preco_abertura DECIMAL(18,2),
    preco_fechamento DECIMAL(18,2),
    volume DECIMAL(18,2),
    PRIMARY KEY (ativo_id, data),
    CONSTRAINT fk_cotacao_ativo FOREIGN KEY (ativo_id)
        REFERENCES Ativos(ativo_id)
);

CREATE TABLE Proventos (
    ativo_id INT NOT NULL,
    data DATE NOT NULL,
    tipo VARCHAR(50),
    valor DECIMAL(18,2),
    PRIMARY KEY (ativo_id, data),
    CONSTRAINT fk_provento_ativo FOREIGN KEY (ativo_id)
        REFERENCES Ativos(ativo_id)
);

CREATE TABLE Carteira_Historico (
    carteira_id INT NOT NULL,
    data DATE NOT NULL,
    valor_total DECIMAL(18,2),
    PRIMARY KEY (carteira_id, data),
    CONSTRAINT fk_hist_carteira FOREIGN KEY (carteira_id)
        REFERENCES Carteira(carteira_id)
);

CREATE TABLE Benchmarks (
    benchmark_id INT IDENTITY(1,1) PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    valor_atual DECIMAL(18,2)
);

CREATE TABLE Comparativo_Benchmark (
    carteira_id INT NOT NULL,
    benchmark_id INT NOT NULL,
    data DATE NOT NULL,
    retorno_carteira DECIMAL(10,2),
    retorno_benchmark DECIMAL(10,2),
    PRIMARY KEY (carteira_id, benchmark_id, data),
    CONSTRAINT fk_comp_carteira FOREIGN KEY (carteira_id)
        REFERENCES Carteira(carteira_id),
    CONSTRAINT fk_comp_bench FOREIGN KEY (benchmark_id)
        REFERENCES Benchmarks(benchmark_id)
);

CREATE TABLE Transacoes (
    transacao_id INT IDENTITY(1,1) PRIMARY KEY,
    carteira_id INT NOT NULL,
    ativo_id INT NOT NULL,
    data DATE NOT NULL,
    tipo VARCHAR(20),
    quantidade DECIMAL(18,2),
    preco DECIMAL(18,2),
    CONSTRAINT fk_transacao_carteira FOREIGN KEY (carteira_id)
        REFERENCES Carteira(carteira_id),
    CONSTRAINT fk_transacao_ativo FOREIGN KEY (ativo_id)
        REFERENCES Ativos(ativo_id)
);

CREATE TABLE Riscos (
    ativo_id INT PRIMARY KEY,
    beta DECIMAL(10,2),
    volatilidade DECIMAL(10,2),
    var DECIMAL(18,2),
    CONSTRAINT fk_risco_ativo FOREIGN KEY (ativo_id)
        REFERENCES Ativos(ativo_id)
);

CREATE TABLE Simulacoes (
    simulacao_id INT IDENTITY(1,1) PRIMARY KEY,
    carteira_id INT NOT NULL,
    descricao VARCHAR(255),
    data_execucao DATE NOT NULL,
    CONSTRAINT fk_simulacao_carteira FOREIGN KEY (carteira_id)
        REFERENCES Carteira(carteira_id)
);

CREATE TABLE Simulacao_Resultados (
    simulacao_id INT NOT NULL,
    ativo_id INT NOT NULL,
    novo_valor DECIMAL(18,2),
    impacto_total DECIMAL(18,2),
    PRIMARY KEY (simulacao_id, ativo_id),
    CONSTRAINT fk_result_simulacao FOREIGN KEY (simulacao_id)
        REFERENCES Simulacoes(simulacao_id),
    CONSTRAINT fk_result_ativo FOREIGN KEY (ativo_id)
        REFERENCES Ativos(ativo_id)
);

CREATE TABLE Dividend_Yield_Historico (
    ativo_id INT NOT NULL,
    ano INT NOT NULL,
    dy_percentual DECIMAL(10,2),
    PRIMARY KEY (ativo_id, ano),
    CONSTRAINT fk_dy_ativo FOREIGN KEY (ativo_id)
        REFERENCES Ativos(ativo_id)
);

CREATE TABLE Alocacao_Setorial (
    carteira_id INT NOT NULL,
    setor_id INT NOT NULL,
    peso_setor DECIMAL(5,2),
    PRIMARY KEY (carteira_id, setor_id),
    CONSTRAINT fk_aloc_carteira FOREIGN KEY (carteira_id)
        REFERENCES Carteira(carteira_id),
    CONSTRAINT fk_aloc_setor FOREIGN KEY (setor_id)
        REFERENCES Setores(setor_id)
);

CREATE TABLE Alertas (
    alerta_id INT IDENTITY(1,1) PRIMARY KEY,
    carteira_id INT NOT NULL,
    ativo_id INT NOT NULL,
    condicao VARCHAR(255),
    data_criacao DATE NOT NULL,
    CONSTRAINT fk_alerta_carteira FOREIGN KEY (carteira_id)
        REFERENCES Carteira(carteira_id),
    CONSTRAINT fk_alerta_ativo FOREIGN KEY (ativo_id)
        REFERENCES Ativos(ativo_id)
);

CREATE TABLE Metas_Investimento (
    meta_id INT IDENTITY(1,1) PRIMARY KEY,
    carteira_id INT NOT NULL,
    descricao VARCHAR(255) NOT NULL,
    valor_alvo DECIMAL(18,2),
    prazo DATE,
    CONSTRAINT fk_meta_carteira FOREIGN KEY (carteira_id)
        REFERENCES Carteira(carteira_id)
);

CREATE TABLE Indicadores_Macroeconomicos (
    indicador_id INT IDENTITY(1,1) PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    valor_atual DECIMAL(18,4),
    data_atualizacao DATE NOT NULL
);

CREATE TABLE Custos_Operacionais (
    custo_id INT IDENTITY(1,1) PRIMARY KEY,
    carteira_id INT NOT NULL,
    descricao VARCHAR(255),
    valor DECIMAL(18,2),
    data DATE,
    CONSTRAINT fk_custo_carteira FOREIGN KEY (carteira_id)
        REFERENCES Carteira(carteira_id)
);
