# Robôs vs. Zumbis (Roblox)

Tower defense + tycoon + gacha. GDD e backlog completos no Notion ("GDD — Robôs vs. Zumbis (Roblox)").

## Como rodar

1. Instale o [Rokit](https://github.com/rojo-rbx/rokit) e, nesta pasta, rode `rokit install` (instala Rojo, Selene e StyLua).
2. Instale o plugin do Rojo no Studio (`rojo plugin install`).
3. Rode `rojo serve` aqui e clique em **Connect** no plugin do Rojo dentro do Studio.
4. Dê Play. Cada jogador recebe uma base provisória e as hordas começam sozinhas.

Configure o jogo para **5 jogadores por servidor** (Game Settings → Places → Max Players).
No Studio, os dados vão para o DataStore `PlayerData_v1_Studio` (separado do jogo publicado).
Sem **Game Settings → Security → Enable Studio Access to API Services**, o ProfileStore usa um DataStore simulado.

## Estrutura

```
src/
  shared/              → ReplicatedStorage.Shared
    Config/Rarity       9 tiers, pesos da roleta, multiplicador exponencial, odds com sorte
    Config/Items        peças (Cabeça/Torso/Braços/Pernas) e armas (Espada/Martelo/Rifle)
    Config/Economy      custos, upgrades, perdas (10% derrota / 5% PvP)
    Config/Horde        escalonamento das hordas, boss a cada 10, limite de 15 vivos
    Config/Grid         grid hexagonal 4 fileiras × 2..7 colunas (A = frente)
    Net                 nomes dos remotes
  server/              → ServerScriptService.Server
    Data/Template       estrutura salva do jogador
    Services/
      DataService       ProfileStore (session lock) + Replica (sincroniza com o cliente)
      RemoteGuard       entrada única do cliente: validação, rate limit, pcall
      BaseService       5 bases ao redor do centro, grid hexagonal e ponto A (gera placeholder)
      RobotService      robôs do grid: perseguem zumbis; vida salva entre hordas, quebrado só volta na derrota
      HordeService      horda instanciada, zumbis caçam robôs e depois a base, pausa do jogador, checkpoints
      RebirthService    Rebirth: troca progresso por multiplicador permanente + giros grátis
      PvpService        ciclo 20/10 min, arena King of the Hill, zona contestada, bônus do vencedor
      SocialService     alianças e trocas seguras (horda 20+, confirmação dupla, troca atômica)
      WorldService      ciclo dia/noite
      InventoryService  roleta, forja 3→1, venda, auto-fundir/vender, equipar, upgrades
  client/              → StarterPlayerScripts.Client
    Hud                 HUD provisório para testes (será trocado pelas telas do Figma)
vendor/                 ProfileStore e Replica (MadStudio, licença MIT)
```

## Regras de segurança

- O cliente **só pede**; todo sorteio, custo, fusão e recompensa é decidido no servidor.
- Toda escrita em dados salvos passa por `DataService` (atualiza perfil e cliente juntos).
- Itens equipados não podem ser vendidos nem fundidos.
- Cada remote tem rate limit (token bucket) em `RemoteGuard.Handle`.

## Ferramentas

- `stylua src` formata o código.
- `selene src` aponta problemas.
- Bibliotecas: [ProfileStore](https://github.com/MadStudioRoblox/ProfileStore) e
  [Replica](https://github.com/MadStudioRoblox/Replica), sucessores oficiais do ProfileService/ReplicaService.
