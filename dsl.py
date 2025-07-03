from pyparsing import Word, alphanums, OneOrMore, Group, Suppress, Optional, pythonStyleComment, ParserElement
import logging
from logic import Logic

ParserElement.set_default_whitespace_chars(' \t')  

log = logging.getLogger(__name__)

class DSLGraph:
    def __init__(self, G):
        # Initialize values for the DSLGraph
        self.graph = G
        self.mac_only = False

        self.queries = []
        self.aliases = {}

        self.logic = Logic(G=G)

        self._build_parser()

    def _build_parser(self):
        # Build the pyparsing parser for the DSL.
        word = Word(alphanums + "_-:.")  
        # Set parsing rules
        node_stmt = Suppress("node") + word("alias") + word("real_name")
        edge_stmt = Suppress("edge") + word("src") + word("dst")
        command_stmt = Suppress("command") + word("cmd") + Optional(OneOrMore(word), default=[])("args")

        stmt = node_stmt.setParseAction(self._handle_node) | \
               edge_stmt.setParseAction(self._handle_edge) | \
               command_stmt.setParseAction(self._handle_command)

        self.parser = stmt.ignore(pythonStyleComment)

    def parse_file(self, filename):
        # Parse a DSL file by line
        with open(filename) as f:
            for lineno, line in enumerate(f, start=1):
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                try:
                    self.parser.parse_string(line, parse_all=True)
                except Exception as e:
                    log.error(f"Failed to parse line {lineno}: {line}\nError: {e}")

    def _handle_node(self, tokens):
        # Handle node variables in files
        alias, real_name = tokens.alias, tokens.real_name
        self.aliases[alias] = real_name

    def _handle_edge(self, tokens):
        # Handle edge variables in file
        src = self.resolve(tokens.src)
        dst = self.resolve(tokens.dst)

    def _handle_command(self, tokens):
        # Handle commands in the dsl
        cmd = tokens.cmd
        args = [self.resolve(arg) for arg in tokens.args]
        handler = None
        for cmd_entry in self.logic.get_commands():
            if cmd_entry['name'] == cmd:
                handler = cmd_entry['handler']
                break
        if handler:
            handler(args)
        else:
            log.error(f"Unknown command: {cmd}")

    def resolve(self, name):
        # Resolve an alias to its real node name
        return self.aliases.get(name, name)

    def _print_result(self, cmd, result):
        # Interpret and print structured result from logic.py
        if 'error' in result:
            print(f"Error: {result['error']}")
            return
        if cmd == 'info':
            self._pretty_print_dict(result)
        elif cmd == 'list_nodes':
            print("Nodes:")
            for n in result.get('nodes', []):
                print(f"  {n}")
        elif cmd in ('query', 'query_mac'):
            for i, path in enumerate(result.get('paths', []), 1):
                print(f"Path {i}: {' -> '.join(path)}")
        elif cmd in ('print', 'print_trust'):
            if 'special' in result:
                if not result['special']:
                    print("No special files found.")
                else:
                    print("Special files:")
                    for entry in result['special']:
                        print(f"  {entry['node']}: {entry['file']} tags={entry['tags']}")
            elif 'trusted' in result:
                if not result['trusted']:
                    print("No trusted nodes found.")
                else:
                    print("Trusted nodes:")
                    for n in result['trusted']:
                        print(f"  {n}")
            elif 'strongest' in result:
                if not result['strongest']:
                    print("No process nodes found.")
                else:
                    print("Strongest process nodes:")
                    for i, entry in enumerate(result['strongest'], 1):
                        print(f"  {i}: ntype={entry['unique_types']} nobj={entry['out_edges']} {entry['name']}")
            elif 'paths' in result:
                if not result['paths']:
                    print("No results to print")
                else:
                    for i, path in enumerate(result['paths'], 1):
                        pretty = []
                        for node in path:
                            name = node['name']
                            if 'trusted' in node:
                                if node['trusted']:
                                    name = f"[T]{name}"
                                else:
                                    name = f"[U]{name}"
                            pretty.append(name)
                        print(f"{i}: {' -> '.join(pretty)}")
        elif isinstance(result, dict):
            self._pretty_print_dict(result)
        else:
            print(result)

    def _pretty_print_dict(self, d, indent=0):
        # Generalized pretty-printer for dicts/lists
        pad = '  ' * indent
        if isinstance(d, dict):
            for k, v in d.items():
                if isinstance(v, (dict, list)):
                    print(f"{pad}{k}:")
                    self._pretty_print_dict(v, indent+1)
                else:
                    print(f"{pad}{k}: {v}")
        elif isinstance(d, list):
            for i, v in enumerate(d):
                print(f"{pad}- [{i}]")
                self._pretty_print_dict(v, indent+1)
        else:
            print(f"{pad}{d}")

