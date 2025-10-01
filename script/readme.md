Script de instalação automática

Com o intúito de facilitar ainda mais a implantação do NEOiD MAESTRO NUVEM desenvolvemos um script para realizar de forma interativa;


# 🖥️ Menu interativo

```bash
sudo curl -fsSL https://raw.githubusercontent.com/neoidtech/maestro-nuvem/main/instalador-maestro.sh | sudo bash
```

🚀 Instalação Rápida
Instalação Automática (Recomendada)

# Instalação completa em um comando (Docker + Maestro Nuvem)

curl -fsSL https://raw.githubusercontent.com/neoidtech/maestro-nuvem/main/instalador-maestro.sh | bash -s install

⚙️ Comandos de Gerenciamento
Instalação Completa
bash
# Instala o Docker e depois o Maestro Nuvem
curl -fsSL https://raw.githubusercontent.com/neoidtech/maestro-nuvem/main/instalador-maestro.sh | bash -s install
Atualização do Maestro
bash
# Atualiza o Maestro Nuvem para a versão mais recente
curl -fsSL https://raw.githubusercontent.com/neoidtech/maestro-nuvem/main/instalador-maestro.sh | bash -s update
Verificar Status
bash
# Mostra o status do container e informações detalhadas
curl -fsSL https://raw.githubusercontent.com/neoidtech/maestro-nuvem/main/instalador-maestro.sh | bash -s status
Verificar Saúde do Serviço
bash
# Executa verificações completas de saúde (conectividade, logs, recursos)
curl -fsSL https://raw.githubusercontent.com/neoidtech/maestro-nuvem/main/instalador-maestro.sh | bash -s health
Parar Serviço
bash
# Para o container do Maestro Nuvem (pode ser reiniciado depois)
curl -fsSL https://raw.githubusercontent.com/neoidtech/maestro-nuvem/main/instalador-maestro.sh | bash -s stop
Remover Container
bash
# Remove o container e imagens do Maestro (mantém o Docker)
curl -fsSL https://raw.githubusercontent.com/neoidtech/maestro-nuvem/main/instalador-maestro.sh | bash -s remove
Remoção Completa (Purge)
bash
# ⚠️ REMOVE TUDO - Container, imagens, volumes e o Docker
curl -fsSL https://raw.githubusercontent.com/neoidtech/maestro-nuvem/main/instalador-maestro.sh | bash -s purge
🖥️ Menu Interativo
Para acesso a todas as funcionalidades via menu amigável:

bash
# Executar menu interativo (recomendado para usuários novos)
curl -fsSL https://raw.githubusercontent.com/neoidtech/maestro-nuvem/main/instalador-maestro.sh | bash
Download e Uso Local
bash
# Download do script
wget https://raw.githubusercontent.com/neoidtech/maestro-nuvem/main/instalador-maestro.sh

# Tornar executável
chmod +x instalador-maestro.sh

# Executar menu interativo
./instalador-maestro.sh

# Ou executar com parâmetros específicos
./instalador-maestro.sh (install|stop|update|status|health|purge)

🌐 Portas e Acesso
Após a instalação bem-sucedida, o Maestro Nuvem estará disponível nas seguintes portas:

HTTP (Web Interface): http://localhost:8080 ou http://SEU_IP:8080

HTTPS (SSL): https://localhost:80 ou https://SEU_IP:80 (SSL auto-assinado)

Verificação de Funcionamento
bash
# Testar se o serviço está respondendo
curl -f http://localhost:8080

# Verificar saúde completa
curl -fsSL https://raw.githubusercontent.com/neoidtech/maestro-nuvem/main/instalador-maestro.sh | bash -s health
🔄 Fluxo Recomendado
Primeira Instalação
bash
# 1. Instalação completa
curl -fsSL https://raw.githubusercontent.com/neoidtech/maestro-nuvem/main/instalador-maestro.sh | bash -s install

# 2. Verificar se está funcionando
curl -fsSL https://raw.githubusercontent.com/neoidtech/maestro-nuvem/main/instalador-maestro.sh | bash -s health

# 3. Acessar a interface web
echo "Acesse: http://$(curl -s ifconfig.me):8080"
Atualização de Versão
bash
# 1. Fazer backup de configurações (se aplicável)
# 2. Atualizar para nova versão
curl -fsSL https://raw.githubusercontent.com/neoidtech/maestro-nuvem/main/instalador-maestro.sh | bash -s update

# 3. Verificar se atualizou corretamente
curl -fsSL https://raw.githubusercontent.com/neoidtech/maestro-nuvem/main/instalador-maestro.sh | bash -s health
Manutenção Rotineira
bash
# Verificar status atual
curl -fsSL https://raw.githubusercontent.com/neoidtech/maestro-nuvem/main/instalador-maestro.sh | bash -s status

# Verificar saúde do sistema
curl -fsSL https://raw.githubusercontent.com/neoidtech/maestro-nuvem/main/instalador-maestro.sh | bash -s health
🛠️ Solução de Problemas
Verificar Logs
bash
# Ver logs do container
curl -fsSL https://raw.githubusercontent.com/neoidtech/maestro-nuvem/main/instalador-maestro.sh | bash -s status
Reiniciar Serviço
bash
# Parar e recriar o container
curl -fsSL https://raw.githubusercontent.com/neoidtech/maestro-nuvem/main/instalador-maestro.sh | bash -s stop
curl -fsSL https://raw.githubusercontent.com/neoidtech/maestro-nuvem/main/instalador-maestro.sh | bash -s update
Verificar Recursos do Sistema
bash
# O comando health mostra consumo de CPU, memória e rede
curl -fsSL https://raw.githubusercontent.com/neoidtech/maestro-nuvem/main/instalador-maestro.sh | bash -s health
🗑️ Remoção
Remoção Parcial (Mantém Docker)
bash
# Remove apenas o Maestro Nuvem
curl -fsSL https://raw.githubusercontent.com/neoidtech/maestro-nuvem/main/instalador-maestro.sh | bash -s remove
Remoção Completa
bash
# ⚠️ ATENÇÃO: Remove tudo permanentemente
# - Container do Maestro
# - Imagens Docker
# - Volumes de dados
# - Docker Engine
curl -fsSL https://raw.githubusercontent.com/neoidtech/maestro-nuvem/main/instalador-maestro.sh | bash -s purge
📝 Notas Importantes
✅ install: Instala Docker + Maestro (uso inicial)

✅ update: Atualiza mantendo dados e configurações

✅ health: Verificação completa do sistema

✅ status: Informações do container e logs

🛑 stop: Para serviço temporariamente

🗑️ remove: Remove Maestro (mantém Docker)

⚠️ purge: Remove TUDO permanentemente

Ícones de Referência
✅ Seguro - Operações rotineiras

🔄 Atualização - Mantém dados

🛑 Parada - Serviço pode ser reiniciado

⚠️ Perigoso - Dados podem ser perdidos

📞 Suporte
Em caso de problemas, execute o comando de saúde para diagnóstico:

bash
curl -fsSL https://raw.githubusercontent.com/neoidtech/maestro-nuvem/main/instalador-maestro.sh | bash -s health
Verifique também se as portas 8080 e 80 estão liberadas no firewall do seu servidor.

📥 Download
📥 Baixar Script de Instalação

Para download direto do script:

bash
wget https://raw.githubusercontent.com/neoidtech/maestro-nuvem/main/instalador-maestro.sh
chmod +x instalador-maestro.sh
./instalador-maestro.sh
