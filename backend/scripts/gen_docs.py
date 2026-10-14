# Regenerates docs/architecture/api-endpoints.md and data-model.md. Run from backend/: PYTHONPATH=. python scripts/gen_docs.py
import django, os, inspect
os.environ.setdefault("DJANGO_SETTINGS_MODULE","config.settings.dev"); django.setup()
from django.urls import get_resolver, URLPattern, URLResolver
from django.apps import apps
out=["# API endpoints\n\nGenerated from the Django URL config. Base: `/api/v1/`. Full request/response shapes: `/api/docs/` (Swagger).\n"]
rows=[]
def walk(ps,prefix=""):
    for p in ps:
        if isinstance(p,URLResolver): walk(p.url_patterns,prefix+str(p.pattern))
        else:
            path=(prefix+str(p.pattern)).replace('^','').replace('$','').replace('\\Z','')
            cb=p.callback; cls=getattr(cb,'cls',None) or getattr(cb,'view_class',None)
            actions=getattr(cb,'actions',None)
            methods=[m.upper() for m in (actions or {}).keys()] if actions else ([m.upper() for m in getattr(cls,'http_method_names',[]) if hasattr(cls,m) and m not in('options','head')] if cls else [])
            if '(?P<format>' in path or path.endswith('.(?P<format>[a-z0-9]+)/?'): continue
            doc=(inspect.cleandoc(cls.__dict__.get('__doc__') or '')).split('\n')[0] if cls else ''
            rows.append((path,', '.join(methods),(cls.__module__.split('.')[1] if cls and cls.__module__.startswith('apps') else ''),cls.__name__ if cls else cb.__name__,doc))
walk(get_resolver().url_patterns)
import itertools
rows=[r for r in rows if r[0].startswith('api/v1/') and r[3]!='APIRootView' and 'format' not in r[0]]
for app,grp in itertools.groupby(sorted(rows,key=lambda r:(r[2],r[0])),key=lambda r:r[2]):
    out.append(f"\n## {app or 'other'}\n\n| Path | Methods | View | Notes |\n|---|---|---|---|\n")
    for path,m,_,v,d in grp:
        path=path.replace('api/v1/','').replace('(?P<','<').replace('>[^/.]+)','>').replace('[/.]+)','').replace('>[^/]+)','>').replace('>[0-9]+)','>')
        out.append(f"| `{path}` | {m} | {v} | {d.replace('|','/')} |\n")
open('../docs/architecture/api-endpoints.md','w').write(''.join(out))
dm=["# Data model\n\nGenerated from the Django models. Every field of every app model, with its type, link and choices. Read with `README.md` for the patterns.\n"]
for cfg in sorted(apps.get_app_configs(),key=lambda c:c.label):
    if not cfg.name.startswith('apps.'): continue
    ms=list(cfg.get_models())
    if not ms: continue
    dm.append(f"\n## {cfg.label}\n")
    for m in ms:
        doc=inspect.cleandoc(m.__dict__.get('__doc__') or '').split('\n')[0]
        if doc.startswith(m.__name__+'('): doc=''
        dm.append(f"\n### {m.__name__}\n{doc}\n\n| Field | Type | Notes |\n|---|---|---|\n")
        for f in m._meta.get_fields():
            if f.auto_created and not f.concrete: continue
            t=f.get_internal_type()
            notes=[]
            if f.is_relation and f.related_model: notes.append(f"→ {f.related_model.__name__}")
            if getattr(f,'choices',None): notes.append("choices: "+", ".join(str(c[0]) for c in f.choices if c[0]!='')[:120])
            if getattr(f,'null',False): notes.append('optional')
            if getattr(f,'db_index',False) and not f.primary_key: notes.append('indexed')
            if getattr(f,'unique',False) and not f.primary_key: notes.append('unique')
            if f.help_text: notes.append(str(f.help_text))
            dm.append(f"| `{f.name}` | {t} | {'; '.join(notes)} |\n")
        cons=[c.name for c in m._meta.constraints]
        if cons: dm.append(f"\nConstraints: {', '.join(cons)}\n")
open('../docs/architecture/data-model.md','w').write(''.join(dm))
print(len(rows))
