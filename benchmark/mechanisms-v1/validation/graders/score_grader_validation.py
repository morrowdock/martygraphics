#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Score grader answers for mechanisms-v1 temporal validation against KEY.json (tolerances from KEY.scoring)."""
import json,re,sys
key=json.load(open(sys.argv[1])); mapping=json.load(open(sys.argv[2])); ans=json.load(open(sys.argv[3]))
tol=key["scoring"]["tolerance"]; K={c["id"]:c for c in key["packets"]}
def nums(s): return [float(x) for x in re.findall(r"-?\d+(?:\.\d+)?",s)]
def circ(a,b): d=abs(a-b)%360; return min(d,360-d)
rows=[];ok_in=0;n_in=0;wrong_dir=0
for a in ans:
    cid=mapping[a["case"]]; c=K[cid]; g=a["answer"].lower().strip(); ok=False
    if cid.startswith("V1"):
        ok = g==c["answer"]
        if c["inScope"] and g in("clockwise","counterclockwise") and g!=c["answer"]: wrong_dir+=1
    elif cid.startswith("V2"):
        kn=nums(c["answer"]); gn=nums(g)
        if len(gn)>=3: ok = circ(gn[0],kn[0])<=tol["valveDegrees"] and circ(gn[1],kn[1])<=tol["valveDegrees"] and gn[2]==kn[2]
    elif cid.startswith("V3"):
        kn=nums(c["answer"]); step=re.search(r"(\d+(?:\.\d+)?)\s*degrees",g)
        pct=[float(x) for x in re.findall(r"(\d+(?:\.\d+)?)\s*%",g)]
        if not pct:
            m=re.search(r"(\d+(?:\.\d+)?)\s*%?\s*(?:-|–|to)\s*(\d+(?:\.\d+)?)\s*%",g)
            if m: pct=[float(m.group(1)),float(m.group(2))]
        m2=re.search(r"(\d+(?:\.\d+)?)\s*(?:-|–)\s*(\d+(?:\.\d+)?)\s*%",g)
        if m2: pct=[float(m2.group(1)),float(m2.group(2))]
        share=sum(pct)/len(pct) if pct else None
        if step and share is not None and "opposite" in g: ok = abs(float(step.group(1))-kn[0])<=tol["genevaStepDegrees"] and abs(share-kn[1])<=tol["genevaSharePoints"]
    elif cid.startswith("V4"):
        if c["inScope"]:
            kt=nums(c["answer"])[0]; gn=nums(g)
            ok = g.startswith("yes") and len(gn)>0 and abs(gn[0]-kt)<=tol["flickerSeconds"]
        else: ok=None
    if c["inScope"]:
        n_in+=1; ok_in+=bool(ok)
    rows.append((a["case"],cid,c["inScope"],c["answer"],a["answer"],ok))
for r in rows: print("%s %-28s in=%s ok=%s | key: %s | got: %s"%(r[0],r[1],r[2],r[5],r[3],r[4]))
rate=ok_in/n_in; passed= rate>=0.9 and wrong_dir==0
print(json.dumps({"inScopeCorrect":ok_in,"inScope":n_in,"rate":round(rate,4),"wrongDirectionInScope":wrong_dir,"pass":passed}))
