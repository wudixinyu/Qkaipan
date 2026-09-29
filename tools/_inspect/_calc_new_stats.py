# -*- coding: utf-8 -*-
REF = {
 'holy_priest':   {'lv':29,'b':{'hp':900,'atk':140,'def':75,'mres':210,'spd':100},'g':{'hp':52,'atk':6,'def':4.4,'mres':10,'spd':0.38}},
 'arcane_girl':   {'lv':29,'b':{'hp':626,'atk':238,'def':44,'mres':76,'spd':100},'g':{'hp':35.3,'atk':9.7,'def':2.6,'mres':3.9,'spd':0.35}},
 'earth_guardian':{'lv':29,'b':{'hp':1441,'atk':119,'def':152,'mres':113,'spd':85},'g':{'hp':46.9,'atk':3.1,'def':5.4,'mres':3.7,'spd':0.17}},
 'elf_ranger':    {'lv':29,'b':{'hp':860,'atk':205,'def':110,'mres':105,'spd':118},'g':{'hp':48,'atk':8.2,'def':6,'mres':5.6,'spd':0.5}},
 'flame_knight':  {'lv':19,'b':{'hp':927,'atk':102,'def':93,'mres':67,'spd':92},'g':{'hp':45.9,'atk':4.1,'def':5.1,'mres':3.3,'spd':0.16}},
}
CARDS = [
 ('tide_siren','holy_priest',{'hp':1950,'atk':350,'def':190,'mres':260,'spd':108}),
 ('shadow_blade','holy_priest',{'hp':1500,'atk':610,'def':110,'mres':120,'spd':138}),
 ('light_catherine','arcane_girl',{'hp':1700,'atk':540,'def':130,'mres':200,'spd':112}),
 ('forest_sedric','earth_guardian',{'hp':2900,'atk':230,'def':330,'mres':230,'spd':92}),
 ('wind_yahi','elf_ranger',{'hp':1600,'atk':530,'def':125,'mres':135,'spd':130}),
 ('ice_eli','arcane_girl',{'hp':1580,'atk':480,'def':125,'mres':185,'spd':106}),
 ('rock_baroque','earth_guardian',{'hp':2750,'atk':220,'def':320,'mres':215,'spd':91}),
 ('dark_leila','elf_ranger',{'hp':1480,'atk':470,'def':115,'mres':125,'spd':128}),
 ('lily_mage','flame_knight',{'hp':1600,'atk':280,'def':110,'mres':160,'spd':102}),
 ('tom_ranger','flame_knight',{'hp':1450,'atk':270,'def':105,'mres':115,'spd':122}),
]
for cid, ref, panel in CARDS:
    R = REF[ref]; lv = R['lv']
    base = {}; grow = {}
    for s in ['hp','atk','def','mres','spd']:
        ratio = R['b'][s] / (R['b'][s] + R['g'][s]*lv)
        b = round(panel[s]*ratio)
        g = round((panel[s]-b)/lv, 2 if s == 'spd' else 1)
        base[s] = int(b); grow[s] = float(g)
    chk = {s: round(base[s]+grow[s]*lv) for s in base}
    print(cid, 'base', base)
    print('    grow', grow, ' Lv%d panel->' % lv, chk)
