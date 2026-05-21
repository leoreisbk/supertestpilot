# TestPilot — Voiceover da Apresentação

---

## Slide 1 — Apresentação

[vídeo do TestPilot rodando ao lado]

> "A gente viu duas coisas hoje: primeiro, como **personas** ajudam o time a olhar o produto pelos olhos de quem realmente usa. Depois, como já dá pra pedir pra **IA fazer um teste exploratório** e devolver um deck pronto."

> "Os dois caminhos usam IA pra experimentar o produto antes da gente. E essa ideia já existia internamente — é o TestPilot, uma ferramenta que a gente desenvolve aqui há um tempo. Foi por essa conexão direta que ele virou o lugar natural pra unir as duas pontas num único fluxo."

> "Mas o que era, exatamente, o TestPilot? Ele nasceu em 2023 fazendo o que a engenharia chama de **teste funcional** — a checagem de que as coisas do app funcionam mesmo: o login dá certo, o botão leva pra tela certa, o cadastro envia direito. Você escrevia em linguagem comum o que queria testar — 'vá até a tela de perfil e troque a foto' — e a IA executava. Útil, mas era uma ferramenta de engenheiro: só rodava com código e alguém da engenharia configurando."

> "Esse ano destravamos pra todo o time. A engrenagem já estava lá — o que mudou foi o jeito que a IA enxerga o app. E é exatamente disso que o próximo slide fala."

---

## Slide 2 — Comparativo

> "A virada está em como a ferramenta enxerga o app."

> "**ANTES**, à esquerda — a IA recebia código. Uma lista de tudo o que existe na tela em forma de texto: tipos, identificadores, posições. Como descrever uma foto inteira por escrito. Pra entender isso, precisava ser engenheiro mobile."

> "**AGORA**, à direita — a IA recebe o print da tela. Ela lê o que o usuário vê: enxerga o botão 'Continue with Apple', o campo de email, a hierarquia visual — igualzinho a gente."

> "E como ela percebe o app pelos mesmos olhos de uma pessoa, abre uma porta nova: dá pra simular como gente diferente experimenta o produto — alguém com baixa visão, daltônico, um usuário apressado que só bate o olho. Aqui as **personas** que vocês acabaram de ver entram em jogo."

> "O efeito prático: agora **qualquer um do time** consegue usar — PM, designer, QA, engenheiro. Todos no mesmo nível."

---

## Slide 3 — Conceito

> "Com essa virada, o TestPilot se desdobrou em três dimensões."

> "**Três modos** de uso. O `analyze` é exploração aberta — solta a IA no app e ela volta com um relatório do que viu. O `test` é validação direta — passou ou falhou, bom pra rodar automaticamente toda vez que algo muda. E o `research` compara seu app com referências reais — busca no Mobbin telas de apps que já resolveram problemas parecidos, e mostra onde o nosso ainda está atrás."

> "**Três plataformas**: iOS, Android e Web. E o Web é o que mais interessa pra esse momento — porque ele roda tanto em sites já no ar quanto em **protótipos navegáveis em HTML, exatamente como os que o Márcio acabou de mostrar**. Ou seja: dá pra soltar a IA em cima daquele protótipo, antes mesmo de virar produto."

> "**Duas estratégias de IA**: o **UX Researcher**, que se comporta como um pesquisador sênior, com critério de evidência e severidade. E o modo **Persona**, em que você descreve um usuário e a IA usa o app como se fosse ele — encaixando direto na apresentação sobre personas."

---

## Slide 4 — Prompt — UX Researcher

> "Aqui está o coração do modo padrão. A gente instruiu a IA pra agir como um pesquisador sênior de UX, com regras claras pra cada observação: precisa ser **específica** — apontar tela e elemento exatos —, **baseada em evidência** — descrever o que foi visto —, e **acionável** — clara o suficiente pra alguém saber o que mudar."

> "Cada achado vem com uma etiqueta de severidade: `[CRITICAL]` quando trava o usuário, `[ISSUE]` quando atrapalha mas não trava, `[POSITIVE]` pra padrões que funcionam bem. Não é mágica — é cuidado em como a gente conversa com a IA. É o que separa um relatório útil de um relatório vago."

---

## Slide 5 — Prompt — Persona

> "Aqui o segundo modo — e é onde a apresentação sobre personas encontra o TestPilot. Você passa uma descrição: 'Maria, 35, mãe de dois filhos, pouca paciência pra tutoriais' — e o prompt muda. Não é mais um pesquisador olhando o app. É a Maria usando o app."

> "A IA passa a escrever em primeira pessoa: 'eu não achei o botão', 'eu fiquei confusa aqui', 'isso eu entendi de cara'. Mesmas categorias — CRITICAL, ISSUE, POSITIVE —, mas pelos olhos de alguém específico."

> "Especialmente útil pra testar pensando em públicos diferentes: alguém daltônico, alguém apressado, alguém que nunca usou o app, um usuário sênior. Cada persona traz uma leitura diferente da mesma tela."

---

## Slide 6 — App

> "Pra colocar tudo isso na mão do time, construímos um app de companhia pro Mac. Você escolhe a plataforma — iOS, Android ou Web —, aponta pro celular conectado ou pra URL do site/protótipo, define o modo, descreve o objetivo, opcionalmente cola a persona. Clica em Rodar."

> "Daí o app mostra cada passo em tempo real — qual tela a IA visitou, qual ação tomou, o que ela observou. No final, gera um relatório pronto pra compartilhar — bem na linha daquele deck automático que vocês viram antes."

---

## Slide 7 — Demo

> "Agora a gente vê isso funcionando. Vou rodar duas análises: a primeira no modo UX Researcher, sem persona — o pesquisador olhando o app. A segunda no modo Persona — vou descrever a Maria e deixar ela usar o app."

[demo 1 — UX Researcher]

> "Repara o que está acontecendo: a IA tira um print, manda pro modelo, recebe uma ação — toca, rola, digita — e executa no app. Sem script, sem código. Só o objetivo escrito em linguagem normal."

[demo 2 — Persona]

> "Mesmo app, mesmo objetivo — mas agora pelos olhos da Maria. Repara como a forma das observações muda: primeira pessoa, mais emocional, mais conectada com a intenção da usuária."

[ao final, mostrar o relatório]

> "No final, tudo vira o relatório: cada print, as observações categorizadas por severidade, e um resumo gerado pela IA. Pronto pra compartilhar com qualquer pessoa do time."

---

## Exemplos de objetivo para a demo
> Avalie a experiência de usar o app. Tente iniciar um treino, da tela inicial até o treino em andamento.
> Avalie a experiência de usar o app. Tente iniciar um treino, da tela inicial até o encerramento do treino
> Encontre um treino leve, adequado pra quem está começando, e inicie ele.
> Encontre e inicie um treino leve de 5 a 10 minutos.

**Persona — Carla (iniciante)** — `personas/fitness-carla-iniciante.
> Registre uma caminhada de 30 minutos que você fez ontem sem o Apple Watch.

**Persona — Rafael (atleta amador)** — `personas/fitness-rafael-atleta-amador.
> Compare seu desempenho de corrida desta semana com a média das últimas quatro semanas. 

> Avalie a página de produto como um possível comprador. Foque em três coisas: a clareza das informações principais (foto, preço, descrição); a facilidade de selecionar variações (tamanho, cor, quantidade); e fricções no caminho até o botão de adicionar ao carrinho.