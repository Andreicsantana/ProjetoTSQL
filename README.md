# Carteira de Investimentos Referencial - T-SQL

## Descrição do Projeto
Este projeto tem como objetivo criar uma **carteira de investimentos referencial** que permite aos usuários acompanhar o desempenho de uma seleção de ativos e tomar decisões mais informadas para suas próprias carteiras.  
O projeto é desenvolvido utilizando **T-SQL** para consultas e análise de dados financeiros, contemplando informações sobre composição da carteira, desempenho histórico, indicadores fundamentalistas e simulações de cenários.

## Objetivos
1. Fornecer uma visão completa da **composição da carteira**, incluindo ativos, pesos, setores e valores investidos.  
2. Permitir análise de **desempenho histórico**, com valorização, comparativos com índices de mercado e dividendos recebidos.  
3. Exibir **indicadores fundamentalistas** de cada ativo da carteira, como P/L, ROE e endividamento.  
4. Realizar **simulações e cenários**, como impactos de variações de preço ou reinvestimento de dividendos.

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
