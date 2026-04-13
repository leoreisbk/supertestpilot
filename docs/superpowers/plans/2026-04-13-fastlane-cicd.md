# Fastlane CI/CD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Substituir o pipeline manual de signing/notarização do `release.yml` por Fastlane + match, e corrigir o job `build-ios` para buildar em Release.

**Architecture:** Fastlane fica em `mac-app/fastlane/`, gerenciado por um `Gemfile` em `mac-app/`. O CI instala Ruby/Bundler, roda `bundle exec fastlane build_and_notarize` que usa match para instalar o Developer ID cert do repo privado `leoreisbk/certificates`, builda com `build_mac_app`, cria o DMG e notariza via ASC API Key.

**Tech Stack:** Fastlane 2.x, Ruby 3.3, `match` (storage: git), `build_mac_app` (gym), `notarize`

---

## Mapa de arquivos

| Arquivo | Ação |
|---|---|
| `mac-app/Gemfile` | Criar |
| `mac-app/Gemfile.lock` | Gerado por `bundle install` |
| `mac-app/fastlane/Fastfile` | Criar |
| `mac-app/fastlane/Matchfile` | Criar |
| `mac-app/fastlane/Appfile` | Criar |
| `.github/workflows/release.yml` | Modificar (jobs `build-ios` e `build-mac-app`) |

---

### Task 1: Criar Gemfile

**Files:**
- Create: `mac-app/Gemfile`

- [ ] **Step 1: Criar `mac-app/Gemfile`**

```ruby
# mac-app/Gemfile
source "https://rubygems.org"

gem "fastlane", "~> 2.227"
```

- [ ] **Step 2: Instalar dependências e gerar lockfile**

```bash
cd mac-app
bundle install
```

Expected: Fastlane e dependências instaladas, `Gemfile.lock` gerado.

- [ ] **Step 3: Verificar instalação**

```bash
cd mac-app
bundle exec fastlane --version
```

Expected: `fastlane 2.x.x`

- [ ] **Step 4: Commit**

```bash
git add mac-app/Gemfile mac-app/Gemfile.lock
git commit -m "build(mac): add Gemfile for Fastlane"
```

---

### Task 2: Criar arquivos de configuração Fastlane

**Files:**
- Create: `mac-app/fastlane/Appfile`
- Create: `mac-app/fastlane/Matchfile`

- [ ] **Step 1: Criar `mac-app/fastlane/Appfile`**

```ruby
# mac-app/fastlane/Appfile
app_identifier("com.leonardoreis.testpilot")
apple_id("leoreisbk@gmail.com")
team_id(ENV["APPLE_TEAM_ID"])
```

- [ ] **Step 2: Criar `mac-app/fastlane/Matchfile`**

Nota: usar HTTPS (não SSH) para que `MATCH_GIT_BASIC_AUTHORIZATION` funcione no CI.

```ruby
# mac-app/fastlane/Matchfile
git_url("https://github.com/leoreisbk/certificates.git")
storage_mode("git")
type("developer_id")
app_identifier("com.leonardoreis.testpilot")
username("leoreisbk@gmail.com")
```

- [ ] **Step 3: Verificar que Fastlane reconhece a configuração**

```bash
cd mac-app
bundle exec fastlane lanes
```

Expected: Lista vazia (sem lanes ainda) sem erros de sintaxe.

- [ ] **Step 4: Commit**

```bash
git add mac-app/fastlane/Appfile mac-app/fastlane/Matchfile
git commit -m "build(mac): add Fastlane Appfile and Matchfile"
```

---

### Task 3: Criar Fastfile com lanes sync_certs e build_and_notarize

**Files:**
- Create: `mac-app/fastlane/Fastfile`

- [ ] **Step 1: Criar `mac-app/fastlane/Fastfile`**

```ruby
# mac-app/fastlane/Fastfile
default_platform(:mac)

platform :mac do
  lane :sync_certs do
    app_store_connect_api_key(
      key_id:                  ENV["ASC_KEY_ID"],
      issuer_id:               ENV["ASC_KEY_ISSUER_ID"],
      key_content:             ENV["ASC_KEY_CONTENT"],
      is_key_content_base64:   true
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

- [ ] **Step 2: Verificar sintaxe do Fastfile**

```bash
cd mac-app
bundle exec fastlane lanes
```

Expected:
```
Available lanes:
mac sync_certs
mac build_and_notarize
```

- [ ] **Step 3: Commit**

```bash
git add mac-app/fastlane/Fastfile
git commit -m "build(mac): add Fastfile with sync_certs and build_and_notarize lanes"
```

---

### Task 4: Atualizar job `build-ios` para Release no `release.yml`

**Files:**
- Modify: `.github/workflows/release.yml`

O job `build-ios` atualmente builda a config `debug` do XCFramework. Para distribuição, deve usar `release`.

- [ ] **Step 1: Atualizar o passo "Build XCFramework"**

Em `.github/workflows/release.yml`, localizar o passo:

```yaml
      - name: Build XCFramework
        run: scripts/build_ios_sdk.sh
```

Substituir por:

```yaml
      - name: Build XCFramework
        run: scripts/build_ios_sdk.sh testpilot:assembleTestPilotSharedReleaseXCFramework
