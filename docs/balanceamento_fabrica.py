# Balanceamento da fábrica: custo, renda e tempo de retorno (payback) de cada linha.
# Compara a configuração do Alfa com a proposta do Beta. Rode: python3 docs/balanceamento_fabrica.py
G = 2.5  # Rarity.Multiplier(t) = G^(t-1)
ALFA_WEIGHTS = {"Torso": 0.5, "Arms": 0.35, "Legs": 0.25, "Head": 0.15}
BETA_WEIGHTS = {"Torso": 0.3, "Arms": 0.25, "Legs": 0.15, "Head": 0.1}

def table(name, base_cost, growth, floors, weights, base_income=2):
    def worker_mult(tier):
        return (G ** (tier - 1)) ** sum(weights.values())
    print(f"\n== {name}: custo {base_cost}×{growth}^n, andares {floors} ==")
    print("linha   custo     renda/s (sem / trab. tier3)   retorno (sem / tier3)")
    ids = [f"{f}-{l}" for f in (1, 2, 3) for l in (1, 2)]
    for i, lid in enumerate(ids):
        floor = int(lid[0])
        cost = base_cost * growth ** i
        inc = base_income * floors[floor - 1]
        inc3 = inc * worker_mult(3)
        print(f"{lid}   {cost:>8,.0f}   {inc:>6.0f} / {inc3:>7.0f}            {cost/inc/60:>6.1f} min / {cost/inc3/60:>5.1f} min")

# Renda das hordas para comparação (recompensa × zumbis por horda / duração ~ 0,6 s por zumbi + 12 s)
print("== Hordas: renda média por segundo ==")
for n in (5, 10, 20, 30):
    count = 6 + int(n * 1.5)
    reward = int(7 * 1.085 ** (n - 1))
    dur = count * 0.6 + 12
    print(f"horda {n:>2}: ~{reward*count/dur:>5.0f}/s")

table("Alfa", 500, 4, (1, 3, 9), ALFA_WEIGHTS)
table("Beta", 500, 3, (1, 4, 16), BETA_WEIGHTS)
