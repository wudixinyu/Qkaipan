import numpy as np
from PIL import Image
import os
from collections import deque
d=r'assets/art/characters'
def dil(m):
    o=m.copy()
    o[1:,:]|=m[:-1,:]; o[:-1,:]|=m[1:,:]; o[:,1:]|=m[:,:-1]; o[:,:-1]|=m[:,1:]
    return o
def comps(mask):
    lab=np.zeros(mask.shape,np.int32); n=0
    ys,xs=np.nonzero(mask)
    for y0,x0 in zip(ys,xs):
        if lab[y0,x0]: continue
        n+=1; lab[y0,x0]=n; q=deque([(y0,x0)])
        while q:
            y,x=q.popleft()
            for ny,nx in ((y+1,x),(y-1,x),(y,x+1),(y,x-1)):
                if 0<=ny<mask.shape[0] and 0<=nx<mask.shape[1] and mask[ny,nx] and not lab[ny,nx]:
                    lab[ny,nx]=n; q.append((ny,nx))
    return lab,n
for k in ['ranger','earth_guardian','priest','arcane_girl']:
    a=np.asarray(Image.open(os.path.join(d,f'char_{k}.png')).convert('RGBA')).astype(np.int32)
    r,g,b,al=a[...,0],a[...,1],a[...,2],a[...,3]
    luma=(r*299+g*587+b*114)//1000
    chroma=np.maximum(np.maximum(r,g),b)-np.minimum(np.minimum(r,g),b)
    white=(al>32)&(luma>=225)&(chroma<=22)
    body=al>32
    dark=body&(luma<120)
    thickwhite=dil(dil(dil(white)))&white          # 距非白>3 的"厚白"
    lab,n=comps(white)
    tot=white.shape[0]*white.shape[1]
    print(f'=== {k}  (image {tot} px, comps {n})')
    rows=[]
    for i in range(1,n+1):
        m=lab==i; sz=int(m.sum())
        if sz<400: continue
        edge=dil(m)&~m
        rows.append((sz, i, int((edge&dark).sum())/max(1,int(edge.sum())),
                        int((m&thickwhite).sum())/sz,
                        int((edge&~body).sum())/max(1,int(edge.sum()))))
    for sz,i,fd,ft,fo in sorted(rows,reverse=True)[:8]:
        print(f'  comp{i:<3d} size={sz:>6d} ({sz/tot*100:4.2f}%)  边界暗墨={fd:.2f}  自身厚白={ft:.2f}  边界接透明={fo:.2f}')
