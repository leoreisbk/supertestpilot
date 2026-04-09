# Como rodar uma análise de UX no iOS, Android e Web

## A motivação

Durante as dailies, o time foi levantando uma necessidade recorrente: ter uma forma mais rápida e consistente de avaliar a experiência de uso do app — sem depender apenas de percepção manual ou sessões de teste com usuários. Era preciso algo que conseguisse navegar pelo app de forma autônoma e gerar observações objetivas sobre o que encontrasse pelo caminho.

Não existia uma ferramenta pronta que fizesse exatamente isso.

---

## Por que o TestPilot?

O TestPilot nasceu como uma ferramenta para engenheiros: um jeito de escrever testes automatizados de app usando linguagem natural em vez de código complexo. Em vez de programar cada clique, o desenvolvedor escrevia algo como *"vai até a tela de perfil e troca a foto"* — e a IA executava isso no app.

A base já estava lá: o TestPilot sabia abrir apps, navegar por telas, tirar capturas de tela e interpretar o que via usando inteligência artificial. Faltava só uma nova camada por cima — uma que não fosse voltada para engenheiros validando código, mas para qualquer pessoa do time avaliando experiência.

---

## O que foi preciso adaptar

O TestPilot original foi construído para **executar passos definidos** — você dizia o que fazer e ele fazia. Para a análise de UX, o comportamento precisava ser diferente: a IA deveria **explorar livremente**, tomar decisões sozinha sobre onde ir, e ao final **registrar o que observou** em vez de apenas confirmar se algo funcionou.

Foram três mudanças principais:

**1. Um novo modo de operação — o modo análise**
Em vez de receber uma lista de tarefas, a IA recebe um *objetivo aberto* e decide por conta própria como explorar o app. Ao final, em vez de um resultado de "passou/falhou", ela gera um relatório com capturas de tela e comentários sobre cada passo.

**2. Suporte a mais serviços de IA**
O TestPilot original usava apenas OpenAI (ChatGPT). Para dar mais flexibilidade ao time — e não depender de um único fornecedor — adicionamos suporte ao **Google Gemini** e ao **Anthropic Claude** também.

**3. Uma solução para a restrição do iPhone**
O iOS tem uma barreira de segurança: nenhum programa externo consegue controlar um app ou tirar capturas de tela diretamente. A Apple só libera esse acesso durante a execução de **testes automatizados**, que recebem permissões especiais para isso.

Para contornar isso sem abrir mão da simplicidade de uso, criamos uma estrutura chamada `harness/`. Ela é composta por:
- **HarnessApp** — um aplicativo auxiliar vazio que precisa estar instalado no aparelho. Você nunca vai abrir ele; ele existe apenas para que o iOS libere as permissões necessárias. Pense nele como um crachá de acesso.
- **AnalystTests** — é quem executa de fato os comandos: tirar capturas de tela, tocar na tela, rolar o conteúdo. É o "braço" que o TestPilot usa para interagir com o app analisado, dentro do contexto de permissão que o HarnessApp abriu.

Você não precisa mexer em nada disso — o TestPilot instala e gerencia tudo automaticamente. No Android essa estrutura não existe porque o sistema já permite esse tipo de controle sem restrições adicionais.

---

## O que o TestPilot faz, na prática

O TestPilot tem dois modos de operação:

### Análise de UX (`./testpilot analyze`)

A IA navega pelo app como se fosse um usuário real e, ao final, gera um relatório com capturas de tela e observações sobre a experiência de uso. Você só precisa dizer **o que quer analisar** — a IA faz o resto.

**Exemplo de objetivo:** *"como é fácil encontrar a aba de treino e iniciar uma atividade"*

### Teste determinístico (`./testpilot test`)

A IA avalia uma afirmação específica sobre o app e retorna **PASSOU** ou **FALHOU** — sem exploração. Ideal para verificar se algo específico está funcionando, ou para integrar com pipelines de CI/CD.

**Exemplo de objetivo:** *"o botão de compra está habilitado na tela do produto"*

