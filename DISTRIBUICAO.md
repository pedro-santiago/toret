# Distribuição

O que falta para o Toret sair do simulador, em ordem de quem pode fazer o quê.

## Bloqueio de conteúdo, antes de qualquer coisa técnica

As leituras de água são inventadas. As posições e os números de placa são reais
— o Comune di Torino os publica —, mas o estado da água, a temperatura na bica e
a trilha de verificações foram escritos à mão como stand-in de um feed ao vivo.

Publicar assim significa dizer a um desconhecido com sede que há água corrente
num lugar onde talvez não haja. Duas saídas, e a escolha é de produto, não de
engenharia:

1. **Ligar a um feed real.** O Comune publica o cadastro dos toret em dados
   abertos; o estado da água exigiria ou uma integração com a AMIAT/SMAT ou um
   modelo de verificação comunitária de verdade (relatos datados, com autor).
   `FountainDossier` e `Verification` já têm o formato certo para receber isso.
2. **Assumir o que é.** Trocar toda a linguagem de estado por "última
   verificação da comunidade" sem afirmação própria do app, e catalogar as ~800
   fontes reais em vez de 12. O app deixa de responder "tem água?" e passa a
   responder "onde ficam?", que é uma pergunta menor mas verdadeira.

Enquanto uma das duas não estiver feita, o resto desta lista é preparação.

## Só você pode fazer

- Apple Developer Program ativo (US$ 99/ano) e aceite dos contratos.
- Preencher `DEVELOPMENT_TEAM` no `project.yml` com o Team ID e rodar
  `xcodegen generate`.
- Registrar no portal os três identificadores e o grupo:
  - `br.tec.nuance.toret`
  - `br.tec.nuance.toret.widgets`
  - `group.br.tec.nuance.toret` — habilitado **nos dois** App IDs, senão o
    `Store` cai no defaults do próprio alvo e os widgets mostram o centro de
    Turim em vez da sua posição.
- Criar o registro no App Store Connect e conferir se o nome "Toret" está livre.
- URL de política de privacidade e de suporte (obrigatórias por usar
  localização).
- Justificar o `UIBackgroundModes: location` e a autorização "sempre" na revisão:
  a geocerca de 100 m em volta das fontes com água é o motivo, e é o único.
- Fazer o upload e submeter — precisa do 2FA da sua Apple ID.

## Já está pronto

- `PrivacyInfo.xcprivacy` nos dois bundles, declarando `UserDefaults` com o
  motivo `CA92.1` (acesso dentro do app e do seu grupo).
- `ITSAppUsesNonExemptEncryption: false`, para o upload não parar na pergunta de
  criptografia a cada envio.
- Rótulo de privacidade: **Data Not Collected**. Nada sai do aparelho — a posição
  é medida, usada para ordenar o catálogo, escrita no app group para os widgets
  lerem, e nunca enviada a lugar nenhum.
- Ícone 1024, `LaunchBackground`, orientação travada em retrato, `pt-BR` como
  região de desenvolvimento.
- Build limpo em Release, sem avisos. 22 testes no mesmo scheme.

## Ainda falta preparar

- Capturas para a App Store: 6,9" e 6,5" obrigatórias. As do simulador em
  `/private/tmp/.../scratchpad/fin-*.png` servem de base, mas precisam do
  enquadramento e dos textos da loja.
- Classificação etária, categoria (Navegação ou Viagem) e preço.
- Texto de "Novidades" e descrição — em pt-BR e, dado que o app é sobre Turim,
  provavelmente também em italiano.
- Decidir se as fontes salvas devem migrar para iCloud antes do primeiro
  lançamento; depois disso, mudar o formato guardado quebra quem já salvou.

## Arquivar, quando o Team ID estiver no lugar

```sh
xcodegen generate
xcodebuild -project Toret.xcodeproj -scheme Toret \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/Toret.xcarchive archive
```

O upload sai do Organizer do Xcode, ou por `xcrun altool`/`notarytool` com uma
chave de App Store Connect que também é sua.
