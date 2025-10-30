import logging
import gzip
import io, json
import time

from flask import render_template, Flask, jsonify, request, redirect, url_for, Response
import networkx as nx   
from overlay import FileNode, IPCNode, ProcessNode

app = Flask(__name__)
log = logging.getLogger(__name__)

CHUNK_SIZE = 10

@app.route("/graph")
def graph():
    return render_template("graph_viewer.html")

@app.route("/")
def index():
    return redirect(url_for('graph'))

@app.route('/graph/stream')
def stream_graph():

    G = app.config['G']
    log.info(f"G Nodes: {G.number_of_nodes()} Edges: {G.number_of_edges()}")
    G_sub = nx.subgraph_view(G, filter_node=lambda n: G.degree(n) > 0)
    log.info(f"G_sub Nodes: {G_sub.number_of_nodes()} Edges: {G_sub.number_of_edges()}")

    # Get graph data in json form
    graph_json = nx.cytoscape_data(G_sub)
    graph_json_str = convert_special_nodes(graph_json)

    # Chunk graph data in sizes of BATCH_SIZE
    def generate():
        
        node_data = graph_json_str["elements"]["nodes"]
        edge_data = graph_json_str["elements"]["edges"]
        log.info(f"Total number of edges {len(edge_data)}")

        tn = 0
        te = 0
        
        for i in range(0, len(node_data), CHUNK_SIZE):
            
            node_data_chunk = node_data[i:i + CHUNK_SIZE]
            node_data_json = {"type": "node", "nodes": node_data_chunk}

            yield f"data: {json.dumps(node_data_json)}\n\n"

            time.sleep(0.1)
            tn += len(node_data_chunk)
    
    log.info("Finished Loading")
    return Response(generate(), mimetype='text/event-stream')

# Get all edges connected to a certain edge
@app.route('/graph/edges')
def get_node_edges(): 

    node_id = request.args.get("node")
    G = app.config['G']
    if node_id not in G:
        return jsonify({"edges": []})

    neighbors = list(G.neighbors(node_id)) + [node_id]
    subG = G.subgraph(neighbors)

    graph_json = nx.cytoscape_data(subG)
    graph_json_str = convert_special_nodes(graph_json)
    edge_data = graph_json_str["elements"]["edges"]

    return jsonify({"edges": edge_data})


def start_server(G): 
    app.config['G'] = G
    app.run(port=5000, debug=True)

# Convert special nodes into strings
def convert_special_nodes(obj):
    if isinstance(obj, (FileNode, IPCNode, ProcessNode)):
        return repr(obj)
    elif isinstance(obj, dict):
        return {k: convert_special_nodes(v) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [convert_special_nodes(item) for item in obj]
    elif isinstance(obj, tuple):
        return tuple(convert_special_nodes(item) for item in obj)
    else:
        return obj
