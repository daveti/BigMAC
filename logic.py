import networkx as nx
import overlay
import pprint
import logging
import stat
from collections import deque

log = logging.getLogger(__name__)

class Logic:
    
    # Getter for commands
    def get_commands(self):
        return self._commands
    
    def __init__(self, G): 
        self.graph = G

        self._commands = [
            {'name' : 'info', 'handler': self.object_info},
            {'name' : 'list_nodes', 'handler': self.list_nodes},
            {'name' : 'query', 'handler': lambda args: self.query(args, mac_only=False)},
            {'name' : 'query_mac', 'handler': lambda args: self.query(args, mac_only=True)},
            {'name' : 'print', 'handler': lambda args: self.print_paths(args, trust=False)},
            {'name' : 'print_trust', 'handler': lambda args: self.print_paths(args, trust=True)},
            {'name' : 'bfs', 'handler': lambda args: self.bfs_path_finder(args, trust=True)}
        ]

        self.node_types = {
            'files': overlay.FileNode,
            'subjects': overlay.SubjectNode,
            'processes': overlay.ProcessNode,
            'ipc': overlay.IPCNode
        }

    def object_info(self, args):
        if len(args) < 1:
            info = {'error': 'Object required'}
            log.info(pprint.pformat(info))
            return info
        name = args[0]
        node_objs = nx.get_node_attributes(self.graph, 'obj')
        if name not in node_objs:
            info = {'error': 'Object not found'}
            log.info(pprint.pformat(info))
            return info
        obj = node_objs[name]
        info = {'name': name, 'type': type(obj).__name__}
        if isinstance(obj, overlay.IPCNode):
            info['ipc'] = True
            info['node_name'] = obj.get_node_name()
            if obj.owner:
                info['owner'] = repr(obj.owner)
                info['owner_node_name'] = obj.owner.get_node_name()
            log.info(pprint.pformat(info))
        elif isinstance(obj, overlay.ProcessNode):
            info['repr'] = repr(obj)
            if hasattr(obj, 'exe') and obj.exe:
                (fn, fo), = obj.exe.items()
                info['backing_file'] = fn
                info['backing_file_obj'] = fo
                # Format the one-line summary
                perms = fo.get('perms', 0)
                size = fo.get('size', '?')
                user = fo.get('user', '?')
                group = fo.get('group', '?')
                selinux = fo.get('selinux', '?')
                path = fn
                # Permissions string
                permstr = stat.filemode(perms) if perms else '?????????'
                summary = f"{permstr} {size} {user} {group} {selinux} {path}"
                log.info(summary)
                log.info(pprint.pformat(fo))
            else:
                log.info(pprint.pformat(info))
        else:
            info['repr'] = repr(obj)
            if hasattr(obj, 'backing_files') and len(obj.backing_files):
                (fn, fo), = obj.backing_files.items()
                info['backing_file'] = fn
                info['backing_file_obj'] = fo
            log.info(pprint.pformat(info))
        return info

    def list_nodes(self, args):

        node_objs = nx.get_node_attributes(self.graph, 'obj')
        if not args:
            return {'nodes': list(node_objs.keys())}
        else:
            arg = args[0].lower()
            if arg in self.node_types:
                filtered = [name for name, obj in node_objs.items() if type(obj) is self.node_types[arg]]
                log.info("\n".join(filtered))
                return {'nodes': filtered}
            else:
                return {'error': f'Unknown filter: {arg}'}

    def query(self, args, mac_only=False):
        if len(args) < 3:
            return {'error': 'Query needs at least 3 arguments'}
        start, end, cutoff = args[:3]
        try:
            cutoff = int(cutoff)
        except ValueError:
            return {'error': 'Cutoff must be an integer'}
        node_objs = nx.get_node_attributes(self.graph, 'obj')
        if start not in node_objs or end not in node_objs:
            return {'error': f'Start or end node not found: {start}, {end}'}
        try:
            all_paths = list(nx.all_simple_paths(self.graph, source=start, target=end, cutoff=cutoff))
        except nx.NetworkXNoPath:
            all_paths = []
        if mac_only:
            filtered_paths = [path for path in all_paths if all(getattr(node_objs[n], 'trusted', False) for n in path)]
            paths = [[n for n in path] for path in filtered_paths]
        else:
            paths = [[n for n in path] for path in all_paths]
        self.result = paths  # Store for later printing
        return {'paths': paths, 'count': len(paths)}

    def print_paths(self, args, trust=False):
        node_objs = nx.get_node_attributes(self.graph, 'obj')
        if args and args[0] == 'special':
            specials = []
            for name, obj in node_objs.items():
                if hasattr(obj, 'backing_files') and obj.backing_files:
                    for fn, fo in obj.backing_files.items():
                        tags = fo.get('tags', [])
                        if tags:
                            specials.append({'node': name, 'file': fn, 'tags': tags})
            return {'special': specials}
        if args and args[0] == 'trusted':
            trusted = [name for name, obj in node_objs.items() if getattr(obj, 'trusted', False)]
            return {'trusted': trusted}
        if args and args[0] == 'strongest':
            process_nodes = [n for n, o in node_objs.items() if type(o).__name__ == 'ProcessNode']
            results = []
            for name in process_nodes:
                out_edges = list(self.graph.out_edges(name))
                uniq_types = set()
                for _, tgt in out_edges:
                    tgt_obj = node_objs.get(tgt)
                    if tgt_obj:
                        uniq_types.add(type(tgt_obj).__name__)
                results.append({'name': name, 'unique_types': len(uniq_types), 'out_edges': len(out_edges)})
            results.sort(key=lambda x: x['out_edges'], reverse=True)
            return {'strongest': results}
        # Default: print stored query result
        if not hasattr(self, 'result') or not self.result:
            return {'error': 'No results to print'}
        cutoff = None
        if args:
            try:
                cutoff = int(args[0])
            except (ValueError, TypeError):
                cutoff = None
        paths = []
        for pathid, path in enumerate(self.result):
            if cutoff is not None and (pathid+1 > cutoff):
                break
            path_info = []
            pretty = []
            for n in path:
                obj = node_objs[n]
                node_name = getattr(obj, 'get_node_name', lambda: n)()
                path_info.append({
                    'name': node_name,
                    'trusted': getattr(obj, 'trusted', False),
                    'type': type(obj).__name__
                })
                if trust:
                    if getattr(obj, 'trusted', False):
                        pretty.append(f"[T]{node_name}")
                    else:
                        pretty.append(f"[U]{node_name}")
                else:
                    pretty.append(node_name)
            print(f"Path {pathid+1}: {' -> '.join(pretty)}")
            paths.append(path_info)
        return {'paths': paths}

    def bfs_path_finder(self, args, trust=False):
        log.info("==== BFS Path Finder Start ====")

        if len(args) < 2:
            log.info("Error: Less than 2 arguments provided.")
            return {'error': 'Path Finder needs at least 2 arguments'}

        root, target = args[:2]
        log.info(f"Root: {root}, Target: {target}")

        node_objs = nx.get_node_attributes(self.graph, 'obj')
        log.info(f"Available nodes in graph: {list(node_objs.keys())}")

        if root not in node_objs or target not in node_objs:
            log.info("Error: Root or target not found in node attributes.")
            return {'error': f'Root or target node not found: {root}, {node_objs}'}

        def bfs(G, root, target):
            visited = set()
            queue = deque()

            queue.append((root, [root]))
            visited.add(root)
            log.info(f"Initialized queue with root: {root}")
            
            while queue:
                current, path = queue.popleft()

                if current == target:
                    formatted_path = " -> ".join(path)
                    log.info(f"Target {target} found! Final path: {formatted_path}")
                    return path

                neighbors = list(G.neighbors(current))

                for neighbor in neighbors:
                    if neighbor not in visited:
                        visited.add(neighbor)
                        new_path = path + [neighbor]
                        queue.append((neighbor, new_path))
                    else:
                        log.info(f"{neighbor} already visited.")
            
            log.info("Target not found in graph.")
            return None

        bfs_path = bfs(self.graph, root, target)
        
        if bfs_path:
            formatted_path = " -> ".join(bfs_path)
            log.info(f"Final path: {formatted_path}")
        else:
            log.info("Final path: None")


        return bfs_path if bfs_path else {'error': 'No path found between nodes.'}





