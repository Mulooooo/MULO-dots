$(cat graphify-out/.graphify_python) -c "
import json
from graphify.build import build_from_json
from graphify.wiki import to_wiki
from graphify.analyze import god_nodes
from pathlib import Path

extraction = json.loads(Path('graphify-out/.graphify_extract.json').read_text())
analysis   = json.loads(Path('graphify-out/.graphify_analysis.json').read_text())
labels_raw = json.loads(Path('graphify-out/.graphify_labels.json').read_text()) if Path('graphify-out/.graphify_labels.json').exists() else {}
doxygen    = json.loads(Path('graphify-out/.graphify_doxygen.json').read_text()) if Path('graphify-out/.graphify_doxygen.json').exists() else {}

G = build_from_json(extraction)
communities = {int(k): v for k, v in analysis['communities'].items()}
cohesion = {int(k): v for k, v in analysis['cohesion'].items()}
labels = {int(k): v for k, v in labels_raw.items()}
gods = god_nodes(G)

n = to_wiki(G, communities, 'graphify-out/wiki', community_labels=labels or None, cohesion=cohesion, god_nodes_data=gods)
print(f'Wiki: {n} articles written to graphify-out/wiki/')
print('  graphify-out/wiki/index.md  ->  agent entry point')

wiki_path = Path('graphify-out/wiki')
for file_path in wiki_path.glob('*.md'):
    content = file_path.read_text()
    node_name = file_path.stem  # Assumes filename matches class/function name
    
    if node_name in doxygen:
        info = doxygen[node_name]
        doc_block = f'\n\n## API Reference\n**Brief:** {info['brief']}\n'
        
        if info['params']:
            doc_block += '\n### Parameters\n'
            for p in info['params']:
                doc_block += f'- \`{p['name']}\`: {p['desc']}\n'
        
        if info['returns']:
            doc_block += f'\n**Returns:** {info['returns']}\n'
            
        # Append to the end of the file or insert before a specific marker
        file_path.write_text(content + doc_block)

print('Doxygen documentation injected into markdown files.')"