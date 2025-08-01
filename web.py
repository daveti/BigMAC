import gzip
from pprint import pprint
from flask import render_template, Flask, jsonify, request, Response
import networkx as nx   
import io, json
from overlay import FileNode, IPCNode, ProcessNode
import time

app = Flask(__name__)


CHUNK_SIZE = 10

@app.route("/graph")
def get_graph():
    return render_template("graph_viewer.html")


@app.route('/graph/stream')
def stream_graph():

    G = app.config['G']
    print(f"G Nodes: {G.number_of_nodes()} Edges: {G.number_of_edges()}")
    #G_sub = nx.subgraph_view(G, filter_node=lambda n: G.degree(n) > 0)
    #print(f"G_sub Nodes: {G_sub.number_of_nodes()} Edges: {G_sub.number_of_edges()}")

    cyto_data = nx.cytoscape_data(G)
    cyto_data = convert_special_nodes_to_repr(cyto_data)

    def generate():
        
        for n in cyto_data["elements"]["nodes"]:
            n["type"] = "node"
            yield f"data: {json.dumps(n)}\n\n"
            time.sleep(0.05)
        # Stream edges
        for e in cyto_data["elements"]["edges"]:
            e["type"] = "edge"
            yield f"data: {json.dumps(e)}\n\n"
            time.sleep(0.05)

    return Response(generate(), mimetype='text/event-stream')


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