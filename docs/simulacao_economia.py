import math, json, sys
G=2.5
W=[60,25,10,3.5,1.1,0.3,0.08,0.015,0.005]
NAMES=["Comum","Incomum","Raro","Ultrarraro","Épico","Lendário","Mítico","Primordial","Galáctico"]
def odds(luck):
    w=[W[0]]+[x*luck for x in W[1:]]; t=sum(w); return [x/t for x in w]
def wave(n, hp_g=1.13, rew_g=1.09, base_hp=20, base_rew=4):
    count=6+math.floor(n*1.5); hp=base_hp*hp_g**(n-1); rew=math.floor(base_rew*rew_g**(n-1))
    total=0; hps=[]
    for i in range(1,count+1):
        k="N"
        if n>=4 and i%5==0: k="F"
        elif n>=7 and i%7==0: k="T"
        if k=="F": total+=rew; hps.append(hp*0.6)
        elif k=="T": total+=rew*2; hps.append(hp*3)
        else: total+=rew; hps.append(hp)
    if n%10==0: total+=rew*25; hps.append(hp*20)
    return count,hp,total,max(hps)
def sim(p, waves=80, verbose=False):
    cash=250; equiv=[0.0]*7  # 4 slots + 3 weapons in "common-equivalents"
    rows=[]; rolls=0; luck=1; killv=0; t=0
    factory=0
    for n in range(1,waves+1):
        c,hp,rew,maxhp=wave(n,p['hp_g'],p['rew_g'],p['base_hp'],p['base_rew'])
        # duration ~ spawn + walk
        dur=c*0.6+12
        earn=rew*(1+0.1*killv)+factory*dur
        cash+=earn; t+=dur
        # spend: alternate rolls / upgrades simple policy: 70% rolls
        o=odds(luck); e=sum(o[i]*3**i for i in range(9))
        nroll=int(cash*p['roll_share']//p['roll_cost'])
        cash-=nroll*p['roll_cost']; rolls+=nroll
        for s in range(7):
            share = 0.8/4 if s<4 else 0.2/3
            equiv[s]+=nroll*share*e
        cash_upg=cash*0.5
        # buy luck/killvalue/factory lines greedily
        cash-=cash_upg; budget=cash_upg
        bestweapon=max(1,min(9,int(math.log(max(equiv[4:]),3))+1)) if max(equiv[4:])>=1 else 1
        bestpart=max(1,min(9,int(math.log(max(min(equiv[:4]),1),3))+1))
        # needed weapon tier: kill normal zombie in <=3 sword hits by one robot
        need=1
        while need<9 and 10*G**(need-1)*3 < hp: need+=1
        rows.append(dict(wave=n,count=c,hp=round(hp,1),reward_wave=round(rew),cash_rolls=rolls,best_weapon=bestweapon,best_part=bestpart,need_weapon=need,minutes=round(t/60,1)))
    return rows
P=dict(hp_g=1.13,rew_g=1.09,base_hp=20,base_rew=4,roll_cost=100,roll_share=0.7)
rows=sim(P)
for r in rows:
    if r['wave'] in (1,5,10,15,20,25,30,40,50,60,70,80): print(r)
