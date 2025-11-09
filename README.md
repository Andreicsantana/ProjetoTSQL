# 💼 Carteira Referencial de Investimentos — *T-SQL*

## 🔄 Backup
- [Backup Drive](https://drive.google.com/file/d/11fg1deNgsxlBHNufpMC6par5jU3o_PXU/view?usp=drive_link)
- [Backup Caminho Git]

## 🧭 Descrição do Projeto
Este projeto organiza um pequeno data warehouse financeiro em SQL Server para responder perguntas sobre uma **Carteira Referencial de Investimentos**. O foco principal é demonstrar como transformar arquivos CSV heterogêneos em um conjunto consistente de tabelas T-SQL e, a partir delas, gerar análises prontas para consumo.

Para lidar com limitações dos datasets originais (textos em várias codificações, campos numéricos com formatos diferentes, ausência de séries completas), o repositório combina **scripts Python** que higienizam e padronizam os CSVs com **scripts SQL** que criam o esquema relacional, populam as tabelas e expõem consultas e views analíticas.

---

## 🎯 Objetivos

1. **Normalizar dados de mercado**: higienizar CSVs originais, corrigir codificação, ajustar formatos numéricos e gerar arquivos consistentes para carga.
2. **Modelar o banco relacional**: criar o banco `TsqlProject`, tabelas de referência e relacionamentos conforme `sql/schema_tables.sql`.
3. **Popular o ambiente analítico**: carregar a carteira simulada e séries históricas geradas pelos scripts Python em tabelas dimensionais e fato.
4. **Responder perguntas de negócio**: expor consultas e views que sintetizam composição da carteira, desempenho, indicadores fundamentalistas e cenários.

---

## ❓ Perguntas-Chave

### 📊 1. Composição da Carteira
- Quais são os ativos presentes na carteira 1 e qual o peso teórico de cada um?
- Qual é a **distribuição setorial** da carteira 1?  
- Qual o **preço atual** registrado para cada ativo da carteira 1?  
- Qual o **valor investido** por ativo e o **total da carteira 1**?

### ⏳ 2. Desempenho Histórico
- Qual foi a **valorização da carteira 1** ao longo de **janeiro de 2025**?  
- Quais ativos da carteira 1 tiveram as **maiores altas e quedas** em janeiro de 2025?  
- Como o **retorno diário** da carteira 1 se comparou ao benchmark **IBOV** em janeiro de 2025?  
- Qual foi o **dividend yield observado** para a carteira 1 em janeiro de 2025?

### 📚 3. Indicadores Fundamentalistas
- Qual é o **P/L médio ponderado** da carteira 1?  
- Qual é o **ROE médio ponderado** da carteira 1?  
- Quais dividendos os ativos da carteira 1 **receberam em janeiro de 2025** e em que valores?  
- Qual ativo da carteira 1 apresenta o **maior indicador Dívida/EBITDA**?

### 🧠 4. Simulações e Cenários
- Se cada ativo da carteira 1 **subir 5%**, qual será o novo valor total?  
- Quanto da carteira 1 está **concentrado em um único setor**?  
- Qual o impacto se o **ativo de maior peso da carteira 1 cair 10%**?  
- Qual seria o **retorno da carteira 1** ao reinvestir os **dividendos recebidos em janeiro de 2025**?

---

## Arquitetura e Fluxo de Dados

- `csvs_usados/`: arquivos brutos obtidos de fontes públicas (B3, Kaggle, séries macroeconômicas). Muitos chegam em ISO-8859-1, com separadores variados e campos numéricos como texto.
- `scripts/build_dataset.py`: script principal de ETL. Seleciona os ativos com dados completos, reforça o universo com renda fixa simulada, recorta uma janela coerente (30 dias) e gera um arquivo CSV por tabela-alvo em `generated_dataset/`.
- `scripts/utf8.py`: devido às inconsistências de codificação nos dados originais, converte cada CSV gerado para UTF-8 em `generated_dataset_utf8/`, garantindo importação direta pelo SQL Server.
- `sql/schema_tables.sql`: cria o banco `TsqlProject` e todas as tabelas normalizadas (setores, empresas, ativos, carteira, séries históricas, benchmarks etc.).
- `sql/usp_load_generated_dataset.sql` e correlatos: procedures e scripts de carga (não detalhados aqui) que transferem os CSVs normalizados para as tabelas definitivas.
- `sql/analises_perguntas.sql`: conjunto de consultas parametrizadas (atualmente fixas para carteira 1 e janela de janeiro/2025) que respondem às perguntas de negócio.
- `sql/views_analises.sql`: materializa cada uma das respostas de `analises_perguntas.sql` em uma view dedicada para facilitar a exploração no SSMS.

### Pipeline resumido
1. Executar `python scripts/build_dataset.py` para gerar os CSVs normalizados.
2. Rodar `python scripts/utf8.py` para evitar erros de codificação durante a importação.
3. Criar o esquema com `sql/schema_tables.sql` e, em seguida, usar os scripts de carga para popular as tabelas a partir de `generated_dataset_utf8/`.
4. Consumir análises via `sql/analises_perguntas.sql` ou diretamente pelas views criadas em `sql/views_analises.sql` (ex.: `SELECT * FROM vw_carteira1_distribuicao_setorial;`).

> Observação: durante o desenvolvimento enfrentamos lacunas nas séries históricas (ativos sem dados para as datas mais recentes). O script Python recorta o intervalo comum a todos os ativos escolhidos e simula preços quando necessário (caso da renda fixa), permitindo manter as consultas SQL simples e determinísticas.

---

## 🧰 Tecnologias Utilizadas
- 🗄️ **SQL Server / T-SQL**
 - 🐍 **Python 3 + Pandas/Numpy** (ETL e saneamento dos datasets)

---

## 🗂️ Gestão do Projeto
- 📋 **Trello:** [Acesse o quadro](https://trello.com/b/IvVcWZZp)

---

## 🔗 Links para Datasets

### 📅 Desempenho Histórico e Diário  
🔹 [B3 - ISE B3 Estatísticas Históricas](https://www.b3.com.br/pt_br/market-data-e-indices/indices/indices-de-sustentabilidade/indice-de-sustentabilidade-empresarial-ise-b3-estatisticas-historicas.htm)

### 💹 DataSet Bovespa (referenciais do Kaggle)  
🔹 [Bovespa — dcampeao](https://www.kaggle.com/datasets/dcampeao/bovespa)  
🔹 [Ibovespa — lusfernandotorres](https://www.kaggle.com/datasets/lusfernandotorres/ibovespa)

### 💾 Cotações Históricas  
🔹 [B3 - Mercado à Vista (Cotações Históricas)](https://www.b3.com.br/pt_br/market-data-e-indices/servicos-de-dados/market-data/historico/mercado-a-vista/cotacoes-historicas/)

---

## Importando csv para o container do docker

docker cp "C:\Users\teste\csvs" sqlserver:/var/opt/mssql/data/
