# Distribuição

O que falta para o Toret chegar à App Store, separado entre o que já está pronto e o que só você pode fazer.

## Já está pronto

- **Dados reais.** 723 fontes públicas de Turim, vindas do OpenStreetMap, embutidas no app
  (`Shared/Resources/fountains.json`, gerado por `tools/build-catalogue.py`). Nenhuma leitura de água
  é inventada: sem relato da comunidade, a fonte aparece como "sem relato recente".
- **Identidade visual** de cartaz de viagem, ícone (claro, escuro e monocromático), tela de abertura.
- **Idiomas:** português (Brasil), inglês e italiano, escolhidos pelo idioma do aparelho; qualquer outro
  idioma cai em inglês.
- **Comunidade:** avaliação e relatos com denunciar, bloquear, apagar o próprio e contato (diretriz 1.2).
- **Widgets, Atividade ao Vivo, controles, Siri e Atalhos.**
- **Texto da loja** em três idiomas: `docs/appstore/metadata.md`.
- **Capturas 6,9" (1320×2868)** em três idiomas: `docs/appstore/screenshots/<idioma>/` (não versionadas;
  refazer com `tools/l10n-screenshots.sh`).
- **Política de privacidade e suporte** em três idiomas: `docs/privacy/` e `docs/support/`.
- **Build:** 176 testes passando; `make archive` gera o `.xcarchive` de Release (4,5 MB).
- `PrivacyInfo.xcprivacy`, `ITSAppUsesNonExemptEncryption = NO`, orientação em retrato, só iPhone.

## Só você pode fazer

1. **Registrar os identificadores na equipe Nuance** (`N859AT5MST`), com uma conta Admin, em
   developer.apple.com. O app já está configurado com eles, e hoje o export falha por falta deles:
   - `br.tec.nuance.toret`
   - `br.tec.nuance.toret.widgets`
   - App Group `group.br.tec.nuance.toret`, habilitado **nos dois** App IDs (senão os widgets não
     enxergam a sua posição)
   - Contêiner do iCloud `iCloud.br.tec.nuance.toret` (CloudKit), habilitado no App ID do app
2. **CloudKit:** criar o esquema e implantar em Produção, com os índices e as funções de segurança
   descritos em `docs/community-moderation.md`. Sem isso os relatos ficam só no aparelho.
3. **App Store Connect:** criar o registro do app com o bundle `br.tec.nuance.toret` e conferir se o nome
   "Toret" está livre (alternativas no `metadata.md`).
4. **Hospedar as duas páginas** e trocar os endereços provisórios. Hoje o app aponta para
   `https://toret.deepdive.dev/privacy` e `/support` (em `SettingsScreen.swift`), e o App Store Connect
   também pede as duas URLs. Opção simples: ligar o GitHub Pages do repositório na pasta `docs/`.
5. **Classificação etária e preço:** gratuito; 12+ por conteúdo gerado por usuários (respostas em
   `metadata.md`).
6. **Rótulo de privacidade:** responder como em `metadata.md` (localização só no aparelho; conteúdo do
   usuário coletado, sem vínculo com identidade, sem rastreamento).
7. **Justificar a localização "sempre"** na revisão: o aviso de proximidade (100 m, 8 regiões) e a
   atualização dos widgets. Tudo funciona também só com "ao usar o app".
8. **Enviar:** o upload precisa de uma conta com acesso; use o comando abaixo e envie para o TestFlight.

## Comandos

```sh
make test                      # testes no simulador (idioma fixo em pt-BR)
make archive                   # arquivo de Release local, nada é enviado
make testflight UPLOAD=NO      # ensaio: assina e escreve o .ipa em build/testflight/export
make testflight                # envia ao TestFlight (precisa dos itens 1 e 3)
```

A chave da API do App Store Connect fica em `local.mk` (fora do Git); veja `local.mk.example`.

## Ainda não verificado

- **CloudKit de verdade.** Tudo passa por um protocolo e foi testado com um servidor falso; salvar,
  consultar, denunciar e as regras de segurança só podem ser testados com o contêiner criado.
- **Em aparelho:** a Dynamic Island, a tela bloqueada, o Centro de Controle, o Botão de Ação, as frases
  da Siri, o widget buscando a localização sozinho, e a bússola com o magnetômetro real.
- **A animação de abertura** (o sol subindo): a primeira imagem bate com o aplicativo, mas o movimento
  não foi visto em captura.
- **Assinatura de distribuição:** o export falha até o item 1 ser feito.
