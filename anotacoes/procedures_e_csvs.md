# Notas sobre procedures e arquivos CSV

## Procedures armazenadas
- `dbo.usp_ImportCarteiraCompleta` (`sql/usp_import_carteira_completa.sql`)
  - Importa um CSV de carteira já higienizado e mantém `Carteira_Indicadores` sincronizada. Normaliza o texto bruto, insere registros faltantes em `Setores`, `Empresas` e `Ativos`, atualiza `Indicadores_Fundamentalistas`, `Dividend_Yield_Historico` e, por fim, executa upsert em `Carteira_Indicadores` com o rótulo/data de snapshot informados.
- `dbo.usp_SincronizarAtivosSetores` (`sql/usp_sync_ativos_setores.sql`)
  - Garante que `Ativos` possua chave estrangeira para `Setores`. Migra a coluna textual legada `setor` (caso ainda exista) para `setor_id`, aplica a constraint `fk_ativos_setores` e informa quantos ativos continuam sem correspondência.
- `usp_SimularInvestimento` (`sql/simulacao procedure.sql`)
  - Registra uma transação simulada para um ativo em uma carteira definida. Cria a linha da carteira quando necessário, grava o lançamento em `Transacoes`, atualiza `Carteira` e `Carteira_Historico`, gera `Alertas` para variações fortes, recalcula `Riscos` e preenche as comparações em `Comparativo_Benchmark`.
- `usp_ImportarDataset` (`sql/carteira_tables_scripts.sql`)
  - Loader central que encapsula a lógica de `BULK INSERT` para diversos formatos de dataset. O parâmetro `@DatasetType` determina quais tabelas de estágio e de destino serão utilizadas.

## Mapa de CSVs para tabelas
| Arquivo CSV | Procedure / tipo de dataset | Tabelas de destino | Observações |
| --- | --- | --- | --- |
| `csvs_usados/carteira_investimentos_modelo_ativos_clean.csv` | `dbo.usp_ImportCarteiraCompleta` | `Setores`, `Empresas`, `Ativos`, `Indicadores_Fundamentalistas`, `Dividend_Yield_Historico`, `Carteira_Indicadores` | Informe o caminho do arquivo e, opcionalmente, rótulo/data/ano do snapshot.
| `csvs_usados/empresas.csv` | `usp_ImportarDataset` com `@DatasetType = 'EMPRESAS'` | `Setores`, `Empresas`, `Ativos` (coluna temporária `setor`) | Execute `dbo.usp_SincronizarAtivosSetores` em seguida para consolidar o `setor_id`.
| `csvs_usados/ISEEQuad_5-2025.csv`, `csvs_usados/ISEEDia_28-08-25.csv`, `csvs_usados/ISEE3Prev_9-2025.csv` | `usp_ImportarDataset` com `@DatasetType = 'ISEE_CARTEIRA'` | `Ativos`, `Carteira_Definicao`, `Carteira` | Informe `@CarteiraNome` e `@DataReferencia`; a routine limpa os pesos anteriores da mesma carteira antes de inserir.
| `csvs_usados/Evolucao_Mensal.csv` | `usp_ImportarDataset` com `@DatasetType = 'ISEE_EVOLUCAO_MENSAL'` | `Ativos`, `Desempenho_Historico`, `Benchmarks` | Cria/atualiza o ticker sintético (padrão `ISEE`) e salva o último valor.
| `csvs_usados/Evolucao_Diaria.csv` | `usp_ImportarDataset` com `@DatasetType = 'ISEE_EVOLUCAO_DIARIA'` e `@Ano` | `Ativos`, `Cotacoes_Diarias`, `Benchmarks` | CSV separado por ponto e vírgula com dias vs. meses; também renova `Ativos.preco_atual`.
| `csvs_usados/Taxa_Media_Crescimento.csv` | `usp_ImportarDataset` com `@DatasetType = 'TAXA_CRESCIMENTO'` | `Indicadores_Macroeconomicos` | Carrega métricas anuais identificadas como `ISEE Valor <ano>`.
| `csvs_usados/Volatilidade_Mensal.csv` | `usp_ImportarDataset` com `@DatasetType = 'VOLATILIDADE_MENSAL'` | `Indicadores_Macroeconomicos` | Registra cada ponto mensal como `Volatilidade ISEE <aaaa-mm>`.
| `csvs_usados/ipca.csv` | `usp_ImportarDataset` com `@DatasetType = 'IPCA_MENSAL'` | `Indicadores_Macroeconomicos` | Converte abreviações de mês para nomes `IPCA aaaa-mm`.
| `csvs_usados/pib-per-capita-r.csv` | `usp_ImportarDataset` com `@DatasetType = 'PIB_PER_CAPITA'` | `Indicadores_Macroeconomicos` | Persistência anual do PIB per capita.
| `csvs_usados/variacao-do-pib.csv` | `usp_ImportarDataset` com `@DatasetType = 'PIB_VARIACAO_TRIMESTRAL'` | `Indicadores_Macroeconomicos` | Grava a variação trimestral como `PIB Variacao <ano>Q<trimestre>`.
| `csvs_usados/meta-para-a-taxa-selic.csv` | `usp_ImportarDataset` com `@DatasetType = 'SELIC_META'` | `Indicadores_Macroeconomicos` | Datas ISO brutas; a coluna de valor precisa estar numérica após substituir vírgulas por pontos.
| `csvs_usados/bvsp.csv` | `usp_ImportarDataset` com `@DatasetType = 'BENCHMARK_HISTORICO'` e `@TargetTicker` (ex.: `BVSP`) | `Ativos`, `Cotacoes_Diarias`, `Desempenho_Historico`, `Benchmarks` | Atualiza cotações e série histórica do benchmark com o fechamento do dia.
| `csvs_usados/cotahist1m.csv`, `csvs_usados/cotahist(2)4m.csv` | `usp_ImportarDataset` com `@DatasetType = 'COTAHIST_MULTI'` | `Ativos`, `Cotacoes_Diarias`, `Desempenho_Historico` | Um único CSV pode carregar vários tickers; o último fechamento renova `Ativos.preco_atual`.
| `csvs_usados/* Dados Historicos.csv`, `csvs_usados/XPML11 Dados Hist mensal.csv` | `usp_ImportarDataset` com `@DatasetType = 'ATIVO_HISTORICO'` e `@TargetTicker` que coincide com o prefixo do arquivo (`BBAS3`, `BBDC4`, `BTCI11`, `HGLG11`, `KLBN11`, `MXRF11`, `PETR4`, `RBRY11`, `VGIR11`, `XPML11`) | `Ativos`, `Cotacoes_Diarias`, `Desempenho_Historico` | Histórico mensal por ticker; o fechamento mais recente também atualiza `Ativos.preco_atual`.

## Notas adicionais
- Execute as cargas em instância SQL Server 2022 (ou superior) para habilitar `FORMAT = 'CSV'` no `BULK INSERT`.
- Os arquivos de apoio em `csvs_utf8/` servem como referência; nenhuma rotina atual consome esse layout diretamente.
- Após importar datasets que preencham `Ativos.setor`, rode `dbo.usp_SincronizarAtivosSetores` para preservar a integridade da chave estrangeira.