Ambos os modos funcionam em **iPhone/iPad** (aparelho físico ou simulador), **Android** (aparelho físico ou emulador) e **Web** (qualquer URL acessível no navegador — incluindo protótipos no ProtoPie, Figma ou ambientes de staging).

---

## Antes de usar pela primeira vez

**1. Tenha o app ou a URL pronta**

- **iPhone/iPad físico:** conecte o aparelho ao Mac com o cabo USB e abra o Xcode para que ele reconheça o aparelho.
- **Simulador de iPhone/iPad:** abra o Xcode, suba um simulador e certifique-se de que o app está instalado nele.
- **Aparelho Android físico:** conecte o aparelho ao computador com o cabo USB. Nas configurações do aparelho, ative o **Modo de desenvolvedor** e dentro dele ative a opção **Depuração USB**.
- **Emulador Android:** abra o Android Studio, suba um emulador e certifique-se de que o app está instalado nele.
- **Web:** basta ter a URL em mãos — nenhuma instalação adicional é necessária. O TestPilot abre o navegador automaticamente.

Se você não sabe como fazer algum dos passos de mobile, peça ajuda a alguém do time de desenvolvimento.

---

**2. Tenha uma chave de acesso à IA**

O TestPilot precisa de uma chave de acesso para usar a inteligência artificial. Essa chave é como uma senha que permite ao TestPilot se comunicar com o serviço de IA escolhido.

Peça ao time de desenvolvimento para criar um arquivo chamado `.env` na pasta do projeto com o seguinte conteúdo:

```
TESTPILOT_API_KEY=sua-chave-aqui
TESTPILOT_PROVIDER=gemini
```

O TestPilot funciona com três serviços de IA diferentes — escolha um:
- **Google Gemini** → use `gemini` (apenas iOS e Android)
- **Anthropic Claude** → use `anthropic`
- **OpenAI (ChatGPT)** → use `openai`

---

**3. Tenha o Xcode instalado no Mac (apenas para iOS)**

O Xcode é o programa da Apple para desenvolvimento de apps. Se não estiver instalado, peça ao time de desenvolvimento para instalar.

---

## Como rodar a análise de UX

Abra o Terminal e, dentro da pasta do projeto, rode um dos comandos abaixo:

**iPhone/iPad — simulador:**
```bash
./testpilot analyze \
  --platform ios \
  --app "Nome do App" \
  --objective "o que você quer analisar"
```

**iPhone/iPad — aparelho físico conectado:**
```bash
./testpilot analyze \
  --platform ios \
  --app "Nome do App" \
  --objective "o que você quer analisar" \
  --device <ID do aparelho> \
  --team-id <seu código de desenvolvedor Apple>
```

> Como encontrar o **ID do aparelho**: abra o Xcode → menu Window → Devices and Simulators.
> Como encontrar o **código de desenvolvedor Apple**: acesse developer.apple.com → Account → Membership.

**Android — emulador ou aparelho físico:**
```bash
./testpilot analyze \
  --platform android \
  --app "Nome do App" \
  --objective "o que você quer analisar"
```

**Web — qualquer URL:**
```bash
./testpilot analyze \
  --platform web \
  --url https://seu-app.com \
  --objective "como é fácil encontrar o fluxo de checkout"
```

O modo web abre um navegador visível para que você possa acompanhar a IA navegando em tempo real.

Ao terminar, o relatório abre automaticamente no navegador.

---

## Como rodar um teste determinístico

Use `./testpilot test` quando quiser uma resposta objetiva de **passou** ou **falhou** para uma condição específica do app.

**iPhone/iPad — simulador:**
```bash
./testpilot test \
  --platform ios \
  --app "Nome do App" \
  --objective "o botão de compra está habilitado na tela do produto"
```

**iPhone/iPad — aparelho físico conectado:**
```bash
./testpilot test \
  --platform ios \
  --app "Nome do App" \
  --objective "o botão de compra está habilitado na tela do produto" \
  --device <ID do aparelho> \
  --team-id <seu código de desenvolvedor Apple>
```

