from pathlib import Path
import json,re,hashlib,subprocess,collections
root=Path(__file__).resolve().parents[1]; src=root/'src/CocoaTop/src'; res=root/'src/CocoaTop/res'
lit=r'@?"(?:\\.|[^"\\])*"'
def dec(s):return json.loads(s.lstrip('@'),strict=False)
def strip_comments(t):
    # Keep quoted strings while discarding comments.
    return re.sub(r'"(?:\\.|[^"\\])*"|/\*[\s\S]*?\*/|//[^\n]*',lambda m:m[0] if m[0].startswith('"') else '',t)
def groups(t):
    return [''.join(dec(p[0]) for p in re.finditer(lit,m[0])) for m in re.finditer(r'@"(?:\\.|[^"\\])*"(?:\s*"(?:\\.|[^"\\])*")*',t)]
txt=(res/'zh-Hans.lproj/Localizable.strings').read_text()
pairs=re.findall(r'("(?:\\.|[^"\\])*")\s*=\s*("(?:\\.|[^"\\])*")\s*;',txt)
table={dec(k):dec(v) for k,v in pairs}; assert len(table)==len(pairs)
rules=json.loads((res/'translation-rules.json').read_text());first={}
for r in rules:first.setdefault(r['original'],r['translation'])
assert len(rules)==225 and len(first)==222
assert (res/'translation-rules.json').read_bytes()==(root.parent/'analysis/translations.json').read_bytes()
overrides=json.loads((res/'translation-overrides.json').read_text());supp=json.loads((res/'translation-supplements.json').read_text())
assert not set(supp).intersection(first), 'Supplements must not silently override extracted values'
for k,v in first.items():
    assert table[k]==overrides.get(k,v),(k,table[k])
assert table['Only columns that fit will actually be shown']=='仅显示当前屏幕宽度能够容纳的列'
assert not any('来了老弟' in v for v in table.values())
owned=['Column.m','Column_ios.h','Column_simulator.h','GridCell.m','RootViewController.m','Setup.m','SetupColumns.m','SockViewController.m','THtmlViewController.m']
source='\n'.join(strip_comments((src/f).read_text()) for f in owned)
# Check exact runtime literal keys exist, with preserved printf tokens.
fmt=re.compile(r'%(?:\d+\$)?[-+#0 ]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|ll|[hljztL])?[@diuoxXfFeEgGaAcCsSpn%]')
calls=[]
for m in re.finditer(r'CTLocalizedString\(\s*(@"(?:\\.|[^"\\])*")\s*\)',source):
    k=dec(m[1]); assert k in table,k; assert fmt.findall(k)==fmt.findall(table[k]),k; calls.append(k)
modelstats={}; modelkeys=[]; description_count=0
for fn in ['Column_ios.h','Column_simulator.h','Column.m']:
    t=strip_comments((src/fn).read_text());stats=collections.Counter()
    for m in re.finditer(r'(psColumnWithName:|fullname:|descr:)\s*(@"(?:\\.|[^"\\])*"(?:\s*"(?:\\.|[^"\\])*")*)',t):
        k=''.join(dec(p[0]) for p in re.finditer(lit,m[2]));kind=m[1];stats[kind]+=1
        if k: modelkeys.append(k)
        if kind in ('fullname:','descr:'): assert k in table,(fn,kind,k)
        if kind=='descr:':
            description_count+=1
            assert k.count('\n')==table[k].count('\n'),(fn,k[:70])
    modelstats[fn]=dict(stats)
# Raw setting storage and selection identity remain intact.
setup=(src/'Setup.m').read_text(); original=subprocess.check_output(['git','show','HEAD:src/CocoaTop/src/Setup.m'],cwd=root,text=True)
assert re.findall(r'chooseFrom:(@\[[^\n]*?\]|nil)',setup)==re.findall(r'chooseFrom:(@\[[^\n]*?\]|nil)',original)
assert 'self.value = self.list[indexPath.row];' in setup
assert '[self.value isEqualToString:self.list[indexPath.row]]' in setup
assert 'FirstColumnStyle" : @"Bundle Identifier"' in (src/'RootViewController.m').read_text()
for fn in owned:
    t=(src/fn).read_text();assert '[NSUserDefaults standardUserDefaults]' not in t,fn
    if '[CTPreferences standardUserDefaults]' in t:assert '#import "CTPreferences.h"' in t,fn
for fn in ['Column_ios.h','Column_simulator.h']:
    assert all('summary:' in line for line in (src/fn).read_text().splitlines() if 'CTLocalizedString(' in line)
for fn in owned:
    original_text=subprocess.check_output(['git','show','HEAD:src/CocoaTop/src/'+fn],cwd=root,text=True)
    key_pattern=r'(?:forKey:|key:|boolForKey:|stringForKey:|integerForKey:|arrayForKey:|floatForKey:)\s*(@"(?:\\.|[^"\\])*")'
    assert re.findall(key_pattern,(src/fn).read_text())==re.findall(key_pattern,original_text),('Changed business keys',fn)
assert 'NSMutableArray *modeItems = [NSMutableArray array];' in (src/'SockViewController.m').read_text()
assert not re.search(r'CTLocalizedString\(\s*(?:proc\.|sock\.|.*\.executable)',source)
assert not re.search('method_exchangeImplementations|class_replaceMethod|%hook',source)
# Immutable labels present in extraction that are source-matched exactly vs normalized substring.
all_literals=groups(source);exact=sum(k in all_literals for k in first)
norm=lambda s:re.sub(r'\s+',' ',s).strip().lower()
matched=sum(any(norm(k) in norm(s) for s in all_literals) for k in first if k)
report={'original_rules':len(rules),'unique_originals':len(first),'localizable_keys':len(table),'overrides':len(overrides),'supplements':len(supp),'literal_calls':len(calls),'unique_literal_call_keys':len(set(calls)),'model_occurrences':modelstats,'description_occurrences_with_preserved_newlines':description_count,'model_nonempty_occurrences':len(modelkeys),'model_translated_occurrences':sum(k in table for k in modelkeys),'model_nonempty_unique':len(set(modelkeys)),'model_translated_unique':len(set(modelkeys)&table.keys()),'unchanged_symbolic_headers':sorted(set(modelkeys)-table.keys()),'extracted_original_exact_source_matches':exact,'extracted_original_normalized_substring_matches':matched,'rule_resource_sha256':hashlib.sha256((res/'translation-rules.json').read_bytes()).hexdigest(),'checks':'PASS; static only; no compiler/device validation'}
print(json.dumps(report,ensure_ascii=False,indent=2))
(root/'docs/localization-audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
