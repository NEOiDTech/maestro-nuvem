# Guia de Implantação do NEOiD MAESTRO Nuvem

## Introdução

Este guia detalha o processo de implantação e configuração inicial do NEOiD Maestro, uma plataforma unificada para o gerenciamento de dispositivos SOMA, ENCODER PRO e DECODER PRO. O Maestro simplifica a administração de sua infraestrutura de streaming de vídeo, oferecendo recursos avançados como agregação automática de links, roteamento de vídeo em tempo real, comunicação de áudio full-duplex e monitoramento unificado.

## 1. Preparação do Ambiente

Antes de iniciar a implantação do NEOiD Maestro, é fundamental garantir que seu ambiente atenda aos requisitos mínimos de hardware, sistema operacional, rede e firewall.

### 1.1. Requisitos de Hardware do Servidor

Para um desempenho ideal do NEOiD Maestro, o servidor deve possuir as seguintes especificações mínimas:

*   **Processador:** 2.0 GHz ou superior
*   **Memória RAM:** 2 GB ou superior
*   **Armazenamento:** 40 GB ou superior de espaço em disco

### 1.2. Requisitos do Sistema Operacional

O NEOiD Maestro é compatível com sistemas operacionais baseados em Linux. Recomenda-se a utilização do Ubuntu 18.04 ou versões posteriores.

### 1.3. Requisitos de Rede

Para garantir a conectividade e o funcionamento adequado do Maestro, observe os seguintes requisitos de rede:

*   **Endereço IP Público:** É necessário pelo menos um endereço IP público para acesso à internet. Este requisito pode ser dispensado caso o acesso à internet não seja uma necessidade para a sua implantação.
*   **Planejamento de Largura de Banda:** A largura de banda da rede deve ser planejada de acordo com a taxa de codificação dos seus fluxos de vídeo. Como regra geral, planeje o dobro da largura de banda da taxa de codificação. Por exemplo, para uma taxa de codificação de 3 Mbps, uma largura de banda de 6 Mbps é recomendada.

### 1.4. Configurações de Firewall

Se houver um firewall em sua rede, é crucial que todas as portas estejam abertas para permitir o streaming em qualquer porta a qualquer momento. Certifique-se de que as configurações do firewall permitam todas as comunicações de rede necessárias, garantindo que o NEOiD Maestro possa operar sem restrições.

  As portas de entrada padrão 
 - WEBUI: 8080 TCP
 - WEBUI COM SSL: XXXX TCP
 - BONDING: 50000 UDP
 - INTERCOM: 40000 a 40050 UDP
 - SIGNALING: 5960 e 5961 TCP
 - HLS: 8080 TCP
 - RTSP: 554 TCP/UDP
 - SRT: Definidas pelo listener usuário

## 2. Implantação do Maestro

Esta seção detalha os passos para a implantação do contêiner Docker do NEOiD Maestro em seu servidor.

### 2.1. Obtenção de Privilégios de Administrador

Para executar as operações necessárias para a instalação do Docker e do Maestro, você precisará de privilégios de administrador. Abra um terminal e execute o seguinte comando:

```bash
sudo su
```

Será solicitado o nome de usuário e a senha do administrador do servidor para verificar sua identidade. Após a autenticação, você terá as permissões necessárias para prosseguir com as operações do Docker.

### 2.2. Instalação do Contêiner Docker (se não estiver instalado)

Caso o Docker ainda não esteja instalado em seu servidor, execute o seguinte comando para iniciar a instalação:

```bash
curl -fsSL https://get.docker.com | bash
```

A instalação pode levar aproximadamente 5 minutos, dependendo da velocidade da sua conexão de rede e do desempenho do hardware do servidor. Para verificar se a instalação foi concluída com sucesso, execute:

```bash
docker --version
```

Este comando deve exibir a versão do Docker instalada, confirmando a conclusão.

### 2.3. Download da Imagem do Neoid Maestro

Com o Docker instalado, o próximo passo é baixar a imagem do NEOiD Maestro. Execute o comando abaixo:

```bash
docker pull neoidtech/maestro
```

Aguarde a conclusão do download. A duração deste processo dependerá do tamanho da imagem e da velocidade da sua conexão com a internet. Este comando recupera a versão mais recente do Maestro, preparando-a para a implantação.

### 2.4. Início do Contêiner Maestro

Após o download da imagem, você pode iniciar o contêiner do Maestro com o seguinte comando:

```bash
docker run -itd --name neoid_maestro --restart=always -v ~/:/data --privileged --user root --network host neoidtech/maestro
```

**Parâmetros Chave:**

*   `--name neoid_maestro`: Define o nome do contêiner como 'neoid_maestro'.
*   `--restart=always`: Garante que o contêiner será reiniciado automaticamente em caso de falha ou reinicialização do servidor.
*   `-v ~/:/data`: Monta o diretório home do usuário no contêiner, permitindo o acesso a dados.
*   `--privileged`: Concede privilégios estendidos ao contêiner, necessários para certas operações.
*   `--user root`: Define o usuário 'root' dentro do contêiner.
*   `--network host`: Configura o contêiner para usar a rede do host, facilitando o acesso aos serviços do Maestro.

## 3. Login e Verificação

Após a implantação do contêiner, siga os passos abaixo para acessar a plataforma Maestro e verificar sua funcionalidade.

### 3.1. Acesso à Plataforma Maestro

Abra um navegador web de sua preferência (por exemplo, Google Chrome ou Mozilla Firefox) e digite o seguinte endereço na barra de navegação:

```
http://<server-ip>:8080
```

Substitua `<server-ip>` pelo endereço IP real do seu servidor. Por exemplo, se o IP do seu servidor for `192.168.1.100`, você digitaria `http://192.168.1.100:8080`.

### 3.2. Login no Painel

Na página de login do Maestro, utilize as credenciais padrão:

*   **Nome de Usuário:** `admin`
*   **Senha:** `admin`

Após inserir as credenciais, clique no botão "Login" ou pressione Enter.

### 3.3. Verificação da Interface de Gerenciamento

Após o login bem-sucedido, você será direcionado ao painel do Maestro. Para verificar a interface de gerenciamento e registrar seus dispositivos, navegue até **Dispositivos > Adicionar Dispositivo**. Aqui, você poderá registrar seu hardware SOMA, ENCODER PRO ou DECODER PRO.

Os indicadores de sucesso incluem a exibição dos painéis de status do dispositivo e métricas em tempo real, confirmando que o Maestro está operando corretamente e gerenciando seus dispositivos.

