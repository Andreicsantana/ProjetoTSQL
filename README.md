# Carteira de Investimentos Referencial - T-SQL

## Descrição do Projeto
Este projeto tem como objetivo criar uma **carteira de investimentos referencial** que permite aos usuários acompanhar o desempenho de uma seleção de ativos e tomar decisões mais informadas para suas próprias carteiras.  
O projeto é desenvolvido utilizando **T-SQL** para consultas e análise de dados financeiros, contemplando informações sobre composição da carteira, desempenho histórico, indicadores fundamentalistas e simulações de cenários.

## Objetivos
1. Composição da carteira: seleção de ativos de diferentes classes (ações, fundos imobiliários, renda fixa, entre outros), permitindo o estudo da diversificação e da alocação de recursos.
2. Desempenho histórico: análise da rentabilidade dos ativos e da carteira como um todo em diferentes períodos de tempo, possibilitando a visualização de tendências e padrões.
3. Indicadores fundamentalistas: integração de métricas como P/L, dividend yield, ROE, volatilidade e outros parâmetros que auxiliam na avaliação da atratividade e risco dos investimentos.
4. Simulações de cenários: projeções e análises hipotéticas baseadas em diferentes condições de mercado (ex.: variação de taxa de juros, inflação, crises econômicas), permitindo avaliar a resiliência da carteira diante de eventos adversos.

## Perguntas que gostaríamos de responder

### 1. Composição da Carteira
- Quais são os ativos presentes na carteira e qual o peso (%) de cada um?  
- Qual é a distribuição setorial dos ativos (bancos, energia, consumo, etc.)?  
- Qual é o preço atual de cada ativo da carteira?  
- Qual é o valor total investido por ativo e o total da carteira?

### 2. Desempenho Histórico
- Qual foi a valorização da carteira nos últimos 30 dias?  
- Qual ativo da carteira teve a maior alta (ou queda) no último mês?  
- Como o retorno acumulado da carteira se compara ao Ibovespa no mesmo período?  
- Qual foi o dividend yield médio da carteira no último ano?

### 3. Indicadores Fundamentalistas
- Qual é o P/L médio ponderado da carteira?  
- Qual é o ROE médio ponderado da carteira?  
- Quais empresas da carteira pagaram dividendos recentemente e qual foi o valor?  
- Qual empresa da carteira apresenta maior dívida/EBITDA?

### 4. Simulações e Cenários
- Se cada ativo da carteira subir 5%, qual será o novo valor total da carteira?  
- Quanto da carteira está exposta a um único setor (ex.: bancos)?  
- Qual seria o impacto se o ativo com maior peso caísse 10%?  
- Se reinvestir todos os dividendos recebidos no último ano, qual seria o retorno total?

## Tecnologias
- **SQL Server / T-SQL**
