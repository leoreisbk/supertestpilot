# Como rodar uma análise de UX no iOS, Android e Web

## O que é o TestPilot?

O TestPilot começou como uma ferramenta para engenheiros: um jeito de escrever testes automatizados de app usando linguagem natural em vez de código complexo. Em vez de programar cada passo, o desenvolvedor escrevia algo como *"vai até a tela de perfil e troca a foto"* — e a IA executava isso no app.

Durante nossas dailies, vendo a necessidade do time por uma ferramenta que ajudasse com benchmarks de UX, lembrei do TestPilot e no quanto ele poderia ser útil para isso. Por isso adicionei uma nova camada: o modo de análise, que qualquer pessoa do time consegue usar sem precisar escrever nenhuma linha de código.

Com o tempo, adicionamos também um segundo modo: o **teste determinístico**, que responde de forma objetiva se uma condição específica do app está satisfeita ou não.

## O que o TestPilot faz?

O TestPilot tem dois modos:

**Análise de UX (`./testpilot analyze`):** a IA navega pelo app como se fosse um usuário real e gera um relatório com capturas de tela e observações sobre a experiência de uso. Você só precisa dizer **o que quer analisar** — a IA faz o resto.

**Exemplo:** *"como é fácil encontrar a aba de treino e iniciar uma atividade"*

**Teste determinístico (`./testpilot test`):** a IA avalia uma condição específica e responde **PASSOU** ou **FALHOU**. Ideal para verificações pontuais ou para rodar em pipelines automatizados.

**Exemplo:** *"o botão de compra está habilitado na tela do produto"*

Ambos funcionam em **iPhone/iPad** (aparelho físico ou simulador), **Android** (aparelho físico ou emulador) e **Web** (qualquer URL acessível no navegador — incluindo protótipos no ProtoPie, Figma ou ambientes de staging).

---

## Como usar o TestPilot

Há duas formas de usar: pelo **app macOS** (recomendado para designers e PMs) ou pelo **terminal** (recomendado para QAs e integração com CI).

### Pelo app macOS

O app macOS é a forma mais simples — sem linha de comando, sem configuração manual.

1. Escolha o **modo** (Analyze ou Test) e a **plataforma** (iOS, Android ou Web)
2. Selecione o dispositivo ou informe a URL do site
3. Escreva o objetivo em texto livre
4. Clique em **Run Analysis** ou **Run Test**

O resultado aparece em tempo real. Para análise, o relatório abre no navegador ao final; para teste, cada passo aparece na tela com o veredicto final em destaque.

### Pelo terminal

Para quem prefere linha de comando ou precisa integrar com CI, todos os recursos estão disponíveis via `./testpilot`. Os exemplos nas seções abaixo usam essa forma.

---

## Antes de usar pela primeira vez

**1. Tenha o app aberto no aparelho, simulador ou a URL em mãos**

- **iPhone/iPad físico:** conecte o aparelho ao Mac com o cabo USB e abra o Xcode para que ele reconheça o aparelho.
- **Simulador de iPhone/iPad:** abra o Xcode, suba um simulador e certifique-se de que o app está instalado nele.
- **Aparelho Android físico:** conecte o aparelho ao computador com o cabo USB. Nas configurações do aparelho, ative o **Modo de desenvolvedor** e dentro dele ative a opção **Depuração USB**.
- **Emulador Android:** abra o Android Studio, suba um emulador e certifique-se de que o app está instalado nele.
- **Web:** basta ter a URL em mãos — nenhuma instalação adicional é necessária.

Se você não sabe como fazer algum dos passos de mobile, peça ajuda a alguém do time de desenvolvimento.

---

**2. Tenha uma chave de acesso à IA**

O TestPilot precisa de uma chave de acesso para usar a inteligência artificial. O TestPilot funciona com três serviços de IA diferentes — escolha um:
- **Google Gemini** → `gemini`
- **Anthropic Claude** → `anthropic`
- **OpenAI (ChatGPT)** → `openai`

