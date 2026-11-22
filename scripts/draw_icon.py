"""Rebuild the original project emblem. Optional authoring dependency: Pillow."""
from pathlib import Path
from PIL import Image, ImageDraw
S=3
im=Image.new('RGB',(512*S,512*S),'#122932')
d=ImageDraw.Draw(im)
def box(coords,fill,r=0,outline=None,width=1):
    coords=tuple(round(n*S) for n in coords)
    d.rounded_rectangle(coords,radius=r*S,fill=fill,outline=outline,width=width*S)
def line(points,fill,width):d.line([(x*S,y*S)for x,y in points],fill=fill,width=width*S,joint='curve')
def ellipse(coords,fill=None,outline=None,width=1):d.ellipse(tuple(n*S for n in coords),fill=fill,outline=outline,width=width*S)
box((19,19,493,493),'#193A43',52,'#37565C',2)
# A compact quest journal with three entries and a search lens.
box((104,74,360,399),'#091D26',22)
box((92,60,348,385),'#F0D99C',18)
box((92,60,121,385),'#D7B96B',12)
box((158,41,282,90),'#DDAE46',13)
box((184,54,256,69),'#785D30',6)
for y,w in [(135,125),(205,105),(275,88)]:
    line([(142,y+8),(155,y+21),(178,y-7)],'#277A72',9)
    box((197,y,197+w,y+10),'#665B40',5)
    box((197,y+20,197+w-24,y+26),'#B09A64',3)
# Lens doubles as a Q-shaped mark.
ellipse((265,259,416,410),'#15343E','#E7B447',15)
ellipse((291,285,390,384),'#244C55')
line([(383,384),(442,443)],'#0A2029',36)
line([(383,384),(442,443)],'#E7B447',24)
line([(315,340),(333,359),(366,318)],'#F4DC9B',10)
output=Path(__file__).resolve().parents[1]/'docs/images/icon.png'
im.resize((512,512),Image.Resampling.LANCZOS).save(output)
print(output)
