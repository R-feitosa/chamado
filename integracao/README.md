# Botão "Abrir chamado" nos sistemas do hub

Leva a pessoa para a Central de Chamados já identificada (nome, setor e cargo vindos do login),
com o sistema de origem pré-selecionado e o contexto técnico anexado ao chamado.

## Como funciona
1. O botão chama `chamados.gerar_link_chamado` **com a sessão de quem está logado** no sistema.
2. O banco lê nome (`hub.pessoas`), e-mail, departamento e cargo (`rh.vw_vinculos_atuais`) e devolve
   `https://chamado-jdc5.vercel.app/?t=<token>`. O token é aleatório, vale **2 horas** e é de **uso único**;
   o banco guarda só o hash (mesmo padrão do DISC).
3. A Central lê o token, tira-o da barra de endereço e mostra o formulário com nome (e setor) travados.
   Departamento do RH vira setor pelo de-para `chamados.setor_departamento`; sem correspondência, a pessoa escolhe.
4. Quem ainda não está na lista de solicitantes é cadastrado automaticamente no primeiro chamado.

## Instalar num sistema (React + supabase-js)
1. Copie `integracao/abrir-chamado.ts` para o projeto (ex.: `src/lib/abrir-chamado.ts`).
2. Coloque o botão (cabeçalho ou menu do usuário), trocando `'crm'` pelo código do sistema:

```tsx
import { abrirChamado } from './lib/abrir-chamado';
import { supabase } from './lib/supabase';

export function BotaoAbrirChamado() {
  return (
    <button type="button" onClick={() => abrirChamado(supabase, 'crm').catch((e) => alert(e.message))}>
      Abrir chamado
    </button>
  );
}
```

Códigos: `academy`, `cash`, `consult`, `crm`, `hub`, `imoveis`, `juris`, `legal_ops`, `ponto`, `rf_ops`, `rh`, `tributario`, `valley`.

## Onde já está instalado
| Sistema | Repositório | Onde | Arquivo |
|---|---|---|---|
| Atlas Hub (`hub`) | Rfeitosagroup/atlas-hub | barra superior, ao lado de "Novo Cliente" | `src/lib/abrirChamado.js` (versão JS deste arquivo) |

## Regras e limites
- Só gera link quem tem conta **ativa** em `acessos.usuarios`.
- Até 20 links por hora por pessoa; contexto até 2 KB; URL da tela até 500 caracteres.
- A tela de origem, o navegador, o cargo e o e-mail aparecem só para o time logado (Painel do time).
- Trocar o domínio da Central: `update chamados.configuracao set valor = '<nova url>' where chave = 'app_url';`