**No app macOS:** abra o menu **Settings**, cole a chave no campo **API Key** e escolha o provedor. Nenhum arquivo precisa ser criado.

**No terminal:** crie um arquivo `.env` na pasta do projeto:

```
TESTPILOT_API_KEY=sua-chave-aqui
TESTPILOT_PROVIDER=gemini
```

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

Enquanto a análise roda, você pode acompanhar a IA navegando pelo app em tempo real. Ao terminar, o relatório abre automaticamente no navegador.

---

## Como rodar um teste determinístico

Use `./testpilot test` quando quiser uma resposta objetiva de **passou** ou **falhou** para uma condição específica:

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

O resultado aparece no terminal em tempo real, passo a passo, e ao final:

```
Running test...
  ✓ Abriu a tela inicial
  ✓ Navegou até a página do produto
  ✗ Botão "Comprar" estava desabilitado

FAILED: Botão "Comprar" estava desabilitado
```

Execuções repetidas do mesmo teste são mais rápidas porque o TestPilot guarda em cache as respostas da IA — se a tela não mudou, a resposta já está salva localmente.

---

## O que acontece durante a execução

Não precisa saber disso para usar — mas se tiver curiosidade:

1. O TestPilot abre o app no simulador, aparelho ou navegador
2. Tira uma captura de tela da tela atual e coleta a lista de elementos de interface disponíveis (botões, campos, links, títulos) com seus rótulos — a "árvore de acessibilidade"
3. Manda a imagem e a lista de elementos para a IA junto com o seu objetivo
4. A IA analisa a imagem como um humano faria — lê textos, identifica botões, entende a hierarquia visual — e também lê diretamente os rótulos dos elementos pelo nome
5. A IA decide o que fazer: tocar em algum lugar, rolar a tela, digitar algo — ou emitir um veredicto (análise: *concluído*; teste: *passou/falhou*)
6. A ação é executada no app
7. Repete isso até concluir ou chegar ao limite de ações
8. **Análise:** gera um relatório HTML com capturas de tela e observações de cada passo
8. **Teste:** exibe PASSOU ou FALHOU com o motivo

---

## Por que existe uma pasta `harness/` no projeto?

O iPhone tem uma restrição de segurança: nenhum programa externo consegue controlar um app ou tirar capturas de tela dele diretamente. A Apple só permite esse tipo de acesso durante a execução de **testes automatizados** — que recebem permissões especiais justamente para isso.

A pasta `harness/` é uma estrutura técnica que existe para dar ao TestPilot esse acesso privilegiado. É composta por duas partes:

- **HarnessApp** — um aplicativo auxiliar vazio que precisa estar instalado no aparelho. Você nunca vai abrir ele, ele só precisa existir para que o iOS libere as permissões necessárias. Pense nele como um crachá de acesso.
- **AnalystTests** — é quem de fato executa os comandos: tirar captura de tela, tocar na tela, rolar o conteúdo. É o "braço" que o TestPilot usa para interagir com o app sendo analisado, dentro do contexto de permissão que o HarnessApp abriu.

Você não precisa mexer em nada disso — o TestPilot instala e gerencia tudo automaticamente. No Android essa estrutura não existe porque o sistema Android já permite esse tipo de controle sem restrições adicionais.

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
| `--max-steps` | `40` | Quantas ações a IA pode tomar antes de parar |
| `--output` | `./report.html` | Onde salvar o relatório gerado (apenas `analyze`) |
| `--lang` | `en` | Idioma do relatório: `en` (inglês) ou `pt-BR` (português) |
| `--provider` | via `.env` | Qual IA usar: `gemini`, `anthropic` ou `openai` |
| `--api-key` | via `.env` | Chave de acesso à IA (alternativa ao arquivo `.env`) |
| `--device` | — | ID do iPhone/iPad para rodar em aparelho físico |
| `--team-id` | — | Código de desenvolvedor Apple (obrigatório ao usar `--device`) |
