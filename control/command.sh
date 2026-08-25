set -euo pipefail
PACK=/opt/minecraft/resourcepack/world-ui-26.3-snapshot-9.zip
REG=/opt/minecraft/server/brigada-item-registry.tsv
python3 - <<'PY'
from pathlib import Path
import json, zipfile
reg={k:int(i) for i,k in (line.split('\t',1) for line in Path('/opt/minecraft/server/brigada-item-registry.tsv').read_text().splitlines() if '\t' in line)}
with zipfile.ZipFile('/opt/minecraft/resourcepack/world-ui-26.3-snapshot-9.zip') as z:
    data=json.loads(z.read('assets/brigada_core/font/item_icons.json'))
chars={ord(p['chars'][0]):p['file'] for p in data['providers'] if p.get('chars')}
items=['minecraft:netherite_sword','minecraft:bone','minecraft:spider_eye','minecraft:arrow','minecraft:bow','minecraft:crossbow','minecraft:cod_bucket','minecraft:poppy','minecraft:shulker_shell','minecraft:gold_nugget','minecraft:magma_cream','minecraft:cod','minecraft:string','minecraft:rotten_flesh','minecraft:feather','minecraft:iron_ingot','minecraft:gold_ingot','minecraft:chicken']
print('=== screenshot item icons ===')
failed=[]
for item in items:
    rid=reg.get(item)
    cp=None if rid is None else 0xE300+rid
    tex=chars.get(cp) if cp is not None else None
    ok=tex is not None
    print(f'{item:32} raw={rid!s:5} cp={hex(cp) if cp else "-":8} ok={ok!s:5} texture={tex}')
    if not ok: failed.append(item)
print('failed=',failed)
print('providers=',len(chars))
PY
sha1sum "$PACK"
curl -fsS http://127.0.0.1:8088/world-ui-26.3-snapshot-9.zip | sha1sum
