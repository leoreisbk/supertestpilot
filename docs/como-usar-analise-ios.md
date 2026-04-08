# Como rodar uma análise de UX no iOS e Android

## O que é o TestPilot?

O TestPilot começou como uma ferramenta para engenheiros: um jeito de escrever testes automatizados de app usando linguagem natural em vez de código complexo. Em vez de programar cada passo, o desenvolvedor escrevia algo como *"vai até a tela de perfil e troca a foto"* — e a IA executava isso no app.

Durante nossas dailies, vendo a necessidade do time por uma ferramenta que ajudasse com benchmarks de UX, lembrei do TestPilot e no quanto ele poderia ser útil para isso. Por isso adicionei uma nova camada: o modo de análise, que qualquer pessoa do time consegue usar sem precisar escrever nenhuma linha de código.

## O que é a análise de UX?

A análise usa inteligência artificial para navegar pelo app como se fosse um usuário real e, ao final, gera um relatório com observações sobre a experiência de uso. Você só precisa dizer **o que quer analisar** — a IA faz o resto.

Funciona tanto em **iPhone/iPad** (aparelho físico ou simulador) quanto em **Android** (aparelho físico ou emulador).

**Exemplo de objetivo:** *"como é fácil encontrar a aba de treino e iniciar uma atividade"*

---

## Antes de usar pela primeira vez

**1. Tenha o app aberto no aparelho ou simulador**

- **iPhone/iPad físico:** conecte o aparelho ao Mac com o cabo USB e abra o Xcode para que ele reconheça o aparelho.
- **Simulador de iPhone/iPad:** abra o Xcode, suba um simulador e certifique-se de que o app está instalado nele.
- **Aparelho Android físico:** conecte o aparelho ao computador com o cabo USB. Nas configurações do aparelho, ative o **Modo de desenvolvedor** e dentro dele ative a opção **Depuração USB**.
- **Emulador Android:** abra o Android Studio, suba um emulador e certifique-se de que o app está instalado nele.

Se você não sabe como fazer algum desses passos, peça ajuda a alguém do time de desenvolvimento.

---

**2. Tenha uma chave de acesso à IA**

O TestPilot precisa de uma chave de acesso para usar a inteligência artificial. Essa chave é como uma senha que permite ao TestPilot se comunicar com o serviço de IA escolhido.

Peça ao time de desenvolvimento para criar um arquivo chamado `.env` na pasta do projeto com o seguinte conteúdo:

```
TESTPILOT_API_KEY=sua-chave-aqui
TESTPILOT_PROVIDER=gemini
```

O TestPilot funciona com três serviços de IA diferentes — escolha um:
- **Google Gemini** → use `gemini`
- **Anthropic Claude** → use `anthropic`
- **OpenAI (ChatGPT)** → use `openai`

---

**3. Tenha o Xcode instalado no Mac (apenas para iOS)**

O Xcode é o programa da Apple para desenvolvimento de apps. Se não estiver instalado, peça ao time de desenvolvimento para instalar.

---

## Como rodar a análise

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

Enquanto a análise roda, você pode acompanhar a IA navegando pelo app em tempo real. Ao terminar, o relatório abre automaticamente no navegador.

---

## O que acontece durante a análise

Não precisa saber disso para usar — mas se tiver curiosidade:

1. O TestPilot abre o app no simulador ou no aparelho
2. Tira uma captura de tela da tela atual
3. Manda a imagem para a IA junto com o seu objetivo
4. A IA decide o que fazer: tocar em algum lugar, rolar a tela, digitar algo
5. A ação é executada no app
6. Repete isso até completar o objetivo ou chegar ao limite de ações
7. Gera um relatório com as capturas de tela e as observações de cada passo

---

## Por que existe uma pasta `harness/` no projeto?

O iPhone tem uma restrição de segurança: nenhum programa externo consegue controlar um app ou tirar capturas de tela dele diretamente. A Apple só permite esse tipo de acesso durante a execução de **testes automatizados** — que recebem permissões especiais justamente para isso.

A pasta `harness/` é uma estrutura técnica que existe para dar ao TestPilot esse acesso privilegiado. É composta por duas partes:

- **HarnessApp** — um aplicativo auxiliar vazio que precisa estar instalado no aparelho. Você nunca vai abrir ele, ele só precisa existir para que o iOS libere as permissões necessárias. Pense nele como um crachá de acesso.
- **AnalystTests** — é quem de fato executa os comandos: tirar captura de tela, tocar na tela, rolar o conteúdo. É o "braço" que o TestPilot usa para interagir com o app sendo analisado, dentro do contexto de permissão que o HarnessApp abriu.

Você não precisa mexer em nada disso — o TestPilot instala e gerencia tudo automaticamente. No Android essa estrutura não existe porque o sistema Android já permite esse tipo de controle sem restrições adicionais.

---

## Opções disponíveis

| Opção | Padrão | O que faz |
|-------|--------|-----------|
| `--app` | — | Nome do app a analisar |
| `--objective` | — | O que você quer analisar (em texto livre) |
| `--max-steps` | `20` | Quantas ações a IA pode tomar antes de parar |
| `--output` | `./report.html` | Onde salvar o relatório gerado |
| `--provider` | via `.env` | Qual IA usar: `gemini`, `anthropic` ou `openai` |
| `--api-key` | via `.env` | Chave de acesso à IA (alternativa ao arquivo `.env`) |
| `--device` | — | ID do iPhone/iPad para rodar em aparelho físico |
| `--team-id` | — | Código de desenvolvedor Apple (obrigatório ao usar `--device`) |
