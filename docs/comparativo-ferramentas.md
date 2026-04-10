# TestPilot vs. outras ferramentas de automação de UI

Este documento compara o TestPilot com duas ferramentas populares — **Maestro** e **FlowDeck** — para ajudar a entender quando usar cada uma e onde o TestPilot se diferencia.

---

## Visão geral das abordagens

| | TestPilot | Maestro | FlowDeck |
|---|---|---|---|
| **Como funciona** | IA enxerga a tela e decide o que fazer | Scripts YAML declarativos | CLI de automação + árvore de acessibilidade |
| **O que você escreve** | Objetivo em linguagem natural | Arquivo `.yaml` com comandos | Comandos de terminal |
| **Quem pode usar** | Qualquer pessoa do time | Engenheiros | Engenheiros |
| **Plataformas** | iOS, Android, Web | iOS, Android, Web | iOS, macOS |
| **Modo exploratório** | Sim (`analyze`) | Não | Não |
| **Modo determinístico** | Sim (`test`) | Sim | Sim |
| **Integração CI** | Sim (exit codes) | Sim | Sim |
| **Depende de IA** | Sim (Gemini, Claude, OpenAI) | Não | Parcialmente |
| **Cache de respostas** | Sim (reruns instantâneos) | N/A | Sim |
| **Árvore de acessibilidade** | Sim (iOS, Android, Web) | Não | Sim |

---

## Maestro

**Como funciona:** Você escreve um arquivo YAML descrevendo os passos do teste. O Maestro interpreta esses passos e os executa no dispositivo usando detecção tradicional de elementos de UI.

```yaml
# Exemplo de fluxo Maestro
appId: com.example.myapp
---
- launchApp
- tapOn: "Login"
- inputText: "user@email.com"
- tapOn: "Continuar"
- assertVisible: "Tela principal"
```

**Quando usar Maestro:**
- Testes de regressão que precisam ser 100% determinísticos
- Times que precisam de controle preciso sobre cada passo (loops, condicionais, JavaScript)
- Quando não se quer depender de uma API de IA em cada execução
- Suítes grandes de testes que rodam em paralelo na nuvem

**Limitações em relação ao TestPilot:**
- Requer escrever e manter scripts YAML para cada fluxo
- Não tem modo exploratório — você precisa saber exatamente o que testar
- Quando a interface muda, os scripts precisam ser atualizados manualmente
- Não está acessível para designers e PMs sem treinamento

---

## FlowDeck

**Como funciona:** CLI que controla o simulador/dispositivo via comandos diretos, capturando screenshots e árvores de acessibilidade. Tem controle preciso sobre o tempo de estabilização entre ações.

```bash
# Exemplo de uso FlowDeck
flowdeck tap --label "Login"
flowdeck type "usuario@email.com"
flowdeck wait --timeout 3000
flowdeck assert --visible "Tela principal"
```

**Quando usar FlowDeck:**
- Automação de UI iOS/macOS onde controle de timing é crítico
- Times que já usam scripts e querem adicionar captura de tela automatizada
- Quando a árvore de acessibilidade do app está bem estruturada

**Limitações em relação ao TestPilot:**
- Requer comandos explícitos para cada interação
- Não tem modo exploratório — só executa o que você programou
- Suporte apenas a iOS e macOS (sem Android ou Web)
- Ainda necessita de escrita de scripts por um engenheiro

---

## TestPilot

**Como funciona:** Você descreve o que quer verificar em linguagem natural. A IA tira capturas de tela, interpreta a interface visualmente e decide sozinha como navegar — sem precisar de seletores, IDs ou scripts.

```bash
# Modo análise — exploração livre
./testpilot analyze \
  --platform ios \
  --app "Meu App" \
  --objective "como é fácil encontrar e usar o fluxo de checkout"

# Modo teste — verificação objetiva
./testpilot test \
  --platform ios \
  --app "Meu App" \
  --objective "o botão de compra está habilitado na tela do produto"
```

**Quando o TestPilot se destaca:**

**1. Análise exploratória de UX** — único modo que não exige que você saiba o que vai encontrar. A IA navega livremente e gera um relatório com capturas de tela e observações. Isso não existe no Maestro nem no FlowDeck.

**2. Times não-técnicos** — designers e PMs conseguem rodar análises diretamente, sem depender de engenheiros para escrever scripts.

**3. Manutenção zero de scripts** — quando a interface do app muda, o TestPilot se adapta automaticamente porque toma decisões a cada passo. Maestro e FlowDeck quebram quando a UI muda.

**6. Árvore de acessibilidade integrada** — além da captura de tela, o TestPilot envia a lista de elementos de interface (botões, campos, links com seus rótulos) para a IA a cada passo. A IA lê os labels dos elementos diretamente, sem depender apenas da interpretação visual — o mesmo nível de precisão que o FlowDeck oferece com a árvore de acessibilidade, mas combinado com visão e sem exigir scripts.

**4. Três provedores de IA** — funciona com Gemini, Anthropic Claude ou OpenAI. Você escolhe o que o time já usa.

**5. Cache inteligente** — reruns do mesmo teste (sem mudança na UI) são instantâneos porque as respostas da IA ficam salvas localmente. Útil em pipelines de CI.

**Onde Maestro e FlowDeck têm vantagem:**
- Testes 100% determinísticos sem custo de API
- Controle preciso sobre cada passo da interação
- Melhor para suítes grandes de regressão onde a UI é estável

---

## Resumo: qual usar em cada situação

| Situação | Ferramenta recomendada |
|---|---|
| "Quero entender como está a experiência de criar conta" | **TestPilot** (analyze) |
| "Quero verificar se o checkout funciona antes de um deploy" | **TestPilot** (test) |
| "Tenho 200 testes de regressão que precisam rodar em 5 minutos" | **Maestro** |
| "Quero um script preciso que testa exatamente os mesmos passos toda vez" | **Maestro** |
| "Quero automação iOS com controle fino de timing e árvore de acessibilidade" | **FlowDeck** |
| "O designer do time precisa validar um fluxo sem ajuda de engenheiro" | **TestPilot** |
| "Quero integrar com CI e receber PASS/FAIL automaticamente" | **TestPilot** ou **Maestro** |
