# CI/CD com Fastlane + match — Design Spec

**Data:** 2026-04-13
**Status:** Aprovado

## Objetivo

Configurar um pipeline de release que gera automaticamente o Mac app DMG assinado e notarizado, além dos artefatos iOS e web, ao publicar uma tag `v*` no GitHub. O Mac app é distribuído para designers e PMs; devs usam a CLI e o app localmente via build DEBUG.

## Decisões

- **Signing:** Fastlane + match (Developer ID, distribuição fora da App Store)
- **Match storage:** repositório privado existente `git@github.com:leoreisbk/certificates.git`
- **Conta Apple:** pessoal (`leoreisbk@gmail.com`)
- **Bundle ID:** `com.leonardoreis.testpilot` (já atualizado no `.xcodeproj`)
- **Bundle ID testes:** `com.leonardoreis.TestPilotTests`

## Estrutura de arquivos

```
mac-app/
  fastlane/
    Fastfile     ← lanes: sync_certs, build_and_notarize
    Matchfile    ← type: developer_id, git_url: git@github.com:leoreisbk/certificates.git
    Appfile      ← app_identifier, team_id
Gemfile          ← gem "fastlane"
Gemfile.lock
```

## Secrets no GitHub (`workco/testpilot`)

| Secret | Origem |
|---|---|
| `MATCH_PASSWORD` | Passphrase do repo de certs (já usada em outro projeto) |
| `MATCH_GIT_BASIC_AUTHORIZATION` | `base64("leoreisbk:github_pat")` (já existe em outro projeto) |
| `ASC_KEY_ID` | App Store Connect → Users and Access → Integrations → Keys |
| `ASC_KEY_ISSUER_ID` | Mesmo lugar (Issuer ID no topo da página) |
| `ASC_KEY_CONTENT` | `base64(AuthKey_XXX.p8)` |
| `APPLE_TEAM_ID` | developer.apple.com → account (10 chars) |

## Fastfile

```ruby
default_platform(:mac)

platform :mac do
  lane :sync_certs do
    app_store_connect_api_key(
      key_id:        ENV["ASC_KEY_ID"],
      issuer_id:     ENV["ASC_KEY_ISSUER_ID"],
      key_content:   ENV["ASC_KEY_CONTENT"],
      is_key_content_base64: true
    )
    match(
      type:     "developer_id",
      readonly: is_ci
    )
  end

  lane :build_and_notarize do
    sync_certs
    build_mac_app(
      project:          "TestPilot.xcodeproj",
      scheme:           "TestPilotApp",
      configuration:    "Release",
      export_method:    "developer-id",
      output_directory: "/tmp/TestPilotExport",
      output_name:      "TestPilotApp"
    )
    sh("hdiutil create -volname TestPilot -srcfolder /tmp/TestPilotExport/TestPilotApp.app -ov -format UDZO /tmp/TestPilot.dmg")
    notarize(
      package:   "/tmp/TestPilot.dmg",
      bundle_id: "com.leonardoreis.testpilot"
    )
  end
end
```

## Matchfile

```ruby
git_url("git@github.com:leoreisbk/certificates.git")
storage_mode("git")
type("developer_id")
app_identifier("com.leonardoreis.testpilot")
username("leoreisbk@gmail.com")
```

## Appfile

```ruby
app_identifier("com.leonardoreis.testpilot")
apple_id("leoreisbk@gmail.com")
team_id(ENV["APPLE_TEAM_ID"])
```

## Mudanças no `release.yml`

### Job `build-mac-app`
Substituir os passos manuais de import cert, xcodebuild, export, notarytool por:

```yaml
- uses: ruby/setup-ruby@v1
  with:
    ruby-version: '3.3'
    bundler-cache: true
  working-directory: mac-app  # Gemfile fica aqui

- name: Build and notarize Mac app
  run: bundle exec fastlane build_and_notarize
  working-directory: mac-app
  env:
    MATCH_PASSWORD:                ${{ secrets.MATCH_PASSWORD }}
    MATCH_GIT_BASIC_AUTHORIZATION: ${{ secrets.MATCH_GIT_BASIC_AUTHORIZATION }}
    ASC_KEY_ID:                    ${{ secrets.ASC_KEY_ID }}
    ASC_KEY_ISSUER_ID:             ${{ secrets.ASC_KEY_ISSUER_ID }}
    ASC_KEY_CONTENT:               ${{ secrets.ASC_KEY_CONTENT }}
    APPLE_TEAM_ID:                 ${{ secrets.APPLE_TEAM_ID }}
    MATCH_READONLY:                "true"
```

### Job `build-ios`
Mudar de debug para release no XCFramework:

```yaml
- name: Build XCFramework
  run: scripts/build_ios_sdk.sh testpilot:assembleTestPilotSharedReleaseXCFramework
```

E atualizar o path de cópia de `debug` para `release`:
```yaml
cp -R sdk/testpilot/build/XCFrameworks/release/TestPilotShared.xcframework dist/ios/
```

## Fluxo local vs CI/CD

| Contexto | Como funciona |
|---|---|
| Dev rodando Mac app no Xcode | `#if DEBUG` pula download — vai direto para `.ready` |
| Dev usando CLI | Artefatos em `~/.testpilot/` (populados manualmente ou via release) |
| Release (tag `v*`) | CI builda tudo, Fastlane assina + notariza, publica no GitHub Releases |
| Designers/PMs | Baixam o `.dmg` do GitHub Releases — instala sem aviso do Gatekeeper |

## Setup inicial (uma vez)

1. Criar App Store Connect API Key (role Developer) e baixar `.p8`
2. Rodar `fastlane match developer_id --username leoreisbk@gmail.com` localmente para gerar e armazenar o cert no repo `certificates`
3. Configurar os 6 secrets no GitHub
4. Criar tag `v0.1.0` para disparar o primeiro release
