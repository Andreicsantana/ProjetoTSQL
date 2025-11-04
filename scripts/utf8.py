import os
import chardet

input_folder = "C:\\Repositorios\\ProjetoTSQL\\datasets\\dataset fundos imobiliarios"
output_folder = "C:\\Repositorios\\ProjetoTSQL\\csvs_utf8_datasets_fundos_imobiliarios"

os.makedirs(output_folder, exist_ok=True)

for filename in os.listdir(input_folder):
    if filename.endswith(".csv"):
        input_path = os.path.join(input_folder, filename)
        output_path = os.path.join(output_folder, filename)

        # Detecta a codificação original
        with open(input_path, 'rb') as f:
            raw_data = f.read(4096)
            result = chardet.detect(raw_data)
            encoding = result['encoding']

        # Converte para UTF-8
        with open(input_path, 'r', encoding=encoding, errors='ignore') as infile:
            with open(output_path, 'w', encoding='utf-8', newline='') as outfile:
                for line in infile:
                    outfile.write(line)

        print(f"✅ {filename} convertido de {encoding} → UTF-8")

print("🚀 Todos os arquivos foram convertidos com sucesso!")


# Instalação do chardet no Windows

# pip install chardet