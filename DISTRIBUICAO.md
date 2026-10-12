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
- **Servidor no ar:** `https://torino.deepdive.dev.br`, uma Lambda em Go com DynamoDB na região
  `eu-south-1` (Milão, UE), sem contas (código em `backend/`, contrato em `docs/backend/api.md`). Os
  relatos e o tempo em Turim (Open-Meteo, buscado pelo servidor) já funcionam de ponta a ponta com o app;
  um relato de teste foi enviado, lido e apagado.
- **Widgets, Atividade ao Vivo, controles, Siri e Atalhos.**
- **Texto da loja** em três idiomas: `docs/appstore/metadata.md`.
- **Capturas 6,9" (1320×2868)** em três idiomas: `docs/appstore/screenshots/<idioma>/` (não versionadas;
  refazer com `tools/l10n-screenshots.sh`).
- **Política de privacidade e suporte** em três idiomas: `docs/privacy/` e `docs/support/`.
- **Build:** 294 testes passando; `make archive` gera o `.xcarchive` de Release (5,2 MB), sem a
  permissão do iCloud, falando por padrão com o servidor acima.
- `PrivacyInfo.xcprivacy`, `ITSAppUsesNonExemptEncryption = NO`, orientação em retrato, só iPhone.

## Só você pode fazer

1. **Registrar os identificadores na equipe Nuance** (`N859AT5MST`), com uma conta Admin, em
   developer.apple.com. O app já está configurado com eles, e hoje o export falha por falta deles:
   - `br.tec.nuance.toret`
   - `br.tec.nuance.toret.widgets`
   - App Group `group.br.tec.nuance.toret`, habilitado **nos dois** App IDs (senão os widgets não
     enxergam a sua posição)

   O app **não** usa mais iCloud nem CloudKit: não há contêiner do iCloud, esquema para implantar nem
   capacidade "iCloud" no App ID. Se ela estiver ligada de uma tentativa anterior, desligue.
2. **Servidor (já implantado em `eu-south-1`):** a comunidade e o tempo dependem dele. Manter a conta AWS
   ativa e o certificado do domínio válido; moderação e operação em `docs/community-moderation.md` e
   `docs/backend/api.md` (seção 9). Duas regras que não mudam sem decisão sua:
   - **SMAT fica desligada** (`SmatEnabled=false`, `notices.enabled=false`) até haver **permissão por
     escrito da SMAT**: ela não publica licença para os dados das obras. Nada no app as mostra.
   - **A Open-Meteo gratuita é só para uso não comercial.** Se o app algum dia render dinheiro (preço,
     compra no app, anúncios), é preciso um plano pago da Open-Meteo antes disso. A atribuição
     (CC BY 4.0) já está em Ajustes e na política de privacidade.
3. **App Store Connect:** criar o registro do app com o bundle `br.tec.nuance.toret` e conferir se o nome
   "Toret" está livre (alternativas no `metadata.md`).
4. **Hospedar as duas páginas** e trocar os endereços provisórios. Hoje o app aponta para
   `https://toret.deepdive.dev/privacy` e `/support` (em `SettingsScreen.swift`): são **placeholders**,
   ainda não existe nada nesses endereços. Antes de enviar, eles precisam apontar para páginas
   hospedadas de verdade (a política em `docs/privacy/index.html` e o suporte em
   `docs/support/index.html`), e o App Store Connect também pede as duas URLs. Opção simples: ligar o
   GitHub Pages do repositório na pasta `docs/` e trocar as constantes.
5. **Classificação etária e preço:** gratuito; 12+ por conteúdo gerado por usuários (respostas em
   `metadata.md`).
6. **Rótulo de privacidade:** responder como em `metadata.md` (localização só no aparelho; conteúdo do
   usuário, ID de usuário, ID de dispositivo e dados de diagnóstico coletados pelo servidor, sem
   rastreamento) e conferir com `Toret/PrivacyInfo.xcprivacy`.
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

- **Servidor, o que foi e o que não foi visto.** Verificado contra o servidor de verdade: tempo em Turim,
  enviar, listar e apagar um relato pelo app, ETag/304, o limite de 429 com `Retry-After` e o ajuste de
  datas no futuro. Não verificado: respostas comprimidas (gzip) e a fila de denúncias, que dependem de
  mais dados e de mais de uma instalação; e o limite global de escritas.
- **Em aparelho:** a Dynamic Island, a tela bloqueada, o Centro de Controle, o Botão de Ação, as frases
  da Siri, o widget buscando a localização sozinho, e a bússola com o magnetômetro real.
- **A animação de abertura** (o sol subindo): a primeira imagem bate com o aplicativo, mas o movimento
  não foi visto em captura.
- **Assinatura de distribuição:** o export falha até o item 1 ser feito.
