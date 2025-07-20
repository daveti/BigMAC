import gzip
from pprint import pprint
from flask import render_template, Flask, jsonify, request
import networkx as nx   
import io, json
from overlay import FileNode, IPCNode, ProcessNode

app = Flask(__name__)

def serialize_data(data): 
    with io.StringIO() as fh:  # replace io with `open(...)` to write to disk
        json.dump(data, fh)
        fh.seek(0)
        return fh.getvalue()


@app.route("/graph")
def get_graph():
    return render_template("graph_viewer.html")

@app.route("/graph/data")
def get_graph_data():
    G = app.config['G']
    cyto_data = nx.cytoscape_data(G)
    cyto_data = convert_special_nodes_to_repr(cyto_data)

    # Pagination params
    page = int(request.args.get('page', 1))
    per_page = int(request.args.get('per_page', 100))

    elements = cyto_data.get('elements', {})
    nodes = elements.get('nodes', [])
    edges = elements.get('edges', [])

    total_nodes = len(nodes)
    start = (page - 1) * per_page
    end = start + per_page
    paginated_nodes = nodes[start:end]

    # Get the set of node ids in the current page
    node_ids = set(n['data']['id'] for n in paginated_nodes if 'data' in n and 'id' in n['data'])

    # Only include edges where both source and target are in the current page
    paginated_edges = [
        e for e in edges
        if 'data' in e and e['data'].get('source') in node_ids and e['data'].get('target') in node_ids
    ]

    paginated_elements = {
        'nodes': paginated_nodes,
        'edges': paginated_edges
    }

    paginated_data = {
        'data': cyto_data.get('data'),
        'directed': cyto_data.get('directed'),
        'multigraph': cyto_data.get('multigraph'),
        'elements': paginated_elements,
        'pagination': {
            'page': page,
            'per_page': per_page,
            'total_nodes': total_nodes,
            'total_pages': (total_nodes + per_page - 1) // per_page
        }
    }

    return jsonify(paginated_data)


def start_server(G): 
    app.config['G'] = G
    app.run(port=5000, debug=True)

def convert_special_nodes_to_repr(obj):
    if isinstance(obj, (FileNode, IPCNode, ProcessNode)):
        return repr(obj)
    elif isinstance(obj, dict):
        return {k: convert_special_nodes_to_repr(v) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [convert_special_nodes_to_repr(item) for item in obj]
    elif isinstance(obj, tuple):
        return tuple(convert_special_nodes_to_repr(item) for item in obj)
    else:
        return obj