**Android — emulador ou aparelho físico:**
```bash
./testpilot test \
  --platform android \
  --app "Nome do App" \
  --objective "o botão de compra está habilitado na tela do produto"
```

**Web — qualquer URL:**
```bash
./testpilot test \
  --platform web \
  --url https://seu-app.com \
  --objective "o botão de compra está habilitado na tela do produto"
```

Durante a execução, cada passo é exibido no terminal em tempo real. Ao final, o resultado aparece em destaque:

```
Running test...
  ✓ Abriu a tela inicial
  ✓ Navegou até a página do produto
  ✗ Botão "Comprar" estava desabilitado

FAILED: Botão "Comprar" estava desabilitado
```

Execuções repetidas do mesmo teste são mais rápidas porque o TestPilot guarda em cache as respostas da IA — se a tela não mudou, a resposta já está salva localmente.

---

## Como lidar com telas de login

Se o app ou site exige login, o TestPilot consegue entrar antes de começar a análise. Há duas formas:

### Login automático (usuário e senha simples)

Passe o usuário e a senha diretamente no comando. O TestPilot faz o login e então executa o objetivo principal:

```bash
./testpilot analyze \
  --platform web \
  --url https://seu-app.com \
  --objective "como é o fluxo de checkout" \
  --username usuario@exemplo.com \
  --password suasenha
```

Isso funciona em **todas as plataformas** — iOS, Android e Web. A sessão web é salva automaticamente: na próxima vez que rodar para o mesmo site, o login é pulado.

### Login manual (SSO, OAuth, autenticação de dois fatores)

Para fluxos de autenticação mais complexos — como login via Google, SSO corporativo ou verificação por SMS — use o comando `web-login`. Ele abre o navegador para você entrar manualmente:

```bash
./testpilot web-login --url https://seu-app.com
```

O terminal exibe a mensagem: *"Browser aberto. Faça o login e pressione Enter para salvar a sessão."*

Após pressionar Enter, a sessão é salva e reutilizada em todas as execuções seguintes para aquele site — sem precisar fazer login de novo.

---

## O que acontece durante a execução

Não precisa saber disso para usar — mas se tiver curiosidade:

1. O TestPilot abre o app no simulador ou no aparelho
2. Tira uma captura de tela da tela atual
3. Manda a imagem para a IA junto com o seu objetivo
4. A IA decide o que fazer: tocar em algum lugar, rolar a tela, digitar algo — ou emitir um veredicto (análise: *concluído*; teste: *passou/falhou*)
5. A ação é executada no app
6. Repete isso até concluir o objetivo ou chegar ao limite de ações
7. **Modo analyze:** gera um relatório com as capturas de tela e as observações de cada passo
7. **Modo test:** exibe PASSOU ou FALHOU com o motivo

---

## Opções disponíveis

As opções abaixo funcionam em ambos os subcomandos (`analyze` e `test`), salvo indicação.

| Opção | Padrão | O que faz |
|-------|--------|-----------|
| `--platform` | — | `ios`, `android` ou `web` |
| `--app` | — | Nome do app (iOS e Android) |
| `--url` | — | Endereço do site ou protótipo (Web) |
| `--objective` | — | O que você quer analisar ou verificar (em texto livre) |
| `--username` | — | Usuário para login automático antes da análise (opcional) |
| `--password` | — | Senha para login automático (opcional; exige `--username`) |
| `--max-steps` | `20` | Quantas ações a IA pode tomar antes de parar |
| `--output` | `./report.html` | Onde salvar o relatório gerado (apenas `analyze`) |
| `--provider` | via `.env` | Qual IA usar: `gemini` (apenas mobile), `anthropic` ou `openai` |
| `--api-key` | via `.env` | Chave de acesso à IA (alternativa ao arquivo `.env`) |
| `--device` | — | ID do iPhone/iPad para rodar em aparelho físico |
| `--team-id` | — | Código de desenvolvedor Apple (obrigatório ao usar `--device`) |
