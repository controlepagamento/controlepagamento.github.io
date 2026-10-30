# Controle de Envios — MpH Engenharia (versão na nuvem)

Todo mundo entra pelo mesmo endereço, só com PIN:

| PIN | Quem | O que abre |
|---|---|---|
| **8 números ou mais** | você (administrador) | o Controle completo |
| **6 números** | engenheiro | só as obras dele: o que já foi vinculado e o que precisa resolver |

O aparelho lembra o PIN ("Lembrar neste aparelho"). Na próxima vez, a pessoa já entra direto.

| Arquivo | O que é |
|---|---|
| `index.html` | Tela do PIN e página de consulta dos engenheiros |
| `admin.html` | O Controle completo (abre sozinho depois do seu PIN) |
| `config.js` | Endereço e chave pública do Supabase, mais o e-mail do admin. É o único arquivo que você edita. |
| `supabase/schema.sql` | Banco, regras de acesso, PIN e convites |
| `.nojekyll` | Arquivo vazio que faz o GitHub Pages publicar os arquivos como estão |

---

## 1. Supabase

1. Em supabase.com, crie um projeto. Na região, escolha **South America (São Paulo)**.
2. Abra **SQL Editor → New query**, cole todo o `supabase/schema.sql` e clique em **Run**.
3. Crie o seu acesso de administrador em **Authentication → Users → Add user → Create new user**:
   - **E-mail:** o seu e-mail. Ninguém precisa digitar; a tela do PIN usa sozinha.
   - **Password:** o seu **PIN de administrador**, com 8 números ou mais. Evite sequências como 12345678.
   - Marque **Auto Confirm User**.
4. No **SQL Editor**, rode a linha abaixo com o mesmo e-mail:
   ```sql
   insert into public.admins (email) values ('seu-email@mphengenharia.com.br');
   ```
5. Em **Authentication → Sign In / Providers**, desligue **Allow new users to sign up**.
6. Em **Project Settings → API**, copie a **Project URL** e a **anon public key** e preencha o `config.js`. No mesmo arquivo, coloque o e-mail do passo 3 em `adminEmail`.

## 2. GitHub e GitHub Pages

1. Na conta **controlepagamento** do GitHub, crie um repositório chamado exatamente **`controlepagamento.github.io`**. Com esse nome, o endereço fica limpo: `https://controlepagamento.github.io/`.
   - O GitHub Pages grátis só publica repositório **público**. Isso deixa o código visível, mas **não os dados**: eles ficam no Supabase, protegidos pelas regras do banco. A chave do `config.js` também é pública por natureza.
   - Para deixar o repositório privado, é preciso um plano pago do GitHub (Pro).
2. Envie todos os arquivos desta pasta para o repositório (**Add file → Upload files**), já com o `config.js` preenchido. Inclua o arquivo `.nojekyll`.
3. Em **Settings → Pages**, configure:
   - **Source:** Deploy from a branch
   - **Branch:** `main` e a pasta `/ (root)`
   - Clique em **Save**.
4. Em um ou dois minutos, o endereço `https://controlepagamento.github.io/` aparece na mesma tela. É esse o link que vai para os engenheiros.
5. Cada arquivo novo que você enviar ao repositório é publicado sozinho, em cerca de um minuto.

## 3. Trazer os dados do seu navegador

1. No Controle antigo (o arquivo local), clique em **💾 Salvar na pasta**. Isso gera o `CONTROLE_DADOS.json`.
2. Entre com o seu PIN, clique em **📥 Importar arquivo** e escolha o `CONTROLE_DADOS.json`.

## 4. Engenheiros

Na aba **👷 Engenheiros**:

1. Digite o nome e clique em **+ Adicionar engenheiro**.
2. Clique em **🔗 Convite**. O link é copiado: mande para o engenheiro por WhatsApp ou e-mail.
3. Ele abre o link, cria o próprio PIN de 6 números e já entra. O aparelho dele lembra o PIN.
4. Clique na coluna **Obras** e marque as obras dele.

Se ele esquecer o PIN:
- mande um **🔗 Convite** novo, e ele cria outro PIN; ou
- use **✏️ Definir**, escolha um PIN e passe para ele.

O link de convite vale 7 dias e serve uma vez só. Para cortar o acesso, desmarque **Ativo**.

O seu PIN de administrador você troca em **🔑 Meu PIN**. Se esquecer, defina um novo no Supabase: **Authentication → Users → o seu usuário → Change password**.

## Segurança

- **Filtro no banco:** quem decide o que cada engenheiro vê é o próprio banco. O navegador dele nunca recebe dados de outras obras.
- **PINs criptografados:** os PINs são guardados só em forma criptografada. Nem você consegue lê-los.
- **Bloqueio:** 5 PINs errados em 15 minutos bloqueiam aquele acesso por 15 minutos. O PIN de administrador também tem limite de tentativas, aplicado pelo próprio Supabase.
- **PINs fáceis recusados:** a tela de criação não aceita PINs como 111111 ou 123456. Também não deixa repetir o PIN de outra pessoa nem usar o convite para descobrir o PIN de alguém.
- **Fora do Google:** as páginas pedem para não aparecer em buscas.
- **Inatividade:** a página do engenheiro fecha após 30 minutos parada.
- **Sair:** o botão faz o aparelho esquecer o PIN. Em computador compartilhado, entre com "Lembrar neste aparelho" desmarcado.

## Toda sexta

1. Eu processo os PDFs e gero o arquivo de importação da semana.
2. No Controle, clique em **📥 Importar arquivo** e escolha esse arquivo. Lançamentos já importados são ignorados.
3. Preencha OC e Fase e use **⚡ Vincular**, como hoje.
4. O que você marca como vinculado aparece para o engenheiro na hora.