```

- [ ] **Step 2: Atualizar o path de cópia de `debug` para `release`**

Localizar:

```yaml
          cp -R sdk/testpilot/build/XCFrameworks/debug/TestPilotShared.xcframework dist/ios/
```

Substituir por:

```yaml
          cp -R sdk/testpilot/build/XCFrameworks/release/TestPilotShared.xcframework dist/ios/
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci(ios): build XCFramework in Release configuration"
```

---

### Task 5: Substituir job `build-mac-app` por Fastlane no `release.yml`

**Files:**
- Modify: `.github/workflows/release.yml`

- [ ] **Step 1: Substituir o conteúdo do job `build-mac-app`**

Localizar o job completo `build-mac-app` (linhas com `Import signing certificate`, `Build and archive Mac app`, `Export app`, `Create DMG`, `Notarize DMG`) e substituir por:

```yaml
  # ── Build, sign, and notarize Mac app DMG ────────────────────────────────────
  build-mac-app:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.3'
          bundler-cache: true
        working-directory: mac-app

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

      - uses: actions/upload-artifact@v4
        with:
          name: mac-dmg
          path: /tmp/TestPilot.dmg
```

- [ ] **Step 2: Verificar que o YAML é válido**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))" && echo "YAML válido"
```

Expected: `YAML válido`

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci(mac): replace manual signing steps with Fastlane build_and_notarize"
```

---

### Task 6: Setup local do match (passo manual — feito por Leonardo)

Este task não envolve código. É executado uma vez localmente para gerar e armazenar o Developer ID cert no repo `leoreisbk/certificates`.

- [ ] **Step 1: Criar App Store Connect API Key**

  1. Acessar [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → Users and Access → **Integrations** → Keys
  2. Clicar em `+` → Nome: `testpilot-ci`, Role: **Developer**
  3. Baixar o arquivo `.p8` (só pode ser baixado uma vez)
  4. Anotar: **Key ID** (ex: `ABC123DEFG`) e **Issuer ID** (no topo da página)

- [ ] **Step 2: Criar variáveis de ambiente temporárias**

```bash
export APPLE_TEAM_ID="<seu team ID de developer.apple.com>"
export ASC_KEY_ID="<Key ID do passo anterior>"
export ASC_KEY_ISSUER_ID="<Issuer ID>"
export ASC_KEY_CONTENT=$(base64 -i /path/to/AuthKey_XXXX.p8)
```

- [ ] **Step 3: Rodar match para gerar e armazenar o cert**

```bash
cd mac-app
bundle exec fastlane match developer_id --username leoreisbk@gmail.com
```

Expected: Match cria um Developer ID Application certificate, armazena criptografado em `https://github.com/leoreisbk/certificates.git`, e instala no Keychain local.

- [ ] **Step 4: Verificar que o cert foi instalado**

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

Expected: linha com `Developer ID Application: Leonardo Reis (XXXXXXXXXX)`

---

### Task 7: Configurar secrets no GitHub (passo manual — feito por Leonardo)

- [ ] **Step 1: Gerar `MATCH_GIT_BASIC_AUTHORIZATION`** (se não reusar de outro projeto)

```bash
echo -n "leoreisbk:<github_personal_access_token>" | base64
```

O PAT precisa ter permissão `repo` (leitura do repo privado `certificates`).

- [ ] **Step 2: Gerar `ASC_KEY_CONTENT`**

```bash
base64 -i /path/to/AuthKey_XXXX.p8
```

- [ ] **Step 3: Adicionar os 6 secrets em `github.com/workco/testpilot` → Settings → Secrets → Actions**

| Secret | Valor |
|---|---|
| `MATCH_PASSWORD` | Passphrase do repo de certs |
| `MATCH_GIT_BASIC_AUTHORIZATION` | Output do Step 1 (ou copiar de outro projeto) |
| `ASC_KEY_ID` | Key ID da App Store Connect |
| `ASC_KEY_ISSUER_ID` | Issuer ID da App Store Connect |
| `ASC_KEY_CONTENT` | Output do Step 2 |
| `APPLE_TEAM_ID` | 10 chars de developer.apple.com/account |

---

### Task 8: Publicar primeiro release

- [ ] **Step 1: Verificar que todos os commits estão em `main`**

```bash
git log --oneline -5
git status
```

Expected: Working tree limpa, todos os commits das Tasks 1-5 presentes.

- [ ] **Step 2: Criar e publicar tag `v0.1.0`**

```bash
git tag v0.1.0
git push origin v0.1.0
```

- [ ] **Step 3: Acompanhar o workflow no GitHub**

Abrir `github.com/workco/testpilot/actions` e acompanhar o run da tag `v0.1.0`.

Ordem esperada dos jobs:
1. `build-ios` e `build-web` rodam em paralelo
2. `build-mac-app` roda em paralelo
3. `create-release` aguarda os 3 e publica

- [ ] **Step 4: Verificar o release publicado**

Abrir `github.com/workco/testpilot/releases/tag/v0.1.0` e confirmar:
- `TestPilotShared.xcframework.zip` presente
- `testpilot-web-runner.tar.gz` presente
- `TestPilot.dmg` presente e notarizado
- `artifacts-manifest.json` presente com SHA256s corretos

- [ ] **Step 5: Testar o DMG em uma máquina limpa**

Baixar `TestPilot.dmg`, abrir, arrastar para Applications — não deve aparecer nenhum aviso do Gatekeeper.
